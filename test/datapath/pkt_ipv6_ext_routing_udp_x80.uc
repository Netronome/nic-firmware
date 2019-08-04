/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00163ec4 0x23450000 0x0b000200 0x86dd6030
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x00000010 0x2bfffe80 0x00000000 0x00000200
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x0bfffe00 0x02003555 0x55556666 0x66667777
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x77778888 0x88881100 0x00000000 0x0000003f
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0x003f0008 0x9b680c79 0x8ce90000

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x46)
move(pkt_vec[2], 0x80)
move(pkt_vec[3], 1)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) | ((14 + 40 + 8) << 16) | (14 << 8) | (14 + 40 + 8)))
