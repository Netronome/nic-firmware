/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00000000 0x00000000 0xffffffff 0xffff86c1
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x5ccdfc7e 0x08060001 0x08000604 0x000186c1
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x5ccdfc7e 0x2801042c 0x00000000 0x00002801
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x00000404

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x38)
move(pkt_vec[2], 0x88)
move(pkt_vec[3], 0x6)
move(pkt_vec[4], 0xffc0)
move(pkt_vec[6], (1<<BF_L(PV_QUEUE_IN_TYPE_bf) | 0xfff00))
