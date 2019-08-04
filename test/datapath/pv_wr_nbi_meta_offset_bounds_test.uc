/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg pkt_offset
.reg pms_offset
.reg pkt_vec[PV_SIZE_LW]

move(BF_A(pkt_vec, PV_NUMBER_bf), 0)
move(BF_A(pkt_vec, PV_MU_ADDR_bf), 0)
move(BF_A(pkt_vec, PV_CSUM_OFFLOAD_bf), 0)

move(pkt_offset, 0)
.while (pkt_offset < 44)
    move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
    pv_write_nbi_meta(pms_offset, pkt_vec, expected_fail_lower_bound#]
    test_fail()
    expected_fail_lower_bound#:
    alu[pkt_offset, pkt_offset, +, 1]
.endw

.while (pkt_offset < 253)
    move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
    pv_write_nbi_meta(pms_offset, pkt_vec, fail#)
    alu[pkt_offset, pkt_offset, +, 1]
.endw

.while (pkt_offset < 16383)
    move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
    pv_write_nbi_meta(pms_offset, pkt_vec, expected_fail_upper_bound#]
    test_fail()
    expected_fail_upper_bound#:
    alu[pkt_offset, pkt_offset, +, 1]
.endw

test_pass()

fail#:

test_fail()
