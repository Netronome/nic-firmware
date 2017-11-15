#include <single_ctx_test.uc>

#include "pkt_inc_pat_9K_x80.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg increment
.reg offset
.reg expected
.reg tested
.reg tmp

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
