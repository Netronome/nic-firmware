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
    __xread unsigned int link_state;

    single_ctx_test();
    for (ctrl = 0; ctrl < NFD_MAX_CTRL; ctrl++) {

        vid = NFD_CTRL2VID(ctrl);

        //test link status: NO LINK (cfg_msg.error = 1)
        reset_cfg_msg(&cfg_msg, vid, 1);

        control = NFD_CFG_CTRL_CAP & ~NFP_NET_CFG_CTRL_ENABLE;

        if(process_ctrl_reconfig(pcie, control, vid, &cfg_msg))
            test_fail();

        mem_read32(&link_state, (nfd_cfg_bar_base(pcie, vid) + NFP_NET_CFG_STS), sizeof link_state);
        test_assert_equal(link_state, 0);
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
