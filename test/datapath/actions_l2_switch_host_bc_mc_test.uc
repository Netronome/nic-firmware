/*
 * Copyright (C) 2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file          actions_l2_switch_host_bc_mc_test.uc
 * @brief         Tests the L2 switch (host) action with broadcast
 *                and multicast traffic
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x44554D4D
#include "pkt_bc_ipv4_udp_x88.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>
#include "single_ctx_test.uc"

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]

alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
nop
local_csr_wr[T_INDEX, __actions_t_idx]
nop
nop
nop

bits_set__sz1(BF_AL(pkt_vec, PV_MAC_DST_MC_bf), 1)
__actions_l2_switch_host(pkt_vec)

test_assert_equal(*$index++, 0x44554D4D)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
