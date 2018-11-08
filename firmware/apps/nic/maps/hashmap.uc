/*
 * Copyright (C) 2014-2017,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file        hashmap.uc
 * @brief       basic lookup table implementation.
 *
 *  Subroutine calls:
 *  htab_map_lookup_elem_subr(in_tid, in_lm_key_offset, out_value_addr)
 *  htab_map_update_elem_subr(in_tid, in_lm_key_offset, in_lm_value_offset, out_rc)
 *  htab_map_delete_elem_subr(in_tid, in_lm_key_offset, out_rc)
 *
 *
 * API calls (macro)
 *
 *  hashmap_alloc_fd(out_fd, in_key_size, in_value_size, in_max_entries, ERROR_LABEL)
 *
 * OP type defines:
 *  HASHMAP_OP_LOOKUP
 *  HASHMAP_OP_ADD
 *  HASHMAP_OP_REMOVE
 *  HASHMAP_OP_GETNEXT
 *
 * return type defines
 *  HASHMAP_RTN_LMEM
 *  HASHMAP_RTN_TINDEX
 *  HASHMAP_RTN_ADDR
 *
 *    hashmap_ops(in_fd,              // fd returned from hashmap_alloc_fd()
 *                in_lm_key_addr,     // LM offset for key, key must start of lm offset + 4
 *                in_lm_value_addr,   // LM offset for value
 *                OP_TYPE,            // HASHMAP_OP_xxx
 *                INVALID_MAP_LABEL,  // label if in_fd is invalid
 *                NOTFOUND_LABEL,     // label if entry is not found
 *                RTN_OPT,            // HASHMAP_RTN_xxx
 *                out_ent_lw,         // optional, length (in lw) of returned data
 *                out_ent_tindex,     // optional, tindex of returned data
 *                out_ent_addr        // optional, addr of returned data
 *                )
 *
 * example use:
 *#if USE_LM
 *    hashmap_ops(fd, main_lm_key_offset, main_lm_value_offset, HASHMAP_OP_LOOKUP,
 *                error_map_fd#, lookup_not_found#,HASHMAP_RTN_LMEM,--,--,--)
 *#elif USE_TINDEX
 *    hashmap_ops(fd, main_lm_key_offset, main_lm_value_offset, HASHMAP_OP_LOOKUP,
 *                error_map_fd#, lookup_not_found#,HASHMAP_RTN_TINDEX,rtn_len,my_tindex,rtn_addr]
 *     __hashmap_read_field(my_tindex, main_lm_value_offset,
 *                rtn_addr[0], rtn_addr[1],rtn_len,HASHMAP_RTN_LMEM, --, --)
 *#elif USE_ADDR
 *    hashmap_ops(fd, main_lm_key_offset, main_lm_value_offset, HASHMAP_OP_LOOKUP,
 *                error_map_fd#, lookup_not_found#,HASHMAP_RTN_ADDR,rtn_len,--,rtn_addr)
 *#endif
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __HASHMAP_UC__
#define __HASHMAP_UC__


#include <passert.uc>
#include <stdmac.uc>
#include <aggregate.uc>
#include <timestamp.uc>
#include "unroll.uc"
#include "lm_handle.uc"
#include "slicc_hash.uc"

#include "hashmap_priv.uc"
#include "hashmap_cam.uc"

/*
 * public functions:
 *      hashmap_alloc_fd()
 *      hashmap_get_fd()
 *      hashmap_ops()
 * assumption:
 *      lm_key[0] = fd
 *      lm_key[1..key_sz_lw] = key
 */


/* ********************************* */
/*
 * compile time configuration
 */

#define HASHMAP_PARTITIONS              1
#define HASHMAP_TOTAL_ENTRIES           (1024<<12)
#define HASHMAP_OVERFLOW_ENTRIES        (512<<14)
#define HASHMAP_MAX_ENTRIES             (1024*2000)
/* the first 1-127 tids are used by ebpf, and managed by cmsg_map.uc */
/* tid 128-254 are reserved for internal use */
#define HASHMAP_MAX_TID_EBPF            128
#define HASHMAP_MAX_TID                 255
    /* 128=max keys + max value + cam overflow = 40+24+32+32 */
    /* 8=lock + tid = 4+4 */
#define_eval HASHMAP_MAX_ENTRY_SZ       (128)
#define HASHMAP_MAX_KEYS_SZ             (56)   // camp_hash limit 120 bytes
#define HASHMAP_MAX_VALU_SZ             (56)
#define HASHMAP_KEYS_VALU_SZ            (64)   // keys + values

