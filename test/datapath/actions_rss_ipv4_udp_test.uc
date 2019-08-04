/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xf0bf

#include "pkt_ipv4_udp_x88.uc"

#include "actions_rss.uc"

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
rss_validate(pkt_vec, NFP_NET_RSS_IPV4_UDP, test_assert_equal, 0x8090a37d)

rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4_UDP, excl, 0, (14 + 12))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4_UDP, incl, (14 + 12), (14 + 12 + 8 + 4))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4_UDP, excl, (14 + 12 + 8 + 4), pkt_len)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
