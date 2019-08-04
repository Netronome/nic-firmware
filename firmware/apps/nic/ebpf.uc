/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   ebpf.uc
 * @brief  Action handler for eBPF execution.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _EBPF_UC
#define _EBPF_UC


#include <nic_basic/nic_stats.h>
#include <aggregate.uc>
#include <stdmac.uc>

#include "nfd_user_cfg.h"

#include "slicc_hash.h"

#define EBPF_CAP_FUNC_ID_LOOKUP 1

#define EBPF_CAP_ADJUST_HEAD_FLAG_NO_META (1 << 0)

#define NFP_BPF_CAP_TYPE_FUNC         1
#define NFP_BPF_CAP_TYPE_ADJUST_HEAD  2
#define NFP_BPF_CAP_TYPE_MAPS         3
#define NFP_BPF_CAP_TYPE_RANDOM       4
#define NFP_BPF_CAP_TYPE_QUEUE_SELECT 5
#define NFP_BPF_CAP_TYPE_ADJUST_TAIL  6

#define EBPF_DEBUG
#define EBPF_MAPS

#ifdef EBPF_DEBUG
    #define JOURNAL_ENABLE 1
    #define DEBUG_TRACE
    #include <journal.uc>
#endif
#if defined(EBPF_MAPS) || defined(EBPF_DEBUG)
    #ifndef PKT_COUNTER_ENABLE
        #define PKT_COUNTER_ENABLE
    #endif
    #include "pkt_counter.uc"
    pkt_counter_init()
    #include "hashmap.uc"
    #include "hashmap_priv.uc"
	#include "cmsg_map.uc"
#endif
#ifdef EBPF_DEBUG
    #include "map_debug_config.h"
    __hashmap_journal_init()
#endif  /* EBPF_DEBUG */

#define __EBPF_CAP_LENGTH 0
#define __EBPF_CAP_DATA 0

#macro ebpf_init_cap_adjust_head(flags, min_offset, max_offset, guaranteed_sub, guaranteed_add)
    #define_eval __EBPF_CAP_DATA '__EBPF_CAP_DATA,NFP_BPF_CAP_TYPE_ADJUST_HEAD,20,(flags),(min_offset),(max_offset),(guaranteed_sub),(guaranteed_add)'
    #define_eval __EBPF_CAP_LENGTH (__EBPF_CAP_LENGTH + 28)
#endm


#macro ebpf_init_cap_func(id, LABEL)
    #define_eval __EBPF_CAP_DATA '__EBPF_CAP_DATA,NFP_BPF_CAP_TYPE_FUNC,8,(id),(LABEL)'
    #define_eval __EBPF_CAP_LENGTH (__EBPF_CAP_LENGTH + 16)
#endm


#macro ebpf_init_cap_maps(types, max_maps, max_elements, max_key_sz, max_val_sz, max_entry_sz)
    #define_eval __EBPF_CAP_DATA '__EBPF_CAP_DATA,NFP_BPF_CAP_TYPE_MAPS,24,(types),(max_maps),(max_elements),(max_key_sz),(max_val_sz),(max_entry_sz)'
    #define_eval __EBPF_CAP_LENGTH (__EBPF_CAP_LENGTH + 32)
#endm


#macro ebpf_init_cap_empty(type)
    #define_eval __EBPF_CAP_DATA '__EBPF_CAP_DATA,(type),0'
    #define_eval __EBPF_CAP_LENGTH (__EBPF_CAP_LENGTH + 8)
#endm

#macro ebpf_init_cap_finalize()
    .alloc_mem _abi_bpf_capabilities emem global __EBPF_CAP_LENGTH 256
    // remove "0," from front of list
    #define_eval __EBPF_CAP_DATA strright('__EBPF_CAP_DATA', -2)
    #define __EBPF_CAP_OFFSET 0
    #while (__EBPF_CAP_OFFSET < (__EBPF_CAP_LENGTH - 4))
        #define_eval VALUE strleft('__EBPF_CAP_DATA', strstr('__EBPF_CAP_DATA', ',') - 1)
        #define_eval __EBPF_CAP_DATA strright('__EBPF_CAP_DATA', strlen('__EBPF_CAP_DATA') - strstr('__EBPF_CAP_DATA', ','))
        .init _abi_bpf_capabilities+__EBPF_CAP_OFFSET VALUE
        #define_eval __EBPF_CAP_OFFSET (__EBPF_CAP_OFFSET + 4)
    #endloop
    .init _abi_bpf_capabilities+__EBPF_CAP_OFFSET __EBPF_CAP_DATA
#endm


ebpf_init_cap_empty(NFP_BPF_CAP_TYPE_RANDOM)
ebpf_init_cap_empty(NFP_BPF_CAP_TYPE_QUEUE_SELECT)
ebpf_init_cap_empty(NFP_BPF_CAP_TYPE_ADJUST_TAIL)
ebpf_init_cap_adjust_head(EBPF_CAP_ADJUST_HEAD_FLAG_NO_META, 44, 248, 84, 112)
ebpf_init_cap_maps(((1 << BPF_MAP_TYPE_HASH)+(1<<BPF_MAP_TYPE_ARRAY)), HASHMAP_MAX_TID_EBPF, HASHMAP_MAX_ENTRIES, HASHMAP_MAX_KEYS_SZ, HASHMAP_MAX_VALU_SZ, \
                   (HASHMAP_KEYS_VALU_SZ))