/* bpf_map_type  from linux include/uapi/linux/bpf.h */
#define BPF_MAP_TYPE_UNSPEC             0
#define BPF_MAP_TYPE_HASH               1
#define BPF_MAP_TYPE_ARRAY              2
#define BPF_MAP_TYPE_PROG_ARRAY         3
#define BPF_MAP_TYPE_PERF_EVENT_ARRAY   4
#define BPF_MAP_TYPE_PERCPU_HASH        5
#define BPF_MAP_TYPE_PERCPU_ARRAY       6
#define BPF_MAP_TYPE_STACK_TRACE        7
#define BPF_MAP_TYPE_CGROUP_ARRAY       8
#define BPF_MAP_TYPE_LRU_HASH           9
#define BPF_MAP_TYPE_LRU_PERCPU_HASH    10


/* ********************************* */
/* call interface
 *
 */
#define HASHMAP_OP_LOOKUP       3
#define HASHMAP_OP_ADD_ANY      4
#define HASHMAP_OP_REMOVE       5
#define HASHMAP_OP_GETNEXT      6
#define HASHMAP_OP_GETFIRST     7
#define HASHMAP_OP_UPDATE       8
#define HASHMAP_OP_ADD_ONLY     9
#define HASHMAP_OP_MAX          HASHMAP_OP_ADD_ONLY

#define HASHMAP_RTN_LMEM        1
#define HASHMAP_RTN_TINDEX      2
#define HASHMAP_RTN_ADDR        3


/* ********************************* */
/*
 * defines
 */

#define_eval HASHMAP_ENTRY_SZ_LW        (HASHMAP_MAX_ENTRY_SZ >> 2)
#define_eval HASHMAP_ENTRY_SZ_SHFT      (LOG2(HASHMAP_MAX_ENTRY_SZ))
#define HASHMAP_LOCK_SZ                 8
#define_eval HASHMAP_LOCK_SZ_SHFT       (LOG2(HASHMAP_LOCK_SZ))
#define_eval HASHMAP_LOCK_SZ_LW         (HASHMAP_LOCK_SZ >> 2)

#define HASHMAP_MAX_KEYS_LW             (HASHMAP_MAX_KEYS_SZ >> 2)

#define HASHMAP_NUM_ENTRIES_SHFT        (LOG2(HASHMAP_TOTAL_ENTRIES))
#define HASHMAP_NUM_ENTRIES_MASK        ((1<<HASHMAP_NUM_ENTRIES_SHFT)-1)

/* key_value size = max entry size - hashmap descriptor */
#define HASHMAP_MAX_KEY_VALUE_SZ        (HASHMAP_MAX_ENTRY_SZ - 4)
#define HASHMAP_MAX_KEY_VALUE_LW        (HASHMAP_MAX_KEY_VALUE_SZ >> 2)

#define HASHMAP_ENTRIES_PER_BUCKET      8
#define HASHMAP_OV_ENTRY_SZ             ((HASHMAP_ENTRIES_PER_BUCKET * 2) * 4)
/* OV_CAM_OFFSET must be 64-byte aligned */
#define HASHMAP_OV_CAM_OFFSET           (HASHMAP_MAX_ENTRY_SZ - HASHMAP_OV_ENTRY_SZ)
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
 *           uint32_t reserved_ov_idx:4 bit 17..19
 *           uint32_t reserved_ov:1;    bit 16 - use in state only, not in mem
 *           uint32_t spare: 1;
 *           uint32_t lock_excl: 1;     bit 14
 *           uint32_t lock_cnt : 13;
 *       };
 *       uint32_t meta;
 *   };
 *  // following are futures
 *   union {
 *      struct {
 *          uint32_t lru_ref : 1;
 *          uint32_t reserved: 31;
 *      };
 *      uint32_t flags;
 *   };
 *   uint32_t spare[2];
 *   //uint32_t fd;   fd is the first word of the key
 * } __hashmap_descriptor_t;
 *
 */
#define __HASHMAP_DESC_LW               1
#define __HASHMAP_DESC_NDX_META         0
#define __HASHMAP_DESC_NDX_LRU_FLG      1
#define __HASHMAP_DESC_NDX_TID          4
#define __HASHMAP_DESC_VALID_BIT        (30)
#define __HASHMAP_DESC_VALID            (1<<__HASHMAP_DESC_VALID_BIT)
                                        // Free 29:20
#define __HASHMAP_DESC_OV_BIT           (19)
#define __HASHMAP_DESC_OV_IDX           (16)
#define __HASHMAP_DESC_LOCK_EXCL_BIT    (14)
#define __HASHMAP_DESC_LOCK_EXCL        (1<<__HASHMAP_DESC_LOCK_EXCL_BIT)
#define __HASHMAP_DESC_LOCK_CNT_MSK     (__HASHMAP_DESC_LOCK_EXCL - 1)
#define __HASHMAP_DESC_LRU_REF_BIT      (31)
#define __HASHMAP_DESC_LRU_REF          (1<<__HASHMAP_DESC_LRU_REF_BIT)

