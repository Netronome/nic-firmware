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
.reg pkt_offset
.reg pms_offset
.reg pkt_vec[PV_SIZE_LW]
.reg tested
.reg read $pms
.sig sig_read

move(BF_A(pkt_vec, PV_NUMBER_bf), 0)
move(BF_A(pkt_vec, PV_MU_ADDR_bf), 0)
move(BF_A(pkt_vec, PV_CSUM_OFFLOAD_bf), 0)

move(pkt_offset, 44)
.while (pkt_offset < 253)
    move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
    pv_write_nbi_meta(pms_offset, pkt_vec, fail#)
    pv_get_ctm_base(ctm_base, pkt_vec)
    mem[read32, $pms, ctm_base, <<8, pms_offset, 1], ctx_swap[sig_read]
    alu[tested, $pms, AND, 0x80, <<24]
    test_assert_equal(tested, 0)
    alu[pkt_offset, pkt_offset, +, 1]
.endw

test_pass()

fail#:

test_fail()
