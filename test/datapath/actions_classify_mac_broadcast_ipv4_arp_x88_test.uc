/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x0011
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x22334455
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0xdeadbeef

#include "pkt_ipv4_arp_x88.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>

.reg expected_pv_broadcast
.reg pkt_len


pv_get_length(pkt_len, pkt_vec)


local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]
pv_invalidate_cache(pkt_vec)

test_assert_equal($__actions[0], 0x0011)
test_assert_equal($__actions[1], 0x22334455)

alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
nop
local_csr_wr[T_INDEX, __actions_t_idx]
nop
nop
nop

__actions_veb_lookup(pkt_vec, discards_filter_mac#)

test_assert_equal(*$index++, 0xc0ffee)
test_assert_equal(*$index++, 0xdeadbeef)

test_pass()

discards_filter_mac#:
test_fail()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
