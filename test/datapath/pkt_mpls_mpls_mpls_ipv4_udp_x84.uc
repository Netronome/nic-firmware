/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80   0x00000000 0x22334455 0x66771122 0x33445566
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90   0x88470006 0x40000006 0x40000000 0x01004500
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0   0x01f20001 0x00004011 0x64960a00 0x00010a00
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0   0x00640bb8 0x0fa001de 0x91500001 0x02030405
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0   0x06070809 0x0a0b0c0d 0x0e0f1011 0x12131415
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0   0x16171819 0x1a1b1c1d 0x1e1f2021 0x22232425
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0   0x26272829 0x2a2b2c2d 0x2e2f3031 0x32333435
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0   0x36373839 0x3a3b3c3d 0x3e3f4041 0x42434445
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100  0x46474849 0x4a4b4c4d 0x4e4f5051 0x52535455
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110  0x56575859 0x5a5b5c5d 0x5e5f6061 0x62636465
;TEST_INIT_EXEC nfp-mem i32.ctm:0x120  0x66676869 0x6a6b6c6d

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0xa4)
move(pkt_vec[2], 0x84)
move(pkt_vec[3], 0x43)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], (((14 + 4 + 4 + 4) << 24) | ((14 + 4 + 4 + 4 + 20) << 16) |
                    ((14 + 4 + 4 + 4) << 8) | (14 + 4 + 4 + 4 + 20)))
