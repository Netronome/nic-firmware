;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x600f

#include <bitfields.uc>

#include <actions.uc>
#include "actions_rss.uc"

#include "pkt_ipv4_tcp_x88.uc"

.reg queue

move(queue, 0)
.while (queue < 256)
    rss_reset_test(pkt_vec)
    bitfield_insert__sz2(BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf), queue)
    __actions_rss(pkt_vec)
    test_assert_unequal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
    test_assert(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf) > 0)
    test_assert(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf) <= 0x80)
    alu[queue, queue, +, 1]
.endw

move(queue, 0)
.while (queue < 0x2f)
    rss_reset_test(pkt_vec)
    bitfield_insert__sz2(BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf), queue)
    bits_set(BF_AL(pkt_vec, PV_QUEUE_SELECTED_bf), 1)
    __actions_rss(pkt_vec)
    test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
    test_assert_equal(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf), queue)
    alu[queue, queue, +, 1]
.endw

rss_reset_test(pkt_vec)
bitfield_insert__sz2(BF_AML(pkt_vec, PV_QUEUE_OFFSET_bf), queue)
bits_set(BF_AL(pkt_vec, PV_QUEUE_SELECTED_bf), 1)
__actions_rss(pkt_vec)
test_assert_unequal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)
//test_assert(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf) > 0)
test_assert(BF_A(pkt_vec, PV_QUEUE_OFFSET_bf) <= 0x80)

test_pass()
