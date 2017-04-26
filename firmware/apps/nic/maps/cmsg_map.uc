/*
 * Copyright (C) 2012-2017 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        cmsg_if.uc
 * Description: Handles parsing and processing of control messages for ebpf maps
 *
 */
#ifndef _CMSG_MAP_
#define _CMSG_MAP_

#include <bitfields.uc>
#include <stdmac.uc>
#include <preproc.uc>
#include <journal.uc>
#include <nfd_user_cfg.h>
#include <ov.uc>
#include <nfd_in.uc>
#include <nfd_out.uc>
#include <gro.uc>
#include "nfd_meta_prepend.uc"
#include "pv.uc"
#include "nfd_cc.uc"

#ifndef NUM_CONTEXT
	#define NUM_CONTEXT 4
	.num_contexts 4
#endif

#ifndef INCL_CMSG_MAP_PROC
	#include "cmsg_map_types.h"
	#include "hashmap.uc"
#endif

#define CMSG_TXFR_COUNT 16
#define CMSG_DESC_LW	3

#macro cmsg_lm_handles_define()
    lm_handle_alloc(CMSG_KEY_LM_HANDLE)
    #define_eval CMSG_KEY_LM_HANDLE    _LM_NEXT_HANDLE
    #define_eval CMSG_KEY_LM_INDEX     _LM_NEXT_INDEX

    lm_handle_alloc(CMSG_VALUE_LM_HANDLE)
    #define_eval CMSG_VALUE_LM_HANDLE    _LM_NEXT_HANDLE
    #define_eval CMSG_VALUE_LM_INDEX     _LM_NEXT_INDEX
#endm

#macro cmsg_lm_handles_undef()
    lm_handle_free(CMSG_KEY_LM_HANDLE)
    #undef CMSG_KEY_LM_HANDLE
    #undef CMSG_KEY_LM_INDEX
    lm_handle_free(CMSG_VALUE_LM_HANDLE)
    #undef CMSG_VALUE_LM_HANDLE
    #undef CMSG_VALUE_LM_INDEX
#endm

#macro nfd_lm_handle_define()
    lm_handle_alloc(NFD_LM_HANDLE)
    #define_eval NFD_LM_HANDLE    _LM_NEXT_HANDLE
    #define_eval NFD_LM_INDEX     _LM_NEXT_INDEX
#endm

#macro nfd_lm_handle_undef()
    lm_handle_free(NFD_LM_HANDLE)
    #undef NFD_LM_HANDLE
    #undef NFD_LM_INDEX
#endm


#define CMSG_LM_FIELD_SZ	64
#define_eval CMSG_LM_FIELD_SZ_SHFT	(LOG2(CMSG_LM_FIELD_SZ))
#define MAP_CMSG_IN_WQ_SZ	4096

#macro cmsg_init()

	.alloc_resource MAP_CMSG_Q_IDX emem0_queues global 1

#ifdef INCL_CMSG_MAP_PROC
	pkt_counter_decl(cmsg_enq)
#else
	pkt_counter_decl(cmsg_rx)
	pkt_counter_decl(cmsg_tx)
	pkt_counter_decl(cmsg_err)
	pkt_counter_decl(cmsg_err_no_credits)
	pkt_counter_decl(cmsg_rx_bad_type)
	pkt_counter_decl(cmsg_dbg_enq)
	pkt_counter_decl(cmsg_dbg_rxq)

	.alloc_mem MAP_CMSG_Q_BASE emem0 global MAP_CMSG_IN_WQ_SZ MAP_CMSG_IN_WQ_SZ
	.init_mu_ring MAP_CMSG_Q_IDX MAP_CMSG_Q_BASE 0

	.alloc_resource MAP_CMSG_Q_DBG_IDX emem0_queues global 1
	.alloc_mem MAP_CMSG_Q_DBG_BASE emem global MAP_CMSG_IN_WQ_SZ MAP_CMSG_IN_WQ_SZ
	.init_mu_ring MAP_CMSG_Q_DBG_IDX MAP_CMSG_Q_DBG_BASE 0

	.alloc_mem LM_CMSG_BASE	lm me (NUM_CONTEXT * (CMSG_LM_FIELD_SZ * 2)) 4

	nfd_out_send_init()

