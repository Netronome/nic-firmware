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

.reg csum_type
.reg ctm_base
.reg offsets
.reg pkt_offset
.reg pms_offset
.reg pkt_vec[PV_SIZE_LW]
.reg read $pms[5]
.xfer_order $pms
.sig sig_read

.reg expected_mac_prepend

move(BF_A(pkt_vec, PV_NUMBER_bf), 0)
move(BF_A(pkt_vec, PV_MU_ADDR_bf), 0)

move(pkt_offset, 44)
.while (pkt_offset < 253)
    move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
    pv_get_ctm_base(ctm_base, pkt_vec)
    immed[csum_type, 0]
    .while (csum_type < 4)
        move(BF_A(pkt_vec, PV_CSUM_OFFLOAD_bf), csum_type)
        pv_write_nbi_meta(pms_offset, pkt_vec, fail#)
        mem[read32, $pms[0], ctm_base, <<8, pms_offset, 5], ctx_swap[sig_read]
        alu[offsets, 0x7, AND, $pms[0], >>24]
        alu[expected_mac_prepend, --, B, csum_type, <<30]
        .if (offsets < 4)
            test_assert_equal($pms[2], expected_mac_prepend)
        .else
            test_assert_equal($pms[4], expected_mac_prepend)
        .endif
        alu[csum_type, csum_type, +, 1]
    .endw
   alu[pkt_offset, pkt_offset, +, 1]
.endw

test_pass()

fail#:

test_fail()
