#ifndef _EBPF_RX_UC
#define _EBPF_RX_UC

/* _nic_stats_extra -- add ebpf stats at end */
/* firmware/lib/nic_basic/nic_stats.h */
/* firmware/lib/nic_basic/_c/nic_stats.c */
#include <nic_basic/nic_stats.h>
#include "nfd_user_cfg.h"
#include "unroll.uc"
#include "lm_handle.uc"


#if 1
#define JOURNAL_ENABLE 1
#define DEBUG_TRACE
#include <journal.uc>
#include "hashmap_priv.uc"
#include "map_debug_config.h"
__hashmap_journal_init()
#endif

#macro ebpf_init()
.alloc_mem _pf0_net_app_id dram global 8 8
.init _pf0_net_app_id+0 (NFD_NET_APP_TYPE)
#endm



#macro ebpf_lm_handles_define()
    #define_eval EBPF_META_PKT_LM_HANDLE    1
    #define_eval EBPF_META_PKT_LM_INDEX     *l$index1

    lm_handle_alloc(EBPF_STACK_LM_HANDLE)
    #define_eval EBPF_STACK_LM_HANDLE    0
    #define_eval EBPF_STACK_LM_INDEX     *l$index0
#endm

#macro ebpf_lm_handles_undef()
    #undef EBPF_META_PKT_LM_HANDLE
    #undef EBPF_META_PKT_LM_INDEX
    #undef EBPF_STACK_LM_HANDLE
    #undef EBPF_STACK_LM_INDEX
#endm

#define EBPF_LM_SIZE   256
#define EBPF_LM_BASE   0
#define_eval EBPF_LM_STACK_BASE (EBPF_LM_SIZE*4)
#define EBPF_LM_STACK_SIZE 512

.alloc_mem ebpf_lm    lmem+EBPF_LM_BASE me (EBPF_LM_SIZE*4)
.alloc_mem ebpf_stack lmem+EBPF_LM_STACK_BASE me (EBPF_LM_STACK_SIZE*4)

#define EBPF_PROG_ADDR NFD_BPF_START_OFF

#define XDP_ABORTED 0		/* ebpf program error, drop packet */
#define XDP_DROP	1
#define XDP_PASS	2
#define XDP_TX		3		/* redir */
#define XDP_MAX		XDP_TX

#define EBPF_BEFORE 0
#define EBPF_AFTER  1
#macro ebpf_lm_addr(STATUS, out_addr, stack_addr)
.begin
    .reg lm_off
    .reg ctx_num
	.reg tmp

#if (STATUS == EBPF_BEFORE)
	alu[ctx_num, --, b, t_idx_ctx, >>7]
#else
	local_csr_rd[ACTIVE_CTX_STS]
    immed[ctx_num, 0]
    alu_shf[ctx_num, ctx_num, and, 0x7]
#endif

    #define_eval _LM_SIZE_ (EBPF_LM_SIZE/2)
    immed[out_addr, EBPF_LM_BASE]
    alu[lm_off, --, b, ctx_num, <<(LOG2(_LM_SIZE_, 1))]
    alu[out_addr, out_addr, +, lm_off]
    #undef _LM_SIZE_

    #define_eval _LM_SIZE_ (EBPF_LM_STACK_SIZE/2)
    immed[stack_addr, EBPF_LM_STACK_BASE]
    alu[lm_off, --, b, ctx_num, <<(LOG2(_LM_SIZE_, 1))]
    alu[stack_addr, stack_addr, +, lm_off]
    #undef _LM_SIZE_
.end
#endm
/*
 * OLD ebpf calling convection
 *  n$nnr2 = [31]:1, [26:16]:pnum, [15:0]:offset + meta_len
 *  n$nnr3 = packet length
 *  n$nnr0 = 0
 *
 *  OLD ebpf return
 *   A0 result - 
 *   B9 meta len
 *   B10 pkt len
 *   n$nnr1 = pkt mark
 *
 *  Temp calling convenction: TO BE CHANGED
 *		in  packet offset:  9 B
 *		in  packet length: 10 B
 *		out result:		    0 A
 *
 */
/* return value bit field description -- change lib/nic_basic/nic_stats.h to match*/
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
#define EBPF_STATS_START_OFFSET 0x80

/*
 * to do:
 *    - set upebpf stack
 *    - save/reserved regs
 *	  - fixed lm index
 */

