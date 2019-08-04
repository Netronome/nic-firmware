/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_inc_pat_256B_x88.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg increment
.reg offset
.reg expected_even
.reg expected_odd
.reg tested

move(offset, 0)
move(increment, 0x0202)
move(expected_even, 0x0102)
move(expected_odd, 0x0203)

pv_seek(pkt_vec, 0)
byte_align_be[--, *$index++]

.while (offset < 251)
    byte_align_be[tested, *$index++]
    alu[tested, --, B, tested, >>16]
    .if ((offset & 1) == 0)
        test_assert_equal(tested, expected_even)
        alu[expected_even, expected_even, +, increment]
    .else
        test_assert_equal(tested, expected_odd)
        alu[expected_odd, expected_odd, +, increment]
    .endif
    alu[offset, offset, +, 1]
    pv_seek(pkt_vec, offset)
    byte_align_be[--, *$index++]
.endw

test_pass()

PV_SEEK_SUBROUTINE#:
    pv_seek_subroutine(pkt_vec)
