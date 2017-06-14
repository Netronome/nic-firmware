/*
 * Copyright (C) 2014-2017,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file        hashmap.uc
 * @brief       basic lookup table implementation.
 *
 *
 *  Subroutine calls:
 *  htab_map_lookup_elem_subr(in_tid, in_lm_key_offset, out_value_addr)
 *  htab_map_update_elem_subr(in_tid, in_lm_key_offset, in_lm_value_offset, out_rc)
 *  htab_map_delete_elem_subr(in_tid, in_lm_key_offset, out_rc)
 *
 *
 * API calls (macro)
 *
 *	  hashmap_alloc_fd(out_fd, in_key_size, in_value_size, in_max_entries, ERROR_LABEL)
 *
 * OP type defines:
 *	HASHMAP_OP_LOOKUP
 *  HASHMAP_OP_ADD
 *	HASHMAP_OP_REMOVE
 *	HASHMAP_OP_GETNEXT
 *
 * return type defines
 *	HASHMAP_RTN_LMEM
 *	HASHMAP_RTN_TINDEX
 *	HASHMAP_RTN_ADDR
 *
 *	  hashmap_ops(	in_fd,				// fd returned from hashmap_alloc_fd()
 *					in_lm_key_addr,		// LM offset for key, key must start of lm offset + 4
 *					in_lm_value_addr, 	// LM offset for value
 *					OP_TYPE, 			// HASHMAP_OP_xxx
 *					INVALID_MAP_LABEL,	// label if in_fd is invalid
 *					NOTFOUND_LABEL,		// label if entry is not found
 *					RTN_OPT,			// HASHMAP_RTN_xxx
 *					out_ent_lw,			// optional, length (in lw) of returned data
 *					out_ent_tindex,		// optional, tindex of returned data
 *					out_ent_addr		// optional, addr of returned data
 *				)
 *
 * example use:
 *#if USE_LM
 *      hashmap_ops(fd, main_lm_key_offset, main_lm_value_offset, HASHMAP_OP_LOOKUP,
 *					error_map_fd#, lookup_not_found#,HASHMAP_RTN_LMEM,--,--,--)
 *#elif USE_TINDEX
 *       hashmap_ops(fd, main_lm_key_offset, main_lm_value_offset, HASHMAP_OP_LOOKUP,
 *					error_map_fd#, lookup_not_found#,HASHMAP_RTN_TINDEX,rtn_len,my_tindex,rtn_addr]
 *       __hashmap_read_field(my_tindex, main_lm_value_offset,
 *					rtn_addr[0], rtn_addr[1],rtn_len,HASHMAP_RTN_LMEM, --, --)
 *#elif USE_ADDR
 *       hashmap_ops(fd, main_lm_key_offset, main_lm_value_offset, HASHMAP_OP_LOOKUP,
 *					error_map_fd#, lookup_not_found#,HASHMAP_RTN_ADDR,rtn_len,--,rtn_addr)
 *#endif
 *
 */
#ifndef __HASHMAP_UC__
#define __HASHMAP_UC__


#include <passert.uc>
#include <stdmac.uc>
#include <aggregate.uc>
#include <timestamp.uc>
#include "unroll.uc"
#include "lm_handle.uc"
#include "camp_hash.uc"

#include <journal.uc>
#include "hashmap_priv.uc"
#include "hashmap_cam.uc"

/*
 * public functions:
 *		hashmap_alloc_fd()
 *		hashmap_get_fd()
 *		hashmap_ops()
 * assumption:
 *		lm_key[0] = fd
 *		lm_key[1..key_sz_lw] = key
 */


/* ********************************* */
/*
 * compile time configuration
 */

#define HASHMAP_PARTITIONS      1
#define HASHMAP_TOTAL_ENTRIES   (1024<<12)
#define HASHMAP_OVERFLOW_ENTRIES (512<<14)
#define HASHMAP_MAX_TID          32
	/* 128=max keys + max value + cam overflow = 40+24+32+32 */
	/* 8=lock + tid = 4+4 */
#define_eval HASHMAP_MAX_ENTRY_SZ    (128)
#define HASHMAP_MAX_KEYS_SZ     (40)			// camp_hash limit 120 bytes
#define HASHMAP_MAX_VALU_SZ		(24)

#define HASHMAP_TXFR_COUNT		16

/* ********************************* */
/* call interface
 *
 */
#define HASHMAP_OP_LOOKUP		3
#define HASHMAP_OP_ADD			4
#define HASHMAP_OP_REMOVE		5
#define HASHMAP_OP_GETNEXT		6
#define HASHMAP_OP_MAX			HASHMAP_OP_GETNEXT

#define HASHMAP_RTN_LMEM		1
#define HASHMAP_RTN_TINDEX		2
#define HASHMAP_RTN_ADDR		3


/* ********************************* */
/*
 * defines
 */

#define_eval HASHMAP_ENTRY_SZ_LW        (HASHMAP_MAX_ENTRY_SZ >> 2)
#define_eval HASHMAP_ENTRY_SZ_SHFT		(LOG2(HASHMAP_MAX_ENTRY_SZ))
#define HASHMAP_LOCK_SZ					8
#define_eval HASHMAP_LOCK_SZ_SHFT		(LOG2(HASHMAP_LOCK_SZ))
#define_eval HASHMAP_LOCK_SZ_LW			(HASHMAP_LOCK_SZ >> 2)

#define HASHMAP_MAX_KEYS_LW				(HASHMAP_MAX_KEYS_SZ >> 2)

#define HASHMAP_NUM_ENTRIES_SHFT		(LOG2(HASHMAP_TOTAL_ENTRIES))
#define HASHMAP_NUM_ENTRIES_MASK		((1<<HASHMAP_NUM_ENTRIES_SHFT)-1)

