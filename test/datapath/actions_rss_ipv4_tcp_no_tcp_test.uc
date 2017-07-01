;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_61=0x600b

#include "pkt_ipv4_tcp_x88.uc"

#include <actions.uc>
#include "actions_rss.uc"

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
rss_validate(pkt_vec, NFP_NET_RSS_IPV4, test_assert_equal, 0xce60ab57)

rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4, excl, 0, (14 + 12))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4, incl, (14 + 12), (14 + 12 + 8))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV4, excl, (14 + 12 + 8), pkt_len)

test_pass()
