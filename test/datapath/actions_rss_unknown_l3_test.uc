/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x7fe3
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xff3f8c02

#include "actions_rss.uc"

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, 8)

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)

bitfield_insert__sz2(BF_AML(pkt_vec, PV_PROTO_bf), 0xff)

test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), 0)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