.reg volatile ebpf_rc
.reg_addr ebpf_rc 0 A
.set ebpf_rc

#macro ebpf_func(in_vec, EGRESS_LABEL, DROP_LABEL)
.begin
	.reg lm_offset
	.reg pkt_length
	.reg pkt_offset
	.reg ebpf_pkt_param
	.reg ebpf_pkt_len
	.reg lm_stack
	//.reg ebpf_rc

	ebpf_lm_addr(EBPF_BEFORE, lm_offset, lm_stack)
	ebpf_lm_handles_define()
	local_csr_wr[ACTIVE_LM_ADDR_/**/EBPF_META_PKT_LM_HANDLE, lm_offset]
		pv_get_length(pkt_length, in_vec)

	/* ebpf_rx: from NBI */
	pv_get_ctm_base(pkt_offset, in_vec)

	unroll_copy(EBPF_META_PKT_LM_INDEX, ++, in_vec, 0, PV_SIZE_LW, PV_SIZE_LW)
	alu[EBPF_META_PKT_LM_INDEX++, --, B, t_idx_ctx]
	alu[EBPF_META_PKT_LM_INDEX++, --, B, __pkt_io_ctm_pkt_no]

	local_csr_wr[ACTIVE_LM_ADDR_/**/EBPF_META_PKT_LM_HANDLE, lm_offset]
	local_csr_wr[ACTIVE_LM_ADDR_/**/EBPF_STACK_LM_HANDLE, lm_stack]

	//__hashmap_dbg_print(0xe101, 0, pkt_offset, pkt_length)
	//__hashmap_dbg_print(0xe001, 0, in_vec[0], in_vec[1], in_vec[2], in_vec[3])
	//__hashmap_dbg_print(0xe002, 0, in_vec[4], in_vec[5], in_vec[6], in_vec[7])

	/* registers are trashed here */
	.reg_addr ebpf_pkt_param 9 B
	alu[ebpf_pkt_param, --, b, pkt_offset]
	.reg_addr ebpf_pkt_len 10 B
	alu[ebpf_pkt_len, --, b, pkt_length]
	//.reg_addr ebpf_rc 0 A
	immed[ebpf_rc, 0]

	.reg valid_bpf
	.reg dbg_tmp
		local_csr_rd[MAILBOX0]
		immed[valid_bpf, 0]
		.if (valid_bpf == 0)
			br[bpf_tx_host#]
		.endif

	//__hashmap_dbg_print(0xe100, 0, ebpf_rc)
	br_addr[EBPF_PROG_ADDR]

	//br[loaded_bpf#]
	//br_addr[EBPF_PROG_ADDR]
	

bpf_ret#:
	//.reentry
	.reg stats_idx
	.reg stats_offset
	.reg nic_stats_extra_hi
	.reg egress_q_base
	.reg_addr ebpf_rc 0 A
	.set ebpf_rc
	.reg rc
	.reg myid

	alu[rc, --, b, ebpf_rc]

#if 0
 #define __MY_ID__ ((__ISLAND << 8) |(__MEID))
	move(myid, __MY_ID__)
	__hashmap_dbg_print(0xe102, 0,myid, rc, ebpf_rc)
 #undef __MY_ID__
#endif

#if 0
	.reg dbg_val
	.reg mb_val
	.reg dbg_ctx
	move(dbg_val, 0x00220203) 	;drop stats + drop
	.if (rc != dbg_val)
		local_csr_rd[ACTIVE_CTX_STS]
    	immed[dbg_ctx, 0]
    	alu_shf[dbg_ctx, dbg_ctx, and, 0x7]
		local_csr_rd[MAILBOX1]
		immed[mb_val, 0]
		alu[mb_val, mb_val, or, dbg_ctx, <<4]
dbg_loop#:
		ctx_arb[voluntary], br[dbg_loop#]
	.endif
#endif


	/* restore pkt meta data */
	ebpf_lm_addr(EBPF_AFTER, lm_offset, lm_stack)
	local_csr_wr[ACTIVE_LM_ADDR_/**/EBPF_META_PKT_LM_HANDLE, lm_offset]
		alu[stats_idx, EBPF_RET_STATS_MASK, and, rc, >>EBPF_RET_STATS_PASS]
		//alu[stats_idx, rc, -, 1]		; XDP rc?
		move(nic_stats_extra_hi, _nic_stats_extra >>8)

	unroll_copy(in_vec, 0, EBPF_META_PKT_LM_INDEX, ++, PV_SIZE_LW, PV_SIZE_LW)
	alu[t_idx_ctx, --, b, EBPF_META_PKT_LM_INDEX++]
	alu[__pkt_io_ctm_pkt_no, --, b, EBPF_META_PKT_LM_INDEX++]

	//__hashmap_dbg_print(0xe011, 0, in_vec[0], in_vec[1], in_vec[2], in_vec[3])
	//__hashmap_dbg_print(0xe012, 0, in_vec[4], in_vec[5], in_vec[6], in_vec[7])

	.if (stats_idx > 0)		
		/* only port 0 for now */
		alu[stats_idx, stats_idx, -, 1]
		alu[stats_offset, --, b, stats_idx, <<4]
		alu[stats_offset, EBPF_STATS_START_OFFSET, +, stats_offset]
		mem[incr64, --, nic_stats_extra_hi, <<8, stats_offset]	;pkts count
		alu[stats_offset, 8, +, stats_offset]					;bytes count
		pv_get_length(pkt_length, in_vec)
		ov_start((OV_IMMED16 | OV_LENGTH))
    	ov_set(OV_LENGTH, ((1 << 2) | (1 << 3)))
    	ov_set_use(OV_IMMED16, pkt_length) 
    	ov_clean()
		mem[add64_imm, --, nic_stats_extra_hi, <<8, stats_offset, 1], indirect_ref
	.endif	


bpf_ret_code#:
	/* ignoring mark TBD  */
	pv_get_ctm_base(pkt_offset, in_vec)
	pv_get_length(pkt_length, in_vec)
	//__hashmap_dbg_print(0xe103, 0, pkt_offset, pkt_length)

	br_bset[rc, EBPF_RET_DROP, DROP_LABEL]
    br_bclr[rc, EBPF_RET_REDIR, bpf_tx_host#]

bpf_tx_wire#:
	//pv_get_ingress_queue(egress_q_base, in_vec)
	move(egress_q_base,0)
	__hashmap_dbg_print(0xe105, 0, egress_q_base)
	pkt_io_tx_wire(in_vec, egress_q_base, EGRESS_LABEL, DROP_LABEL)

bpf_tx_host#:
	//alu[egress_q_base, BF_A(in_vec, PV_QUEUE_OUT_bf), and, 0x3f]
	//__hashmap_dbg_print(0xe104, 0, egress_q_base)
	move(egress_q_base,0)
	pkt_io_tx_host(in_vec, egress_q_base, EGRESS_LABEL, DROP_LABEL)

	ebpf_lm_handles_undef()
/* should not get here */
	br[ret#]
	nop
	nop
	nop

/* ebpf program  */
loaded_bpf#:
.begin
	.reentry
	.reg rc 
	.reg pkt_len
	.reg pkt_addr

	/* test code */
	.reg_addr ebpf_pkt_param 9 B
	.set ebpf_pkt_param
	alu[pkt_addr, --, b, ebpf_pkt_param]

	.reg_addr ebpf_pkt_len 10 B
	.set ebpf_pkt_len
	alu[pkt_len, --, b, ebpf_pkt_len]

#if 0
	#define_eval __RC_DROP	((1<<EBPF_RET_STATS_DROP)+(1<<EBPF_RET_DROP))
	#define_eval __RC_PASS	((1<<EBPF_RET_STATS_PASS)+(1<<EBPF_RET_PASS))
	#define_eval __RC_REDIR	((1<<EBPF_RET_STATS_REDIR)+(1<<EBPF_RET_REDIR))
#endif
	#define_eval __RC_DROP	XDP_DROP
	#define_eval __RC_PASS	XDP_PASS
	#define_eval __RC_REDIR	XDP_TX

	move(rc, __RC_DROP)

	.if (pkt_len > 50)
		move(rc, __RC_PASS)
	.endif

	.if (pkt_len > 256)
		move(rc, __RC_REDIR)
	.endif

	#undef __RC_DROP
	#undef __RC_PASS
	#undef __RC_REDIR

	.reg_addr ebpf_rc 0 A
	alu[ebpf_rc, --, b, rc]
	br[bpf_ret#]
.end

ret#:
.end
#endm


#endif 	/*_EBPF_RX_UC */
