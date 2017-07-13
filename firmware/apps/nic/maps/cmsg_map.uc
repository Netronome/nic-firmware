/*
 * Copyright (C) 2012-2017 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        cmsg_map.uc
 * Description: Handles parsing and processing of control messages for ebpf maps
 *
 * API calls:
 *	 cmsg_init() - declare global and local resources
 *	 cmsg_rx() - receive from workq and process cmsg
 *	 cmsg_desc_workq() - create GRO descriptors destined for cmsg workq
 *
 * typical use
 *	 from datapath action
 *		cmsg_init()
 *
 *		to send to cmsg process ME
 *			.reg $gro_meta[GRO_META_SIZE_LW]
 *			.xfer_order $gro_meta
 *			cmsg_desc_workq($gro_meta, in_pkt_vec, EGRESS_LABEL)
 *			gro_cli_send(seq_ctx, seq_no, $gro_meta, 0)
 *
 *	from cmsg handler ME
 *		cmsg_init()
 *
 *		cmsg_rx()
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
#include "pkt_buf.uc"

#ifndef NUM_CONTEXT
	#define NUM_CONTEXT 4
	.num_contexts 4
#endif

#ifndef INCL_CMSG_MAP_PROC
	#include "cmsg_map_types.h"
	#include "slicc_hash.h"
	#include "hashmap.uc"
	#include "hashmap_priv.uc"
#endif

#define CMSG_TXFR_COUNT 16
#define HASHMAP_TXFR_COUNT 16
#define	HASHMAP_RXFR_COUNT 16
#define CMSG_DESC_LW	3

#ifndef NFD_META_MAX_LW
    #define NFD_META_MAX_LW NFP_NET_META_FIELD_SIZE
#endif

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

#ifdef CMSG_MAP_PROC
	.init_csr mecsr:CtxEnables.NNreceiveConfig 0x2 const ; 0x2=NN path from CTM MiscEngine
	slicc_hash_init_nn()

	pkt_counter_decl(cmsg_enq)
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

	.reg volatile read $map_rxfr[HASHMAP_RXFR_COUNT]
	.xfer_order $map_rxfr

	.reg write $map_txfr[HASHMAP_TXFR_COUNT]
	.xfer_order $map_txfr
	__hashmap_set($map_txfr)

	.reg read $map_cam[8]
	.xfer_order $map_cam

	#define MAP_RDXR $map_rxfr
	#define MAP_TXFR $map_txfr
	#define MAP_RXCAM $map_cam[0]

	nfd_out_send_init()

#endif
#endm

#macro cmsg_free_mem_buffer(in_nfd)
	.reg bls
	.reg mu_addr
	.reg pkt_num

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
	.reg meta_len
	.reg nfd_bls
	.reg mu_ptr, mu_addr
	.reg plen
	.reg $credit
	.sig credit_sig

#define __WAIT_FOR_CREDITS
#define NO_CREDIT_SLEEP 500

	nfd_out_get_credits($credit, NIC_PCI, NFD_CTRL_QUEUE, 1, credit_sig, SIG_WAIT)
	alu[--, --, b, $credit]
	beq[NO_CREDIT_LABEL]

#ifdef __WAIT_FOR_CREDITS
	.while ($credit == 0)
		#define_eval _SLEEP_TICKS (NO_CREDIT_SLEEP / 16)
            timestamp_sleep(_SLEEP_TICKS)
        #undef _SLEEP_TICKS

        nfd_out_get_credits($credit, NIC_PCI, NFD_CTRL_QUEUE, 1, credit_sig,
                                SIG_WAIT)
    .endw
#endif

	alu[plen, --, b, in_pkt_len]

	move(pkt_offset, NFD_IN_DATA_OFFSET)
	cmsg_get_mem_addr(mu_addr, in_nfd_out_desc)
	immed[meta_len, 0]
		// meta prepend is not needed
	bitfield_extract(nfd_bls, BF_AML(in_nfd_out_desc, NFD_OUT_BLS_fld))
	bitfield_extract(mu_ptr, BF_AML(in_nfd_out_desc, NFD_OUT_MUADDR_fld))

	.reg ctm_isl
	.reg ctm_pnum
	.reg ctm_split

	bitfield_extract(ctm_isl, BF_AML(in_nfd_out_desc, NFD_OUT_CTM_ISL_fld))
	bitfield_extract(ctm_pnum, BF_AML(in_nfd_out_desc, NFD_OUT_PKTNUM_fld))
	bitfield_extract(ctm_split, BF_AML(in_nfd_out_desc, NFD_OUT_SPLIT_fld))

	pkt_buf_free_ctm_buffer(ctm_pnum)
	
    //nfd_out_fill_desc(nfdo_desc, ctm_isl, ctm_pnum, ctm_split, nfd_bls,
    nfd_out_fill_desc(nfdo_desc, 0, 0, 0, nfd_bls,
                      mu_ptr, pkt_offset, plen,
                      meta_len)

    nfd_lm_handle_define()
   	nfd_out_send(nfdo_desc, NIC_PCI, NFD_CTRL_QUEUE, NFD_LM_HANDLE)
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
    alu[desc, pkt_len, OR, BF_A(in_vec, PV_META_LENGTH_bf), <<NFD_OUT_METALEN_shf]
    #ifndef GRO_EVEN_NFD_OFFSETS_ONLY
       alu[desc, desc, OR, BF_A(in_vec, PV_OFFSET_bf), <<31]
    #endif
    alu[out_desc[3], desc, OR, BF_A(in_vec, PV_QUEUE_IN_bf), <<NFD_OUT_QID_shf]

.end
	#undef __NUM_WORKQ_DESC__
	#undef __WORKQ_ISL__
#endm
#macro cmsg_desc_workq(o_gro_meta, in_vec, SUCCESS_LABEL)
.begin
	.reg q_idx
	.reg word, dest
	.reg desc
	.reg msk

	move(q_idx, MAP_CMSG_Q_IDX)
	cmsg_get_gro_workq_desc(o_gro_meta, in_vec, q_idx)

	br[SUCCESS_LABEL]
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
	.reg cmsg_type
	.reg cmsg_tag
	.reg reply_pktlen
	.reg nfd_meta_len
	.reg c_offset
	.reg req_fd
	.reg read $cmsg_data[NFD_META_MAX_LW]
	.xfer_order $cmsg_data
	.reg cmsg_hdr_w0

    // Fetch work from queue.
	#define_eval __CMSG_Q_BASE__	MAP_CMSG_Q_BASE
	#define_eval __CMSG_Q_IDX__		MAP_CMSG_Q_IDX

    move(q_base_hi, (((__CMSG_Q_BASE__ >>32) & 0xff) <<24))
    immed[q_idx, __CMSG_Q_IDX__]

	#undef __CMSG_Q_BASE__
	#undef __CMSG_Q_IDX__

    mem[qadd_thread, $nfd_data[0], q_base_hi, <<8, q_idx, CMSG_DESC_LW], ctx_swap[q_sig]
	pkt_counter_incr(cmsg_rx)

	alu[nfd_pkt_meta[0], --, b, $nfd_data[0]]
	alu[nfd_pkt_meta[1], --, b, $nfd_data[1]]
	alu[nfd_pkt_meta[2], --, b, $nfd_data[2]]

	// extract buffer address.
	cmsg_get_mem_addr(mem_location, $nfd_data)

    .sig read_sig
	move(c_offset, NFD_IN_DATA_OFFSET)
	mem[read32, $cmsg_data[0], c_offset, mem_location, <<8, 2], ctx_swap[read_sig]
	alu[cmsg_hdr_w0, --, b, $cmsg_data[0]]
	alu[req_fd, --, b, $cmsg_data[1]]

	cmsg_validate(cmsg_type, cmsg_tag, cmsg_hdr_w0, cmsg_error#)

//		__hashmap_dbg_print(0xc002, 0, mem_location, c_offset, cmsg_type, req_fd)

    cmsg_proc(mem_location, reply_pktlen, cmsg_type, req_fd, cmsg_tag, cmsg_exit_free#)
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
 *    0  |    type       |     version   |         tag                   |
 *       +---------------+---------------+-------------------------------+
*/

