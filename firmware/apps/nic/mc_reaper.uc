/*
 * Copyright (c) 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file   mc_reaper.uc
 * @brief  Multicast Reaper: reference count and recover multicast packet buffers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <aggregate.uc>
#include <blm_api.uc>
#include <nfd_user_cfg.h>
#include <ov.uc>
#include <ring_utils.uc>
#include <timestamp.uc>

#include "license.h"

#macro mcr_collect(bufs, offset, meta, ring_base, EMPTY_BATCH_LABEL)
.begin
    .reg ctm_isl
    .reg mu_addr
    .sig s0, s1, s2, s3

#define LOOP 0
#while (LOOP < 4)
    alu[mu_addr, --, B, bufs[(offset + LOOP)], <<3]
#if (! streq('EMPTY_BATCH_LABEL', '--'))
    #if (LOOP)
        beq[sync_/**/LOOP#]
    #else
        beq[EMPTY_BATCH_LABEL]
    #endif
#endif

    #define_eval SIG_NR (LOOP % 4)
    mem[test_sub, meta[(4 * LOOP)], mu_addr, <<8, 0, 4], sig_done[s/**/SIG_NR]
    #undef SIG_NR

    #define_eval LOOP (LOOP + 1)
#endloop

sync_4#:
    ctx_arb[s0, s1, s2, s3], br[free_4#]

sync_3#:
    ctx_arb[s0, s1, s2], br[free_3#]

sync_2#:
    ctx_arb[s0, s1], br[free_2#]

sync_1#:
    ctx_arb[s0], br[free_1#]

#while (LOOP > 0)
free_/**/LOOP#:
    #define_eval LOOP (LOOP - 1)

    alu[--, meta[(4 * LOOP + 0)], -, 1]
    bne[skip_buffer_/**/LOOP#]

    // free CTM buffer
    alu[ctm_isl, --, B, meta[(4 * LOOP + 1)], <<24]
    mem[packet_free, --, ctm_isl, <<8, meta[(4 * LOOP + 2)]]

    // free MU buffer
    #define_eval META_IDX (4 * LOOP + 3)
    ov_single(OV_IMMED16, meta[META_IDX])
    mem[fast_journal, --, ring_base, <<8, bufs[(offset + LOOP)]], indirect_ref
    #undef META_IDX

skip_buffer_/**/LOOP#:

#endloop
#undef LOOP

.end
#endm

.reg ring_base
.reg sig_mask
.reg $pkt_meta[16]
.xfer_order $pkt_meta
.reg read $buffers[16]
.xfer_order $buffers
.sig sig_single
.sig sig_double

#define_eval _MCR_BLM_RING_BASE strleft(NFD_OUT_BLM_POOL_START, strlen(NFD_OUT_BLM_POOL_START)-2)
#if (_MCR_BLM_RING_BASE/**/_LOCALITY == MU_LOCALITY_DIRECT_ACCESS)
    alu[ring_base, --, B, ((_MCR_BLM_RING_BASE/**/_LOCALITY << 6) | (_MCR_BLM_RING_BASE/**/_ISLAND & 0x3f)), <<24]
#else
    alu[ring_base, --, B, ((_MCR_BLM_RING_BASE/**/_LOCALITY << 6) | (1 << 5) | ((_MCR_BLM_RING_BASE/**/_ISLAND & 0x3) << 3)), <<24]
#endif

timestamp_enable()

#define LOOP 0
#while (LOOP < 4)
    immed[$pkt_meta[(4 * LOOP + 0)], 1]
    immed[$pkt_meta[(4 * LOOP + 1)], 0]
    immed[$pkt_meta[(4 * LOOP + 2)], 0]
    immed[$pkt_meta[(4 * LOOP + 3)], 0]
    #define_eval LOOP (LOOP + 1)
#endloop
#undef LOOP

br[start#]

full_batch#:
    br_signal[sig_double[1], partial_batch#]

    mcr_collect($buffers, 0, $pkt_meta, ring_base, --)
    mcr_collect($buffers, 4, $pkt_meta, ring_base, --)
    mcr_collect($buffers, 8, $pkt_meta, ring_base, --)
    mcr_collect($buffers, 12, $pkt_meta, ring_base, --)

start#:
    ov_single(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    mem[get, $buffers[0], ring_base, <<8, (NFD_OUT_BLM_POOL_START + 3), max_16], indirect_ref, sig_done[sig_double]
    ctx_arb[sig_double[0]], br[full_batch#]

partial_batch#:
    timestamp_sleep(128)
    ov_single(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    mem[get_freely, $buffers[0], ring_base, <<8, (NFD_OUT_BLM_POOL_START + 3), max_16], indirect_ref, ctx_swap[sig_single]

    mcr_collect($buffers, 0, $pkt_meta, ring_base, partial_batch#)
    mcr_collect($buffers, 4, $pkt_meta, ring_base, partial_batch#)
    mcr_collect($buffers, 8, $pkt_meta, ring_base, partial_batch#)
    mcr_collect($buffers, 12, $pkt_meta, ring_base, partial_batch#)

    ov_single(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    mem[get, $buffers[0], ring_base, <<8, (NFD_OUT_BLM_POOL_START + 3), max_16], indirect_ref, sig_done[sig_double]
    ctx_arb[sig_double[0]], br[full_batch#]

