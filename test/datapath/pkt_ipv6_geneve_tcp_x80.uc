/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80     0x00154d0e 0x04a5001b 0x213cac30 0x86dd6aaa
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90     0xaaaaff00 0x11fffe80 0x00000000 0x00000200
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0     0x0bfffe00 0x03003555 0x55556666 0x66667777
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0     0x77778888 0x8888a9b3 0x17c1005a 0x00000000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0     0x65580000 0x0b00b69e 0xd2495148 0xfe71d883
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0     0x724f86dd 0x6aaaaaaa 0xff0006ff 0xfe800000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0     0x00000000 0x02000bff 0xfe000300 0x35555555
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0     0x66666666 0x77777777 0x88888888 0xc8190016
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100    0x17b30caf 0x00000000 0xa0023908 0xe4370000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110    0x020405b4 0x0402080a 0xab6d56be 0x00000000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x120    0x01030307

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0xa4)
move(pkt_vec[2], 0x80)
move(pkt_vec[3], 0xa0)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) | ((14 + 40) << 16) |
                 ((14 + 40 + 8 + 8 + 14) << 8) |
                 (14 + 40 + 8 + 8 + 14 + 40)))