#endif
#endm

#macro cmsg_free_mem_buffer(in_nfd)
	.reg bls
	.reg mu_addr
	.reg pkt_num
	//pv_free_buffers(in_nfd)			; MARY FIX ME
	cmsg_get_nfd_bls(bls, in_nfd)
	cmsg_get_mem_addr(mu_addr, in_nfd)
	bitfield_extract(pkt_num, BF_AML(in_nfd, NFD_OUT_PKTNUM_fld))
	pkt_buf_free_mu_buffer(bls, mu_addr)
	pkt_buf_free_ctm_buffer(pkt_num)
#endm

#macro cmsg_get_mem_addr(out_mem_addr, in_nfd)
.begin
	.reg mu_ptr
	bitfield_extract__sz1(mu_ptr, BF_AML(in_nfd, NFD_OUT_MUADDR_fld)) ;
	#define __MU_PTR_msb__ 28
	alu[out_mem_addr, --, B, mu_ptr, <<(31 - __MU_PTR_msb__)]
	#undef __MU_PTR_msb__
.end
#endm
#macro cmsg_get_nfd_bls(out_bls, in_nfd)
	bitfield_extract__sz1(out_bls, BF_AML(in_nfd, NFD_OUT_BLS_fld)) ;
#endm

#macro cmsg_lm_ctx_addr(out_lm_fld1,out_lm_fld2, in_ctx)
.begin
	.reg lm_off
	#define_eval __LM_CTX_SZ_SHFT__    (LOG2(CMSG_LM_FIELD_SZ * 2))
	immed[out_lm_fld1, LM_CMSG_BASE]
	alu[lm_off, --, b, in_ctx, <<__LM_CTX_SZ_SHFT__]
	alu[out_lm_fld1, out_lm_fld1, +, lm_off]
	alu[out_lm_fld2, out_lm_fld1, +, CMSG_LM_FIELD_SZ]
	#undef __LM_CTX_SZ_SHFT__
.end
#endm

/*
 * we're working on nfd out descriptor format
 */

#macro cmsg_reply(in_nfd_out_desc, in_pkt_len, NO_CREDIT_LABEL)
.begin
	.reg nfdo_desc[NFD_OUT_DESC_SIZE_LW]
	.reg nfd_credit
	.reg pkt_offset
	.reg pcinum, nfd_q, meta_len
	.reg nfd_bls
	.reg mu_ptr, mu_addr
	.reg plen

	immed[pcinum, 0]
	bitfield_extract(nfd_q, BF_AML(in_nfd_out_desc, NFD_OUT_QID_fld))

    immed[nfd_credit, 1]
	nfd_cc_acquire(0, nfd_q, NO_CREDIT_LABEL)

	alu[plen, --, b, in_pkt_len]
#ifdef CMSG_UNITTEST_CODE
	.if (plen < 64)
		immed[plen, 64]
	.endif
#endif

	move(pkt_offset, NFD_IN_DATA_OFFSET)
	cmsg_get_mem_addr(mu_addr, in_nfd_out_desc)
	immed[meta_len, 0]
			// returns plen, pkt_offset, meta_len
	nfd_out_meta_prepend(plen, pkt_offset, meta_len, CMSG_PORT, mu_addr, NFP_NET_META_REPR, YES)
	bitfield_extract(nfd_bls, BF_AML(in_nfd_out_desc, NFD_OUT_BLS_fld))
	bitfield_extract(mu_ptr, BF_AML(in_nfd_out_desc, NFD_OUT_MUADDR_fld))

    nfd_out_fill_desc(nfdo_desc, 0, 0, 0, nfd_bls,
                      mu_ptr, pkt_offset, plen,
                      meta_len)

    nfd_lm_handle_define()
   	nfd_out_send(nfdo_desc, pcinum, nfd_q, NFD_LM_HANDLE)
    nfd_lm_handle_undef()

	pkt_counter_incr(cmsg_tx)
.end
#endm

