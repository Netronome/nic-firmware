;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x7fe3
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xff3f8c02

#include "pkt_ipv6_udp_x88.uc"

#include <actions.uc>
#include "actions_rss.uc"

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
rss_validate(pkt_vec, NFP_NET_RSS_IPV6_UDP, test_assert_equal, 0x5333e499)

rss_validate_range(pkt_vec, NFP_NET_RSS_IPV6_UDP, excl, 0, (14 + 8))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV6_UDP, incl, (14 + 8), (14 + 8 + 32 + 4))
rss_validate_range(pkt_vec, NFP_NET_RSS_IPV6_UDP, excl, (14 + 8 + 32 + 4), pkt_len)

test_pass()
