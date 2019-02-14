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
#include "app_mac_vlan_config_cmsg.c"
#include "app_control_lib.c"
#include "nfd_cfg_base_decl.c"

void test(uint32_t pcie) {
    uint32_t type, vnic, vid, pf, control, update;
    int vf;
    struct nfd_cfg_msg cfg_msg;

    //First indicate PF's are enabled
    for (pf = 0; pf < NFD_MAX_PFS; pf++) {
        set_nic_control_word(pcie, NFD_PF2VID(pf),
                get_nic_control_word(pcie,
                    NFD_PF2VID(pf)) | NFP_NET_CFG_CTRL_ENABLE);
        setup_pf_mac(pcie, NFD_PF2VID(pf), TEST_MAC);
    }

    for (vf = 0; vf < NFD_MAX_VFS; vf++) {

        vid = NFD_VF2VID(vf);
        NFD_VID2VNIC(type, vnic, vid);

        reset_cfg_msg(&cfg_msg, vid, 0);

        //Invalid control, valid update
        control = ~NFD_CFG_VF_CAP;
        update = NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(pcie, control, update, vid, &cfg_msg)) {
            if(cfg_msg.error == 0)
                 test_fail();
        } else {
            test_fail();
        }

        //valid control, invalid update
        control = NFD_CFG_VF_CAP;
        update = ~NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(pcie, control, update, vid, &cfg_msg)) {
            if(cfg_msg.error == 0)
                 test_fail();
        } else {
            test_fail();
        }

        //Invalid control, invalid update
        control = ~NFD_CFG_VF_CAP;
        update = ~NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(pcie, control, update, vid, &cfg_msg)) {
            if(cfg_msg.error == 0)
                 test_fail();
        } else {
            test_fail();
        }

        ctassert(NFD_MAX_PFS >= 1);
        //Disable PF 0
        set_nic_control_word(pcie, NFD_PF2VID(0),
            get_nic_control_word(pcie,
                NFD_PF2VID(0)) & ~NFP_NET_CFG_CTRL_ENABLE);

        //Valid control, valid update. Must fail b/c PF 0 is disabled
        control = NFD_CFG_VF_CAP;
        update = NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(pcie, control, update, vid, &cfg_msg)) {
            if(cfg_msg.error == 0)
                 test_fail();
        } else {
            test_fail();
        }
    }

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
