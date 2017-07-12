;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x600f

#include <actions.uc>
#include "actions_rss.uc"

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, 8)

rss_reset_test(pkt_vec)
__actions_rss(pkt_vec)

test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OUT_bf), 0)

test_pass()
