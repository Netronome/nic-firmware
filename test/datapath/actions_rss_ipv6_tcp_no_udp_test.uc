/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xf0bf

#include "pkt_ipv6_tcp_x88.uc"

#include "actions_rss.uc"

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
rss_validate(pkt_vec, NFP_NET_RSS_IPV6_TCP, test_assert_equal, 0x619df87b)

rss_validate_range(pkt_vec, NFP_NET_RSS_IPV6_TCP, excl, 0, (14 + 8))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV6_TCP, incl, (14 + 8), (14 + 8 + 32 + 4))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV6_TCP, excl, (14 + 8 + 32 + 4), pkt_len)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