/**
 * GRO descriptor for delivery via workq
 *   word 0: GRO specific
 *   word 1-3: NFD OUT desc
 *
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +--------------+-------------+-------------------+-------+------+
 *    0  |   q_hi       |   unused    |    qnum           | dest  |type  |
 *       +-------------------------------+-------------------------------+
 *    1  |  CTM ISL  |C|  Packet Number  |SPL|0|     Starting Offset     |
 *       +-+---+-----+-+-----------------+---+-+-------------------------+
 *    2  |N|BLS|           MU Buffer Address [39:11]                     |
 *       +-+---+---------+---------------+-------------------------------+
 *    3  |D| Meta Length |  RX Queue     |           Data Length         |
 *       +-+-------------+---------------+-------------------------------+
 *
 */
#macro cmsg_get_gro_workq_desc(out_desc, in_vec, q_idx)
.begin
    .reg buf_list
    .reg ctm_buf_sz
    .reg ctm_only
    .reg desc
    .reg offset
    .reg pkt_len
    .reg pkt_num

    #if (NBI_COUNT != 1 || SS != 0)
        #error "Only targets PCIe = 0 and NFD_OUT_NBI_wrd assumes nbi = 0"
    #endif

    // Word 0
	#define __NUM_WORKQ_DESC__ 3
	#define __WORKQ_ISL__	   24
	move(desc, __NUM_WORKQ_DESC__ | ((__WORKQ_ISL__ | 0x80) << GRO_META_RINGHI_shf))
	alu_shf[desc, desc, or, q_idx, <<GRO_META_MEM_RING_RINGLO_shf]
	alu_shf[out_desc[0], desc, or, GRO_DEST_MEM_RING_3WORD, <<GRO_META_DEST_shf]

	// word 1 -- NFD_OUT_SPLIT_wrd+1
    alu[desc, BF_A(in_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_NUMBER_bf, PV_BLS_bf
    alu[pkt_len, 0, +16, desc]
    alu[pkt_num, desc, -, pkt_len]

    alu[offset, 0x7f, AND, BF_A(in_vec, PV_OFFSET_bf), >>1] ; PV_OFFSET_bf
    alu[ctm_only, 1, AND~, BF_A(in_vec, PV_SPLIT_bf), >>BF_L(PV_SPLIT_bf)] ; PV_SPLIT_bf
    alu[desc, offset, OR, ctm_only, <<NFD_OUT_CTM_ONLY_shf]			; C + offset
	alu[desc, desc, or, pkt_num]

    alu[desc, desc, OR, __ISLAND, <<NFD_OUT_CTM_ISL_shf]			;CTM ISL
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf))	; PV_CBS_bf
    alu[out_desc[1], desc, OR, ctm_buf_sz, <<NFD_OUT_SPLIT_shf] 	; SPL

    // Word 2 -- NFD_OUT_BLS_wrd+1
    alu[desc, BF_A(in_vec, PV_MU_ADDR_bf), AND~, ((BF_MASK(PV_SPLIT_bf) << BF_WIDTH(PV_CBS_bf)) | BF_MASK(PV_CBS_bf)), <<BF_L(PV_CBS_bf)]
    bitfield_extract__sz1(buf_list, BF_AML(in_vec, PV_BLS_bf)) ; PV_BLS_bf
    alu[out_desc[2], desc, OR, buf_list, <<NFD_OUT_BLS_shf]

    // Word 3 -- NFD_OUT_QID_wrd+1
    alu[desc, pkt_len, OR, BF_A(in_vec, PV_HOST_META_LENGTH_bf), <<NFD_OUT_METALEN_shf]
    #ifndef GRO_EVEN_NFD_OFFSETS_ONLY
       alu[desc, desc, OR, BF_A(in_vec, PV_OFFSET_bf), <<31]
    #endif
    alu[out_desc[3], desc, OR, BF_A(in_vec, PV_QUEUE_OUT_bf), <<NFD_OUT_QID_shf]

.end

	#undef __NUM_WORKQ_DESC__
	#undef __WORKQ_ISL__
