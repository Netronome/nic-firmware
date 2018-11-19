/*
 * Copyright (C) 2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file          actions_l2_switch_host_match_ipv4_udp_x88_test.uc
 * @brief         Tests the L2 switch (host) action with UDP traffic.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeafbeef
;TEST_INIT_EXEC nfp-rtsym _mac_lkup_tbl:0x1540 0x04488cd1
;TEST_INIT_EXEC nfp-rtsym _mac_lkup_tbl:0x154C 0x40006000
;TEST_INIT_EXEC nfp-rtsym i32.NIC_CFG_INSTR_TBL:0x6000 0x44554D4D

#include "pkt_ipv4_udp_x88.uc"
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

__actions_l2_switch_host(pkt_vec)

test_assert_equal(*$index++, 0x44554D4D)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
