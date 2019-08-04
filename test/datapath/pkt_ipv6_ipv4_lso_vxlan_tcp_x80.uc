/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem emem0:0x80     0x00154d0a 0x0d1a6805 0xca306ab8 0x86dd6aaa
;TEST_INIT_EXEC nfp-mem emem0:0x90     0xaaaaff00 0x11fffe80 0x00000000 0x00000200
;TEST_INIT_EXEC nfp-mem emem0:0xa0     0x0bfffe00 0x03003555 0x55556666 0x66667777
;TEST_INIT_EXEC nfp-mem emem0:0xb0     0x77778888 0x8888d87e 0x12b5ff00 0x00000800
;TEST_INIT_EXEC nfp-mem emem0:0xc0     0x0000ffff 0xff00404d 0x8e6f97ad 0x001e101f
;TEST_INIT_EXEC nfp-mem emem0:0xd0     0x00010800 0x4555ff00 0x7a9f4000 0x4006ffff
;TEST_INIT_EXEC nfp-mem emem0:0xe0     0xc0a80164 0xd5c7b3a6 0xcb580050 0xea8d9a10
;TEST_INIT_EXEC nfp-mem emem0:0xf0     0xffffffff 0x51ffffff 0xffffffff 0x97ae878f
;TEST_INIT_EXEC nfp-mem emem0:0x100    0x08377a4d 0x85a1fec4 0x97a27c00 0x784648ea
;TEST_INIT_EXEC nfp-mem emem0:0x110    0x31ab0538 0xac9ca16e 0x8a809e58 0xa6ffc15f

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
move(pkt_vec[0], 0xa0)
move(pkt_vec[1], 0x13000000)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
