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
#include "app_mac_vlan_config_cmsg.c"
#include "app_control_lib.c"
#include "nfd_cfg_base_decl.c"

void test(int pcie) {
    uint32_t type, vnic, vid, pf, control, update;
    struct nfd_cfg_msg cfg_msg;

    for (pf = 0; pf < NFD_MAX_PFS; pf++) {

        vid = NFD_PF2VID(pf);
        NFD_VID2VNIC(type, vnic, vid);

        reset_cfg_msg(&cfg_msg, vid, 0);

        //Invalid control, valid update
        control = ~NFD_CFG_PF_CAP;
        update = NFD_CFG_PF_LEGAL_UPD & ~NFP_NET_CFG_UPDATE_BPF; //BPF updates tested separately
        if (process_pf_reconfig(pcie, control, update, vid, vnic, &cfg_msg)) {
             if(cfg_msg.error == 0)
                 test_fail();
        } else {
            test_fail();
        }

        //Valid control, invalid update
        control = NFD_CFG_PF_CAP;
        update = ~NFD_CFG_PF_LEGAL_UPD;
        if (process_pf_reconfig(pcie, control, update, vid, vnic, &cfg_msg)) {
             if(cfg_msg.error == 0)
                 test_fail();
        } else {
            test_fail();
        }

        //invalid control, invalid update
        control = ~NFD_CFG_PF_CAP;
        update = ~NFD_CFG_PF_LEGAL_UPD;
        if (process_pf_reconfig(pcie, control, update, vid, vnic, &cfg_msg)) {
             if(cfg_msg.error == 0)
                 test_fail();
        } else {
            test_fail();
        }
    }

    test_pass();
}

void main() {
    int  pcie;
    single_ctx_test();

    for (pcie = 0; pcie < NFD_MAX_ISL; pcie++) {
        if (pcie_is_present(pcie))
            test(pcie);
    }

    test_pass();
}
