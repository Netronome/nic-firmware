/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-mem emem0:0x80     0x00154d0a 0x0d1a6805 0xca306ab8 0x86dd6aaa
;TEST_INIT_EXEC nfp-mem emem0:0x90     0xaaaaff00 0x2ffffe80 0x00000000 0x00000200
;TEST_INIT_EXEC nfp-mem emem0:0xa0     0x0bfffe00 0x03003555 0x55556666 0x66667777
;TEST_INIT_EXEC nfp-mem emem0:0xb0     0x77778888 0x88882000 0x6558ffff 0xffff404d
;TEST_INIT_EXEC nfp-mem emem0:0xc0     0x8e6f97ad 0x001e101f 0x000186dd 0x65555555
;TEST_INIT_EXEC nfp-mem emem0:0xd0     0xff0006ff 0xfe800000 0x00000000 0x02000bff
;TEST_INIT_EXEC nfp-mem emem0:0xe0     0xfe000300 0x35555555 0x66666666 0x77777777
;TEST_INIT_EXEC nfp-mem emem0:0xf0     0x88888888 0xcb580050 0xea8d9a10 0xffffffff
;TEST_INIT_EXEC nfp-mem emem0:0x100    0x51ffffff 0xffffffff 0x97ae878f 0x08377a4d
;TEST_INIT_EXEC nfp-mem emem0:0x110    0x85a1fec4 0x97a27c00 0x784648ea 0x31ab0538
;TEST_INIT_EXEC nfp-mem emem0:0x120    0xac9ca16e 0x8a809e58 0xa6ffc15f 0x6597596f
;TEST_INIT_EXEC nfp-mem emem0:0x130    0x2cea31dd

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
move(pkt_vec[0], 0xb4)
move(pkt_vec[1], 0x13000000)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
