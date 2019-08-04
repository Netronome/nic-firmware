/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x080     0x00000000 0x00000000 0x6805ca30 0x6a390015
;TEST_INIT_EXEC nfp-mem i32.ctm:0x090     0x4d0a0d97 0x08004500 0x00fa635b 0x0000002f
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0a0     0x42780a00 0x00010a00 0x0002a000 0x6558f226
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0b0     0x00000000 0x007b001e 0x101f0001 0x404d8e6f
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0c0     0x97ad0800 0x450000cc 0x15fe0000 0x3b06b349
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0d0     0x52c06118 0xc0a80164 0x0050cfd6 0xfaddeff7
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0e0     0xbd1499a9 0x80188102 0x288a0000 0x0101080a
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0f0     0x6597596f 0x2cea31dd 0x9cc6e223 0x704479e4
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100     0xe9f709df 0xf71e0d3a 0xda768c7b 0xace107d3
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110     0x1f761d67 0x1d2f6a42 0x9af29a46 0x9b539afb
;TEST_INIT_EXEC nfp-mem i32.ctm:0x120     0x5b625bba 0x4fcc3ed1 0xd6eade7a 0xfc47db1f
;TEST_INIT_EXEC nfp-mem i32.ctm:0x130     0x0f9c343c 0x59794af3 0x54c969da 0xe982d393
;TEST_INIT_EXEC nfp-mem i32.ctm:0x140     0x67f2cf8c 0x9d959d7d 0x7e2ef9dc 0x60dba2b6
;TEST_INIT_EXEC nfp-mem i32.ctm:0x150     0x7be763ce 0xdf6a0f6f 0xefba1074 0xe1d245ff
;TEST_INIT_EXEC nfp-mem i32.ctm:0x160     0x8be73bbc 0x3bce5cf2 0xb874f2b2 0xdbe51357
;TEST_INIT_EXEC nfp-mem i32.ctm:0x170     0xb8579aaf 0x3a5f6dea 0x74e03cfe 0x93d34fc7
;TEST_INIT_EXEC nfp-mem i32.ctm:0x180     0xbb9cbb9a 0xaeb95c6b 0xb9ee7abd 0xb57b66f7


#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x108)
move(pkt_vec[2], 0x88)
move(pkt_vec[3], 0xc2)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) |
                 ((14 + 20 + 12 + 14) << 8) |
                 (14 + 20 + 12 + 14 + 20)))
