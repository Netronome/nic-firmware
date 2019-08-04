/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   pkt_buf.uc
 * @brief  Packet buffer management library.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _PKT_BUF_UC
#define _PKT_BUF_UC

#include <blm_api.uc>
#include <ov.uc>
#include <timestamp.uc>

#ifndef PKT_BUF_ME_CTM_PACKETS
    #define PKT_BUF_ME_CTM_PACKETS 48
#endif

#ifndef PKT_BUF_ME_CTM_BUFFERS
    #define PKT_BUF_ME_CTM_BUFFERS 12
#endif

.alloc_mem _pkt_buf_ctm_credits cls island 8
.init _pkt_buf_ctm_credits PKT_BUF_ME_CTM_PACKETS PKT_BUF_ME_CTM_BUFFERS

#define _PKT_BUF_CTM_PACKETS_OFFSET 0
#define _PKT_BUF_CTM_BUFFERS_OFFSET 4


/** pkt_buf_alloc_ctm
 *
 * Allocates a CTM buffer.
 *
 * @param in_buf_sz     CTM buffer size to allocate, allowed values are 0, 1, 2, 3 for 256B, 512B, 1K and 2K buffers respectively.
 * @param FAIL_LABEL    Label to branch if allocation fails due to buffer exhaustion. A label of '--' will cause the macro to go
 *                      into a blocking loop until a credit can be allocated. Use with care, not safe in all application contexts.
 * @param out_pkt_no    The packet number associated with the allocated buffer.
 */
