#include <single_ctx_test.uc>

#include "pkt_inc_pat_9K_x88.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg increment
.reg offset
.reg expected
.reg tested

move(offset, 0)
move(increment, 0x00020002)
move(expected, 0x00010002)

pv_seek(pkt_vec, 0)

.while (offset < 9212)
    byte_align_be[--, *$index++]
    byte_align_be[tested, *$index]
    test_assert_equal(tested, expected)
    alu[expected, expected, +, increment]
    alu[offset, offset, +, 4]
    pv_seek(pkt_vec, offset)
.endw

test_pass()
