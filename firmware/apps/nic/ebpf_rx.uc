#ifndef _EBPF_RX_UC
#define _EBPF_RX_UC

#include <nic_basic/nic_stats.h>
#include <aggregate.uc>
#include "nfd_user_cfg.h"
#include "lm_handle.uc"

//#undef EBPF_DEBUG
//#define EBPF_DEBUG

#ifdef EBPF_DEBUG
	#ifndef PKT_COUNTER_ENABLE
		#define PKT_COUNTER_ENABLE
	#endif
	#include "pkt_counter.uc"
	pkt_counter_init()

	#define JOURNAL_ENABLE 1
	#define DEBUG_TRACE
	#include <journal.uc>
	#define _EBPF_RX_
	#include "hashmap.uc"
	#include "hashmap_priv.uc"
	#include "map_debug_config.h"
	__hashmap_journal_init()
#endif	/* EBPF_DEBUG */

#macro ebpf_init()
	.alloc_mem _pf0_net_app_id dram global 8 8
	.init _pf0_net_app_id+0 (NFD_NET_APP_TYPE)

	.reg volatile ebpf_rc
	.reg_addr ebpf_rc 0 A
	.set ebpf_rc

	.reg_addr t_idx_ctx 29 A
	.set t_idx_ctx

	.reg_addr __pkt_io_ctm_pkt_no 29 B
	.set __pkt_io_ctm_pkt_no

	//hashmap_init()
#endm

#macro ebpf_lm_handles_define()
    #define_eval EBPF_STACK_LM_HANDLE    0
    #define_eval EBPF_STACK_LM_INDEX     *l$index0
#endm

#macro ebpf_lm_handles_undef()
    #undef EBPF_STACK_LM_HANDLE
    #undef EBPF_STACK_LM_INDEX
#endm

#define EBPF_LM_STACK_SIZE 64
.alloc_mem ebpf_stack_base lmem me (EBPF_LM_STACK_SIZE*4) 64

#define EBPF_LM_INDEX	PV_SIZE_LW
#define EBPF_PORT_STATS_BLK	(8)		/* 8 u64 counters */

#macro ebpf_lm_addr(stack_addr)
.begin
    .reg lm_off
    .reg ctx_num
	.reg tmp

	alu[ctx_num, --, b, t_idx_ctx, >>7]

    #define_eval _LM_SIZE_ (EBPF_LM_STACK_SIZE/2)
    immed[stack_addr, ebpf_stack_base]
    alu[lm_off, --, b, ctx_num, <<(LOG2(_LM_SIZE_, 1))]
    alu[stack_addr, stack_addr, +, lm_off]
    #undef _LM_SIZE_
.end
#endm
/*
 *  ebpf return
 *   A0 result -
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
 *    - save/reserved regs
 *	  - tx stats
 */
#macro ebpf_func(in_vec, DROP_LABEL, TX_WIRE_LABEL)
.begin
	.reg lm_stack

	ebpf_lm_handles_define()

	ebpf_lm_addr(lm_stack)
	local_csr_wr[ACTIVE_LM_ADDR_/**/EBPF_STACK_LM_HANDLE, lm_stack]

	.reg_addr ebpf_rc 0 A
	immed[ebpf_rc, 0]

	alu[LM_PV_INDEX[EBPF_LM_INDEX], --, B, act_t_idx]

	br_addr[NFD_BPF_START_OFF, bpf_ret#],live_regs[ebpf_rc,t_idx_ctx, __pkt_io_ctm_pkt_no]

	nop
	nop
	nop


bpf_ret#:
	.reg stats_idx
	.reg stats_offset
	.reg nic_stats_extra_hi
	.reg pkt_length
	.reg_addr ebpf_rc 0 A
	.set ebpf_rc
	.reg rc

	alu[rc, --, b, ebpf_rc]

	alu[stats_idx, EBPF_RET_STATS_MASK, and, rc, >>EBPF_RET_STATS_PASS]
	move(nic_stats_extra_hi, _nic_stats_extra >>8)
	alu[act_t_idx, --, b, LM_PV_INDEX[EBPF_LM_INDEX]]

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
	br_bset[rc, EBPF_RET_DROP, DROP_LABEL], defer[1]
	local_csr_wr[T_INDEX, act_t_idx]

    br_bclr[rc, EBPF_RET_REDIR, bpf_tx_host#]

bpf_tx_wire#:
	.reg stats_base
	alu[stats_base, 0xff, AND, BF_A(in_vec, PV_STAT_bf), >>BF_L(PV_STAT_bf)]
	alu[stats_base, stats_base, +, EBPF_PORT_STATS_BLK]
	pv_stats_select(in_vec, stats_base)
	pv_reset_egress_queue(in_vec)
	br[TX_WIRE_LABEL], defer[1]
	pv_get_ingress_queue_nbi_chan(egress_q_base, in_vec)


bpf_tx_host#:
	pv_set_tx_host_rx_bpf(in_vec)
	immed[egress_q_mask, BF_MASK(PV_QUEUE_OUT_bf)]	;restore
	/* falls thru, continue with next actions  - ensure $actions[] is still live*/

	ebpf_lm_handles_undef()
ret#:
.end
#endm


#endif 	/*_EBPF_RX_UC */