/* key_value size = max entry size - hashmap descriptor */
#define HASHMAP_MAX_KEY_VALUE_SZ		(HASHMAP_MAX_ENTRY_SZ - 4)
#define HASHMAP_MAX_KEY_VALUE_LW		(HASHMAP_MAX_KEY_VALUE_SZ >> 2)

#define HASHMAP_ENTRIES_PER_BUCKET      8
#define HASHMAP_OV_ENTRY_SZ             ((HASHMAP_ENTRIES_PER_BUCKET * 2) * 4)
/* OV_CAM_OFFSET must be 64-byte aligned */
#define HASHMAP_OV_CAM_OFFSET			(HASHMAP_MAX_ENTRY_SZ - HASHMAP_OV_ENTRY_SZ)
#define HASHMAP_OV_ENTRY_OFFSET         (HASHMAP_ENTRIES_PER_BUCKET * 4)


/* ******************************** */
/* data structures
 */

/*
 * typedef __packed struct {
 *   union {
 *       struct {
 *           uint32_t valid : 1;
 *           uint32_t reserved1: 10;
 *			 uint32_t reserved_ov_idx:4 bit 17..19
 *			 uint32_t reserved_ov:1;	bit 16 - use in state only, not in mem
 *			 uint32_t spare: 1;
 *			 uint32_t lock_excl: 1;		bit 14
 *           uint32_t lock_cnt : 13;
 *       };
 *       uint32_t meta;
 *   };
 *	// following are futures
 *	 union {
 *		struct {
 *			uint32_t lru_ref : 1;
 *			uint32_t reserved: 31;
 *		};
 *		uint32_t flags;
 *	 };
 *   uint32_t spare[2];
 *	 //uint32_t fd;   fd is the first word of the key
 * } __hashmap_descriptor_t;
 *
 */
#define __HASHMAP_DESC_LW				1
#define __HASHMAP_DESC_NDX_META			0
#define __HASHMAP_DESC_NDX_LRU_FLG		1
#define __HASHMAP_DESC_NDX_TID			4
#define __HASHMAP_DESC_VALID_BIT        (30)
#define __HASHMAP_DESC_VALID			(1<<__HASHMAP_DESC_VALID_BIT)
										// Free 29:20
#define __HASHMAP_DESC_OV_BIT			(19)
#define __HASHMAP_DESC_OV_IDX			(16)
#define __HASHMAP_DESC_LOCK_EXCL_BIT    (14)
#define __HASHMAP_DESC_LOCK_EXCL		(1<<__HASHMAP_DESC_LOCK_EXCL_BIT)
#define __HASHMAP_DESC_LOCK_CNT_MSK		(__HASHMAP_DESC_LOCK_EXCL - 1)
#define __HASHMAP_DESC_LRU_REF_BIT      (31)
#define __HASHMAP_DESC_LRU_REF			(1<<__HASHMAP_DESC_LRU_REF_BIT)

/*
 * typedef struct {
 *   __hashmap_descriptor_t  desc;	4 bytes (1 words)
 *   uint32_t                data[HASHMAP_MAX_KEY_VALUE_LW];	key=40,value=24,64 bytes
 *   uint32_t				 ov_cam[8];
 *   uint32_t				 ov_offset[8]
 * } __hashmap_entry_t;
 */
#define __HASHMAP_ENTRY_NDX_DESC	0
#define __HASHMAP_ENTRY_NDX_DATA	0
#define __HASHMAP_ENTRY_NDX_KEY		(__HASHMAP_ENTRY_NDX_DATA)
#define __HASHMAP_ENTRY_KEY_OFFSET  (__HASHMAP_ENTRY_NDX_KEY << 2)


/*
 * FD TBL description
 * entry 0 is reserved:
 * entry 1 is first valid entry
 *
 * typedef struct {               //
 *   uint16_t key_size;           //  in LWs
 *   uint16_t value_size;         //  in LWs
 *   uint32_t max_entries;        //  maximum number of entries
 *	 uint32_t key_mask;
 *	 uint32_t value_mask;
 *   uint32_t num_entries_credits;   // number of free entries
 *	 uint32_t map_type;
 *   uint32_t lru_counts_active;
 *	 uint32_t lru_counts_inactive;
 *	 uint32_t lru_qsize_active;
 *	 uint32_t lru_qsize_inactive;
 *	 uint32_t spares[6];
 * } hashmap_fd_t;
*/

#define __HASHMAP_FD_TBL_SZ_LW		16
#define_eval __HASHMAP_FD_TBL_SZ	(__HASHMAP_FD_TBL_SZ_LW * 4)
#define_eval __HASHMAP_FD_TBL_SHFT	(LOG2(__HASHMAP_FD_TBL_SZ))
#define __HASHMAP_FD_NDX_KEY		0
#define __HASHMAP_FD_NDX_VALUE		0
#define __HASHMAP_FD_NDX_MAX_ENT	1
#define __HASHMAP_FD_NDX_KEY_MASK	2
#define __HASHMAP_FD_NDX_VALUE_MASK	3
#define __HASHMAP_FD_NDX_CUR_CRED	4
#define __HASHMAP_FD_NDX_TYPE		5
#define __HASHMAP_FD_NDX_CNT_ACT	6
#define __HASHMAP_FD_NDX_CNT_INACT	7
#define __HASHMAP_FD_NDX_QCNT_ACT	8
#define __HASHMAP_FD_NDX_QCNT_INACT	9
#define __HASHMAP_FD_NUM_LW_USED	5
#define __HASHMAP_FD_MAX_NUM_LW		10



