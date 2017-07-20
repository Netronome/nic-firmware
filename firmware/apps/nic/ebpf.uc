#ifndef _EBPF_UC
#define _EBPF_UC


#include <nic_basic/nic_stats.h>
#include <aggregate.uc>
#include <stdmac.uc>

#include "nfd_user_cfg.h"

#include "slicc_hash.h"

#define EBPF_CAP_FUNC_ID_LOOKUP 1

#define EBPF_CAP_ADJUST_HEAD_FLAG_NO_META (1 << 0)

#define NFP_BPF_CAP_TYPE_FUNC 1
#define NFP_BPF_CAP_TYPE_ADJUST_HEAD 2
#define NFP_BPF_CAP_TYPE_MAPS 3

//#define EBPF_DEBUG
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


#macro ebpf_init_cap_finalize()
    .alloc_mem bpf_capabilities emem global __EBPF_CAP_LENGTH 256
    // remove "0," from front of list
    #define_eval __EBPF_CAP_DATA strright('__EBPF_CAP_DATA', -2)
    #define __EBPF_CAP_OFFSET 0
    #while (__EBPF_CAP_OFFSET < (__EBPF_CAP_LENGTH - 4))
        #define_eval VALUE strleft('__EBPF_CAP_DATA', strstr('__EBPF_CAP_DATA', ',') - 1)
        #define_eval __EBPF_CAP_DATA strright('__EBPF_CAP_DATA', strlen('__EBPF_CAP_DATA') - strstr('__EBPF_CAP_DATA', ','))
        .init bpf_capabilities+__EBPF_CAP_OFFSET VALUE
        #define_eval __EBPF_CAP_OFFSET (__EBPF_CAP_OFFSET + 4)
    #endloop
    .init bpf_capabilities+__EBPF_CAP_OFFSET __EBPF_CAP_DATA
#endm


ebpf_init_cap_adjust_head(EBPF_CAP_ADJUST_HEAD_FLAG_NO_META, 44, 248, 84, 112)
ebpf_init_cap_maps((1 << BPF_MAP_TYPE_HASH), HASHMAP_MAX_TID, HASHMAP_TOTAL_ENTRIES, HASHMAP_MAX_KEYS_SZ, HASHMAP_MAX_VALU_SZ, \
                   (HASHMAP_MAX_KEYS_SZ + HASHMAP_MAX_VALU_SZ))
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
#define EBPF_RET_STATS_REDIR	        22
#define EBPF_RET_STATS_ABORT	        23

#define EBPF_RET_STATS_MASK		0xf

//-- change lib/nic_basic/nic_stats.h to match
#define EBPF_STATS_START_OFFSET         0x80 // after rx and tx stats

#define _ebpf_pkt_vec *l$index1

#macro ebpf_reentry()
.begin
    .reg egress_q_base
    .reg stats_base
    .reg stats_idx
    .reg stats_flags
    .reg stats_offset
    .reg nic_stats_extra_hi
    .reg pkt_length
    .reg ebpf_rc
    .reg_addr ebpf_rc 0 A
    .set ebpf_rc
    .reg rc

    alu[rc, --, b, ebpf_rc]

    // can this be written as an index by the eBPF code?
    alu[stats_flags, EBPF_RET_STATS_MASK, AND, rc, >>EBPF_RET_STATS_PASS]

    beq[skip_ebpf_stats#]
	/* only port 0i for now */
        ffs[stats_idx, stats_flags]
        alu[stats_offset, EBPF_STATS_START_OFFSET, OR, stats_idx, <<4]
        move(nic_stats_extra_hi, _nic_stats_extra >>8)
        mem[incr64, --, nic_stats_extra_hi, <<8, stats_offset] // pkts count
        alu[stats_offset, stats_offset, +, 8] // bytes count
        pv_get_length(pkt_length, _ebpf_pkt_vec)
        ov_start((OV_IMMED16 | OV_LENGTH))
        ov_set(OV_LENGTH, ((1 << 2) | (1 << 3)))
        ov_set_use(OV_IMMED16, pkt_length)
        ov_clean()
        mem[add64_imm, --, nic_stats_extra_hi, <<8, stats_offset, 1], indirect_ref
    skip_ebpf_stats#:

    br_bset[rc, EBPF_RET_DROP, drop#]

    __actions_restore_t_idx()

    pv_set_tx_host_rx_bpf(_ebpf_pkt_vec)

    br_bset[rc, EBPF_RET_PASS, actions#]

    pv_stats_add_tx_octets(_ebpf_pkt_vec)

    alu[stats_base, 0xff, AND, BF_A(_ebpf_pkt_vec, PV_STAT_bf), >>BF_L(PV_STAT_bf)]
    alu[stats_base, stats_base, +, EBPF_PORT_STATS_BLK]
    pv_stats_select(_ebpf_pkt_vec, stats_base)
    pv_reset_egress_queue(_ebpf_pkt_vec)
    pv_get_nbi_egress_channel_mapped_to_ingress(egress_q_base, _ebpf_pkt_vec)

    pkt_io_tx_wire(_ebpf_pkt_vec, egress_q_base, egress#, drop#)
.end
#endm


#macro ebpf_call(in_vec, in_ustore_addr, DROP_LABEL, TX_WIRE_LABEL)
.begin
    .reg jump_offset
    .reg stack_addr

    load_addr[jump_offset, ebpf_start#]
    alu[jump_offset, in_ustore_addr, -, jump_offset]
    jump[jump_offset, ebpf_start#], targets[dummy0#, dummy1#], defer[3]
        immed[stack_addr, EBPF_STACK_BASE]
        .reg_addr stack_addr 22 B
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

    br_addr[NFD_BPF_START_OFF, ebpf_reentry#], live_regs[@dma_semaphore, t_idx_ctx, __actions_t_idx, __pkt_io_nfd_pkt_no, __pkt_io_quiescent]
.end
#endm


hashmap_init()
cmsg_init()

.if (0)
	#pragma warning(push)
	#pragma warning(disable: 4702) // disable warning "unreachable code"

HTAB_MAP_LOOKUP_SUBROUTINE#:
	pv_invalidate_cache(_ebpf_pkt_vec)
	htab_map_lookup_subr_func()
HTAB_MAP_UPDATE_SUBROUTINE#:
//	htab_map_update_subr_func()

HTAB_MAP_DELETE_SUBROUTINE#:
//	htab_map_delete_subr_func()

	#pragma warning(pop)
.endif

#endif 	/*_EBPF_UC */
