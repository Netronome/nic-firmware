/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem emem0:0x80     0x00154d0a 0x0d1a6805 0xca306ab8 0x080045aa
;TEST_INIT_EXEC nfp-mem emem0:0x90     0xff00de06 0x4000402f 0xffff0501 0x01020501
;TEST_INIT_EXEC nfp-mem emem0:0xa0     0x01012000 0x6558ffff 0xffff404d 0x8e6f97ad
;TEST_INIT_EXEC nfp-mem emem0:0xb0     0x001e101f 0x00010800 0x4555ff00 0x7a9f4000
;TEST_INIT_EXEC nfp-mem emem0:0xc0     0x4006ffff 0xc0a80164 0xd5c7b3a6 0xcb580050
;TEST_INIT_EXEC nfp-mem emem0:0xd0     0xea8d9a10 0xffffffff 0x51ffffff 0xffffffff
;TEST_INIT_EXEC nfp-mem emem0:0xe0     0x97ae878f 0x08377a4d 0x85a1fec4 0x97a27c00
;TEST_INIT_EXEC nfp-mem emem0:0xf0     0x784648ea 0x31ab0538 0xac9ca16e 0x8a809e58
;TEST_INIT_EXEC nfp-mem emem0:0x100    0xa6ffc15f 0x6597596f 0x2cea31dd

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
move(pkt_vec[0], 0x8c)
move(pkt_vec[1], 0x13000000)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
