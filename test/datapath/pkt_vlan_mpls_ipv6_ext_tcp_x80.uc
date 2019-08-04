/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80   0x00154d0e 0x04a5ffff 0xffffffee 0x81008014
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90   0x88470000 0x21ff6000 0x0000005d 0x3c405555
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0   0x66667777 0x88880000 0x00000000 0x00011111
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0   0x22223333 0x44440000 0x00000000 0x00013c01
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0   0x01280000 0x00000000 0x00000000 0x00003c01
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0   0x01040000 0x00000000 0x00000000 0x00002b01
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0   0x01040000 0x00000000 0x00000000 0x00000602
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0   0x00010000 0x0000aaaa 0xbbbb3333 0x44440000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100  0x00000000 0x00010014 0x00500000 0x00000000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110  0x00005002 0x20009de2 0x00005800


#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x9a)
move(pkt_vec[2], 0x80)
move(pkt_vec[3], 0x40)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], (((14 + 4 + 4) << 24) | ((14 + 4 + 4 + 112) << 16) | ((14 + 4 + 4) << 8) | (14 + 4 + 4 + 112)))
