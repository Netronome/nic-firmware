/*
 * Copyright (c) 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _CMSG_PRINT_UC
#define _CMSG_PRINT_UC


#include <aggregate.uc>
#include <stdmac.uc>
#include <blm_api.uc>
#include <ov.uc>
#include <endian.uc>

#include "pkt_buf.uc"
#include "blm_custom.h"

/*
 *
 *  cmsg_print:
 *		function to implement bpf function:
 *				* int bpf_perf_event_output(ctx, map, flags, data, size)
 *					where data and size are input to cmsg_print()
 *
 *		or bpf_trace_printk(____fmt, sizeof(____fmt), ##__VA_ARGS__);
 *				max of 5 args, but need to implement format string
 *
 */



/**
 * Packet prepend format for packets going to the host that need to
 * include RSS or input port information.
 *
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-----------+-+-----------------+---+-+-------------------------+
 *    0  |  CTM ISL  |C|  Packet Number  |SPL|0|     Starting Offset     |
 *       +-+---+-----+-+-----------------+---+-+-------------------------+
 *    1  |N|BLS|           MU Buffer Address [39:11]                     |
 *       +-+---+---------+---------------+-------------------------------+
 *    2  |D| Meta Length |  RX Queue     |           Data Length         |
 *       +-+-------------+---------------+-------------------------------+
 *    3  |             VLAN              |             Flags             |
 *       +-------------------------------+-------------------------------+
 */



/*
 * format:
			uint32_t type:8;      CMSG_TYPE_PRINT
            uint32_t ver:8;
            uint32_t tag:16;
			struct {				 can be > 1
				uint32_t length;	 in bytes
				uint32_t data;		 data
			};

			tag format is iimc
				where ii = island number
					  m  = me number
					  c  = context number
 */


#macro __cmsg_print_lm_handles_define()
	#define_eval CMSG_PRINT_LM_HANDLE 3
	#define_eval CMSG_PRINT_LM_INDEX  *l$index3
#endm

#macro __cmsg_print_lm_handles_undef()
	#undef CMSG_PRINT_LM_HANDLE
	#undef CMSG_PRINT_LM_INDEX
#endm

#macro cmsg_alloc_mu_buffer(in_bls, out_mu_addr, out_mu_ptr)
.begin
    .reg blm_ring
    .reg addr_hi
	.reg $mem_bufptr
	.sig blm_alloc_sig

	#define __MU_PTR_msb__ 28
    #define_eval _PKT_BUF_ALLOC_POOL strleft(NFD_OUT_BLM_POOL_START, strlen(NFD_OUT_BLM_POOL_START)-2)
    #if (_PKT_BUF_ALLOC_POOL/**/_LOCALITY == MU_LOCALITY_DIRECT_ACCESS)
        alu[addr_hi, --, B, ((_PKT_BUF_ALLOC_POOL/**/_LOCALITY << 6) | (_PKT_BUF_ALLOC_POOL/**/_ISLAND & 0x3f)), <<24]
    #else
        alu[addr_hi, --, B, ((_PKT_BUF_ALLOC_POOL/**/_LOCALITY << 6) | (1 << 5) | ((_PKT_BUF_ALLOC_POOL/**/_ISLAND & 0x3) << 3)), <<24]
    #endif

	move(blm_ring, BLM_NBI8_BLQ0_EMU_QID)
	alu[blm_ring, blm_ring, or, in_bls]

