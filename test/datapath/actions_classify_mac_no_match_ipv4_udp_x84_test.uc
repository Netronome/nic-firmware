/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x5
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x0
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0xdeadbeef

#include "pkt_vlan_ipv4_udp_x84.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>
#include "actions_classify_veb_insertion.uc"

.reg key[2]
.reg action[2]

move(key[0], 0x08801234)
move(key[1], 0x88888888)
move(action[0], 0xeeffc000)
move(action[1], 0xefbeadde)

veb_entry_insert(key, action, continue#)
continue#:

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]

test_assert_equal($__actions[0], 0x5)
test_assert_equal($__actions[1], 0x0)

alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
nop
local_csr_wr[T_INDEX, __actions_t_idx]
nop
nop
nop

alu[BF_A(pkt_vec, PV_VLAN_ID_bf), --, B, 0]

__actions_veb_lookup(pkt_vec, discards_filter_mac#)

test_fail()

discards_filter_mac#:

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
