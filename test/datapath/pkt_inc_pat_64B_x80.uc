/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x01020304 0x05060708 0x090a0b0c 0x0d0e0f10
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x11121314 0x15161718 0x191a1b1c 0x1d1e1f20
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x21222324 0x25262728 0x292a2b2c 0x2d2e2f30
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x31323334 0x35363738 0x393a3b3c

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x3c)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
