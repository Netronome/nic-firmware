/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80     0x00154d0e 0x04a5001b 0x213cac30 0x08004500
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90     0x006e8806 0x40004011 0x8a761400 0x00021400
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0     0x0001a9b3 0x17c1005a 0x00000000 0x65580000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0     0x0b00b69e 0xd2495148 0xfe71d883 0x724f0800
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0     0x4500003c 0x5a114000 0x4006a4a8 0x1e000002
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0     0x1e000001 0xc8190016 0x17b30caf 0x00000000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0     0xa0023908 0xe4370000 0x020405b4 0x0402080a
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0     0xab6d56be 0x00000000 0x01030307

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x7b)
move(pkt_vec[2], 0x80)
move(pkt_vec[3], 0xe2)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) | ((14 + 20) << 16) |
                 ((14 + 20 + 8 + 8 + 14) << 8) |
                 (14 + 20 + 8 + 8 + 14 + 20)))
