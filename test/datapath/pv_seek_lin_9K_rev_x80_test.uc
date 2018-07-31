#include <single_ctx_test.uc>

#include "pkt_inc_pat_9K_x80.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

#macro fail_alloc_macro
    br[fail#]
#endm

.reg increment
.reg offset
.reg expected
.reg tested
.reg tmp
.reg pkt_num

#define PKT_NUM_i 0
#while PKT_NUM_i < 0x100
    move(pkt_num, PKT_NUM_i)
    pkt_buf_free_ctm_buffer(--, pkt_num)
    #define_eval PKT_NUM_i (PKT_NUM_i + 1)
#endloop
#undef PKT_NUM_i

pkt_buf_alloc_ctm(pkt_num, 3, fail#, fail_alloc_macro)

test_assert_equal(pkt_num, 0)

move(pkt_vec[2], 0x80000080)

move(offset, 9212)
move(increment, 0x00020002)

pv_seek(pkt_vec, offset, PV_SEEK_REVERSE)

move(tested, 0xffff0000)
alu[tested, tested, AND, *$index--]
move(expected, 0x11fe0000)
test_assert_equal(tested, expected)

move(expected, 0x11fc11fd)
alu[offset, offset, -, 4]

.while (offset > 0)
    move(tested, *$index--)
    test_assert_equal(tested, expected)
    alu[expected, expected, -, increment]
    alu[offset, offset, -, 4]
    alu[tmp, offset, AND, 127]
    .if(tmp==124)
        pv_seek(pkt_vec, offset, PV_SEEK_REVERSE)
    .endif
.endw

test_pass()

fail#:
test_fail()
