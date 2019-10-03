//TEST_REQ_BLM
//TEST_REQ_RESET

/*
    Tests the process_pf_reconfig funtion in app_master
*/

#include "defines.h"
#include "test.c"
#include "app_master_test.h"
#include "vnic_setup.c"
#include "action_parse.c"
#include "app_private.c"
#include "app_config_tables.c"
#include "nic_tables.c"
#include "map_cmsg_rx.c"
#include "app_control_lib.c"
#include "nfd_cfg_base_decl.c"

void test(uint32_t pcie) {
    uint32_t type, vnic, vid, pf, control, update, i;
    struct nfd_cfg_msg cfg_msg;

    for (pf = 0; pf < NFD_MAX_PFS; pf++) {

        vid = NFD_PF2VID(pf);
        NFD_VID2VNIC(type, vnic, vid);

        reset_cfg_msg(&cfg_msg, vid, 0);

        setup_pf_mac(NIC_PCI, vid, TEST_MAC);

        control = NFD_CFG_PF_CAP & ~NFP_NET_CFG_CTRL_PROMISC;
        update = NFD_CFG_PF_LEGAL_UPD & ~NFP_NET_CFG_UPDATE_BPF; //BPF updates tested separately

        if (process_pf_reconfig(control, update, vid, vnic, &cfg_msg)) {
            test_fail();
        }

        verify_wire_action_list(NIC_PCI, vnic);

        for (i = 0; i < NFD_VID_MAXQS(vid); ++i)
            verify_host_action_list(NIC_PCI, NFD_VID2QID(vid, i));
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
