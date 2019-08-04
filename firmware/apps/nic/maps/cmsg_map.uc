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
 *
 * SPDX-License-Identifier: BSD-2-Clause
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
#include <endian.uc>
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

#macro cmsg_bm_lm_define()
    lm_handle_alloc(CMSG_BM_LM_HANDLE)
    #define_eval CMSG_BM_LM_HANDLE    _LM_NEXT_HANDLE
    #define_eval CMSG_BM_LM_INDEX     _LM_NEXT_INDEX
#endm

#macro cmsg_bm_lm_undef()
    lm_handle_free(CMSG_BM_LM_HANDLE)
    #undef CMSG_BM_LM_HANDLE
    #undef CMSG_BM_LM_INDEX
#endm

#define CMSG_LM_FIELD_SZ	(CMSG_MAP_KEY_VALUE_LW * 4)
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

	#define CMSG_NUM_FD_BM_LW	((HASHMAP_MAX_TID_EBPF+31)/32)
	.alloc_mem LM_CMSG_FD_BITMAP lm me (CMSG_NUM_FD_BM_LW * 4) 8
	.init LM_CMSG_FD_BITMAP 0

	.alloc_mem LM_CMSG_BASE	lm me (NUM_CONTEXT * (CMSG_LM_FIELD_SZ * 4)) 8
	.init LM_CMSG_BASE 0

    #define CMSG_TXFR_COUNT 16
    #define HASHMAP_TXFR_COUNT 16
    #define HASHMAP_RXFR_COUNT 16

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
.begin
    .reg isl
    .reg bls
    .reg mu_addr
    .reg pkt_num

    bitfield_extract(bls, BF_AML(in_nfd, NFD_OUT_BLS_fld))
    bitfield_extract(mu_addr, BF_AML(in_nfd, NFD_OUT_MUADDR_fld))
    bitfield_extract(pkt_num, BF_AML(in_nfd, NFD_OUT_PKTNUM_fld))
    bitfield_extract(isl, BF_AML(in_nfd, NFD_OUT_CTM_ISL_fld))
    pkt_buf_free_mu_buffer(bls, mu_addr)
    pkt_buf_free_ctm_buffer(isl, pkt_num)
.end
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

#macro cmsg_lm_ctx_addr(out_lm_fld1,out_lm_fld2, in_ctx)
.begin
	.reg lm_off
		/* 4 context mode */
	#define_eval __LM_CTX_SZ_SHFT__    (LOG2(CMSG_LM_FIELD_SZ))
	immed[out_lm_fld1, LM_CMSG_BASE]
	alu[lm_off, --, b, in_ctx, <<__LM_CTX_SZ_SHFT__]
	alu[out_lm_fld1, out_lm_fld1, +, lm_off]
	alu[out_lm_fld2, out_lm_fld1, +, CMSG_LM_FIELD_SZ]
	#undef __LM_CTX_SZ_SHFT__
.end
#endm

#macro cmsg_alloc_fd_from_bm(out_tid, NO_FREE_TID_LABEL)
.begin
	.reg lm_addr
	.reg bitmap
	.reg count
	.reg bm_idx
	.reg bm_offset

	immed[lm_addr, LM_CMSG_FD_BITMAP]
	cmsg_bm_lm_define()
	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_BM_LM_HANDLE, lm_addr]
	immed[count, CMSG_NUM_FD_BM_LW]
	immed[out_tid, 0]
	immed[bm_offset, 0]