/*
 * typedef struct {
 *   __hashmap_descriptor_t  desc;  4 bytes (1 words)
 *   uint32_t                data[HASHMAP_MAX_KEY_VALUE_LW];    key=40,value=24,64 bytes
 *   uint32_t                ov_cam[8];
 *   uint32_t                ov_offset[8]
 * } __hashmap_entry_t;
 */
#define __HASHMAP_ENTRY_NDX_DESC    0
#define __HASHMAP_ENTRY_NDX_DATA    0
#define __HASHMAP_ENTRY_NDX_KEY     (__HASHMAP_ENTRY_NDX_DATA)
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
 *   uint32_t key_mask;
 *   uint32_t value_mask;
 *   uint32_t num_entries_credits;   // number of free entries
 *   uint32_t map_type;
 *   uint32_t lru_counts_active;
 *   uint32_t lru_counts_inactive;
 *   uint32_t lru_qsize_active;
 *   uint32_t lru_qsize_inactive;
 *   uint32_t spares[6];
 * } hashmap_fd_t;
*/

#define __HASHMAP_FD_TBL_SZ_LW      16
#define_eval __HASHMAP_FD_TBL_SZ    (__HASHMAP_FD_TBL_SZ_LW * 4)
#define_eval __HASHMAP_FD_TBL_SHFT  (LOG2(__HASHMAP_FD_TBL_SZ))
#define __HASHMAP_FD_NDX_KEY        0
#define __HASHMAP_FD_NDX_VALUE      0
#define __HASHMAP_FD_NDX_MAX_ENT    1
#define __HASHMAP_FD_NDX_KEY_MASK   2
#define __HASHMAP_FD_NDX_VALUE_MASK 3
#define __HASHMAP_FD_NDX_CUR_CRED   4
#define __HASHMAP_FD_NDX_TYPE       5
#define __HASHMAP_FD_NDX_CNT_ACT    6
#define __HASHMAP_FD_NDX_CNT_INACT  7
#define __HASHMAP_FD_NDX_QCNT_ACT   8
#define __HASHMAP_FD_NDX_QCNT_INACT 9
#define __HASHMAP_FD_NUM_LW_USED    6
#define __HASHMAP_FD_MAX_NUM_LW     10



/* *************************************** */

#macro hashmap_declare_block(NUM_ENTRIES)
    #if (HASHMAP_PARTITIONS == 1)
        .alloc_mem __HASHMAP_DATA_0 emem global (HASHMAP_MAX_ENTRY_SZ * NUM_ENTRIES)  256
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
#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
    #define HASH_MAP_IMEM imem1
#else
    #define HASH_MAP_IMEM imem
#endif
    /* fd table */
    .alloc_mem __HASHMAP_FD_TBL    HASH_MAP_IMEM global (__HASHMAP_FD_TBL_SZ_LW * 4 * HASHMAP_MAX_TID) 256
    .init __HASHMAP_FD_TBL 0
#endm

#macro hashmap_init()
    hashmap_declare_block(HASHMAP_TOTAL_ENTRIES)
    __hashmap_freelist_init(HASHMAP_OVERFLOW_ENTRIES)
    __hashmap_journal_init()
#endm


/* *************************************** */
/*
 * lookup(fd, key, value)
 *  returns 0 and stores elem into value   if match
 *  return negative error
 *
 * update(fd, key, value)
 *  returns 0 or negative error
 *
 * delete(fd, key)
 *  find and delete element by key
 *
 * getnext(fd, key)
 *   find key and return next key
 */
/*
 * should cache fd table in lmem
 *
 */

#macro __hashmap_rounded_mask(in_val, out_val, out_mask, endian)
.begin
    .reg tmp
    .reg mask
    .reg val

    alu[tmp, --, b, in_val]
    alu[tmp, tmp, +, 3]
    alu[out_val, tmp, and~, 0x3]

    alu[tmp, out_val, -, in_val]

    alu[tmp, --, b, tmp, <<3]
    alu[mask, tmp, ~B, 0]

    #if (streq('endian', 'swap'))
        alu[mask, tmp, b, mask, <<indirect]
        alu[out_mask, --, b, mask, >>indirect]
    #else
        alu[mask, tmp, b, mask, >>indirect]
        alu[out_mask, --, b, mask, <<indirect]
    #endif
.end
#endm

#macro __hashmap_calc_value_addr(in_val, in_bytes, out_val)
    alu[out_val, in_val, +, in_bytes]
    alu[out_val, out_val, +, 7]
    alu[out_val, out_val, and~, 0x7]