#macro cmsg_validate(o_msg_type, o_tag, in_ctrl_w0, ERROR_LABEL)
.begin
	.reg version

	ld_field_w_clr[o_msg_type, 0001, in_ctrl_w0, >>24]
    .if(o_msg_type > CMSG_TYPE_MAP_MAX)
		br[ERROR_LABEL]
    .endif

	ld_field_w_clr[version, 0001, in_ctrl_w0, >>16]
    .if(version > CMSG_MAP_VERSION)
		br[ERROR_LABEL]
    .endif
	ld_field_w_clr[o_tag, 0011, in_ctrl_w0]
.end
#endm

#macro cmsg_set_reply(out_cmsg, in_cmsg_type, in_cmsg_tag)
.begin
	.reg v
	.reg t

	ld_field_w_clr[v, 0100, CMSG_MAP_VERSION, <<16]
	ld_field[v, 0011, in_cmsg_tag]
	alu[t, --, b, in_cmsg_type]
	alu[t, t, or, 1, <<CMSG_TYPE_MAP_REPLY_BIT]
	alu[out_cmsg, v, or, t, <<24]
.end
#endm


#macro cmsg_proc(in_addr_hi, out_pktlen, in_cmsg_type, in_fd, in_cmsg_tag, ERROR_LABEL)
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
			_cmsg_alloc_fd(in_fd, $pkt_data, in_addr_hi, in_cmsg_tag, out_pktlen)
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

			//	__hashmap_dbg_print(0xc0a1, 0, $pkt_data[0], $pkt_data[1], $pkt_data[2], $pkt_data[3])

			#define_eval	__VALUE_IDX__	(__LW_CNT__)
			aggregate_copy(CMSG_VALUE_LM_INDEX, ++, $pkt_data, __VALUE_IDX__, CMSG_MAP_VALUE_LW)
			//	__hashmap_dbg_print(0xc0a2, 0, $pkt_data[10], $pkt_data[11], $pkt_data[12], $pkt_data[13])
			#undef __LW_CNT__
			#undef __VALUE_IDX__

			cmsg_lm_handles_undef()

			_cmsg_hashmap_op(in_cmsg_type, in_fd, lm_key_offset, lm_value_offset, in_addr_hi, in_cmsg_tag, out_pktlen)

		.end

