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

.reg ctm_base
.reg delete_bytes
.reg pkt_offset
.reg pms_offset
.reg pkt_vec[PV_SIZE_LW]
.reg read $pms[3]
.xfer_order $pms
.sig sig_read

.reg tested_offset_len
.reg expected_offset_len

move(BF_A(pkt_vec, PV_NUMBER_bf), 0)
move(BF_A(pkt_vec, PV_MU_ADDR_bf), 0)
move(BF_A(pkt_vec, PV_CSUM_OFFLOAD_bf), 0)

move(pkt_offset, 44)
.while (pkt_offset < 253)
    move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
    pv_write_nbi_meta(pms_offset, pkt_vec, fail#)
    pv_get_ctm_base(ctm_base, pkt_vec)
    mem[read32, $pms[0], ctm_base, <<8, pms_offset, 3], ctx_swap[sig_read]

    alu[delete_bytes, 0xff, AND, $pms[0], >>16]
    alu[expected_offset_len, delete_bytes, +, 15]
    alu[expected_offset_len, --, B, expected_offset_len, >>4]

    alu[tested_offset_len, 0x7, AND, $pms[0], >>24]
    test_assert_equal(tested_offset_len, expected_offset_len)
    test_assert_equal($pms[1], 0x04142434)
    .if (expected_offset_len > 3)
        test_assert_equal($pms[2], 0x44546474)
    .endif
    alu[pkt_offset, pkt_offset, +, 1]
.endw

test_pass()

fail#:

test_fail()
