/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x0011
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x22334455
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0xdeadbeef

#include "pkt_ipv4_multicast_x88.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>

.reg pkt_len


pv_get_length(pkt_len, pkt_vec)
pv_invalidate_cache(pkt_vec)


local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]
nop
nop
nop

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x0011)
test_assert_equal($__actions[1], 0x22334455)

/*
 * The MAC is MC so should not be dropped, even though it does not match.
 * Packet: 01:11:22:33:44:55
 * Action: 00:11:22:33:44:55
 */
__actions_dst_mac_match(pkt_vec, discards_filter_mac#)

/* Ensure the *$index pointer is positioned correctly after the call */
test_assert_equal(*$index++, 0xc0ffee)
test_assert_equal(*$index++, 0xdeadbeef)

test_pass()

discards_filter_mac#:

test_fail()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
