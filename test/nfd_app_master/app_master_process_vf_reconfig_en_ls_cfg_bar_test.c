//TEST_REQ_BLM
//TEST_REQ_RESET

/*
    Tests the process_vf_reconfig funtion in app_master
*/

#include "defines.h"
#include "test.c"
#include "app_master_test.h"
#include "vnic_setup.c"
#include "app_private.c"
#include "app_config_tables.c"
#include "nic_tables.c"
#include "map_cmsg_rx.c"
#include "app_control_lib.c"
#include "action_parse.c"
#include "nfd_cfg_base_decl.c"

#define NFP_NET_CFG_CTRL_DISABLE (~NFP_NET_CFG_CTRL_ENABLE & 1)

void reconfig(int pcie, uint32_t vf_enable, uint32_t vf_mode, uint32_t pf_link)
{
    uint32_t type, vnic, vid, control, update;
    uint32_t pf = 0;
    int vf;
    struct nfd_cfg_msg cfg_msg;

    set_nic_control_word(pcie, NFD_PF2VID(pf),
            get_nic_control_word(pcie,
                NFD_PF2VID(pf)) | NFP_NET_CFG_CTRL_ENABLE);
    setup_pf_mac(pcie, NFD_PF2VID(pf), TEST_MAC);
    set_ls_current(pcie, NFD_PF2VID(pf), pf_link & 1);

    for (vf = 0; vf < NFD_MAX_VFS; vf++) {

        vid = NFD_VF2VID(vf);
        NFD_VID2VNIC(type, vnic, vid);

        reset_cfg_msg(&cfg_msg, vid, 0);

        setup_vf_mac(pcie, vid, TEST_MAC);
        setup_sriov_cfg_data(NIC_PCI, vf, 0, 0,
                (vf_mode & 3) | (0 << NFD_VF_CFG_CTRL_TRUSTED_shf));

        control = NFD_CFG_VF_CAP & (~NFP_NET_CFG_CTRL_ENABLE);
        control |= vf_enable;
        update = NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(pcie, control, update, vid, &cfg_msg)) {
            test_fail();
        }
    }
}

void verify_ls_cfg_bar(int pcie, uint32_t expected_ls)
{
    int vf;
    __xread uint32_t sts;

    for (vf = 0; vf < NFD_MAX_VFS; vf++) {
        mem_read32(&sts,
                nfd_cfg_bar_base(pcie, NFD_VF2VID(vf)) + NFP_NET_CFG_STS,
                sizeof(sts));

        test_assert_equal((sts & 1), expected_ls);
    }
}

void test(int pcie) {

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_DOWN);
    verify_ls_cfg_bar(pcie, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_UP);
    verify_ls_cfg_bar(pcie, LINK_UP);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_DOWN);
    verify_ls_cfg_bar(pcie, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_UP);
    verify_ls_cfg_bar(pcie, LINK_UP);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_DOWN);
    verify_ls_cfg_bar(pcie, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_UP);
    verify_ls_cfg_bar(pcie, LINK_UP);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_DOWN);
    verify_ls_cfg_bar(pcie, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_UP);
    verify_ls_cfg_bar(pcie, LINK_UP);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_DOWN);
    verify_ls_cfg_bar(pcie, LINK_UP);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_UP);
    verify_ls_cfg_bar(pcie, LINK_UP);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_DOWN);
    verify_ls_cfg_bar(pcie, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_UP);
    verify_ls_cfg_bar(pcie, LINK_UP);
}

void main(void)
{
    int pcie;
    switch (ctx()) {
        case 0:
            for (pcie = 0; pcie < NFD_MAX_ISL; pcie++) {
                if (pcie_is_present(pcie))
                    test(pcie);
            }
            test_pass();
            break;
        default:
            map_cmsg_rx();
            break;
    }
}
