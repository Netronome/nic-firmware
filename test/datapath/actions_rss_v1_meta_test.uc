/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xffe3
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xff3f8c02

#include "pkt_ipv4_tcp_x88.uc"

#include "actions_rss.uc"

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), NFP_NET_RSS_IPV4_TCP)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
