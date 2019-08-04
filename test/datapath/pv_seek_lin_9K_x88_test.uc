/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_inc_pat_9K_x88.uc"

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

move(pkt_vec[2], 0x80000088)

move(offset, 0)
move(increment, 0x00020002)
move(expected, 0x00010002)

pv_seek(pkt_vec, 0)
byte_align_be[--, *$index++]

.while (offset < 9212)
    byte_align_be[tested, *$index++]
    test_assert_equal(tested, expected)
    alu[expected, expected, +, increment]
    alu[offset, offset, +, 4]
    .if_unsigned((offset & 63) == 0)
        pv_seek(pkt_vec, offset)
        byte_align_be[--, *$index++]
    .endif
.endw

test_pass()

fail#:
test_fail()

PV_SEEK_SUBROUTINE#:
    pv_seek_subroutine(pkt_vec)