#endm
#macro cmsg_desc_workq(o_gro_meta, in_vec, SUCCESS_LABEL)
.begin
	.reg gro_desc[GRO_META_SIZE_LW]
	.reg q_idx
	.reg word, dest
	.reg desc
	.reg msk

	move(q_idx, MAP_CMSG_Q_IDX)
	cmsg_get_gro_workq_desc(o_gro_meta, in_vec, q_idx)

	pkt_counter_incr(cmsg_enq)
	br[SUCCESS_LABEL]
.end
#endm

#macro cmsg_enqueue_dbg(in_nfd_cmsg)
.begin
    .reg q_base_hi
    .reg q_idx
    .reg $q_entry[CMSG_DESC_LW]
    .xfer_order $q_entry
	.sig q_sig

    aggregate_copy($q_entry, in_nfd_cmsg, CMSG_DESC_LW)

    move(q_base_hi, (((MAP_CMSG_Q_DBG_BASE >>32) & 0xff) <<24))
    immed[q_idx, MAP_CMSG_Q_DBG_IDX]

    pkt_counter_incr(cmsg_dbg_enq)
	mem[qadd_work, $q_entry[0], q_base_hi, <<8, q_idx, CMSG_DESC_LW], ctx_swap[q_sig]

.end
#endm

#macro cmsg_recv_workq(out_cmsg, SIGNAL, SIGTYPE)
.begin
    .reg q_base_hi
    .reg q_idx

    move(q_base_hi, (((MAP_CMSG_Q_BASE >>32) & 0xff) <<24))
    immed[q_idx, MAP_CMSG_Q_IDX]
	#if (streq('SIGTYPE', 'SIG_DONE'))
		mem[qadd_thread, out_cmsg[0], q_base_hi, <<8, q_idx, CMSG_DESC_LW], sig_done[SIGNAL]
	#elif (streq('SIGTYPE', 'SIG_WAIT'))
		mem[qadd_thread, out_cmsg[0], q_base_hi, <<8, q_idx, CMSG_DESC_LW], ctx_swap[SIGNAL]
	#else
		#error "unknown signal type"
	#endif
    pkt_counter_incr(cmsg_dbg_rxq)
.end
#endm


#macro cmsg_rx()
.begin
	.reg q_base_hi
	.reg q_idx
	.reg $nfd_data[4]
    .xfer_order $nfd_data
    .sig q_sig
	.sig cmsg_type_read_sig
	.reg nfd_pkt_meta[CMSG_DESC_LW]		; need to save first 3 words of nfd meta
	.reg mem_location
	.reg msg_type
	.reg reply_pktlen
	.reg nfd_meta_len
	.reg c_offset
	.reg req_fd

    // Fetch work from queue.
#ifndef CMSG_UNITTEST_CODE
	#define_eval __CMSG_Q_BASE__	MAP_CMSG_Q_BASE
	#define_eval __CMSG_Q_IX__		MAP_CMSG_Q_IDX
#else
	#define_eval __CMSG_Q_BASE__	MAP_CMSG_Q_DBG_BASE
	#define_eval __CMSG_Q_IDX__		MAP_CMSG_Q_DBG_IDX
#endif
    move(q_base_hi, (((__CMSG_Q_BASE__ >>32) & 0xff) <<24))
    immed[q_idx, __CMSG_Q_IDX__]
