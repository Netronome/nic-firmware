;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x600d

#include "pkt_ipv6_tcp_x88.uc"

#include <actions.uc>
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
