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
.reg pms_offset
.reg pkt_vec[PV_SIZE_LW]
.reg read $nbi_meta[2]
.xfer_order $nbi_meta
.sig sig_read
.reg pkt_num

#define PKT_NUM_i 0
#while PKT_NUM_i < 0x100
    move(pkt_num, PKT_NUM_i)
    pkt_buf_free_ctm_buffer(--, pkt_num)
    #define_eval PKT_NUM_i (PKT_NUM_i + 1)
#endloop
#undef PKT_NUM_i

move(BF_A(pkt_vec, PV_NUMBER_bf), 0x38a4965)
move(BF_A(pkt_vec, PV_MU_ADDR_bf), 0xfb7ae13c)
move(BF_A(pkt_vec, PV_OFFSET_bf), 0x80)
move(BF_A(pkt_vec, PV_CSUM_OFFLOAD_bf), 0)

pv_write_nbi_meta(pms_offset, pkt_vec, fail#]

move(ctm_base, 0)
mem[read32, $nbi_meta[0], ctm_base, 0, 2], ctx_swap[sig_read]

test_assert_equal($nbi_meta[0], 0x38a4965)
test_assert_equal($nbi_meta[1], 0x9b7ae13c)

test_pass()

fail#:

test_fail()