#undef __CMSG_Q_BASE__
#undef __CMSG_Q_IDX__

    mem[qadd_thread, $nfd_data[0], q_base_hi, <<8, q_idx, CMSG_DESC_LW], ctx_swap[q_sig]
	pkt_counter_incr(cmsg_rx)

	bitfield_extract(nfd_meta_len, BF_AML($nfd_data, NFD_OUT_METALEN_fld))
	alu[--, nfd_meta_len, -, 0]
	beq[cmsg_error#], defer[3]
		alu[nfd_pkt_meta[0], --, b, $nfd_data[0]]
		alu[nfd_pkt_meta[1], --, b, $nfd_data[1]]
		alu[nfd_pkt_meta[2], --, b, $nfd_data[2]]
	alu[c_offset, NFD_IN_DATA_OFFSET, -, nfd_meta_len]

	// extract buffer address.
	cmsg_get_mem_addr(mem_location, $nfd_data)
	nfd_in_meta_parse($nfd_data, nfd_meta_len, mem_location, 4, cmsg_exit_free#)

	move(c_offset, NFD_IN_DATA_OFFSET)

	alu[msg_type, --, b, *$index++]
	alu[req_fd, --, b, *$index++]
	cmsg_validate(msg_type, cmsg_error#)

    cmsg_proc(mem_location, reply_pktlen, msg_type, req_fd, cmsg_exit_free#)
	cmsg_reply(nfd_pkt_meta, reply_pktlen, cmsg_no_credit#)
	br[cmsg_exit#]

cmsg_error#:
	// count errors
	pkt_counter_incr(cmsg_err)
cmsg_exit_free#:
cmsg_no_credit#:
		pkt_counter_incr(cmsg_err_no_credits)
cmsg_pkt_error#:
	// free MU buffers
	cmsg_free_mem_buffer(nfd_pkt_meta)
	br[cmsg_exit#]
cmsg_exit_no_free#:
cmsg_exit#:
.end
#endm

/* Format of the control message -- common to all
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +---------------+---------------+---------------+---------------+
 *    0  |    padding    |     padding   |     type      |    version    |
 *       +---------------+---------------+-------------------------------+
*/

#macro cmsg_validate(io_msg_type, ERROR_LABEL)
.begin
	.reg version
	.reg tmp_type

	ld_field_w_clr[tmp_type, 0001, io_msg_type, >>8]
    .if(tmp_type > CMSG_TYPE_MAP_MAX)
		br[ERROR_LABEL]
    .endif

	ld_field_w_clr[version, 0001, io_msg_type]
    .if(version > CMSG_VERSION)
		br[ERROR_LABEL]
    .endif
	alu[io_msg_type, --, b, tmp_type]
.end
#endm

#macro cmsg_set_reply(out_cmsg, cmsg_type)
.begin
	.reg v
	.reg t

	ld_field_w_clr[v, 0001, CMSG_VERSION]
	alu[t, --, b, cmsg_type]
	alu[t, t, or, 1, <<CMSG_TYPE_MAP_REPLY_BIT]
	alu[t, v, or, t, <<8]
	alu[out_cmsg, --, b, t]
.end
#endm


#macro cmsg_proc(in_addr_hi, out_pktlen, in_cmsg_type, in_fd, ERROR_LABEL)
.begin
    .reg read $pkt_data[CMSG_TXFR_COUNT]
    .xfer_order $pkt_data
    .sig rd_sig
	.reg ctx_num
	.reg $cmsg_reply
	.reg addr_lo

	#define __CMSG_DATA_OFFSET__ (NFD_IN_DATA_OFFSET+8)
	immed[addr_lo, __CMSG_DATA_OFFSET__]
	#undef __CMSG_DATA_OFFSET__

    // Read packet data
    ov_single(OV_LENGTH, CMSG_TXFR_COUNT, OVF_SUBTRACT_ONE) // Length in 32-bit LWs
    mem[read32, $pkt_data[0], in_addr_hi, <<8, addr_lo, max_/**/CMSG_TXFR_COUNT], indirect_ref, sig_done[rd_sig]

	local_csr_rd[ACTIVE_CTX_STS]
    immed[ctx_num, 0]
    alu[ctx_num, ctx_num, and, 7]

    ctx_arb[rd_sig]

    // cmsg type  has been validated
    // Process the control message.
    #define_eval MAX_JUMP (CMSG_TYPE_MAP_MAX + 1)
    preproc_jump_targets(j, MAX_JUMP)

    #ifdef _CMSG_LOOP
        #error "_CMSG_LOOP is already defined" (_CMSG_LOOP)
    #endif
    #define_eval _CMSG_LOOP 0
    jump[in_cmsg_type, j0#], targets[PREPROC_LIST]
    #while (_CMSG_LOOP < MAX_JUMP)
        j/**/_CMSG_LOOP#:
            br[s/**/_CMSG_LOOP#]
        #define_eval _CMSG_LOOP (_CMSG_LOOP + 1)
    #endloop
    #undef _CMSG_LOOP
    #undef MAX_JUMP

    s/**/CMSG_TYPE_MAP_ALLOC#:
			_cmsg_alloc_fd(in_fd, $pkt_data, in_addr_hi, out_pktlen)
			cmsg_set_reply($cmsg_reply, in_cmsg_type)
			br[cmsg_proc_ret#]

	s0#:
    s/**/CMSG_TYPE_MAP_FREE#:		/* not supported yet */
			pkt_counter_incr(cmsg_rx_bad_type)
			br[ERROR_LABEL]

    s/**/CMSG_TYPE_MAP_LOOKUP#:
    s/**/CMSG_TYPE_MAP_ADD#:
    s/**/CMSG_TYPE_MAP_DELETE#:
    s/**/CMSG_TYPE_MAP_GETNEXT#:
		.begin
			.reg lm_key_offset
			.reg lm_value_offset

			cmsg_lm_ctx_addr(lm_key_offset,lm_value_offset, ctx_num)

			cmsg_lm_handles_define()

			local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_KEY_LM_HANDLE, lm_key_offset]
			local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_VALUE_LM_HANDLE, lm_value_offset]
			nop
			nop

			alu[CMSG_KEY_LM_INDEX++, --, b, in_fd]
			#define_eval	__LW_CNT__	CMSG_MAP_KEY_LW
			aggregate_copy(CMSG_KEY_LM_INDEX, ++, $pkt_data, 0, __LW_CNT__)

			#define_eval	__VALUE_IDX__	(__LW_CNT__)
			aggregate_copy(CMSG_VALUE_LM_INDEX, ++, $pkt_data, __VALUE_IDX__, CMSG_MAP_VALUE_LW)
			#undef __LW_CNT__
			#undef __VALUE_IDX__

			cmsg_lm_handles_undef()

			_cmsg_hashmap_op(in_cmsg_type, in_fd, lm_key_offset, lm_value_offset, in_addr_hi, out_pktlen)

		.end
        br[cmsg_proc_ret#]

cmsg_proc_ret#:
.end
#endm

#macro _cmsg_alloc_fd(in_key, in_data, in_addr_hi, out_len)
.begin
		.reg key_sz
		.reg value_sz
		.reg max_entries
		.reg fd
		.reg $reply[2]
		.xfer_order $reply
		.sig sig_reply_map_alloc
		.reg addr_lo

		alu[key_sz, --, b, in_key]

		#define_eval _VALUE_IDX_ (CMSG_MAP_ALLOC_REQ_VALUE_IDX - 1)
		#define_eval _MAX_ENT_IDX_ (CMSG_MAP_ALLOC_REQ_MAX_IDX - 1)
		alu[value_sz, --, b, in_data[_VALUE_IDX_]]
		alu[max_entries, --, b, in_data[_MAX_ENT_IDX_]]
		#undef _VALUE_IDX_
		#undef _MAX_ENT_IDX_

		immed[fd, 0]
		alu[$reply[1], --, b, fd]

		hashmap_alloc_fd(fd, key_sz, value_sz, max_entries, cont#]

		alu[$reply[1], --, b, fd]

cont#:
		cmsg_set_reply($reply[0], CMSG_TYPE_MAP_ALLOC)
		immed[addr_lo, NFD_IN_DATA_OFFSET]
		mem[write32, $reply[0], in_addr_hi, <<8, addr_lo, 2], sig_done[sig_reply_map_alloc]
		immed[out_len, (2<<2)]
		ctx_arb[sig_reply_map_alloc]

.end
#endm

#macro _cmsg_hashmap_op(in_op, in_fd, in_lm_key, in_lm_value, in_addr_hi, out_len)
.begin
	.reg op
	.reg r_addr[2]
	.reg reply_lw
	.sig sig_reply_map_ops
	.sig sig_read_ent

#define_eval __CMSG_MAX_REPLY_LW__	(CMSG_MAP_KEY_LW+2)

	.reg $reply[__CMSG_MAX_REPLY_LW__]
	.xfer_order $reply
	aggregate_directive(.set, $reply, __CMSG_MAX_REPLY_LW__)


	#define_eval	__HASHMAP_OP__ (CMSG_TYPE_MAP_LOOKUP - HASHMAP_OP_LOOKUP)
	alu[op, in_op, -, __HASHMAP_OP__]
	#undef __HASHMAP_OP__

	#define_eval MAX_JUMP (HASHMAP_OP_MAX + 1)
    preproc_jump_targets(j, MAX_JUMP)

    #ifdef _CMSG_LOOP
        #error "_CMSG_LOOP is already defined" (_CMSG_LOOP)
    #endif
    #define_eval _CMSG_LOOP 0
    jump[op, j0#], targets[PREPROC_LIST]
    #while (_CMSG_LOOP < MAX_JUMP)
        j/**/_CMSG_LOOP#:
            br[s/**/_CMSG_LOOP#]
        #define_eval _CMSG_LOOP (_CMSG_LOOP + 1)
    #endloop
    #undef _CMSG_LOOP
    #undef MAX_JUMP

s0#:
s1#:
s2#:
	br[error_map_parse#]

s/**/HASHMAP_OP_LOOKUP#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_LOOKUP, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr)
	alu[--, reply_lw, -, 0]				;error if 0
	bne[cont_proc#]
	br[error_map_function#]

s/**/HASHMAP_OP_ADD#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_ADD, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr)

	alu[--, reply_lw, -, 0]				;add & delete returns 0
	beq[success_reply#]
	br[error_map_function#]

s/**/HASHMAP_OP_REMOVE#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_REMOVE, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr)
	alu[--, reply_lw, -, 0]				;add & delete returns 0
	beq[success_reply#]
	br[error_map_function#]

s/**/HASHMAP_OP_GETNEXT#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_GETNEXT, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr)
	alu[--, reply_lw, -, 0]				;error if 0
	bne[cont_proc#]
	br[error_map_function#]

cont_proc#:
	alu[--, reply_lw, -, CMSG_MAP_KEY_LW]
	bgt[error_map_function#]
	ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, reply_lw, OVF_SUBTRACT_ONE)   ; length is in 32-bit LWs
    ov_clean
    mem[read32, $reply[2], r_addr[0], <<8, r_addr[1], max_/**/CMSG_MAP_KEY_LW], indirect_ref, sig_done[sig_read_ent]
	ctx_arb[sig_read_ent]

	unroll_copy($reply, 2, $reply, 2, reply_lw, CMSG_MAP_KEY_LW, --)

success_reply#:
	br[write_reply#], defer[2]
	immed[$reply[1], CMSG_RC_SUCCESS]
	alu[reply_lw, 2, +, reply_lw]

error_map_fd#:
	br[write_reply#], defer[2]
	immed[$reply[1], CMSG_RC_ERR_MAP_FD]
	immed[reply_lw, 2]

error_map_function#:
	br[write_reply#], defer[2]
	immed[$reply[1], CMSG_RC_ERR_MAP_ERR]
	immed[reply_lw, 2]

error_map_parse#:
	br[write_reply#], defer[2]
	immed[$reply[1], CMSG_RC_ERR_MAP_PARSE]
	immed[reply_lw, 2]

not_found#:
	br[write_reply#], defer[2]
	immed[$reply[1], CMSG_RC_ERR_MAP_NOENT]
	immed[reply_lw, 2]

write_reply#:
	.reg addr_lo
	cmsg_set_reply($reply[0], in_op)
	immed[addr_lo, NFD_IN_DATA_OFFSET]
	ov_single(OV_LENGTH, reply_lw, OVF_SUBTRACT_ONE)
    mem[write32, $reply[0], in_addr_hi, <<8, addr_lo, max_/**/__CMSG_MAX_REPLY_LW__], indirect_ref, sig_done[sig_reply_map_ops]

	alu[out_len, --, b, reply_lw, <<2]

	ctx_arb[sig_reply_map_ops]

#undef __CMSG_MAX_REPLY_LW__
.end
#endm



#endif
