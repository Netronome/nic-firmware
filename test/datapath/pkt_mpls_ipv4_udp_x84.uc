/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80   0x00000000 0x22334455 0x66771122 0x33445566
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90   0x88470000 0x01004500 0x01f20001 0x00004011
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0   0x64960a00 0x00010a00 0x00640bb8 0x0fa001de
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0   0x91500001 0x02030405 0x06070809 0x0a0b0c0d
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0   0x0e0f1011 0x12131415 0x16171819 0x1a1b1c1d
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0   0x1e1f2021 0x22232425 0x26272829 0x2a2b2c2d
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0   0x2e2f3031 0x32333435 0x36373839 0x3a3b3c3d
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0   0x3e3f4041 0x42434445 0x46474849 0x4a4b4c4d
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100  0x4e4f5051 0x52535455 0x56575859 0x5a5b5c5d
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110  0x5e5f6061 0x62636465 0x66676869 0x6a6b6c6d


#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x9c)
move(pkt_vec[2], 0x84)
move(pkt_vec[3], 0x43)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], (((14 + 4) << 24) | ((14 + 4 + 20) << 16) | ((14 + 4) << 8) | (14 + 4 + 20)))
move(pkt_vec[6], (1<<BF_L(PV_QUEUE_IN_TYPE_bf) | 0xfff00))
//move(pkt_vec[10], (1 << (BF_L(PV_MPD_bf))))
