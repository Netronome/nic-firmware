/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00000000 0x00000000 0x00000000 0x86dd6000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x00000010 0x117f0123 0x456789ab 0xcdef0000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x00000000 0x0001fedc 0xba987654 0x32100000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x00000000 0xfffffa00 0x270f0010 0x0000fedc
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0xba987654 0x32100000

// Correct UDP CSUM: 0x7ce3

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_num
move(pkt_num, 0)
.while(pkt_num < 0x100)
    pkt_buf_free_ctm_buffer(--, pkt_num)
    alu[pkt_num, pkt_num, +, 1]
.endw
pkt_buf_alloc_ctm(pkt_num, 3, --, test_fail)
test_assert_equal(pkt_num, 0)

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)

bits_set__sz1(BF_AL(pkt_vec, PV_CTM_ALLOCATED_bf), 1)
bits_set__sz1(BF_AL(pkt_vec, PV_CBS_bf), 3)
alu[BF_A(pkt_vec, PV_OFFSET_bf), BF_A(pkt_vec, PV_OFFSET_bf), OR, 0x80]

move(pkt_vec[0], 70)
move(pkt_vec[3], 1)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], 0x0e360e36)


