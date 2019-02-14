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

void reconfig(uint32_t vf_enable, uint32_t vf_mode, uint32_t pf_link)
{
    uint32_t type, vnic, vid, pf, control, update;
    int vf;
    struct nfd_cfg_msg cfg_msg;

    for (pf = 0; pf < NFD_MAX_PFS; pf++) {
        set_nic_control_word(NIC_PCI, NFD_PF2VID(pf),
                get_nic_control_word(NIC_PCI,
                    NFD_PF2VID(pf)) | NFP_NET_CFG_CTRL_ENABLE);
        setup_pf_mac(NIC_PCI, NFD_PF2VID(pf), TEST_MAC);
        set_ls_current(NIC_PCI, NFD_PF2VID(pf), pf_link & 1);
    }

    for (vf = 0; vf < NFD_MAX_VFS; vf++) {

        vid = NFD_VF2VID(vf);
        NFD_VID2VNIC(type, vnic, vid);

        reset_cfg_msg(&cfg_msg, vid, 0);

        setup_vf_mac(NIC_PCI, vid, TEST_MAC);
        setup_sriov_cfg_data(NIC_PCI, vf, 0, 0,
                (vf_mode & 3) | (0 << NFD_VF_CFG_CTRL_TRUSTED_shf));

        control = NFD_CFG_VF_CAP & (~NFP_NET_CFG_CTRL_ENABLE);
        control |= vf_enable;
        update = NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(NIC_PCI, control, update, vid, &cfg_msg)) {
            test_fail();
        }
    }
}

void verify_vs_ls_current(uint32_t expected_vs, uint32_t expected_ls)
{
    int vf;
    for (vf = 0; vf < NFD_MAX_VFS; vf++) {
        test_assert_equal(get_vs_current(NIC_PCI, NFD_VF2VID(vf)), expected_vs);
        test_assert_equal(get_ls_current(NIC_PCI, NFD_VF2VID(vf)), expected_ls);
    }
}

void test(uint32_t pcie) {

    reconfig(NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_DOWN);
    verify_vs_ls_current(LINK_DOWN, LINK_DOWN);

    reconfig(NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_UP);
    verify_vs_ls_current(LINK_DOWN, LINK_UP);

    reconfig(NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_DOWN);
    verify_vs_ls_current(LINK_DOWN, LINK_DOWN);

    reconfig(NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_UP);
    verify_vs_ls_current(LINK_DOWN, LINK_UP);

    reconfig(NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_DOWN);
    verify_vs_ls_current(LINK_DOWN, LINK_DOWN);

    reconfig(NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_UP);
    verify_vs_ls_current(LINK_DOWN, LINK_UP);

    reconfig(NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_DOWN);
    verify_vs_ls_current(LINK_UP, LINK_DOWN);

    reconfig(NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_UP);
    verify_vs_ls_current(LINK_UP, LINK_UP);

    reconfig(NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_DOWN);
    verify_vs_ls_current(LINK_UP, LINK_UP);

    reconfig(NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_UP);
    verify_vs_ls_current(LINK_UP, LINK_UP);

    reconfig(NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_DOWN);
    verify_vs_ls_current(LINK_UP, LINK_DOWN);

    reconfig(NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_UP);
    verify_vs_ls_current(LINK_UP, LINK_UP);

    test_pass();
}

void main(void)
{
    switch (ctx()) {
        case 0:
            test(0);
            break;
        default:
            map_cmsg_rx();
            break;
    }
}
