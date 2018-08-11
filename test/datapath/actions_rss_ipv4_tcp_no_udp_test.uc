;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x7fe3
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xff3f8c02

#include "pkt_ipv4_tcp_x88.uc"

#include <actions.uc>
#include "actions_rss.uc"

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
rss_validate(pkt_vec, NFP_NET_RSS_IPV4_TCP, test_assert_equal, 0x3bf00e81)

rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4_TCP, excl, 0, (14 + 12))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4_TCP, incl, (14 + 12), (14 + 12 + 8 + 4))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4_TCP, excl, (14 + 12 + 8 + 4), pkt_len)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
