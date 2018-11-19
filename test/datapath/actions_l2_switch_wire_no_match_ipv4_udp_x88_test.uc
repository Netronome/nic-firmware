/*
 * Copyright (C) 2018-2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file            actions_l2_switch_wire_match_ipv4_udp_x88_test.uc
 * @brief           Tests the L2 switch (wire) action with UDP traffic.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x0011

#include "pkt_ipv4_udp_x88.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>
#include "single_ctx_test.uc"


alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
local_csr_wr[T_INDEX, __actions_t_idx]
nop
nop
nop

__actions_l2_switch_wire(pkt_vec, mac_not_found#)

test_fail()

mac_not_found#:
test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
