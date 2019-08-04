/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00000000 0x00000000 0x00154d12 0x2cc60000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x0b000300 0x86dd6030 0x00000014 0x06fffe80
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x00000000 0x00000200 0x0bfffe00 0x03003555
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x55556666 0x66667777 0x77778888 0x88880000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0x00000000 0x00000000 0x00005000 0x00004aed
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0  0x00006acf 0x14990000

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x4a)
move(pkt_vec[2], 0x88)
move(pkt_vec[3], 0x0)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) | ((14 + 40) << 16) | (14 << 8) | (14 + 40)))