#define PKT_BUF_ALLOC_CTM_SZ_256B 0
#define PKT_BUF_ALLOC_CTM_SZ_512B 1
#define PKT_BUF_ALLOC_CTM_SZ_1K   2
#define PKT_BUF_ALLOC_CTM_SZ_2K   3
#macro pkt_buf_alloc_ctm(out_pkt_no, in_buf_sz, FAIL_LABEL, FAIL_OPS)
.begin
    .reg addr
    .reg delta
    .reg mask_0x7ff
    .reg mask_0x1ff
    .reg zero

    .reg read $credits

    .reg read $buffer_credits
    .reg buffer_credits
    .reg buffer_deficit
    .reg buffer_surplus

    .reg read $packet_credits
    .reg packet_credits
    .reg packet_deficit
    .reg packet_surplus

    .sig sig_buffers
    .sig sig_packets
    .sig sig_credits

    immed[addr, _pkt_buf_ctm_credits]
    cls[test_subsat_imm, $packet_credits, addr, _PKT_BUF_CTM_PACKETS_OFFSET, 1], sig_done[sig_packets]
    cls[test_subsat_imm, $buffer_credits, addr, _PKT_BUF_CTM_BUFFERS_OFFSET, 1], sig_done[sig_buffers]
    ctx_arb[sig_packets, sig_buffers], defer[2], br[check_credits#]
        immed[buffer_deficit, 0]
        immed[zero, 0]

retry_or_fail#:
    alu[delta, 1, -, packet_deficit]
    alu[packet_credits, packet_credits, +, delta]
    ov_start(OV_IMMED16)
    ov_set_use(OV_IMMED16, packet_credits)
    ov_clean()
    cls[add_imm, --, addr, _PKT_BUF_CTM_PACKETS_OFFSET, 0], indirect_ref

    alu[delta, 1, -, buffer_deficit]
    alu[buffer_credits, buffer_credits, +, delta]
    ov_start(OV_IMMED16)
    ov_set_use(OV_IMMED16, buffer_credits)
    ov_clean()
    cls[add_imm, --, addr, _PKT_BUF_CTM_BUFFERS_OFFSET, 0], indirect_ref

#if (streq('FAIL_LABEL', '--'))
    // backoff and retry
    timestamp_sleep(8)
    cls[test_subsat_imm, $packet_credits, addr, _PKT_BUF_CTM_PACKETS_OFFSET, 1], sig_done[sig_packets]
    cls[test_subsat_imm, $buffer_credits, addr, _PKT_BUF_CTM_BUFFERS_OFFSET, 1], sig_done[sig_buffers]
    ctx_arb[sig_packets, sig_buffers], br[check_credits#]
#else
#if (! streq('FAIL_OPS', '--'))
    FAIL_OPS()
#endif
    br[FAIL_LABEL]
#endif

buffer_deficit#:
    alu[--, --, B, $packet_credits]
    bne[refresh_credits#], defer[2]
        immed[packet_deficit, 0]
        immed[buffer_deficit, 1]

packet_deficit#:
    immed[packet_deficit, 1]

refresh_credits#:
    // always check for new credits, since the last packet_alloc may have left zero credits in CLS
    mem[packet_credit_get, $credits, 0, <<8, zero, 1], defer[2], ctx_swap[sig_credits]
        immed[mask_0x7ff, 0x7ff]
        immed[mask_0x1ff, 0x1ff]

    alu[packet_credits, mask_0x7ff, AND, $credits, >>9]
    alu[buffer_credits, mask_0x1ff, AND, $credits]

    alu[packet_surplus, packet_credits, -, packet_deficit]
    bmi[retry_or_fail#]

    alu[buffer_surplus, buffer_credits, -, buffer_deficit]
    bmi[retry_or_fail#]

    // sufficient credits were received to satisfy current request
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, in_buf_sz)
    ov_clean()
    mem[packet_alloc, $credits, 0, <<8, zero, 0], indirect_ref, ctx_swap[sig_credits]

    alu[packet_credits, mask_0x7ff, AND, $credits, >>9]
    alu[packet_credits, packet_credits, +, packet_surplus]

    br[recycle#], defer[2]
        alu[buffer_credits, mask_0x1ff, AND, $credits]
        alu[buffer_credits, buffer_credits, +, buffer_surplus]

check_credits#:
    alu[--, --, B, $buffer_credits]
    beq[buffer_deficit#]

    alu[--, --, B, $packet_credits]
    beq[packet_deficit#]

    // sufficient credits were present in the CLS tracking cache, allocate the CTM buffer
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, in_buf_sz)
    ov_clean()
    mem[packet_alloc, $credits, 0, <<8, zero, 0], indirect_ref, defer[2], ctx_swap[sig_credits]
        immed[mask_0x7ff, 0x7ff]
        immed[mask_0x1ff, 0x1ff]

    alu[packet_credits, mask_0x7ff, AND, $credits, >>9]
    alu[buffer_credits, mask_0x1ff, AND, $credits]

recycle#:
    ov_start(OV_IMMED16)
    ov_set_use(OV_IMMED16, packet_credits)
    ov_clean()
    cls[add_imm, --, addr, _PKT_BUF_CTM_PACKETS_OFFSET, 0], indirect_ref

    alu[out_pkt_no, mask_0x1ff, AND, $credits, >>20]

    ov_start(OV_IMMED16)
    ov_set_use(OV_IMMED16, buffer_credits)
    ov_clean()
    cls[add_imm, --, addr, _PKT_BUF_CTM_BUFFERS_OFFSET, 0], indirect_ref

.end
#endm


#macro pkt_buf_free_mu_buffer(in_bls, in_mu_addr)
.begin
    .reg ring
    .reg addr_hi

    #define_eval _PKT_BUF_FREE_POOL strleft(NFD_OUT_BLM_POOL_START, strlen(NFD_OUT_BLM_POOL_START)-2)
    #if (_PKT_BUF_FREE_POOL/**/_LOCALITY == MU_LOCALITY_DIRECT_ACCESS)
        alu[addr_hi, --, B, ((_PKT_BUF_FREE_POOL/**/_LOCALITY << 6) | (_PKT_BUF_FREE_POOL/**/_ISLAND & 0x3f)), <<24]
    #else
        alu[addr_hi, --, B, ((_PKT_BUF_FREE_POOL/**/_LOCALITY << 6) | (1 << 5) | ((_PKT_BUF_FREE_POOL/**/_ISLAND & 0x3) << 3)), <<24]
    #endif

    alu[ring, NFD_OUT_BLM_POOL_START, +, in_bls]
    ov_start(OV_IMMED16)
    ov_set_use(OV_IMMED16, ring)
    ov_clean()
    mem[fast_journal, --, addr_hi, <<8, in_mu_addr], indirect_ref
.end
#endm


#macro pkt_buf_free_ctm_buffer(in_isl, in_pkt_num)
.begin
    #if (streq('in_isl', '--'))
        mem[packet_free, --, 0, in_pkt_num]
    #else
        .reg addr_hi
        alu[addr_hi, --, B, in_isl, <<24]
        alu[addr_hi, addr_hi, OR, 1, <<31]
        mem[packet_free, --, addr_hi, <<8, in_pkt_num]
    #endif
.end
#endm

#if (WORKERS_PER_ISLAND > 4)
    .reg volatile @dma_semaphore // per ME lock, permit one outstanding DMA per ME for now (12 per island)
    .reg_addr @dma_semaphore 28 A
    immed[@dma_semaphore, (16 / WORKERS_PER_ISLAND)] // implicit init on #include
#endif

/** pkt_buf_copy_mu_head_to_ctm
 *
 * Copy packet head from MU to CTM
 *
 * @param in_pkt_num       Packet number for destination CTM buffer
 * @param in_src_mu_addr   29 bit MU pointer (the >>11 of a 2K aligned 40-bit address)
 *                         (the most significant 3 bits are ignored by this macro, garbage is permitted)
 * @param in_offset        11 bit offset within packet buffer to copy from
 * @param in_length        Number of 64B chunks to copy, 0=64B, 1=128B...
 *
 */
#macro pkt_buf_copy_mu_head_to_ctm(in_pkt_num, in_src_mu_addr, in_offset, in_length)
.begin
    .reg mu_addr_isl
    .reg mu_addr
    .reg tmp

    .reg ctm_dma_addr

    .sig sig_dma

    .reg $status
    .sig sig_status

retry_status#:
    mem[packet_read_packet_status, $status, in_pkt_num, 0], sig_done[sig_status]
    ctx_arb[sig_status], defer[2], br[check_status#]
        alu[mu_addr_isl, 0xff, AND, in_src_mu_addr, >>21]
        alu[mu_addr, in_offset, OR, in_src_mu_addr, <<11]

backoff_retry_status#:
    timestamp_sleep(2)
    br[retry_status#]

#if (WORKERS_PER_ISLAND > 4)
yield_retry_dma#:
    ctx_arb[voluntary], br[retry_dma#], defer[2]
        alu[@dma_semaphore, @dma_semaphore, +, 1]
        nop
#endif

check_status#:
    alu[--, $status, +, 1]
    beq[backoff_retry_status#]

    immed[ctm_dma_addr, 0x7fff]
    alu[ctm_dma_addr, ctm_dma_addr, AND, $status, <<5]
    #if (isnum(in_offset))
        alu[ctm_dma_addr, ctm_dma_addr, +, (in_offset >> 3)]
    #else
        alu[tmp, --, B, in_offset, >>3]
        alu[ctm_dma_addr, ctm_dma_addr, +, tmp]
    #endif

#if (WORKERS_PER_ISLAND > 4)
retry_dma#:
    alu[@dma_semaphore, @dma_semaphore, -, 1]
    bmi[yield_retry_dma#]
#endif

    ov_start((OV_BYTE_MASK | OV_IMMED16 | OV_LENGTH))
    ov_set(OV_BYTE_MASK, mu_addr_isl)
    ov_set(OV_LENGTH, in_length)
    ov_set_use(OV_IMMED16, ctm_dma_addr)
    ov_clean()
    mem[pe_dma_from_memory_buffer , --, mu_addr, 0, <<8, 1], indirect_ref, ctx_swap[sig_dma]

#if (WORKERS_PER_ISLAND > 4)
    alu[@dma_semaphore, @dma_semaphore, +, 1]
#endif

.end
#endm

/** pkt_buf_copy_ctm_to_mu_head
 *
 * Copy packet head from CTM to MU
 *
 * @param in_pkt_num       Packet number for source CTM buffer
 * @param in_dst_mu_addr   29 bit MU pointer (the >>11 of a 2K aligned 40-bit address)
 *                         (the most significant 3 bits are ignored by this macro, garbage is permitted)
 * @param in_offset        11 bit offset within packet buffer to copy from
 *                         (garbage is permitted above the 11th bit, this macro will mask the bits it needs)
 */
#macro pkt_buf_copy_ctm_to_mu_head(in_pkt_num, in_dst_mu_addr, in_offset)
.begin
    .reg mu_addr_hi
    .reg mu_addr_lo
    .reg offset

    .sig sig_dma

#if (WORKERS_PER_ISLAND > 4)
retry_dma#:
    alu[@dma_semaphore, @dma_semaphore, -, 1]
    bmi[yield_retry_dma#]
#endif

    alu[offset, 0xff, AND, in_offset, >>3]
    alu[mu_addr_hi, 0x1f, AND, in_dst_mu_addr, >>24]
    alu[mu_addr_lo, offset, OR, in_dst_mu_addr, <<8]

    ov_start((OV_BYTE_MASK | OV_IMMED16 | OV_LENGTH))
    ov_set(OV_BYTE_MASK, offset)
    ov_set(OV_LENGTH, mu_addr_hi)
    ov_set_use(OV_IMMED16, in_pkt_num)
    ov_clean()

#if (WORKERS_PER_ISLAND > 4)
    mem[pe_dma_to_memory_packet, --, mu_addr_lo, 0, <<8, 1], indirect_ref, sig_done[sig_dma]
    ctx_arb[sig_dma], br[release_semaphore#]

yield_retry_dma#:
    ctx_arb[voluntary], br[retry_dma#], defer[2]
        alu[@dma_semaphore, @dma_semaphore, +, 1]
        nop
#else
    mem[pe_dma_to_memory_packet, --, mu_addr_lo, 0, <<8, 1], indirect_ref, ctx_swap[sig_dma]
#endif

#if (WORKERS_PER_ISLAND > 4)
release_semaphore#:
    alu[@dma_semaphore, @dma_semaphore, +, 1]
#endif

.end
#endm


#endif
