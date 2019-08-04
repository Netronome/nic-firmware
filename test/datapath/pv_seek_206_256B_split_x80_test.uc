/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_inc_pat_256B_split_x80.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg expected
.reg tested

// seek entirely in emem
pv_seek(pkt_vec, (192+14))

// Seek field should be 3
move(tested, pkt_vec[4])
move(expected, 0xc0)
test_assert_equal(tested, expected)

// 16th byte should be word aligned
move(tested, *$index)
move(expected, 0xcfd0e1e2)
test_assert_equal(tested, expected)

// byte_aligned T_INDEX should agree
byte_align_be[--, *$index++]
byte_align_be[tested, *$index]
test_assert_equal(tested, expected)

// EXIT_LABEL version should also agree
move(pkt_vec[0], 0x3c)
move(pkt_vec[2], 0x80000080)
move(pkt_vec[4], 0x3fc0)

pv_seek(pkt_vec, (192+14), PV_SEEK_DEFAULT, done#)

#pragma warning(disable:4702)
test_fail()
#pragma warning(default:4702)

done#:
// Seek field should be 3
move(tested, pkt_vec[4])
move(expected, 0xc0)
test_assert_equal(tested, expected)

move(tested, *$index)
move(expected, 0xcfd0e1e2)
test_assert_equal(tested, expected)

test_pass()

PV_SEEK_SUBROUTINE#:
    pv_seek_subroutine(pkt_vec)
