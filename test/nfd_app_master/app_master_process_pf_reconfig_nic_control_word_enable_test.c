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

void test(uint32_t pcie) {
    uint32_t type, vnic, vid, pf, control, update;
    uint32_t test_control;
    struct nfd_cfg_msg cfg_msg;

    for (pf = 0; pf < NFD_MAX_PFS; pf++) {

        vid = NFD_PF2VID(pf);
        NFD_VID2VNIC(type, vnic, vid);

        setup_pf_mac(pcie, vid, TEST_MAC);
        reset_cfg_msg(&cfg_msg, vid, 0);

        set_nic_control_word(NIC_PCI, vid, get_nic_control_word(NIC_PCI, vid) & ~NFP_NET_CFG_CTRL_ENABLE);

        /*If nic_control_word[vid] is not NFP_NET_CFG_CTRL_ENABLE and
         * NFP_NET_CFG_CTRL_ENABLE is passed to the function, then it
         * must be NFP_NET_CFG_CTRL_ENABLE*/
        control = NFP_NET_CFG_CTRL_ENABLE;
        update = NFD_CFG_PF_LEGAL_UPD & ~NFP_NET_CFG_UPDATE_BPF; //BPF updates tested separately

        if (process_pf_reconfig(control, update, vid, vnic, &cfg_msg)) {
            test_fail();
        }
        
        test_control = get_nic_control_word(NIC_PCI, vid);
        test_assert_equal(test_control & NFP_NET_CFG_CTRL_ENABLE, NFP_NET_CFG_CTRL_ENABLE);
    }

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

