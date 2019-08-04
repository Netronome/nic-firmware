/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x88  0x000001ab 0xcdef0000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x01020304 0x08004500 0x00518b94 0x04004006
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x00000a02 0x02020a01 0x01010400 0x00507492
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x1fa2493a 0x13dd5012 0xaaaa0000 0x00010001
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0x02030405 0x06070809 0x0a0b0c0d 0x0e0f1011
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0  0x12131415 0x16171819 0x1a1b1c1d 0x1e1f2021
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0  0x22232425 0x26272800

// Correct IPv4 CSUM: 0xd40d
// Correct TCP CSUM: 0x52cb

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
alu[BF_A(pkt_vec, PV_OFFSET_bf), BF_A(pkt_vec, PV_OFFSET_bf), OR, 0x88]

move(pkt_vec[0], 95)
move(pkt_vec[3], 2)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], 0x0e220e22)


