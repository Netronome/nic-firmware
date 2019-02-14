/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
   Tests the process_ctrl_reconfig funtion in app_master
   */

#include "defines.h"
#include "test.c"
#include "vnic_setup.c"
#include "app_private.c"
#include "app_control_lib.c"
#include "app_config_tables.c"
#include "nfd_cfg_base_decl.c"

void test(int pcie) {
    uint32_t control, vid, ctrl;
    struct nfd_cfg_msg cfg_msg;

    single_ctx_test();
    for (ctrl = 0; ctrl < NFD_MAX_CTRL; ctrl++) {

        vid = NFD_CTRL2VID(ctrl);

        //test invalid control CAP
        reset_cfg_msg(&cfg_msg, vid, 0);

        control = ~NFD_CFG_CTRL_CAP;

        if(process_ctrl_reconfig(pcie, control, vid, &cfg_msg)) {
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