/* *************************************** */

#macro hashmap_declare_block(NUM_ENTRIES)
	#if (HASHMAP_PARTITIONS == 1)
		.alloc_mem __HASHMAP_DATA_0 emem global	(HASHMAP_MAX_ENTRY_SZ * NUM_ENTRIES)  256
		.init __HASHMAP_DATA_0 0

	#elif (HASHMAP_PARTITIONS == 2)
		.alloc_mem __HASHMAP_DATA_0 emem0 global (HASHMAP_MAX_ENTRY_SZ * (NUM_ENTRIES/2))  256
		.alloc_mem __HASHMAP_DATA_1 emem1 global (HASHMAP_MAX_ENTRY_SZ * (NUM_ENTRIES/2))  256
		.init __HASHMAP_DATA_0 0
		.init __HASHMAP_DATA_1 0

	#else
		.alloc_mem __HASHMAP_DATA_0 emem0 global (HASHMAP_MAX_ENTRY_SZ * (NUM_ENTRIES/3))  256
		.alloc_mem __HASHMAP_DATA_1 emem1 global (HASHMAP_MAX_ENTRY_SZ * (NUM_ENTRIES/3))  256
		.alloc_mem __HASHMAP_DATA_2 emem2 global (HASHMAP_MAX_ENTRY_SZ * (NUM_ENTRIES/3))  256
		.init __HASHMAP_DATA_0 0
		.init __HASHMAP_DATA_1 0
		.init __HASHMAP_DATA_2 0

	#endif

	/* lock table */
	.alloc_mem __HASHMAP_LOCK_TBL emem global (HASHMAP_LOCK_SZ * NUM_ENTRIES) 256
	.init __HASHMAP_LOCK_TBL 0

	/* fd table */
	.alloc_mem __HASHMAP_FD_TBL	imem global (__HASHMAP_FD_TBL_SZ_LW * 4 * HASHMAP_MAX_TID) 256
	.init __HASHMAP_FD_TBL 0

	.reg volatile $map_txfr[HASHMAP_TXFR_COUNT]
	.xfer_order $map_txfr

#endm

#macro hashmap_init()
	hashmap_declare_block(HASHMAP_TOTAL_ENTRIES)
	__hashmap_freelist_init(HASHMAP_OVERFLOW_ENTRIES)
	camp_hash_init(HASHMAP_MAX_KEYS_LW, $map_txfr)
	__hashmap_journal_init()
#endm


/* *************************************** */
/*
 * lookup(fd, key, value)
 *	returns 0 and stores elem into value   if match
 *	return negative error
 *
 * update(fd, key, value)
 *	returns 0 or negative error
 *
 * delete(fd, key)
 *	find and delete element by key
 *
 * getnext(fd, key)
 *   find key and return next key
 */
/*
 * should cache fd table in lmem
 *
 */

