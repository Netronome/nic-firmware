/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00000000 0x00000000 0x00888888 0x99999999
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0xaaaaaaaa 0x08004500 0x00340000 0x00004006
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0xf970c0a8 0x0001c0a8 0x00020400 0x00500000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x00000000 0x00005000 0x0000985c 0x00006865
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0x6c6c6f20 0x776f726c 0x640a0000 0x00000000

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x42)
move(pkt_vec[2], 0x88)
move(pkt_vec[3], 0x2)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((14 << 24) | ((14 + 20) << 16) | (14 << 8) | (14 + 20)))
