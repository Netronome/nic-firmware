//TEST_REQ_BLM
//TEST_REQ_RESET

/*
    Tests the process_pf_reconfig funtion in app_master
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
#include "nfd_cfg_base_decl.c"

void test(int pcie) {
    uint32_t type, vnic, vid, pf, control, update;
    uint32_t test_control;
    struct nfd_cfg_msg cfg_msg;

    for (pf = 0; pf < NFD_MAX_PFS; pf++) {

        vid = NFD_PF2VID(pf);
        NFD_VID2VNIC(type, vnic, vid);

        reset_cfg_msg(&cfg_msg, vid, 0);

        set_nic_control_word(pcie, vid, NFP_NET_CFG_CTRL_ENABLE);

        /*If nic_control_word[vid] has NFP_NET_CFG_CTRL_ENABLE set and
         * ~NFP_NET_CFG_CTRL_ENABLE is passed to the function, then it
         * must be ~NFP_NET_CFG_CTRL_ENABLE*/
        control = NFD_CFG_PF_CAP & ~NFP_NET_CFG_CTRL_ENABLE;
        update = NFD_CFG_PF_LEGAL_UPD & ~NFP_NET_CFG_UPDATE_BPF; //BPF updates tested separately

        if (process_pf_reconfig(pcie, control, update, vid, vnic, &cfg_msg))
            test_fail();

        test_control = get_nic_control_word(pcie, vid);
        test_assert_equal(test_control & NFP_NET_CFG_CTRL_ENABLE, 0);
    }

}

void main(void)
{
    int  pcie;
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
