/*
 * Copyright (C) 2018-2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file            actions_l2_switch_wire_match_ipv4_udp_x88_test.uc
 * @brief           Tests the L2 switch (wire) action with UDP traffic.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x0011
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x22334455
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0xdeadbeef
;TEST_INIT_EXEC nfp-rtsym _mac_lkup_tbl:0x1540 0x04488cd1
;TEST_INIT_EXEC nfp-rtsym _mac_lkup_tbl:0x154C 0x40006000
;TEST_INIT_EXEC nfp-rtsym i32.NIC_CFG_INSTR_TBL:0x6000 0x44554D4D

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

test_assert_equal(*$index++, 0x44554D4D)

test_pass()

mac_not_found#:
test_fail()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
