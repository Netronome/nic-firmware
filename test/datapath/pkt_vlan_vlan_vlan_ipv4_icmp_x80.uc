/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00154d0e 0x04a50800 0x273d254e 0x81000065
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x81000258 0x81000258 0x08004500 0x003c18f1
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x00008001 0x9e7cc0a8 0x0101c0a8 0x01020800
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x2b5c0200 0x20006162 0x63646566 0x6768696a
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0x6b6c6d6e 0x6f707172 0x73747576 0x77616263
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0  0x64656667 0x68690000

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x56)
move(pkt_vec[2], 0x80)
move(pkt_vec[3], 0x6)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], (((14 + 4 + 4 + 4) << 24) | ((14 + 4 + 4 + 4) << 8)))
