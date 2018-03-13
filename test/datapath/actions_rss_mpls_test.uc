;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x600f

#include "pkt_ipv4_udp_x88.uc"

#include <actions.uc>
#include "actions_rss.uc"

#include <bitfields.uc>

bitfield_insert__sz2(BF_AML(pkt_vec, PV_PARSE_MPD_bf), 1)
rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), 0)

bitfield_insert__sz2(BF_AML(pkt_vec, PV_PARSE_MPD_bf), 2)
rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), 0)

bitfield_insert__sz2(BF_AML(pkt_vec, PV_PARSE_MPD_bf), 3)
rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)
test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), 0)


test_pass()