ebpf_init_cap_func(EBPF_CAP_FUNC_ID_LOOKUP, HTAB_MAP_LOOKUP_SUBROUTINE#)
ebpf_init_cap_finalize()

#define EBPF_STACK_SIZE 512
.alloc_mem EBPF_STACK_BASE lmem me (4 * (1 << log2(EBPF_STACK_SIZE, 1))) (4 * (1 << log2(EBPF_STACK_SIZE, 1)))

#define EBPF_PORT_STATS_BLK	(8)		/* 8 u64 counters */

/**
 *  return value bit field description
 *
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +---------------+-+-+-+-+-+-+-+-+---------------------------+-+-+
 *    0  |               |a|r|d|p| |R|D|P|                           |I|S|
 *       +---+-----------+-+-+-+-+-+-+-+-+---------------------------+-+-+
 */
#define EBPF_RET_SKB_MARK		0
#define EBPF_RET_IFE_MARK		1
#define EBPF_RET_PASS			16
#define EBPF_RET_DROP			17
#define EBPF_RET_REDIR			18
#define EBPF_RET_STATS_PASS		20
#define EBPF_RET_STATS_DROP		21
#define EBPF_RET_STATS_REDIR	22
#define EBPF_RET_STATS_ABORT	23

#define EBPF_RET_STATS_MASK		0xf

//-- change lib/nic_basic/nic_stats.h to match
#define EBPF_STATS_START_OFFSET         0x80 // after rx and tx stats

#define _ebpf_pkt_vec *l$index1

#macro ebpf_reentry()
.begin
    .reg egress_q_base
    .reg stat
    .reg pkt_length
    .reg ebpf_rc
    .reg_addr ebpf_rc 0 A
    .set ebpf_rc
    .reg rc

    pv_restore_meta_lm_ptr(_ebpf_pkt_vec)

    alu[rc, --, B, ebpf_rc] // would have preferred ebpf_rc in bank B

    alu[stat, EBPF_RET_STATS_MASK, AND, rc, >>EBPF_RET_STATS_PASS]
    beq[skip_ebpf_stats#]
        ffs[stat, stat] // would have preferred stat as an index
        alu[stat, stat, +, NIC_STATS_QUEUE_BPF_PASS_IDX]
        pv_stats_update(_ebpf_pkt_vec, stat, --)
    skip_ebpf_stats#:

    br_bset[rc, EBPF_RET_DROP, drop#]

    pv_set_tx_flag(_ebpf_pkt_vec, BF_L(PV_TX_HOST_RX_BPF_bf))
    pv_invalidate_cache(_ebpf_pkt_vec)

    __actions_restore_t_idx()
    br_bset[rc, EBPF_RET_PASS, actions#]

    // EBF_RET_REDIR
    pv_get_nbi_egress_channel_mapped_to_ingress(egress_q_base, _ebpf_pkt_vec)
    pkt_io_tx_wire(_ebpf_pkt_vec, egress_q_base, egress#)
.end
#endm


#macro ebpf_call(in_vec, in_ustore_addr)
.begin
    .reg jump_offset
    .reg stack_addr

    pv_save_meta_lm_ptr(_ebpf_pkt_vec)
    load_addr[jump_offset, ebpf_start#]
    alu[jump_offset, in_ustore_addr, -, jump_offset]
    jump[jump_offset, ebpf_start#], targets[dummy0#, dummy1#], defer[3]
        immed[stack_addr, EBPF_STACK_BASE]
        .reg_addr stack_addr 22 A
        #if (log2(EBPF_STACK_SIZE, 1) <= 8)
            alu[stack_addr, stack_addr, OR, t_idx_ctx, >>(8 - log2(EBPF_STACK_SIZE, 1))]
        #else
            alu[stack_addr, stack_addr, OR, t_idx_ctx, <<(log2(EBPF_STACK_SIZE, 1) - 8)]
        #endif
        local_csr_wr[ACTIVE_LM_ADDR_0, stack_addr]

ebpf_start#:
dummy0#:
    nop
dummy1#:
    nop

    br_addr[NFD_BPF_START_OFF], rtn[ebpf_reentry#], targets[HTAB_MAP_LOOKUP_SUBROUTINE#]
.end
#endm


hashmap_init()
cmsg_init()

.if (0)
	#pragma warning(push)
	#pragma warning(disable: 4702) // disable warning "unreachable code"

HTAB_MAP_LOOKUP_SUBROUTINE#:
	htab_map_lookup_subr_func()
HTAB_MAP_UPDATE_SUBROUTINE#:
//	htab_map_update_subr_func()

HTAB_MAP_DELETE_SUBROUTINE#:
//	htab_map_delete_subr_func()

	#pragma warning(pop)
.endif

#endif 	/*_EBPF_UC */
