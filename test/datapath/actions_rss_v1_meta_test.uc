;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xe00f

#include "pkt_ipv4_tcp_x88.uc"

#include <actions.uc>
#include "actions_rss.uc"

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), NFP_NET_RSS_IPV4_TCP)

test_pass()