cmsg_proc_ret#:
.end
#endm

#macro _cmsg_alloc_fd(in_key, in_data, in_addr_hi, in_cmsg_tag, out_len)
.begin
		.reg key_sz
		.reg value_sz
		.reg max_entries
		.reg fd
		.reg $reply[3]
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
		immed[$reply[1], 1]		;rc
		immed[$reply[2], 0]		;tid

	//		__hashmap_dbg_print(0xc012, 0, key_sz, value_sz, max_entries)

		hashmap_alloc_fd(fd, key_sz, value_sz, max_entries, cont#)

		alu[$reply[2], --, b, fd]
		immed[$reply[1], 0]		;rc
	//		__hashmap_dbg_print(0xc013, 0, fd)

cont#:
		cmsg_set_reply($reply[0], CMSG_TYPE_MAP_ALLOC, in_cmsg_tag)
		immed[addr_lo, NFD_IN_DATA_OFFSET]
		mem[write32, $reply[0], in_addr_hi, <<8, addr_lo, 3], sig_done[sig_reply_map_alloc]
		immed[out_len, (3<<2)]
		ctx_arb[sig_reply_map_alloc]

.end
#endm

#macro _cmsg_hashmap_op(in_op, in_fd, in_lm_key, in_lm_value, in_addr_hi, in_cmsg_tag, out_len)
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
	hashmap_ops(in_fd, in_lm_key, --, HASHMAP_OP_LOOKUP, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr)
	alu[--, reply_lw, -, 0]				;error if 0
	bne[cont_proc#]
	br[error_map_function#]

s/**/HASHMAP_OP_ADD#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_ADD, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, --)

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
	cmsg_set_reply($reply[0], in_op, in_cmsg_tag)
	immed[addr_lo, NFD_IN_DATA_OFFSET]
	ov_single(OV_LENGTH, reply_lw, OVF_SUBTRACT_ONE)
    mem[write32, $reply[0], in_addr_hi, <<8, addr_lo, max_/**/__CMSG_MAX_REPLY_LW__], indirect_ref, sig_done[sig_reply_map_ops]

	alu[out_len, --, b, reply_lw, <<2]

	ctx_arb[sig_reply_map_ops]

#undef __CMSG_MAX_REPLY_LW__
.end
#endm



#endif
