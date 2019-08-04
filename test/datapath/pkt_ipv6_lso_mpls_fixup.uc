/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem emem0:0x80  0x00154d12 0x2cc60000 0x0b000300 0x88470000
;TEST_INIT_EXEC nfp-mem emem0:0x90  0x21006fff 0xffffff00 0x06fffe80 0x00000000
;TEST_INIT_EXEC nfp-mem emem0:0xa0  0x00000200 0x0bfffe00 0x03003555 0x55556666
;TEST_INIT_EXEC nfp-mem emem0:0xb0  0x66667777 0x77778888 0x8888ffff 0xffff0000
;TEST_INIT_EXEC nfp-mem emem0:0xc0  0x0000ffff 0xffff51ff 0xffffffff 0xffff6acf
;TEST_INIT_EXEC nfp-mem emem0:0xd0  0x14990000

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg volatile pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x54)
move(pkt_vec[1], 0x13000000)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
