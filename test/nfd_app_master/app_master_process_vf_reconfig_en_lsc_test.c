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
    int vf;
    struct nfd_cfg_msg cfg_msg;

    set_nic_control_word(pcie, NFD_PF2VID(0),
            get_nic_control_word(pcie,
                NFD_PF2VID(0)) | NFP_NET_CFG_CTRL_ENABLE);
    setup_pf_mac(pcie, NFD_PF2VID(0), TEST_MAC);
    set_ls_current(pcie, NFD_PF2VID(0), pf_link & 1);

    for (vf = 0; vf < NFD_MAX_VFS; vf++) {

        vid = NFD_VF2VID(vf);
        NFD_VID2VNIC(type, vnic, vid);

        reset_cfg_msg(&cfg_msg, vid, 0);

        setup_vf_mac(pcie, vid, TEST_MAC);
        setup_sriov_cfg_data(pcie, vf, 0, 0,
                (vf_mode & 3) | ( 0 << NFD_VF_CFG_CTRL_TRUSTED_shf));

        control = NFD_CFG_VF_CAP & (~NFP_NET_CFG_CTRL_ENABLE);
        control |= vf_enable;
        update = NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(pcie, control, update, vid, &cfg_msg)) {
            test_fail();
        }
    }
}

void verify_vf_lsc(int pcie, uint32_t port, uint32_t expected)
{
    int vf;
    for (vf = 0; vf < NFD_MAX_VFS; vf++)
        test_assert_equal(get_vf_lsc(port, pcie, NFD_VF2VID(vf)), expected);

}


void verify_other_vf_lsc(int pcie, uint32_t port, uint32_t expected)
{
    int vf, i;
    for (vf = 0; vf < NFD_MAX_VFS; vf++) {
        for (i = 0; i < NS_PLATFORM_NUM_PORTS; i++) {
            if (i != port)
                test_assert_equal(get_vf_lsc(i, pcie, NFD_VF2VID(vf)), expected);
        }
    }
}

void test(int pcie) {
    uint32_t port = 0;

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_DOWN);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_UP);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_DOWN);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_UP);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_DOWN);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_DISABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_UP);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_DOWN);
    verify_vf_lsc(pcie, port, LINK_UP);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_AUTO, LINK_UP);
    verify_vf_lsc(pcie, port, LINK_UP);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_DOWN);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_ENABLE, LINK_UP);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_DOWN);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);

    reconfig(pcie, NFP_NET_CFG_CTRL_ENABLE, NFD_VF_CFG_CTRL_LINK_STATE_DISABLE, LINK_UP);
    verify_vf_lsc(pcie, port, LINK_DOWN);
    verify_other_vf_lsc(pcie, port, LINK_DOWN);


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
