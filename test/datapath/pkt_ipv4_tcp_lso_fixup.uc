/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem emem0:0x80  0x00888888 0x99999999 0xaaaaaaaa 0x080045ff
;TEST_INIT_EXEC nfp-mem emem0:0x90  0xff000000 0x00004006 0xffffc0a8 0x0001c0a8
;TEST_INIT_EXEC nfp-mem emem0:0xa0  0x0002ffff 0xffff0000 0x0000ffff 0xffff51ff
;TEST_INIT_EXEC nfp-mem emem0:0xb0  0xffffffff 0xffff6865 0x6c6c6f20 0x776f726c
;TEST_INIT_EXEC nfp-mem emem0:0xc0  0x640a0000

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

#define pkt_vec  *l$index1
#define pre_meta *l$index2
local_csr_wr[ACTIVE_LM_ADDR_1, 0x80]
local_csr_wr[ACTIVE_LM_ADDR_2, 0xa0]
nop
nop
nop

aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x42)
move(pkt_vec[1], 0x13000000)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