#macro __hashmap_rounded_mask(in_val, out_val, out_mask)
.begin
	.reg tmp
	.reg mask
	.reg mval
	.reg val

	alu[tmp, --, b, in_val]
	alu[tmp, tmp, +, 3]
	alu[out_val, tmp, and~, 0x3]

	alu[tmp, out_val, -, in_val]

	move(mask, ~0)
	alu[out_mask, --, b, mask]
	alu[tmp, --, b, tmp, <<3]
	beq[ret#], defer[1]
	alu[mval, --, b, mask]
	alu[--, tmp, or, 0]
	alu[mask, mval, and, mask, >>indirect]
	alu[--, tmp, or, 0]
	alu[out_mask, --, b, mask, <<indirect]
ret#:
.end
#endm


#macro hashmap_alloc_fd(out_tid, key_size, value_size, max_entries, ERROR_LABEL)
.begin
	.reg base
	.reg offset
	.reg rnd_val
	.reg key_value_sz
	.sig create_fd_sig
	.reg tmp
	.reg $tid

	move(base, __HASHMAP_FD_TBL>>8)
	immed[offset, 0]
	immed[$tid, 1]
	mem[test_add, $tid, base, <<8, offset, 1], sig_done[create_fd_sig]
	ctx_arb[create_fd_sig]
	alu[--, HASHMAP_MAX_TID, - , $tid]
	bgt[alloc_fd_cont#], defer[2]
	alu[out_tid, 1, +, $tid]
	alu[offset, --, b, out_tid, <<__HASHMAP_FD_TBL_SHFT]

	mem[sub, $tid, base, <<8, offset, 1], sig_done[create_fd_sig]
	ctx_arb[create_fd_sig], defer[2], br[ERROR_LABEL]
		immed[out_tid, 0]
		nop

alloc_fd_cont#:
	__hashmap_rounded_mask(key_size, rnd_val, $map_txfr[__HASHMAP_FD_NDX_KEY_MASK])
	alu[rnd_val, --, b, rnd_val, >>2]
	ld_field_w_clr[key_value_sz, 1100, rnd_val, <<16]
	__hashmap_rounded_mask(value_size, rnd_val, $map_txfr[__HASHMAP_FD_NDX_VALUE_MASK])
	alu[rnd_val, --, b, rnd_val, >>2]
	ld_field[key_value_sz, 0011, rnd_val]

	alu[$map_txfr[__HASHMAP_FD_NDX_KEY], --, b, key_value_sz]
	move[tmp, max_entries]
	alu[$map_txfr[__HASHMAP_FD_NDX_MAX_ENT], --, b, tmp]
	alu[$map_txfr[__HASHMAP_FD_NDX_CUR_CRED], --, b, tmp]

	ov_start(OV_LENGTH)
	ov_set_use(OV_LENGTH, __HASHMAP_FD_NUM_LW_USED, OVF_SUBTRACT_ONE)
	ov_clean
	mem[atomic_write, $map_txfr[0], base, <<8, offset, max_/**/__HASHMAP_FD_NUM_LW_USED], indirect_ref, ctx_swap[create_fd_sig]

.end
#endm

#macro hashmap_get_fd(in_fd, key_size, value_size, key_mask, value_mask, ERROR_LABEL)
.begin

	.reg base
	.reg offset
	.sig get_fd_sig

	alu[--, in_fd, -, HASHMAP_MAX_TID]
	bge[ERROR_LABEL]

	move(base, __HASHMAP_FD_TBL>>8)
	alu[offset, --, b, in_fd, <<__HASHMAP_FD_TBL_SHFT]
	mem[read32, $map_txfr[0], base, <<8, offset, __HASHMAP_FD_NUM_LW_USED], ctx_swap[get_fd_sig]
	ld_field_w_clr[key_size, 0011, $map_txfr[__HASHMAP_FD_NDX_KEY], >>16]
	ld_field_w_clr[value_size, 0011, $map_txfr[__HASHMAP_FD_NDX_VALUE]]
	alu[key_mask, --, b, $map_txfr[__HASHMAP_FD_NDX_KEY_MASK]]
	alu[value_mask, --, b, $map_txfr[__HASHMAP_FD_NDX_VALUE_MASK]]

.end
#endm

#macro __hashmap_table_return_credits(in_fd)
.begin
	.reg base
	.reg tbl_offset

	move(base, __HASHMAP_FD_TBL>>8)
	alu[tbl_offset, --, b, in_fd, <<__HASHMAP_FD_TBL_SHFT]
	#define __CUR_CRED_OFFSET__ (__HASHMAP_FD_NDX_CUR_CRED * 4)
	alu[tbl_offset, tbl_offset, +, __CUR_CRED_OFFSET__]
	#undef __CUR_CRED_OFFSET__

	mem[incr, --, base, <<8, tbl_offset, 1]
.end
#endm

#macro __hashmap_table_take_credits(in_fd, FULL_LABEL)
.begin
	.reg $fd_credits
	.reg base
	.reg tbl_offset
	.sig fd_inc_sig

	move(base, __HASHMAP_FD_TBL>>8)
	alu[tbl_offset, --, b, in_fd, <<__HASHMAP_FD_TBL_SHFT]
	#define __CUR_CRED_OFFSET__ (__HASHMAP_FD_NDX_CUR_CRED * 4)
	alu[tbl_offset, tbl_offset, +, __CUR_CRED_OFFSET__]
	#undef __CUR_CRED_OFFSET__

	alu[$fd_credits, --, b, 1]
	mem[test_sub, $fd_credits, base, <<8, tbl_offset, 1], sig_done[fd_inc_sig]
	ctx_arb[fd_inc_sig]
	alu[--, $fd_credits, -, 0]
	bgt[ret#], defer[1]
		immed[$fd_credits, 0]
	mem[atomic_write, $fd_credits, base, <<8, tbl_offset, 1], sig_done[fd_inc_sig]
	ctx_arb[fd_inc_sig], br[FULL_LABEL]
ret#:
.end
#endm


#macro __hashmap_lock_init(state, addr_hi, addr_lo, mu_partitions, idx)
.begin

#if (HASHMAP_PARTITIONS == 1)
	move(addr_hi, __HASHMAP_DATA_0 >>8)
#elif (HASHMAP_PARTITIONS == 2)
	alu[--, mu_partitions, -, 0]
	beq[cont#], defer[1]
	move(addr_hi, __HASHMAP_DATA_0 >>8)
	move(addr_hi, __HASHMAP_DATA_1 >>8)
#else (HASHMAP_PARTITIONS == 3)
	alu[--, mu_partitions, -, 0]
	beq[cont#], defer[1]
	move(addr_hi, __HASHMAP_DATA_0 >>8)
	alu[--, mu_partitions, -, 1]
	beq[cont#], defer[2]
	move(addr_hi, __HASHMAP_DATA_1 >>8)
	move(addr_hi, __HASHMAP_DATA_2 >>8)
#endif

cont#:
	immed[state,1]			; state=1
	alu_shf[addr_lo, --, b, idx, <<HASHMAP_ENTRY_SZ_SHFT]
.end
#endm

#macro __hashmap_lock_shared(in_idx, in_tid, NOT_VALID_LABEL, NOT_MATCH_TID)
.begin
	.reg $desc_xfer[2]
	.xfer_order $desc_xfer

	.sig lock_shared_sig
	.reg lk_addr_hi
	.reg lk_addr_lo

	immed[$desc_xfer[0], 1]			;lo
	immed[$desc_xfer[1], 0]			;hi
	move(lk_addr_hi, __HASHMAP_LOCK_TBL >>8)
	alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]

retry_lock#:
	mem[test_add64, $desc_xfer[0], lk_addr_hi, <<8, lk_addr_lo, 1], sig_done[lock_shared_sig]
	ctx_arb[lock_shared_sig]
	br_bclr[$desc_xfer[0], __HASHMAP_DESC_LOCK_EXCL_BIT, ret#]
	mem[sub, $desc_xfer[0], lk_addr_hi, <<8, lk_addr_lo], ctx_swap[lock_shared_sig]
	timestamp_sleep(100)
	br[retry_lock#]

ret#:
	br_bclr[$desc_xfer[0], __HASHMAP_DESC_VALID_BIT, NOT_VALID_LABEL]
	alu[--, in_tid, -, $desc_xfer[1]]
	bne[NOT_MATCH_TID]
.end
#endm /* __hashmap_lock_shared */

#macro __hashmap_lock_upgrade(in_idx, io_state, NO_LOCK_LABEL)
.begin
	.reg $desc_xfer
	.set $desc_xfer
	.sig lock_upgrade_sig
	.sig lock_wait_sig
	.reg cnt
	.reg desc
	.reg lk_addr_hi
	.reg lk_addr_lo

	move(lk_addr_hi, __HASHMAP_LOCK_TBL >>8)
	br_bset[io_state, __HASHMAP_DESC_OV_BIT, get_lock#], defer[2]
	alu[desc, --, b, 1, <<__HASHMAP_DESC_LOCK_EXCL_BIT]
	alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]

	alu[desc, desc, or, 1, <<__HASHMAP_DESC_VALID_BIT]

get_lock#:
	alu[$desc_xfer, --, b, desc]
	mem[test_set, $desc_xfer, lk_addr_hi, <<8, lk_addr_lo,1], sig_done[lock_upgrade_sig]
	ctx_arb[lock_upgrade_sig]
	br_bclr[$desc_xfer, __HASHMAP_DESC_LOCK_EXCL_BIT, has_excl#],defer[1]
		alu[desc, --, b, $desc_xfer]
	alu[$desc_xfer, --, b, 1]
	mem[sub, $desc_xfer, lk_addr_hi, <<8, lk_addr_lo, 1], ctx_swap[lock_upgrade_sig]

	timestamp_sleep(100)

	#define_eval __DESC_OV_MASK ((7 << __HASHMAP_DESC_OV_IDX) | (1 << __HASHMAP_DESC_OV_BIT))
	.reg tmp
	move(tmp, __DESC_OV_MASK)
	alu[io_state, io_state, and~, tmp]
	#undef __DESC_OV_MASK

	br[NO_LOCK_LABEL]

has_excl#:
	// check for shared locks
	move(cnt, __HASHMAP_DESC_LOCK_CNT_MSK)
	alu[cnt, cnt, and, $desc_xfer]
	alu[cnt, cnt, -, 1]
	beq[ret#]
	// wait for shared threads to finish
	timestamp_sleep(50)
	mem[read_atomic, $desc_xfer, lk_addr_hi, <<8, lk_addr_lo, 1], sig_done[lock_wait_sig]
	ctx_arb[lock_wait_sig], br[has_excl#]

ret#:
	alu_shf[io_state, io_state, or, 1, <<__HASHMAP_DESC_LOCK_EXCL_BIT]

.end
#endm /* __hashmap_lock_upgrade  */


#macro __hashmap_lock_release(in_idx, state)
.begin
	.reg imm_ref
	.reg lk_addr_hi
	.reg lk_addr_lo

	move(lk_addr_hi, __HASHMAP_LOCK_TBL >>8)
	alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]
	ld_field_w_clr[imm_ref, 1100, state, <<16]	/* data16, lock->state  */
	alu[imm_ref, imm_ref, or, 2, <<3]			/* ove_data=2 override  */
	alu_shf[--, imm_ref, or, 17, <<7]			/* ov_len (1<<7) | length (16<<8) */
	mem[sub_imm, --, lk_addr_hi, <<8, lk_addr_lo], indirect_ref
	immed[state, 0]
ret#:
.end
#endm	/* __hashmap_lock_release */

#macro __hashmap_lock_release_and_invalidate(in_idx, state)
.begin
	.reg $desc_xfer
	.reg tmp
	.sig lock_rel_invalid_sig
	.reg lk_addr_hi
	.reg lk_addr_lo

	move(lk_addr_hi, __HASHMAP_LOCK_TBL >>8)
	alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]
	alu_shf[tmp, --,b, 1, <<__HASHMAP_DESC_VALID_BIT]
	alu_shf[$desc_xfer, tmp, or, state]
	mem[sub, $desc_xfer, lk_addr_hi, <<8, lk_addr_lo, 1], ctx_swap[lock_rel_invalid_sig]
	immed[state, 0]

	/* TODO for LRU
	 *		clear ref flag
	 *		incr free_credits
	 */
.end
#endm /* __hashmap_lock_release_and_invalidate */


#macro __hashmap_select_1_partition(hash, selection_mu)
	alu[selection_mu, --, b, 0]
#endm

#macro __hashmap_select_2_partition(hash, selection_mu)
	br_bclr(hash, 31, mu_selected#), defer[1]
	alu[selection_mu, --, b, 0]
	alu[selection_mu, --, b, 1]
mu_selected#:
#endm

#macro __hashmap_select_3_partition(hash, selection_mu)
	br=byte[hash, 0, 0x55, mu_selected#], defer[1]
	alu[selection_mu, --, b, 0]
	br=byte[hash, 0, 0xAA, mu_selected#], defer[1]
	alu[selection_mu, --, b, 1]
	alu[selection_mu, --, b, 2]
mu_selected#:
#endm

#macro __hashmap_select_next_1_partition(selection_mu,index, MISS_LABEL)
.begin
	.reg max
	move(max, HASHMAP_TOTAL_ENTRIES)
	alu[selection_mu, --, b, 0]
	alu[index, index, +, 1]
	alu[--, index, -, max]
	bge[MISS_LABEL]
.end
#endm

#macro __hashmap_select_next_2_partition(selection_mu,index,MISS_LABEL)
.begin
	.reg max
	alu[--, selection_mu, -, 0]
	beq[ret#],defer[2]
	alu[selection_mu, --, b, 1]
	move(max, HASHMAP_TOTAL_ENTRIES)

	alu[selection_mu, --, b, 0]
	alu[index, index, +, 1]
	alu[--, index, -, max]
	bge[MISS_LABEL]
ret#:
.end
#endm

#macro __hashmap_select_next_3_partition(selection_mu,index,MISS_LABEL)
.begin
	.reg max
	.reg tmp
	alu[tmp, selection_mu, -, 0]
	beq[ret#],defer[2]
	alu[selection_mu, --, b, 1]
	move(max, HASHMAP_TOTAL_ENTRIES)

	alu[--, tmp, -, 1]
	beq[ret#],defer[1]
	alu[selection_mu, --, b, 2]

	alu[selection_mu, --, b, 0]
	alu[index, index, +, 1]
	alu[--, index, -, max]
	bge[MISS_LABEL]
ret#:
.end
#endm

#macro __hashmap_index_from_hash(value, idx)
	move(idx, HASHMAP_NUM_ENTRIES_MASK)
    alu[idx, value, and, idx]
	#ifdef OV_DEBUG
		.reg dbg_tmp
		//#define __DBG_HASH_MASK__ 0xff
		#define __DBG_HASH_MASK__ 3
		alu[idx, __DBG_HASH_MASK__, and, idx]
		alu[dbg_tmp, __DBG_HASH_MASK__, and, hash[1]]
		#undef __DBG_HASH_MASK__
		move(hash[1], 0xbeef)
		alu[hash[1], hash[1], or, dbg_tmp, <<16]
	#endif
#endm


/*
 * key MUST start at lm_key_addr[1]
 */

#macro hashmap_ops(fd, lm_key_addr, lm_value_addr, OP, INVALID_MAP_LABEL, NOTFOUND_LABEL, RTN_OPT, out_ent_lw, out_ent_tindex, out_ent_addr)
.begin
	.reg ent_addr_hi
	.set ent_addr_hi
	.reg tbl_addr_hi
	.set tbl_addr_hi
	.reg ent_state
	.set ent_state
	.reg key_lwsz
	.reg value_lwsz
	.reg offset
	.set offset
	.reg key_mask
	.reg value_mask
	.reg hash[2]
	.reg mu_partition
	.reg ent_index
	.set ent_index
	.reg bytes
	.reg keys_n_tid
	.reg my_act_ctx
	.reg map_tindex

	__hashmap_set($map_txfr)

	__hashmap_lm_handles_define()
	local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, lm_key_addr]

	hashmap_get_fd(fd, key_lwsz, value_lwsz, key_mask, value_mask, INVALID_MAP_LABEL)

	alu[HASHMAP_LM_INDEX, --, b, fd]
	alu[keys_n_tid, 1, +, key_lwsz]
	alu[bytes, --, b, keys_n_tid, <<2]
	alu[offset, bytes, +, lm_key_addr]
	alu[offset, offset, -, 4]
	local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, offset]		; 3 cycles

	local_csr_rd[ACTIVE_CTX_STS]
    immed[my_act_ctx, 0]
    alu_shf[my_act_ctx, my_act_ctx, and, 0x7]

	alu[HASHMAP_LM_INDEX, key_mask, and, HASHMAP_LM_INDEX]
	__hashmap_lm_handles_undef()

	camp_hash(hash, lm_key_addr, keys_n_tid, HASHMAP_MAX_KEYS_LW)

    __hashmap_index_from_hash(hash[0], ent_index)
    __hashmap_lock_init(ent_state, ent_addr_hi, offset, mu_partition, ent_index)
	alu[tbl_addr_hi, --, b, ent_addr_hi]

retry#:
    __hashmap_lock_shared(ent_index, fd, check_ov#, check_ov_valid#)
    __hashmap_compare(map_tindex, lm_key_addr, ent_addr_hi, offset, key_lwsz, check_ov_valid#)
found#:		/* found entry which matches the key */
	#if (OP == HASHMAP_OP_LOOKUP)
		alu[bytes, --, b, key_lwsz, <<2]
		alu[offset, offset, +, bytes]
		/* TODO LRU:  set ref flag */
		__hashmap_set_opt_field(out_ent_lw, value_lwsz)
		__hashmap_read_field(map_tindex, lm_value_addr, ent_addr_hi, offset, value_lwsz, RTN_OPT, out_ent_addr, out_ent_tindex)
    #elif (OP == HASHMAP_OP_REMOVE)
        __hashmap_lock_upgrade(ent_index, ent_state, retry#)
		__hashmap_table_return_credits(fd)
		__hashmap_set_opt_field(out_ent_lw, 0)
		br_bset[ent_state, __HASHMAP_DESC_OV_BIT, delete_ov_ent#]
        __hashmap_lock_release_and_invalidate(ent_index, ent_state)
    #elif (OP == HASHMAP_OP_GETNEXT)
getnext_loop#:
		/* check overflow first */
		__hashmap_ov_getnext(tbl_addr_hi, ent_index, fd, ent_addr_hi, offset, ent_state, read_next_key#)
		__hashmap_lock_release(ent_index, ent_state)
		__hashmap_select_next_/**/HASHMAP_PARTITIONS/**/_partition(mu_partition,ent_index, NOTFOUND_LABEL)
		__hashmap_lock_init(ent_state, tbl_addr_hi, offset, mu_partition, ent_index)
		__hashmap_lock_shared(ent_index, fd, getnext_loop#, getnext_loop#)
		alu[ent_addr_hi, --, b, tbl_addr_hi]
read_next_key#:
		__hashmap_set_opt_field(out_ent_lw, key_lwsz)
		immed[map_tindex, 0]		; force read
		__hashmap_read_field(map_tindex,lm_value_addr,ent_addr_hi, offset, key_lwsz, RTN_OPT, out_ent_addr, out_ent_tindex)
	#elif (OP == HASHMAP_OP_ADD) /* update entry */
        __hashmap_lock_upgrade(ent_index, ent_state, retry#)
		br[update_entry#]
    #endif
    br[ret#]

check_ov_valid#:
	alu[ent_state, ent_state, or, 1, <<__HASHMAP_DESC_VALID_BIT]
check_ov#:
	__hashmap_ov_lookup(hash[1], fd, tbl_addr_hi, ent_index, lm_key_addr, key_lwsz, map_tindex, ent_addr_hi, offset, ent_state, found#)
    #if (OP == HASHMAP_OP_ADD)	/* ADD an entry */
		/* TODO LRU: __hashmap_lru_add_element() */
        __hashmap_lock_upgrade(ent_index, ent_state, retry#)
		__hashmap_table_take_credits(fd, miss#)
		br_bclr[ent_state, __HASHMAP_DESC_VALID_BIT, write_tid_key#], defer[1]
		alu[ent_state, ent_state, and~, 1, <<__HASHMAP_DESC_VALID_BIT]

		__hashmap_ov_add(hash[1], tbl_addr_hi, ent_index, fd, ent_addr_hi, offset, add_error#)
		br[write_key#]
write_tid_key#:
		__hashmap_write_tid(fd, ent_index)
write_key#:
		.reg lm_kaddr
		alu[lm_kaddr, 4, +, lm_key_addr]
        __hashmap_write_field(lm_kaddr, key_mask, ent_addr_hi, offset, key_lwsz)


update_entry#:
		/* TODO LRU:  set ref flag */
		__hashmap_set_opt_field(out_ent_lw, 0)
		alu[bytes, --, b, key_lwsz, <<2]
		alu[offset, offset, +, bytes]
		__hashmap_write_field(lm_value_addr, value_mask, ent_addr_hi, offset, value_lwsz)
        br[ret#]
add_error#:
	__hashmap_table_return_credits(fd)
    #endif
    /* falls thru to miss if entry is not valid, not found, and not add/update function */
miss#:
    __hashmap_lock_release(ent_index, ent_state)
    br[NOTFOUND_LABEL]
delete_ov_ent#:
	__hashmap_ov_delete(tbl_addr_hi, ent_index, offset, ent_state)
	br[ret#]
ret#:
	__hashmap_lock_release(ent_index, ent_state)
.end
#endm


/**
 *
 * Subroutine wrapper
 *
 */
//#define EBPF_SUBROUTINE
#define DO_NEW_REGS
#ifdef EBPF_SUBROUTINE

#ifdef DO_NEW_REGS
	#define HTAB_MAP_DELETE_SUBROUTINE_addr	947
	#define HTAB_MAP_LOOKUP_SUBROUTINE_addr 30
	#define HTAB_MAP_UPDATE_SUBROUTINE_addr 361
#endif

#macro htab_subr_declare()
	#define __GLOBAL__ volatile
	//#define __GLOBAL__ global
	#ifndef HASHMAP_GLOBALS_DECLARED
		#define HASHMAP_GLOBALS_DECLARED
		.reg __GLOBAL__ htab_g_tid_rc			/* input=tid, output=rc */
		.reg __GLOBAL__ htab_g_lm_key_offset
		.reg __GLOBAL__ htab_g_return_addr
		.set htab_g_tid_rc			/* input=tid, output=rc */
		.set htab_g_lm_key_offset
		.set htab_g_return_addr
	#endif
	#undef __GLOBAL__
#endm
#macro htab_subr_lookup_declare()
	htab_subr_declare()
	//#define __GLOBAL__ global
	#define __GLOBAL__ volatile
	#ifndef HASHMAP_LOOKUP_GLOBALS_DECLARED
		#define HASHMAP_LOOKUP_GLOBALS_DECLARED
		.reg __GLOBAL__ htab_g_value_addr[2]
		.set htab_g_value_addr[0]
		.set htab_g_value_addr[1]
	#endif
	#undef __GLOBAL__
#endm
#macro htab_subr_update_declare()
	htab_subr_declare()
	//#define __GLOBAL__ global
	#define __GLOBAL__ volatile
	#ifndef HASHMAP_UPDATE_GLOBALS_DECLARED
		#define HASHMAP_UPDATE_GLOBALS_DECLARED
		.reg __GLOBAL__ htab_g_lm_value_offset
		.set htab_g_lm_value_offset
	#endif
	#undef __GLOBAL__
#endm

#macro xbalr(return_addr, SUBR_LABEL)
#ifdef DO_NEW_REGS
	/* SUBR_LABEL must be a constant */
	#define_eval __SUBR_LABEL	'SUBR_LABEL/**/_addr'
	#warning "br_addr for " SUBR_LABEL " is " __SUBR_LABEL
	.set return_addr
	.reg_addr return_addr	4 A
	load_addr[return_addr, ret_label#]
	br_addr[__SUBR_LABEL]
	#undef __SUBR_LABEL
  ret_label#:
#else
	#define_eval __SUBR_LABEL	'SUBR_LABEL/**/#'
	balr(return_addr, __SUBR_LABEL)
	#undef __SUBR_LABEL
#endif
#endm


#macro htab_map_lookup_elem_subr(in_tid, in_lm_key_offset, out_value_addr)
.begin
	#ifdef DO_NEW_REGS
		.reg_addr htab_g_tid_rc		3 A
		alu[htab_g_tid_rc, --, b, in_tid]
		.reg_addr htab_g_lm_key_offset	0 B
		alu[htab_g_lm_key_offset, --, b, in_lm_key_offset]
		.reg_addr htab_g_value_addr[0] 5 A
		alu[htab_g_value_addr[0], --, b, 0]
		.reg_addr htab_g_value_addr[1] 2 B
		alu[htab_g_value_addr[1], --, b, 0]
	#else
		move(htab_g_tid_rc, in_tid)
		move(htab_g_lm_key_offset, in_lm_key_offset)
	#endif
	xbalr(htab_g_return_addr, HTAB_MAP_LOOKUP_SUBROUTINE)

	#ifdef DO_NEW_REGS
		.reentry
	#endif
	.set htab_g_value_addr[0]
	.set htab_g_value_addr[1]
	alu[out_value_addr[0], --, b, htab_g_value_addr[0]]
	alu[out_value_addr[1], --, b, htab_g_value_addr[1]]
.end
#endm

#macro htab_map_lookup_subr_func()
.subroutine
.begin
	hashmap_ops(htab_g_tid_rc, htab_g_lm_key_offset, --, HASHMAP_OP_LOOKUP, htab_lookup_error_map#, htab_lookup_not_found#, HASHMAP_RTN_ADDR, --, --, htab_g_value_addr)
	rtn[htab_g_return_addr]

htab_lookup_error_map#:
htab_lookup_not_found#:
	move(htab_g_value_addr[0], 0)
	move(htab_g_value_addr[1], 0)
	rtn[htab_g_return_addr]
.end
.endsub
#endm

#macro htab_map_update_elem_subr(in_tid, in_lm_key_offset, in_lm_value_offset, out_rc)
.begin
	#ifdef DO_NEW_REGS
		.reg_addr htab_g_tid_rc			3 A		/* input=tid, output=rc */
		alu[htab_g_tid_rc, --, b, in_tid]
		.reg_addr htab_g_lm_key_offset	0 B
		alu[htab_g_lm_key_offset, --, b, in_lm_key_offset]
		.reg_addr htab_g_lm_value_offset	1 B
		alu[htab_g_lm_value_offset, --, b, in_lm_value_offset]
	#else
		move(htab_g_tid_rc, in_tid)
		move(htab_g_lm_key_offset, in_lm_key_offset)
		move(htab_g_lm_value_offset, in_lm_value_offset)
	#endif
	xbalr(htab_g_return_addr, HTAB_MAP_UPDATE_SUBROUTINE)
	#ifdef DO_NEW_REGS
		.reentry
	#endif

	.set htab_g_tid_rc
	alu[out_rc, --, b, htab_g_tid_rc]
.end
#endm
#macro htab_map_update_subr_func()
.subroutine
.begin
	hashmap_ops(htab_g_tid_rc, htab_g_lm_key_offset, htab_g_lm_value_offset, HASHMAP_OP_ADD, htab_update_error_map#, htab_update_not_found#, HASHMAP_RTN_ADDR, --, --, --)
	move(htab_g_tid_rc, 0)
	rtn[htab_g_return_addr]

htab_update_error_map#:
	#define  _RC_EINVAL_	(-22)
	move(htab_g_tid_rc, _RC_EINVAL_)
	#undef _RC_EINVAL_
	rtn[htab_g_return_addr]
htab_update_not_found#:
	#define  _RC_ENOMEM_	(-12)
	move(htab_g_tid_rc, _RC_ENOMEM_)
	#undef _RC_ENOMEM_
	rtn[htab_g_return_addr]
.end
.endsub
#endm

#macro htab_map_delete_elem_subr(in_tid, in_lm_key_offset, out_rc)
.begin
	#ifdef DO_NEW_REGS
		.reg_addr htab_g_tid_rc		3 A		/* input=tid, output=rc */
		alu[htab_g_tid_rc, --, b, in_tid]
		.reg_addr htab_g_lm_key_offset	0 B
		alu[htab_g_lm_key_offset, --, b, in_lm_key_offset]
	#else
		move(htab_g_tid_rc, in_tid)
		move(htab_g_lm_key_offset, in_lm_key_offset)
	#endif

	xbalr(htab_g_return_addr, HTAB_MAP_DELETE_SUBROUTINE)
	#ifdef DO_NEW_REGS
		.reentry
	#endif
	.set htab_g_tid_rc
	alu[out_rc, --, b, htab_g_tid_rc]
.end
#endm
#macro htab_map_delete_subr_func()
.subroutine
.begin
	hashmap_ops(htab_g_tid_rc, htab_g_lm_key_offset, --, HASHMAP_OP_REMOVE, htap_del_error_map#, htap_del_not_found#, HASHMAP_RTN_ADDR, --, --, --)
	move(htab_g_tid_rc, 0)
	rtn[htab_g_return_addr]
htap_del_error_map#:
	#define  _RC_EINVAL_	(-22)
	move(htab_g_tid_rc, _RC_EINVAL_)
	#undef _RC_EINVAL_
	rtn[htab_g_return_addr]
htap_del_not_found#:
	#define  _RC_ENOENT_	(-2)
	move(htab_g_tid_rc, _RC_ENOENT_)
	#undef _RC_ENOENT_
.end
.endsub
#endm

htab_subr_declare()
htab_subr_update_declare()
htab_subr_lookup_declare()

br[__hashmap_subr_decl_end#]
HTAB_MAP_LOOKUP_SUBROUTINE#:
	htab_map_lookup_subr_func()

HTAB_MAP_UPDATE_SUBROUTINE#:
	htab_map_update_subr_func()

HTAB_MAP_DELETE_SUBROUTINE#:
	htab_map_delete_subr_func()

__hashmap_subr_decl_end#:

#endif /* EBPF_SUBROUTINE */


#endif	/* __HASHMAP_UC__ */