alloc_mu#:
	mem[pop, $mem_bufptr, addr_hi, <<8, blm_ring, 1], sig_done[blm_alloc_sig]
	ctx_arb[blm_alloc_sig[0]]
	br_!signal[blm_alloc_sig[1], ret#], defer[2]
    	alu[out_mu_ptr, --, B, $mem_bufptr, <<(31 - __MU_PTR_msb__)]
		alu[out_mu_addr, --, b, $mem_bufptr]

blm_buf_error#:     // no buffers, wait
    #define __NO_BLM_BUFFERS_SLEEP__ 500
    #define_eval _SLEEP_TICKS (__NO_BLM_BUFFERS_SLEEP__ / 16)
            timestamp_sleep(_SLEEP_TICKS)
            br[alloc_mu#]
    #undef _SLEEP_TICKS
    #undef __NO_BLM_BUFFERS_SLEEP__

ret#:
	.io_completed blm_alloc_sig
    #undef __MU_PTR_msb__
.end
#endm


#macro cmsg_print(in_lm_addr, in_bytes_len)
.begin

	.reg bls
	.reg nfdo_desc[NFD_OUT_DESC_SIZE_LW]
	.reg mu_ptr
	.reg cmsg_hdr
	.reg start_lw
	.reg cur_tindex
	.reg cur_lm
	.reg write_lw
	.reg num_lw_to_print
	.reg $credit
    .sig credit_sig
	.reg pkt_offset
	.reg pkt_len
	.reg bytes
	.sig write_sig
	.reg mu_addr
	.reg cmsg_tag
	.reg cmsg_ctx
	.reg tmp


alloc_mu#:
	immed[bls, 0]
	cmsg_alloc_mu_buffer(bls, mu_addr, mu_ptr)

	__cmsg_print_lm_handles_define()

	alu[cur_lm, --, b, in_lm_addr]

	#define __CMSG_PRINT_HDR__ ((CMSG_TYPE_PRINT << 24) | (CMSG_MAP_VERSION << 16) )
	move(cmsg_hdr, __CMSG_PRINT_HDR__)
	#undef __CMSG_PRINT_HDR__

	local_csr_rd[ACTIVE_CTX_STS]
	immed[cmsg_ctx, 0]
	alu_shf[cmsg_tag, cmsg_ctx, and, 0x7]
	alu_shf[tmp, 0xB, and, cmsg_ctx, >>3]
	alu[cmsg_tag, cmsg_tag, or, tmp, <<4]
	alu_shf[tmp, 0x3f, and, cmsg_ctx, >>25]
	alu[cmsg_tag, cmsg_tag, or, tmp, <<8]
	alu_shf[cmsg_ctx, cmsg_ctx, and, 0x7]

	alu[cmsg_tag, cmsg_hdr, or, cmsg_tag]
	swap(tmp, cmsg_tag, NO_LOAD_CC)
	alu[CMSG_TXFR[0], --, b, tmp]
	swap(tmp, in_bytes_len, NO_LOAD_CC)
	alu[CMSG_TXFR[1], --, b, tmp]

	alu[num_lw_to_print, --, b, in_bytes_len, >>2]
	immed[start_lw, 2]
	immed[pkt_len, 0]
    move(pkt_offset, NFD_IN_DATA_OFFSET)
	alu[cur_tindex, (&CMSG_TXFR[2] << 2), OR, cmsg_ctx, <<7]

loop#:
	local_csr_wr[T_INDEX, cur_tindex]
	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_PRINT_LM_HANDLE, cur_lm]
	alu[write_lw, CMSG_PRINT_XFR_COUNT, -, start_lw]
	alu[--, num_lw_to_print, -, write_lw]
	bgt[do_write#]
	alu[write_lw, --, b, num_lw_to_print]

do_write#:
	unroll_copy(*$index, ++, CMSG_PRINT_LM_INDEX, ++, write_lw, CMSG_PRINT_XFR_COUNT, --)

	alu[num_lw_to_print, num_lw_to_print, -, write_lw]
	alu[bytes, --, b, write_lw, <<2]
	alu[cur_lm, cur_lm, +, bytes]
	alu[write_lw, start_lw, +, write_lw]

	ov_start(OV_LENGTH)
	ov_set_use(OV_LENGTH, write_lw, OVF_SUBTRACT_ONE)
	ov_clean
	mem[write32_swap, CMSG_TXFR[0], mu_ptr, <<8, pkt_offset, max_/**/CMSG_PRINT_XFR_COUNT], indirect_ref, sig_done[write_sig]
		alu[cur_tindex, (&CMSG_TXFR[0] << 2), OR, cmsg_ctx, <<7]
		immed[start_lw, 0]
		alu[bytes, --, b, write_lw, <<2]
	ctx_arb[write_sig]

	alu[--, num_lw_to_print, -, 0]
	bne[loop#], defer[2]
	alu[pkt_offset, pkt_offset, +, bytes]
	alu[pkt_len, pkt_len, +, bytes]


/* finish writing */
    move(pkt_offset, NFD_IN_DATA_OFFSET)


	/* setup nfd descriptors */
	/* pkt_len = cmsg_hdr + in_bytes_len */
	/* meta_len = 0, ctm_isl=0, ctm_pnum=0, ctm_split=0 */
	nfd_out_fill_desc(nfdo_desc, 0, 0, 0, bls, mu_addr, pkt_offset, pkt_len, 0)
#define __WAIT_FOR_CREDITS
#define NO_CREDIT_SLEEP 500

get_credits#:
    nfd_out_get_credits($credit, NIC_PCI, NFD_CTRL_QUEUE, 1, credit_sig, SIG_WAIT)
    alu[--, --, b, $credit]
    bne[send_nfd#]

		#define __NO_CREDIT_SLEEP__ 500
        #define_eval _SLEEP_TICKS (__NO_CREDIT_SLEEP__ / 16)
            timestamp_sleep(_SLEEP_TICKS)
			br[get_credits#]
        #undef _SLEEP_TICKS

send_nfd#:
    nfd_out_send(nfdo_desc, NIC_PCI, NFD_CTRL_QUEUE, CMSG_PRINT_LM_HANDLE)

	__cmsg_print_lm_handles_undef()

.end
#endm

#macro __cmsg_print_set($io_txfr)
    #pragma warning(push)
    #pragma warning(disable: 5008)
    aggregate_directive(.set, $io_txfr,  CMSG_PRINT_XFR_COUNT)
    #pragma warning(pop)
#endm

#macro bpf_cmsg_print_func(in_print_lm, in_print_len)
.begin
	#define CMSG_PRINT_XFR_COUNT 8
	#define CMSG_RDXR MAP_RDXR

	.reg write $__cmsg_txfr[CMSG_PRINT_XFR_COUNT]
	.xfer_order $__cmsg_txfr
	__cmsg_print_set($__cmsg_txfr)
    #define CMSG_TXFR $__cmsg_txfr

	cmsg_print(in_print_lm, in_print_len)

	#undef CMSG_PRINT_XFR_COUNT
	#undef CMSG_RDXR
	#undef CMSG_TXFR
.end
#endm

#macro cmsg_print_func(in_print_lm, in_print_len)
.begin
	#define CMSG_PRINT_XFR_COUNT 8
	.reg read $__cmsg_rxfr[CMSG_PRINT_XFR_COUNT]
	__cmsg_print_set($__cmsg_rxfr)
	#define CMSG_RDXR $__cmsg_rxfr

	.reg write $__cmsg_txfr[CMSG_PRINT_XFR_COUNT]
	.xfer_order $__cmsg_txfr
	__cmsg_print_set($__cmsg_txfr)
    #define CMSG_TXFR $__cmsg_txfr

	cmsg_print(in_print_lm, in_print_len)

	#undef CMSG_PRINT_XFR_COUNT
	#undef CMSG_RDXR
	#undef CMSG_TXFR
.end
#endm


#macro cmsg_print_unittest(in_lm)
.begin
	.reg w_lm
	.reg value
	.reg idx

	__cmsg_print_lm_handles_define()

	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_PRINT_LM_HANDLE, in_lm]
	alu[w_lm, --, b, in_lm]
	immed[idx, 15]
	immed[value,1]
loop#:
	alu[CMSG_PRINT_LM_INDEX++, --, b, value]
	alu[value, 1, +, value]
	alu[idx, idx, -, 1]
	bge[loop#]

	alu[w_lm, w_lm, +, 64]
	local_csr_wr[ACTIVE_LM_ADDR_/**/CMSG_PRINT_LM_HANDLE, w_lm]
	nop
	immed[idx, 17]
	immed[value, 18]

	alu[CMSG_PRINT_LM_INDEX++, --, b, idx]
	alu[CMSG_PRINT_LM_INDEX++, --, b, value]

	__cmsg_print_lm_handles_undef()

	immed[idx, 17]
pr_loop#:
	alu[value, --, b, idx, <<2]
	cmsg_print_func(in_lm, value)
	alu[idx, idx, -, 1]
	bgt[pr_loop#]

.end
#endm

#endif 	/*_CMSG_PRINT_UC */
