/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

hashmap_alloc_fd(SRIOV_TID, 8, 32, 2000, --, swap, BPF_MAP_TYPE_HASH)

.alloc_mem LM_KEY_BASE_ADDR lmem me (16 * (1 << log2((4 * 4), 1))) 128

#macro veb_entry_insert(key, action, SUCCESS)
.begin

	.reg lm_key_base
	.reg lm_key_offset
	.reg lm_value_offset
	.reg tid

	move(lm_key_base, LM_KEY_BASE_ADDR)
	passert((LM_KEY_BASE_ADDR & 0x7f), "EQ", 0)
	alu[lm_key_offset, lm_key_base, OR, t_idx_ctx, >>(7-(log2((4 * 4), 1)))]
	local_csr_wr[ACTIVE_LM_ADDR_0, lm_key_offset]
	alu[lm_value_offset, lm_key_offset, +, 12]
	nop
	alu[tid, --, b, SRIOV_TID]

	move(*l$index0++, key[0])
	move(*l$index0++, key[1])
	move(*l$index0++, 0)
	move(*l$index0++, action[0])
	move(*l$index0++, action[1])

	//insert sriov entry into hashmap table
	#define HASHMAP_RXFR_COUNT 16
	#define MAP_RDXR $__pv_pkt_data

	#define_eval HASHMAP_TXFR_COUNT 8
	.reg write $__map_txfr[HASHMAP_TXFR_COUNT]
	.xfer_order $__map_txfr
	__hashmap_set($__map_txfr)
	#define MAP_TXFR $__map_txfr

	#define MAP_RXCAM $__pv_pkt_data[16]	/* start at 16 for 8 regs */

	hashmap_ops(tid,
			lm_key_offset,
			lm_value_offset,
			HASHMAP_OP_ADD_ANY,
			error_map_fd#,
			lookup_not_found#,
			HASHMAP_RTN_LMEM,
			--,
			--,
			--,
			swap)
	#undef MAP_RDXR
	#undef HASHMAP_RXFR_COUNT
	#undef HASHMAP_TXFR_COUNT
	#undef MAP_TXFR
	#undef MAP_RXCAM

	pv_invalidate_cache(pkt_vec)

	br[SUCCESS]

	error_map_fd#:
	lookup_not_found#:
	test_fail()

.end
#endm