loop#:
		alu[bitmap, --, ~b, CMSG_BM_LM_INDEX]
		beq[next#]				; no free slots
		ffs[bm_idx, bitmap]
		alu[--, bm_idx, or, 0]
		alu[bitmap, CMSG_BM_LM_INDEX, or, 1, <<indirect]
		alu[CMSG_BM_LM_INDEX, --, b, bitmap]
		alu[bm_idx, bm_idx, +, 1]
		alu[out_tid, bm_idx, +, bm_offset]
		br[ret#]
	next#:
		alu[--, --, b, CMSG_BM_LM_INDEX++]
		alu[bm_offset, bm_offset, +, 32]
		alu[count, count, -, 1]
		bne[loop#]

	br[NO_FREE_TID_LABEL]
ret#:
	cmsg_bm_lm_undef()
.end
#endm

#macro cmsg_free_fd_from_bm(in_tid, ERROR_LABEL)
.begin
	.reg lm_addr
	.reg bitmap
	.reg bm_offset
	.reg bm_idx
	.reg tid
    .reg tmp

	alu[--, in_tid, -, HASHMAP_MAX_TID_EBPF]
	bgt[ERROR_LABEL]

    immed[lm_addr, LM_CMSG_FD_BITMAP]
    alu[tid, in_tid, -, 1]
    alu[bm_offset, --, b, tid, >>5]
    alu[tmp, --, b, bm_offset, <<2]
    alu[lm_addr, lm_addr, +, tmp]

	cmsg_bm_lm_define()
	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_BM_LM_HANDLE, lm_addr]
	alu[bm_offset, --, b, bm_offset, <<5]
	alu[bm_idx, tid, -, bm_offset]
	nop
	alu[--, bm_idx, or, 0]
	alu[CMSG_BM_LM_INDEX, CMSG_BM_LM_INDEX, and~, 1, <<indirect]

	cmsg_bm_lm_undef()
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
	immed[meta_len, 0]
		// meta prepend is not needed
	bitfield_extract(nfd_bls, BF_AML(in_nfd_out_desc, NFD_OUT_BLS_fld))
	bitfield_extract(mu_ptr, BF_AML(in_nfd_out_desc, NFD_OUT_MUADDR_fld))

	.reg ctm_pnum
    .reg ctm_isl

	bitfield_extract(ctm_pnum, BF_AML(in_nfd_out_desc, NFD_OUT_PKTNUM_fld))
    bitfield_extract(ctm_isl, BF_AML(in_nfd_out_desc, NFD_OUT_CTM_ISL_fld))
	pkt_buf_free_ctm_buffer(ctm_isl, ctm_pnum)

    nfd_out_fill_desc(nfdo_desc, 0, 0, nfd_bls,
                      mu_ptr, plen, 0, pkt_offset,
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
    .reg meta_len
    .reg offset
    .reg pkt_len
    .reg pkt_num

    #if (SS != 0)
        #error "Only targets PCIe = 0"
    #endif

    #ifdef SPLIT_EMU_RINGS
        // NFD supports SPLIT_EMU_RINGS (separate EMU rings for each NBI)
        // by providing the "N" bit extending the BLS field.  In practice
        // If SPLIT_EMU_RINGS is _not_ used, then N is simply zero for all
        // NBIs.
        #error "SPLIT_EMU_RINGS configuration not supported."
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
    #ifndef GRO_EVEN_NFD_OFFSETS_ONLY
        alu[desc, pkt_len, OR, BF_A(in_vec, PV_OFFSET_bf), <<31]
        alu[out_desc[3], desc, OR, BF_A(in_vec, PV_QUEUE_IN_bf), <<NFD_OUT_QID_shf]
    #else
        alu[out_desc[3], pkt_len, OR, BF_A(in_vec, PV_QUEUE_IN_bf), <<NFD_OUT_QID_shf]
    #endif

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
	.reg cmsg_addr_hi
	.reg cmsg_type
	.reg cmsg_reply_pktlen
	.reg nfd_meta_len
	.reg c_offset
	.reg read $cmsg_data[6]
	.xfer_order $cmsg_data
	.reg cmsg_hdr_w0
	.reg cmsg_tag

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
	cmsg_get_mem_addr(cmsg_addr_hi, $nfd_data)

    .sig read_sig
	move(c_offset, NFD_IN_DATA_OFFSET)
	mem[read32, $cmsg_data[0], c_offset, cmsg_addr_hi, <<8, 6], ctx_swap[read_sig]
	alu[cmsg_hdr_w0, --, b, $cmsg_data[0]]

	cmsg_validate(cmsg_type, cmsg_tag, cmsg_hdr_w0, cmsg_error#)

    cmsg_proc($cmsg_data, cmsg_exit_free_error#, cmsg_exit_free#)
	cmsg_reply(nfd_pkt_meta, cmsg_reply_pktlen, cmsg_no_credit#)
	br[cmsg_exit#]

cmsg_error#:
	pkt_counter_incr(cmsg_err)
cmsg_no_credit#:
cmsg_exit_free_error#:
	pkt_counter_incr(cmsg_err_no_credits)
cmsg_pkt_error#:
	// free CTM + MU buffers
cmsg_exit_free#:
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


 #macro cmsg_proc(HDR_DATA, ERROR_LABEL, FREE_LABEL)
.begin
    .reg read $pkt_data[CMSG_TXFR_COUNT]
    .xfer_order $pkt_data
	.reg write $reply[3]
	.xfer_order $reply
    .sig rd_sig
	.reg ctx_num
	.reg addr_lo
	.reg count, flags
	.reg key_offset, value_offset
	.reg rc
	.sig sig_reply_map_ops
	.reg map_op
	.reg l_cmsg_type
	.reg cur_fd
	.reg map_type

	#define __CMSG_DATA_OFFSET__ (NFD_IN_DATA_OFFSET)
	immed[addr_lo, __CMSG_DATA_OFFSET__]
	#undef __CMSG_DATA_OFFSET__

	local_csr_rd[ACTIVE_CTX_STS]
    immed[ctx_num, 0]
    alu[ctx_num, ctx_num, and, 7]

	immed[cmsg_reply_pktlen, 0]
	alu[l_cmsg_type, --, b, cmsg_type]


    // cmsg type  has been validated
    // Process the control message.
    #define_eval MAX_JUMP (CMSG_TYPE_MAP_MAX + 1)
    preproc_jump_targets(j, MAX_JUMP)

    #ifdef _CMSG_LOOP
        #error "_CMSG_LOOP is already defined" (_CMSG_LOOP)
    #endif
    #define_eval _CMSG_LOOP 0
    jump[cmsg_type, j0#], targets[PREPROC_LIST]
    #while (_CMSG_LOOP < MAX_JUMP)
        j/**/_CMSG_LOOP#:
            br[s/**/_CMSG_LOOP#]
        #define_eval _CMSG_LOOP (_CMSG_LOOP + 1)
    #endloop
    #undef _CMSG_LOOP
    #undef MAX_JUMP

    s/**/CMSG_TYPE_MAP_ALLOC#:
		.begin
			.reg keysz, valuesz, maxent
			alu[keysz, --, b, HDR_DATA[CMSG_MAP_ALLOC_KEYSZ_IDX]]
			alu[valuesz, --, b,  HDR_DATA[CMSG_MAP_ALLOC_VALUESZ_IDX]]
			alu[maxent, --, b,  HDR_DATA[CMSG_MAP_ALLOC_MAXENT_IDX]]
			alu[map_type, --, b, HDR_DATA[CMSG_MAP_ALLOC_TYPE_IDX]]
			bne[alloc_cont#]
			immed[map_type, BPF_MAP_TYPE_HASH]		; default is hash
alloc_cont#:
			_cmsg_alloc_fd(keysz, valuesz, maxent, swap, map_type)
			br[cmsg_proc_ret#]
		 .end

	s0#:
    s/**/CMSG_TYPE_MAP_FREE#:
			alu[cur_fd, --, b, HDR_DATA[CMSG_MAP_TID_IDX]]
			_cmsg_free_fd(cur_fd)
			br[cmsg_proc_ret#]

    s/**/CMSG_TYPE_MAP_LOOKUP#:
    s/**/CMSG_TYPE_MAP_ADD#:
    s/**/CMSG_TYPE_MAP_DELETE#:
    s/**/CMSG_TYPE_MAP_GETNEXT#:
    s/**/CMSG_TYPE_MAP_GETFIRST#:
		.begin
			.reg lm_key_offset
			.reg lm_value_offset
			.reg save_rc
			.reg l_cmsg_type
			.reg rtn_count
			.reg map_type
			.reg max_entries
			.reg cur_key
			.reg le_key

			cmsg_lm_ctx_addr(lm_key_offset,lm_value_offset, ctx_num)
			cmsg_lm_handles_define()
			immed[cmsg_reply_pktlen, 0]
			immed[rtn_count, 0]
			immed[cur_key, 0]
			immed[le_key, 0]

			alu[cur_fd, --, b, HDR_DATA[CMSG_MAP_TID_IDX]]
			alu[count, --, b, HDR_DATA[CMSG_MAP_OP_COUNT_IDX]]
			alu[flags, --, b, HDR_DATA[CMSG_MAP_OP_FLAGS_IDX]]
			alu[key_offset, addr_lo, +, (CMSG_OP_HDR_LW*4)]
			alu[l_cmsg_type, --, b, cmsg_type]

			immed[save_rc, CMSG_RC_ERR_MAP_FD]
			hashmap_get_fd_attr(cur_fd, map_type, max_entries, done#)
			immed[save_rc, CMSG_RC_SUCCESS]

			.if (cmsg_type == CMSG_TYPE_MAP_ADD)
				.if (flags == CMSG_BPF_NOEXIST)
					immed[l_cmsg_type, HASHMAP_OP_ADD_ONLY]
				.elif (flags == CMSG_BPF_EXIST)
					immed[l_cmsg_type, HASHMAP_OP_UPDATE]
				.endif
			.endif

proc_loop#:
			local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_KEY_LM_HANDLE, lm_key_offset]
			local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_VALUE_LM_HANDLE, lm_value_offset]
			nop
			nop

			alu[--, map_type, -, BPF_MAP_TYPE_ARRAY]
			beq[proc_array_map#]
    		ov_single(OV_LENGTH, CMSG_TXFR_COUNT, OVF_SUBTRACT_ONE) // Length in 32-bit LWs
    		mem[read32_swap, $pkt_data[0], cmsg_addr_hi, <<8, key_offset, max_/**/CMSG_TXFR_COUNT], indirect_ref, sig_done[rd_sig]
			ctx_arb[rd_sig]
			aggregate_copy(CMSG_KEY_LM_INDEX, ++, $pkt_data, 0, (CMSG_TXFR_COUNT-1))
			br[proc_loop_cont#]
proc_array_map#:
    		mem[read32_swap, $pkt_data[0], cmsg_addr_hi, <<8, key_offset, 1], sig_done[rd_sig]
			ctx_arb[rd_sig]
			alu[cur_key, --, b, $pkt_data[0]]
            .if (l_cmsg_type == CMSG_TYPE_MAP_GETFIRST)
                br[array_map_setkey#], defer[2]
                    immed[cur_key, 0]
                    immed[l_cmsg_type, CMSG_TYPE_MAP_ARRAY_GETNEXT]
            .elif (l_cmsg_type == CMSG_TYPE_MAP_GETNEXT)
                immed[l_cmsg_type, CMSG_TYPE_MAP_ARRAY_GETNEXT]
                alu[cur_key, cur_key, +, 1]
                alu[--, max_entries, -, cur_key]
                bge[array_map_setkey#]
                immed[cur_key, 0]
                br[array_map_setkey#]
            .endif
            alu[--, max_entries, -, cur_key]
            bgt[array_map_setkey#]
            immed[save_rc, CMSG_RC_ERR_E2BIG]
            br[done#], defer[2]
                alu[value_offset, key_offset, +,64]
                alu[cmsg_reply_pktlen, cmsg_reply_pktlen, +, (64*2)]
        array_map_setkey#:
			alu[CMSG_KEY_LM_INDEX++, --, b, cur_key]

proc_loop_cont#:
			alu[value_offset, key_offset, +, 64]		; value & key offset in cmsg

    		ov_single(OV_LENGTH, CMSG_TXFR_COUNT, OVF_SUBTRACT_ONE) // Length in 32-bit LWs
    		mem[read32_swap, $pkt_data[0], cmsg_addr_hi, <<8, value_offset, max_/**/CMSG_TXFR_COUNT], indirect_ref, sig_done[rd_sig]
			ctx_arb[rd_sig]

			aggregate_copy(CMSG_VALUE_LM_INDEX, ++, $pkt_data, 0, CMSG_TXFR_COUNT)

			cmsg_lm_handles_undef()

do_op#:
			swap(le_key, cur_key, NO_LOAD_CC)

			_cmsg_hashmap_op(l_cmsg_type, cur_fd, lm_key_offset, lm_value_offset, cmsg_addr_hi, key_offset, value_offset, flags, rc, swap, le_key, cur_key)
    /* check if reply required */
            alu[--, cur_fd, -, SRIOV_TID]
            beq[FREE_LABEL]
			alu[key_offset, value_offset, +, 64]
			alu[cmsg_reply_pktlen, cmsg_reply_pktlen, +, (64*2)]
			alu[save_rc, save_rc, or, rc]
			.if (rc == CMSG_RC_SUCCESS)
				alu[rtn_count, 1, +, rtn_count]
			.endif
			alu[count, count, -, 1]
			beq[done#]
			.if (l_cmsg_type == CMSG_TYPE_MAP_GETFIRST)
				immed[l_cmsg_type, CMSG_TYPE_MAP_GETNEXT]
			.endif
			.if (l_cmsg_type == CMSG_TYPE_MAP_GETNEXT)
				.if (rc != CMSG_RC_SUCCESS)
					br[done#]
				.endif
				br[do_op#], defer[1]
				alu[value_offset, key_offset, +, 64]
			.elif (l_cmsg_type == CMSG_TYPE_MAP_ARRAY_GETNEXT)
				alu[cur_key, cur_key, +, 1]
				alu[--, max_entries, -, cur_key]
				beq[done#]
				br[do_op#], defer[1]
				alu[value_offset, key_offset, +, 64]
			.endif
			br[proc_loop#]

done#:
			/* fill in header here */
			cmsg_set_reply($reply[0], cmsg_type, cmsg_tag)
			alu[$reply[1], --, b, save_rc]
			alu[$reply[2], --, b, rtn_count]
			immed[addr_lo, NFD_IN_DATA_OFFSET]
    		mem[write32, $reply[0], cmsg_addr_hi, <<8, addr_lo, 3], sig_done[sig_reply_map_ops]
    		alu[cmsg_reply_pktlen, cmsg_reply_pktlen, +, (4*4)]
			ctx_arb[sig_reply_map_ops]

		.end

cmsg_proc_ret#:
.end
#endm

#macro _cmsg_alloc_fd(key_sz, value_sz, max_entries, endian, map_type)
.begin
		.reg fd
		.reg $reply[3]
		.xfer_order $reply
		.sig sig_reply_map_alloc
		.reg addr_lo


		immed[$reply[1], CMSG_RC_ERR_MAP_FD]		; error
		immed[fd, 0]
		alu[$reply[2], --, b, fd]					; fd=0 error

		cmsg_alloc_fd_from_bm(fd, cont#)			; skip alloc if no free slots

		// driver will initialize arraymap
		hashmap_alloc_fd(fd, key_sz, value_sz, max_entries, cont#, endian, map_type)

		immed[$reply[1], CMSG_RC_SUCCESS]			; success
		alu[$reply[2], --, b, fd]

cont#:
		cmsg_set_reply($reply[0], CMSG_TYPE_MAP_ALLOC, cmsg_tag)
		immed[addr_lo, NFD_IN_DATA_OFFSET]
		mem[write32, $reply[0], cmsg_addr_hi, <<8, addr_lo, 3], sig_done[sig_reply_map_alloc]
		immed[cmsg_reply_pktlen, (3<<2)]
		ctx_arb[sig_reply_map_alloc]


ret#:
.end
#endm

#macro _cmsg_free_fd(in_fd)
.begin
		.reg del_entries
		.reg $reply[3]
		.xfer_order $reply
		.sig sig_reply_map_free
		.reg addr_lo
		.reg key_sz
		.reg value_sz
		.reg ent_state, ent_addr_hi, ent_offset, mu_partition, ent_index
		.reg tbl_addr_hi, out_ent_lw

		immed[del_entries, 0]

		immed[$reply[1], CMSG_RC_ERR_MAP_FD]			;
		cmsg_free_fd_from_bm(in_fd, ret#)

		__hashmap_table_delete(in_fd)		/* set num entries to 0 */

		immed[ent_index, 0]
loop#:
		__hashmap_lock_init(ent_state, ent_addr_hi, ent_offset, mu_partition, ent_index)
		alu[tbl_addr_hi, --, b, ent_addr_hi]
		__hashmap_lock_shared(ent_index, in_fd, cont#, cont#)
cont#:
        /* check overflow first */
        __hashmap_ov_getnext(tbl_addr_hi, ent_index, in_fd, ent_addr_hi, ent_offset, ent_state, del_ent#)
        __hashmap_lock_release(ent_index, ent_state)
        __hashmap_select_next_/**/HASHMAP_PARTITIONS/**/_partition(mu_partition,ent_index, end_loop#)
        __hashmap_lock_init(ent_state, tbl_addr_hi, ent_offset, mu_partition, ent_index)
        __hashmap_lock_shared(ent_index, in_fd, cont#, cont#)
        alu[ent_addr_hi, --, b, tbl_addr_hi]
del_ent#:
        __hashmap_lock_upgrade(ent_index, ent_state, loop#)
        __hashmap_set_opt_field(out_ent_lw, 0)
        br_bset[ent_state, __HASHMAP_DESC_OV_BIT, delete_ov_ent#]
        __hashmap_lock_release_and_invalidate(ent_index, ent_state, in_fd)

		alu[del_entries, 1, +, del_entries]
		br[loop#]

delete_ov_ent#:
    	__hashmap_ov_delete(tbl_addr_hi, ent_index, ent_offset, ent_state)
    	__hashmap_lock_release(ent_index, ent_state)

		alu[del_entries, 1, +, del_entries]
		br[loop#]

end_loop#:

		immed[$reply[1], CMSG_RC_SUCCESS]

ret#:
		alu[$reply[2], --, b, del_entries]

		cmsg_set_reply($reply[0], CMSG_TYPE_MAP_FREE, cmsg_tag)
		immed[addr_lo, NFD_IN_DATA_OFFSET]
		mem[write32, $reply[0], cmsg_addr_hi, <<8, addr_lo, 3], sig_done[sig_reply_map_free]
		immed[cmsg_reply_pktlen, (3<<2)]
		ctx_arb[sig_reply_map_free]

.end
#endm

#define_eval _CMSG_FLD_LW 			(CMSG_MAP_KEY_VALUE_LW)
#define_eval _CMSG_FLD_LW_MINUS_1   (_CMSG_FLD_LW - 1)

#macro _cmsg_hashmap_op(in_op, in_fd, in_lm_key, in_lm_value, in_addr_hi, in_key_offset, in_value_offset, in_flags, out_rc, endian, array_lekey, array_bekey)
.begin
	.reg op
	.sig sig_read_ent
	.sig sig_reply_map_ops
	.reg $ent_reply[_CMSG_FLD_LW]
	.xfer_order $ent_reply
	.sig sig_write_reply
	.reg reply_lw
	.reg error_value
	.reg r_addr[2]
	.reg ent_offset
	.reg tmp

	aggregate_directive(.set, $ent_reply, _CMSG_FLD_LW)

	#define_eval	__HASHMAP_OP__ (CMSG_TYPE_MAP_LOOKUP - HASHMAP_OP_LOOKUP)
	.if (in_op == CMSG_TYPE_MAP_ARRAY_GETNEXT)
		cmsg_lm_handles_define()
    	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_KEY_LM_HANDLE, lm_key_offset]
		immed[op, CMSG_TYPE_MAP_LOOKUP]
		alu[$ent_reply[0], --, b, array_lekey]
		mem[write32, $ent_reply[0], in_addr_hi, <<8, in_key_offset, 1], sig_done[sig_reply_map_ops]
		alu[CMSG_KEY_LM_INDEX, --, b, array_bekey]
    	cmsg_lm_handles_undef()
    	ctx_arb[sig_reply_map_ops]
	.else
		alu[op, in_op, -, __HASHMAP_OP__]
	.endif
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
	br[error_map_function#], defer[1]
	immed[out_rc, CMSG_RC_ERR_MAP_PARSE]

s/**/HASHMAP_OP_LOOKUP#:
	hashmap_ops(in_fd, in_lm_key, --, HASHMAP_OP_LOOKUP, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr, endian, out_rc)
	alu[--, reply_lw, -, 0]				;error if 0
	bne[reply_value#]
	br[error_map_function#], defer[1]
	immed[out_rc, CMSG_RC_ERR_MAP_ERR]

s/**/HASHMAP_OP_ADD_ANY#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_ADD_ANY, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, --, endian, out_rc)
    br[ret#]

s/**/HASHMAP_OP_UPDATE#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_UPDATE, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, --, endian, out_rc)
    br[ret#]

s/**/HASHMAP_OP_ADD_ONLY#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_ADD_ONLY, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, --, endian, out_rc)
    br[ret#]

s/**/HASHMAP_OP_REMOVE#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_REMOVE, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr, endian, out_rc)
    br[ret#]

s/**/HASHMAP_OP_GETNEXT#:
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_GETNEXT, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr, endian, out_rc)
	alu[--, reply_lw, -, 0]				;error if 0
	bne[reply_keys#]
	br[error_map_function#], defer[1]
	immed[out_rc, CMSG_RC_ERR_MAP_ERR]

s/**/HASHMAP_OP_GETFIRST#:
	#pragma warning(push)
    #pragma warning(disable: 4702) // disable warning "unreachable code"
	hashmap_ops(in_fd, in_lm_key, in_lm_value, HASHMAP_OP_GETFIRST, error_map_fd#, not_found#,HASHMAP_RTN_ADDR,reply_lw, --, r_addr, endian, out_rc)
	alu[--, reply_lw, -, 0]				;error if 0
	bne[reply_keys#]
	br[error_map_function#], defer[1]
	immed[out_rc, CMSG_RC_ERR_MAP_ERR]
	#pragma warning(pop)

error_map_fd#:
	br[error_map_function#], defer[1]
	immed[out_rc, CMSG_RC_ERR_MAP_FD]

not_found#:
	br[error_map_function#], defer[1]
	immed[out_rc, CMSG_RC_ERR_MAP_NOENT]

error_map_function#:
    .if (out_rc == CMSG_RC_ERR_EEXIST)
        immed[out_rc, CMSG_RC_ERR_MAP_EXIST]
    .elif (out_rc == CMSG_RC_ERR_ENOMEM)
        immed[out_rc, CMSG_RC_ERR_NOMEM]
    .endif
	move(error_value, 0xffff0000)
	alu[$ent_reply[0], error_value, or, out_rc]
	alu[ent_offset, in_key_offset, +, (15*4)]				; write FFs and rc to last 1 words of key
    mem[write32, $ent_reply[0], in_addr_hi, <<8, ent_offset, 1], sig_done[sig_reply_map_ops]
	ctx_arb[sig_reply_map_ops], br[ret#]

reply_keys#:
    alu[--, reply_lw, -, 0]
    beq[error_map_function#], defer[1]
        immed[out_rc, CMSG_RC_ERR_MAP_ERR]
	ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, reply_lw, OVF_SUBTRACT_ONE)   ; length is in 32-bit LWs
    ov_clean
    mem[read32, $ent_reply[0], r_addr[0], <<8, r_addr[1], max_/**/_CMSG_FLD_LW], indirect_ref, sig_done[sig_read_ent]
	aggregate_zero($ent_reply, _CMSG_FLD_LW)
	ctx_arb[sig_read_ent]

	unroll_copy($ent_reply, 0, $ent_reply, 0, reply_lw, _CMSG_FLD_LW, --)
	ov_single(OV_LENGTH, _CMSG_FLD_LW, OVF_SUBTRACT_ONE)
    mem[write32, $ent_reply[0], in_addr_hi, <<8, in_key_offset, max_/**/_CMSG_FLD_LW], indirect_ref, sig_done[sig_reply_map_ops]

		/* copy keys to LM for getnext & getfirst */
	cmsg_lm_handles_define()
	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_KEY_LM_HANDLE, lm_key_offset]
	nop
	nop
	nop
	aggregate_copy(CMSG_KEY_LM_INDEX, ++, $ent_reply, 0, _CMSG_FLD_LW_MINUS_1)
	cmsg_lm_handles_undef()

	alu[tmp, --, b, reply_lw, <<2]
    __hashmap_calc_value_addr(r_addr[1], tmp, r_addr[1])
	alu[reply_lw, 16, -, reply_lw]
	ctx_arb[sig_reply_map_ops]				; falls thru

reply_value#:
    alu[--, reply_lw, -, 0]
    beq[error_map_function#], defer[1]
        immed[out_rc, CMSG_RC_ERR_MAP_ERR]
	ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, reply_lw, OVF_SUBTRACT_ONE)   ; length is in 32-bit LWs
    ov_clean
    mem[read32, $ent_reply[0], r_addr[0], <<8, r_addr[1], max_/**/_CMSG_FLD_LW], indirect_ref, sig_done[sig_read_ent]
	aggregate_zero($ent_reply, _CMSG_FLD_LW)
	ctx_arb[sig_read_ent]

	unroll_copy($ent_reply, 0, $ent_reply, 0, reply_lw, _CMSG_FLD_LW, --)

	ov_single(OV_LENGTH, _CMSG_FLD_LW, OVF_SUBTRACT_ONE)
    mem[write32, $ent_reply[0], in_addr_hi, <<8, in_value_offset, max_/**/_CMSG_FLD_LW], indirect_ref, sig_done[sig_reply_map_ops]

	immed[out_rc, CMSG_RC_SUCCESS]
	ctx_arb[sig_reply_map_ops]

ret#:

.end
#endm

/*
 * This macro is currently not used.  Driver initializes arraymap
 * init array map entries
 * array maps:  key_size = 4, key = 0..max_entries-1
 *              value_size must be zeroed
 * TABLE_OP = INIT or CLEANUP
 */
#macro _cmsg_arraymap_table_op(in_fd, in_num_entries, SUCCESS_LABEL, TABLE_OP)
.begin
	.reg lm_key_offset
	.reg lm_value_offset
	.reg ctx_num
	.reg array_ndx
	.reg reply_lw
	//.reg le_key

	local_csr_rd[ACTIVE_CTX_STS]
    immed[ctx_num, 0]
    alu[ctx_num, ctx_num, and, 7]

	cmsg_lm_ctx_addr(lm_key_offset, lm_value_offset, ctx_num)
	cmsg_lm_handles_define()

    local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_VALUE_LM_HANDLE, lm_value_offset]
	immed[array_ndx, 0]
    nop
    nop
	aggregate_zero(CMSG_VALUE_LM_INDEX, CMSG_TXFR_COUNT)

init_loop#:
	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_KEY_LM_HANDLE, lm_key_offset]
		nop
		swap(le_key, array_ndx, NO_LOAD_CC)
	alu[CMSG_KEY_LM_INDEX++, --, b, le_key]

    cmsg_lm_handles_undef()

	#if (streq('TABLE_OP', 'INIT'))
		hashmap_ops(in_fd, lm_key_offset, lm_value_offset, HASHMAP_OP_ADD_ANY, error_rtn#, error_rtn#, HASHMAP_RTN_ADDR, reply_lw, --, --, be)
	#else
		hashmap_ops(in_fd, lm_key_offset, lm_value_offset, HASHMAP_OP_REMOVE, error_rtn#, error_rtn#, HASHMAP_RTN_ADDR, reply_lw, --, --, be)
	#endif

	alu[--, reply_lw, -, 0]
	bne[error_rtn#]

	alu[array_ndx, 1, +, array_ndx]
	alu[--, in_num_entries, -, array_ndx]
	bne[init_loop#]

	br[SUCCESS_LABEL]

error_rtn#:
.end
#endm


#endif
