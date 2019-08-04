/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_inc_pat_64B_x88.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg expected
.reg tested

move(expected, 0x0f101112)

// 16th byte should be word aligned
pv_seek(pkt_vec, 14)
move(tested, *$index)
test_assert_equal(tested, expected)

// byte_aligned T_INDEX should agree
byte_align_be[--, *$index++]
byte_align_be[tested, *$index]
test_assert_equal(tested, expected)

test_pass()

PV_SEEK_SUBROUTINE#:
    pv_seek_subroutine(pkt_vec)
