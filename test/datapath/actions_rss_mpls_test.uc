/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x7fe3
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xff3f8c02

#include "pkt_ipv4_udp_x88.uc"

#include "actions_rss.uc"

#include <bitfields.uc>

.reg tmp
/* must create true MPLS packets. RSS now run over MPLS packets
alu[tmp, --, B, BF_A(pkt_vec, PV_MPD_bf)]
alu[tmp, tmp, OR, 1, <<BF_L(PV_MPD_bf)]
alu[BF_A(pkt_vec, PV_MPD_bf), --, B, tmp]
rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), 0)

alu[tmp, --, B, BF_A(pkt_vec, PV_MPD_bf)]
alu[tmp, tmp, OR, 2, <<BF_L(PV_MPD_bf)]
alu[BF_A(pkt_vec, PV_MPD_bf), --, B, tmp]
rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), 0)

alu[tmp, --, B, BF_A(pkt_vec, PV_MPD_bf)]
alu[tmp, tmp, OR, 3, <<BF_L(PV_MPD_bf)]
alu[BF_A(pkt_vec, PV_MPD_bf), --, B, tmp]
rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), 0)
*/

test_pass()