#endm


#macro hashmap_alloc_fd(in_tid, key_size, value_size, max_entries, ERROR_LABEL, endian, type)
.begin
    .reg base
    .reg offset
    .reg rnd_val
    .reg key_value_sz
    .sig create_fd_sig
    .reg tmp
    .reg $tid
    .reg $fd_xfer[__HASHMAP_FD_NUM_LW_USED]
    .xfer_order $fd_xfer

    move(base, __HASHMAP_FD_TBL >>8)
    alu[offset, --, b, in_tid, <<__HASHMAP_FD_TBL_SHFT]

    __hashmap_rounded_mask(key_size, rnd_val, $fd_xfer[__HASHMAP_FD_NDX_KEY_MASK], endian)
    alu[rnd_val, --, b, rnd_val, >>2]
    ld_field_w_clr[key_value_sz, 1100, rnd_val, <<16]
    __hashmap_rounded_mask(value_size, rnd_val, $fd_xfer[__HASHMAP_FD_NDX_VALUE_MASK], endian)
    alu[rnd_val, --, b, rnd_val, >>2]
    ld_field[key_value_sz, 0011, rnd_val]

    alu[$fd_xfer[__HASHMAP_FD_NDX_KEY], --, b, key_value_sz]
    move[tmp, max_entries]
    alu[$fd_xfer[__HASHMAP_FD_NDX_MAX_ENT], --, b, tmp]
    alu[$fd_xfer[__HASHMAP_FD_NDX_CUR_CRED], --, b, tmp]
    alu[$fd_xfer[__HASHMAP_FD_NDX_TYPE], --, b, type]

    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, __HASHMAP_FD_NUM_LW_USED, OVF_SUBTRACT_ONE)
    ov_clean
    mem[atomic_write, $fd_xfer[0], base, <<8, offset, max_/**/__HASHMAP_FD_NUM_LW_USED], indirect_ref, ctx_swap[create_fd_sig]

.end
#endm

#macro _hashmap_get_fd(in_fd, ERROR_LABEL)
.begin

    .reg base
    .reg offset
    .sig get_fd_sig

    alu[--, in_fd, -, HASHMAP_MAX_TID]
    bge[ERROR_LABEL]

    move(base, __HASHMAP_FD_TBL >>8)
    alu[offset, --, b, in_fd, <<__HASHMAP_FD_TBL_SHFT]
    mem[read32, MAP_RDXR[0], base, <<8, offset, __HASHMAP_FD_NUM_LW_USED], ctx_swap[get_fd_sig]
.end
#endm

#macro hashmap_get_fd(in_fd, key_size, value_size, key_mask, value_mask, map_type, ERROR_LABEL)
.begin
    _hashmap_get_fd(in_fd, ERROR_LABEL)
    ld_field_w_clr[key_size, 0011, MAP_RDXR[__HASHMAP_FD_NDX_KEY], >>16]
    ld_field_w_clr[value_size, 0011, MAP_RDXR[__HASHMAP_FD_NDX_VALUE]]
    alu[key_mask, --, b, MAP_RDXR[__HASHMAP_FD_NDX_KEY_MASK]]
    alu[value_mask, --, b, MAP_RDXR[__HASHMAP_FD_NDX_VALUE_MASK]]
    alu[map_type, --, b, MAP_RDXR[__HASHMAP_FD_NDX_TYPE]]
.end
#endm

#macro hashmap_get_fd_attr(in_fd, out_map_type, out_max_entries, ERROR_LABEL)
.begin
    _hashmap_get_fd(in_fd, ERROR_LABEL)
    alu[out_map_type, --, b, MAP_RDXR[__HASHMAP_FD_NDX_TYPE]]
    alu[out_max_entries, --, b, MAP_RDXR[__HASHMAP_FD_NDX_MAX_ENT]]
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
    mem[test_subsat, $fd_credits, base, <<8, tbl_offset, 1], sig_done[fd_inc_sig]
    ctx_arb[fd_inc_sig]
    alu[--, --, b, $fd_credits]
    beq[FULL_LABEL]
ret#:
.end
#endm

