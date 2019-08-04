/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xffff
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xffffffff
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0xdeadbeef

#include "pkt_vlan_ipv4_udp_x84.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>
#include "actions_classify_veb_insertion.uc"
#include "single_ctx_test.uc"

.reg expected_pv_broadcast
.reg key[2]
.reg action[2]

move(key[0], 0x02a000bb)
move(key[1], 0xccddeeff)
move(action[0], 0xeeffc000)
move(action[1], 0xefbeadde)

move(expected_pv_broadcast, 0x1002a)

veb_entry_insert(key, action, continue#)
continue#:

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]

test_assert_equal($__actions[0], 0xffff)
test_assert_equal($__actions[1], 0xffffffff)

alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
nop
local_csr_wr[T_INDEX, __actions_t_idx]
nop
nop
nop

__actions_veb_lookup(pkt_vec, discards_filter_mac#)

//test_assert_equal(pkt_vec[PV_VLAN_wrd], expected_pv_broadcast)

test_assert_equal(*$index++, 0xc0ffee)
test_assert_equal(*$index++, 0xdeadbeef)

test_pass()

discards_filter_mac#:
error_map_fd#:
lookup_not_found#:
test_fail()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
