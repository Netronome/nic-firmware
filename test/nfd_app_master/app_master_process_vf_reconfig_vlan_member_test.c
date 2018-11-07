/*
 * Copyright 2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file        app_master_process_vf_reconfig_vlan_member_test.c
 * @brief       Tests the process_vf_reconfig funtion in app_master
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//TEST_REQ_BLM
//TEST_REQ_RESET

#include "defines.h"
#include "test.c"
#include "vnic_setup.c"
#include "app_master_test.h"
#include "action_parse.c"
#include "app_private.c"
#include "app_config_tables.c"
#include "nic_tables.c"
#include "map_cmsg_rx.c"
#include "app_control_lib.c"
#include "nfd_cfg_base_decl.c"

#define VLAN_ID 1 //arbitrary

static void test(uint32_t pcie)
{
    uint32_t type, vnic, vid, control, update, vlan_id;
    int pf, vf;
    struct nfd_cfg_msg cfg_msg;
    __xread uint64_t vlan_members;

    //First indicate PF's are enabled
    for (pf = 0; pf < NFD_MAX_PFS; pf++) {
        set_nic_control_word(pcie, NFD_PF2VID(pf),
                            get_nic_control_word(pcie,
                            NFD_PF2VID(pf)) | NFP_NET_CFG_CTRL_ENABLE);

        setup_pf_mac(pcie, NFD_PF2VID(pf), TEST_MAC);
    }

    for (vf = 0; vf < NFD_MAX_VFS; vf++) {

        reset_cfg_msg(&cfg_msg, vid, 0);
        vid = NFD_VF2VID(vf);
        NFD_VID2VNIC(type, vnic, vid);

        setup_vf_mac(pcie, vid, 0);
        setup_sriov_cfg_data(pcie, vf, 0, VLAN_ID + vf,
                NFD_VF_CFG_CTRL_LINK_STATE_ENABLE | (0 << NFD_VF_CFG_CTRL_TRUSTED_shf));

        control = NFD_CFG_VF_CAP;
        update = NFD_CFG_VF_LEGAL_UPD;
        if (process_vf_reconfig(pcie, control, update, vid, &cfg_msg)) {
            test_fail();
        }
        load_vlan_members(pcie, (VLAN_ID + vf), &vlan_members);
        test_assert_equal_64(vlan_members & (1ull << vid), (1ull << vid));
    }
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
