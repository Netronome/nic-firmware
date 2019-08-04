/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80     0x00000000 0x00000000 0x00154d0a 0x0d1a6805
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90     0xca306ab8 0x08004500 0x007ede06 0x40004011
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0     0x50640501 0x01020501 0x0101d87e 0x12b5006a
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0     0x00000800 0x00000000 0x0000404d 0x8e6f97ad
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0     0x001e101f 0x00010800 0x4500004c 0x7a9f0000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0     0x40067492 0xc0a80164 0xd5c7b3a6 0xcb580050
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0     0xea8d9a10 0xb3b6fc8d 0x5019ffff 0x51060000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0     0x97ae878f 0x08377a4d 0x85a1fec4 0x97a27c00
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100    0x784648ea 0x31ab0538 0xac9ca16e 0x8a809e58
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110    0xa6ffc15f

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x8c)
move(pkt_vec[2], 0x88)
move(pkt_vec[3], 0x62)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) | ((14 + 20) << 16) |
                 ((14 + 20 + 8 + 8 + 14) << 8) |
                 (14 + 20 + 8 + 8 + 14 + 20)))
