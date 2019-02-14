/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
    Tests the process_pf_reconfig funtion in app_master
*/

#include "defines.h"
#include "test.c"
#include "vnic_setup.c"
#include "app_private.c"
#include "app_control_lib.c"
#include "app_config_tables.c"
#include "action_parse.c"
#include "nfd_cfg_base_decl.c"

void test(int pcie) {
    uint32_t type, vnic, vid, control, i;
    struct nfd_cfg_msg cfg_msg;
    single_ctx_test();

    for (vid = 0; vid < NVNICS; vid++) {

        reset_cfg_msg(&cfg_msg, vid, 0);

        NFD_VID2VNIC(type, vnic, vid);

        if (type == NFD_VNIC_TYPE_CTRL) {

            control = NFD_CFG_CTRL_CAP;
            if(process_ctrl_reconfig(pcie, control, vid, &cfg_msg))
                test_fail();

            verify_wire_action_list(pcie, vnic);

            for (i = 0; i < NFD_VID_MAXQS(vid); ++i)
                verify_host_action_list(pcie, NFD_VID2QID(vid, i));
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