#macro __hashmap_table_delete(in_fd)
.begin
    .reg $fd_values[4]
    .xfer_order $fd_values
    .reg base
    .reg tbl_offset
    .sig fd_inc_sig

    alu[--, in_fd, -, HASHMAP_MAX_TID]
    bge[ret#]

    move(base, __HASHMAP_FD_TBL>>8)
    alu[tbl_offset, --, b, in_fd, <<__HASHMAP_FD_TBL_SHFT]
    #define __CUR_OFFSET__ (__HASHMAP_FD_NDX_MAX_ENT * 4)
    alu[tbl_offset, tbl_offset, +, __CUR_OFFSET__]
    #undef __CUR_OFFSET__

    alu[$fd_values[0], --, b, 0]
    alu[$fd_values[1], --, b, 0]
    alu[$fd_values[2], --, b, 0]
    alu[$fd_values[3], --, b, 0]
    mem[atomic_write, $fd_values[0], base, <<8, tbl_offset, 4], sig_done[fd_inc_sig]
    ctx_arb[fd_inc_sig]
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
    immed[state,1]          ; state=1
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

    immed[$desc_xfer[0], 1]         ;lo
    immed[$desc_xfer[1], 0]         ;hi
    move(lk_addr_hi, __HASHMAP_LOCK_TBL >>8)
    alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]

retry_lock#:
    mem[test_add64, $desc_xfer[0], lk_addr_hi, <<8, lk_addr_lo, 1], sig_done[lock_shared_sig]
    ctx_arb[lock_shared_sig]
    br_bclr[$desc_xfer[0], __HASHMAP_DESC_LOCK_EXCL_BIT, ret#]
    mem[sub, $desc_xfer[0], lk_addr_hi, <<8, lk_addr_lo], ctx_swap[lock_shared_sig]
    timestamp_sleep(4000)
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

    move(lk_addr_hi, (__HASHMAP_LOCK_TBL>>8))
    alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]
    ld_field_w_clr[imm_ref, 1100, state, <<16]  /* data16, lock->state  */
    alu[imm_ref, imm_ref, or, 2, <<3]           /* ove_data=2 override  */
    alu_shf[--, imm_ref, or, 17, <<7]           /* ov_len (1<<7) | length (16<<8) */
    mem[sub_imm, --, lk_addr_hi, <<8, lk_addr_lo], indirect_ref
    immed[state, 0]
ret#:
.end
#endm   /* __hashmap_lock_release */

#macro __hashmap_lock_release_and_invalidate(in_idx, state, in_fd)
.begin
    .reg $desc_xfer[2]
    .xfer_order $desc_xfer
    .reg tmp
    .sig lock_rel_invalid_sig
    .reg lk_addr_hi
    .reg lk_addr_lo

    move(lk_addr_hi, __HASHMAP_LOCK_TBL >>8)
    alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]
    alu_shf[tmp, --,b, 1, <<__HASHMAP_DESC_VALID_BIT]
    alu_shf[$desc_xfer[0],tmp, or, state]
    alu[$desc_xfer[1], --, b, in_fd]
    mem[sub64, $desc_xfer[0], lk_addr_hi, <<8, lk_addr_lo, 1], ctx_swap[lock_rel_invalid_sig]
    immed[state, 0]
    /* TODO for LRU
     *      clear ref flag
     *      incr free_credits
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
#endm


/*
 * key MUST start at lm_key_addr[0]
 * value addr is 8-byte aligned
 */

#macro hashmap_ops(fd, lm_key_addr, lm_value_addr, OP, INVALID_MAP_LABEL, NOTFOUND_LABEL, RTN_OPT, out_ent_lw, out_ent_tindex, out_ent_addr, endian)
    hashmap_ops(fd, lm_key_addr, lm_value_addr, OP, INVALID_MAP_LABEL, NOTFOUND_LABEL, RTN_OPT, out_ent_lw, out_ent_tindex, out_ent_addr, endian, --)
#endm

