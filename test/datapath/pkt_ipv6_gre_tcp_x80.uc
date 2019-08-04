/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x080     0x00154d0e 0x04a5001b 0x213cac30 0x86dd6aaa
;TEST_INIT_EXEC nfp-mem i32.ctm:0x090     0xaaaaff00 0x2ffffe80 0x00000000 0x00000200
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0a0     0x0bfffe00 0x03003555 0x55556666 0x66667777
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0b0     0x77778888 0x8888a000 0x6558f226 0x00000000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0c0     0x007b001e 0x101f0001 0x404d8e6f 0x97ad0800
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0d0     0x450000cc 0x15fe0000 0x3b06b349 0x52c06118
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0e0     0xc0a80164 0x0050cfd6 0xfaddeff7 0xbd1499a9
;TEST_INIT_EXEC nfp-mem i32.ctm:0x0f0     0x80188102 0x288a0000 0x0101080a 0x6597596f
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100     0x2cea31dd 0x9cc6e223 0x704479e4 0xe9f709df
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110     0xf71e0d3a 0xda768c7b 0xace107d3 0x1f761d67
;TEST_INIT_EXEC nfp-mem i32.ctm:0x120     0x1d2f6a42 0x9af29a46 0x9b539afb 0x5b625bba
;TEST_INIT_EXEC nfp-mem i32.ctm:0x130     0x4fcc3ed1 0xd6eade7a 0xfc47db1f 0x0f9c343c
;TEST_INIT_EXEC nfp-mem i32.ctm:0x140     0x59794af3 0x54c969da 0xe982d393 0x67f2cf8c
;TEST_INIT_EXEC nfp-mem i32.ctm:0x150     0x9d959d7d 0x7e2ef9dc 0x60dba2b6 0x7be763ce
;TEST_INIT_EXEC nfp-mem i32.ctm:0x160     0xdf6a0f6f 0xefba1074 0xe1d245ff 0x8be73bbc
;TEST_INIT_EXEC nfp-mem i32.ctm:0x170     0x3bce5cf2 0xb874f2b2 0xdbe51357 0xb8579aaf
;TEST_INIT_EXEC nfp-mem i32.ctm:0x180     0x3a5f6dea 0x74e03cfe 0x93d34fc7 0xbb9cbb9a
;TEST_INIT_EXEC nfp-mem i32.ctm:0x190     0xaeb95c6b 0xb9ee7abd 0xb57b66f7
#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x11c)
move(pkt_vec[2], 0x80)
move(pkt_vec[3], 0x82)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) |
                 ((14 + 40 + 12 + 14) << 8) |
                 (14 + 40 + 12 + 14 + 20)))
