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

void main() {
    uint32_t control, vid, ctrl;
    struct nfd_cfg_msg cfg_msg;
    __xread unsigned int link_state;

    single_ctx_test();
    for (ctrl = 0; ctrl < NFD_MAX_CTRL; ctrl++) {

        vid = NFD_CTRL2VID(ctrl);

        //test link status: NO LINK (DISABLE)
        reset_cfg_msg(&cfg_msg, vid, 0);

        control = NFD_CFG_CTRL_CAP & ~NFP_NET_CFG_CTRL_ENABLE;

        if(process_ctrl_reconfig(control, vid, &cfg_msg))
            test_fail();

        mem_read32(&link_state, (NFD_CFG_BAR_ISL(PCIE_ISL, vid) + NFP_NET_CFG_STS), sizeof link_state);
        test_assert_equal(link_state, 0);

    }

    test_pass();
}
