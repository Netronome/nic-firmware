/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xf0bf

#include <bitfields.uc>

#include "actions_rss.uc"

#include "pkt_ipv4_tcp_x88.uc"

.reg queue
.reg queue_offset

move(queue, 0)
.while (queue < 256)
    rss_reset_test(pkt_vec)
    bitfield_insert__sz2(BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf), queue)
    __actions_rss(pkt_vec)
    test_assert_unequal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
    test_assert(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf) > 0)
    bitfield_extract__sz1(queue_offset, BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf)) ; PV_QUEUE_OFFSET_bf
    test_assert(queue_offset <= 0x80)
    alu[queue, queue, +, 1]
.endw

move(queue, 0)
.while (queue < 0x2f)
    rss_reset_test(pkt_vec)
    bitfield_insert__sz2(BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf), queue)
    bits_set(BF_AL(pkt_vec, PV_QUEUE_SELECTED_bf), 1)
    __actions_rss(pkt_vec)
    test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
    bitfield_extract__sz1(queue_offset, BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf)) ; PV_QUEUE_OFFSET_bf
    test_assert_equal(queue_offset, queue)
    alu[queue, queue, +, 1]
.endw

rss_reset_test(pkt_vec)
bitfield_insert__sz2(BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf), queue)
bits_set(BF_AL(pkt_vec, PV_QUEUE_SELECTED_bf), 1)
__actions_rss(pkt_vec)
//test_assert_unequal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
bitfield_extract__sz1(queue_offset, BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf)) ; PV_QUEUE_OFFSET_bf
test_assert(queue_offset > 0)
test_assert(queue_offset <= 0x80)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