#macro hashmap_ops(fd, lm_key_addr, lm_value_addr, OP, INVALID_MAP_LABEL, NOTFOUND_LABEL, RTN_OPT, out_ent_lw, out_ent_tindex, out_ent_addr, endian, out_rc)
.begin
    .reg ent_addr_hi
    .reg tbl_addr_hi
    .reg ent_state
    .reg key_lwsz
    .reg value_lwsz
    .reg offset
    .reg key_mask
    .reg value_mask
    .reg hash[2]
    .reg mu_partition
    .reg ent_index
    .reg bytes
    .reg keys_n_tid
    .reg my_act_ctx
    .reg map_tindex
    .reg map_type

    __hashmap_lm_handles_define()

    hashmap_get_fd(fd, key_lwsz, value_lwsz, key_mask, value_mask, map_type, INVALID_MAP_LABEL)
    alu[bytes, --, b, key_lwsz, <<2]
    alu[offset, bytes, +, lm_key_addr]
    alu[offset, offset, -, 4]
    local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, offset]      ; 3 cycles

    local_csr_rd[ACTIVE_CTX_STS]
    immed[my_act_ctx, 0]
    alu_shf[my_act_ctx, my_act_ctx, and, 0x7]

    alu[HASHMAP_LM_INDEX, key_mask, and, HASHMAP_LM_INDEX]

    __hashmap_lm_handles_undef()

    #if (OP == HASHMAP_OP_GETFIRST)
        br[getfirst_ent#]
    #else
        slicc_hash_words(hash, fd, lm_key_addr, key_lwsz, key_mask)
        __hashmap_index_from_hash(hash[0], ent_index)
        __hashmap_lock_init(ent_state, ent_addr_hi, offset, mu_partition, ent_index)
        alu[tbl_addr_hi, --, b, ent_addr_hi]
    #endif

retry#:
    __hashmap_set_opt_field(out_rc, CMSG_RC_ERR_ENOENT)
    __hashmap_lock_shared(ent_index, fd, check_ov#, check_ov_valid#)

    __hashmap_compare(map_tindex, lm_key_addr, ent_addr_hi, offset, key_lwsz, check_ov_valid#, endian, map_type)
found#:     /* found entry which matches the key */
    __hashmap_set_opt_field(out_rc, CMSG_RC_SUCCESS)
    #if (OP == HASHMAP_OP_LOOKUP)
        alu[bytes, --, b, key_lwsz, <<2]
        __hashmap_calc_value_addr(offset, bytes, offset)
        /* TODO LRU:  set ref flag */
        __hashmap_set_opt_field(out_ent_lw, value_lwsz)
        __hashmap_read_field(map_tindex, lm_value_addr, ent_addr_hi, offset, value_lwsz, RTN_OPT, out_ent_addr, out_ent_tindex, endian)
        __hashmap_lock_release(ent_index, ent_state)
        br[ret#]
    #elif (OP == HASHMAP_OP_REMOVE)
        __hashmap_lock_upgrade(ent_index, ent_state, retry#)
        __hashmap_table_return_credits(fd)
        __hashmap_set_opt_field(out_ent_lw, 0)
        br_bset[ent_state, __HASHMAP_DESC_OV_BIT, delete_ov_ent#]
        __hashmap_lock_release_and_invalidate(ent_index, ent_state, fd)
        br[ret#]
    #elif ( (OP == HASHMAP_OP_GETNEXT) || (OP == HASHMAP_OP_GETFIRST) )
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
        immed[map_tindex, 0]        ; force read
        __hashmap_read_field(map_tindex,lm_value_addr,ent_addr_hi, offset, key_lwsz, RTN_OPT, out_ent_addr, out_ent_tindex, endian)
        __hashmap_lock_release(ent_index, ent_state)
        br[ret#]
    #elif ( (OP == HASHMAP_OP_ADD_ANY) || (OP == HASHMAP_OP_UPDATE) ) /* entry exists */
        __hashmap_lock_upgrade(ent_index, ent_state, retry#)
        __hashmap_set_opt_field(out_ent_lw, 0)
        alu[bytes, --, b, key_lwsz, <<2]
        __hashmap_calc_value_addr(offset, bytes, offset)
        __hashmap_write_field(lm_value_addr, value_mask, ent_addr_hi, offset, value_lwsz, endian)
        __hashmap_lock_release(ent_index, ent_state)
        br[ret#]
    #else
        __hashmap_set_opt_field(out_rc, CMSG_RC_ERR_EEXIST)
        br[miss#]
    #endif

check_ov_valid#:
    alu[ent_state, ent_state, or, 1, <<__HASHMAP_DESC_VALID_BIT]
check_ov#:
    __hashmap_ov_lookup(hash[1], fd, tbl_addr_hi, ent_index, lm_key_addr, key_lwsz, map_tindex, ent_addr_hi, offset, ent_state, found#, endian, map_type)
#if ( (OP == HASHMAP_OP_ADD_ANY) || (OP == HASHMAP_OP_ADD_ONLY) )   /* entry does not exist */
        __hashmap_lock_upgrade(ent_index, ent_state, retry#)
        __hashmap_set_opt_field(out_rc, CMSG_RC_ERR_E2BIG)
        __hashmap_table_take_credits(fd, miss#)
        br_bclr[ent_state, __HASHMAP_DESC_VALID_BIT, write_tid_key#], defer[1]
        alu[ent_state, ent_state, and~, 1, <<__HASHMAP_DESC_VALID_BIT]

        __hashmap_ov_add(hash[1], tbl_addr_hi, ent_index, fd, ent_addr_hi, offset, add_error#)
        br[write_key#]
write_tid_key#:
        __hashmap_write_tid(fd, ent_index)
write_key#:
        __hashmap_write_field(lm_key_addr, key_mask, ent_addr_hi, offset, key_lwsz, endian)
        __hashmap_set_opt_field(out_ent_lw, 0)
        alu[bytes, --, b, key_lwsz, <<2]
        __hashmap_calc_value_addr(offset, bytes, offset)
        __hashmap_write_field(lm_value_addr, value_mask, ent_addr_hi, offset, value_lwsz, endian)
        __hashmap_lock_release(ent_index, ent_state)
        __hashmap_set_opt_field(out_rc, CMSG_RC_SUCCESS)
        br[ret#]
add_error#:
    __hashmap_table_return_credits(fd)
#endif /* ADD_ANY/UPDATE entry */
    /* falls thru to miss if entry is not valid, not found, and not add/update function */
miss#:
    __hashmap_lock_release(ent_index, ent_state)
    #if (OP != HASHMAP_OP_GETNEXT)
        br[NOTFOUND_LABEL]
    #else
        br[getfirst_ent#]
    #endif
#if ((OP == HASHMAP_OP_GETNEXT) || (OP == HASHMAP_OP_GETFIRST))
getfirst_ent#:
        immed[ent_index, 0]
        __hashmap_lock_init(ent_state, ent_addr_hi, offset, mu_partition, ent_index)
        alu[tbl_addr_hi, --, b, ent_addr_hi]
        __hashmap_lock_shared(ent_index, fd, found#, found#)
        br[found#]
#endif
#if (OP == HASHMAP_OP_REMOVE)
delete_ov_ent#:
    __hashmap_ov_delete(tbl_addr_hi, ent_index, offset, ent_state)
    __hashmap_lock_release(ent_index, ent_state)
    br[ret#]
#endif  /* REMOVE entry */
ret#:
.end
#endm


/**
 *
 * Subroutine wrapper
 *
 */

#define HTAB_EBPF_LM_KEY_HANDLE 0
#define HTAB_EBPF_LM_KEY_INDEX  *l$index0

#macro htab_reserve_regs(START, END)
    #define_eval __REGS START
    #while (__REGS <= END)
        .reg ra/**/__REGS
        .reg_addr ra/**/__REGS __REGS A
        .set ra/**/__REGS
        .reg rb/**/__REGS
        .reg_addr rb/**/__REGS __REGS B
        .set rb/**/__REGS

        #define_eval __REGS (__REGS+1)
    #endloop
    #undef __REGS
#endm

#macro htab_free_regs(START, END)
    #define_eval __REGS START
    #while (__REGS <= END)
        .use ra/**/__REGS
        .use rb/**/__REGS

        #define_eval __REGS (__REGS+1)
    #endloop
    #undef __REGS
#endm

#macro htab_subr_regs_alloc()
    htab_reserve_regs(12,22)
#endm

#macro htab_subr_regs_free()
    htab_free_regs(12,22)
#endm

#macro htab_map_lookup_subr_func()
.reentry
.begin
    htab_subr_regs_alloc()
    .reg htab_return_addr
    .reg_addr htab_return_addr 0 B
    .set htab_return_addr
    .reg rtnB1
    .reg_addr rtnB1 1 B
    .set rtnB1
    .reg htab_value_addr_hi
    .reg_addr htab_value_addr_hi 1 A
    .set htab_value_addr_hi
    .reg htab_in_tid
    .reg_addr htab_in_tid 0 A
    .set htab_in_tid

    .reg rtn_addr
    .reg ebpf_rc
    .reg tid
    .reg lm_key_offset
    .reg out_addr[2]

    #define MAP_RDXR $__pv_pkt_data
    #define HASHMAP_RXFR_COUNT 16

    local_csr_rd[ACTIVE_LM_ADDR_/**/HTAB_EBPF_LM_KEY_HANDLE]
    immed[lm_key_offset, 0]
    alu[tid, htab_in_tid, or, 0]

    alu[rtn_addr, --, b, htab_return_addr]
    immed[out_addr[0], 0]
    immed[out_addr[1], 0]

    hashmap_ops(tid, lm_key_offset, --, HASHMAP_OP_LOOKUP, htab_lookup_error_map#, htab_lookup_not_found#, HASHMAP_RTN_ADDR, --, --, out_addr, swap)

htab_lookup_error_map#:
htab_lookup_not_found#:
    // restore stack LM before returning from map function
    local_csr_wr[ACTIVE_LM_ADDR_/**/HTAB_EBPF_LM_KEY_HANDLE, lm_key_offset]

    #pragma warning(push)
    #pragma warning(disable: 5186) //disable warning "gpr_wrboth is experimental"
    .reg_addr ebpf_rc 0 A
    alu[ebpf_rc, --, b, out_addr[1]], gpr_wrboth

    .reg_addr htab_value_addr_hi 1 A
    alu[htab_value_addr_hi, --, b, out_addr[0]], gpr_wrboth
    #pragma warning (pop)

ret#:
    htab_subr_regs_free()
    #pragma warning(push)
    #pragma warning(disable: 5116)  // disable warning "Return register may not contain valid addr"
        .use htab_return_addr
        .use ebpf_rc
        .use htab_value_addr_hi
        .use rtnB1
        rtn[rtn_addr]
    #pragma warning(pop)

    #undef HASHMAP_RXFR_COUNT
    #undef MAP_RDXR
.end
#endm

#macro htab_map_update_subr_func()
.reentry
.begin
    htab_subr_regs_alloc()
    .reg htab_return_addr
    .reg_addr htab_return_addr 0 B
    .set htab_return_addr

    .reg ebpf_rc

    #define HASHMAP_RXFR_COUNT 16
    #define MAP_RDXR $__pv_pkt_data

    #define HASHMAP_TXFR_COUNT 8
    .reg write $__map_txfr[HASHMAP_TXFR_COUNT]
    .xfer_order $__map_txfr
    __hashmap_set($__map_txfr)
    #define MAP_TXFR $__map_txfr

    #define MAP_RXCAM $__pv_pkt_data[16]    /* start at 16 for 8 regs */

    .reg tid
    .reg lm_key_offset
    .reg lm_value_offset

    local_csr_rd[ACTIVE_LM_ADDR_/**/HTAB_EBPF_LM_KEY_HANDLE]
    immed[lm_key_offset, 0]
    alu[tid, --, b,HTAB_EBPF_LM_KEY_INDEX]
    alu[lm_value_offset, 40, +, lm_key_offset]  ; assume value is 40 bytes after keys

    hashmap_ops(tid, lm_key_offset, lm_value_offset, HASHMAP_OP_ADD, htab_update_error_map#, htab_update_not_found#, HASHMAP_RTN_ADDR, --, --, --, swap)

    .reg_addr ebpf_rc 0 A
    immed[ebpf_rc, 0]
    br[ret#]

    #undef HASHMAP_TXFR_COUNT
    #undef MAP_TXFR
    #undef HASHMAP_RXFR_COUNT
    #undef MAP_RDXR
    #undef MAP_RXCAM

htab_update_error_map#:
    #define  _RC_EINVAL_    (-22)
    .reg_addr ebpf_rc 0 A
    .set ebpf_rc
    move(ebpf_rc, _RC_EINVAL_)
    #undef _RC_EINVAL_
    br[ret#]
htab_update_not_found#:
    #define  _RC_ENOMEM_    (-12)
    .reg_addr ebpf_rc 0 A
    .set ebpf_rc
    move(ebpf_rc, _RC_ENOMEM_)
    #undef _RC_ENOMEM_

    htab_subr_regs_free()
ret#:
    #pragma warning(push)
    #pragma warning(disable: 5116)  // disable warning "Return register may not contain valid addr"
        .use ebpf_rc
        .use htab_return_addr
        rtn[htab_return_addr]
    #pragma warning(pop)
.end
#endm

#macro htab_map_delete_subr_func()
.reentry
.begin
    htab_subr_regs_alloc()

    .reg htab_return_addr
    .reg_addr htab_return_addr 0 B
    .set htab_return_addr

    .reg ebpf_rc

    #define HASHMAP_RXFR_COUNT 16
    #define MAP_RDXR $__pv_pkt_data
    .reg tid
    .reg lm_key_offset

    local_csr_rd[ACTIVE_LM_ADDR_/**/HTAB_EBPF_LM_KEY_HANDLE]
    immed[lm_key_offset, 0]
    alu[tid, --, b,HTAB_EBPF_LM_KEY_INDEX]
    hashmap_ops(tid, lm_key_offset, --, HASHMAP_OP_REMOVE, htap_del_error_map#, htap_del_not_found#, HASHMAP_RTN_ADDR, --, --, --, swap)
    .reg_addr ebpf_rc 0 A
    immed[ebpf_rc, 0]
    br[ret#]
    #undef HASHMAP_RXFR_COUNT
    #undef MAP_RDXR
htap_del_error_map#:
    #define  _RC_EINVAL_    (-22)
    .reg_addr ebpf_rc 0 A
    .set ebpf_rc
    move(ebpf_rc, _RC_EINVAL_)
    #undef _RC_EINVAL_
    br[ret#]
htap_del_not_found#:
    #define  _RC_ENOENT_    (-2)
    .reg_addr ebpf_rc 0 A
    .set ebpf_rc
    move(ebpf_rc, _RC_ENOENT_)
    #undef _RC_ENOENT_

    htab_subr_regs_free()
ret#:
    #pragma warning(push)
    #pragma warning(disable: 5116)  // disable warning "Return register may not contain valid addr"
        .use ebpf_rc
        .use htab_return_addr
        rtn[htab_return_addr]
    #pragma warning(pop)
.end
#endm


#endif  /* __HASHMAP_UC__ */
