/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   global.uc
 * @brief  Global data plane initialization.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "license.h"

/* Optimization and simplifying assumptions */
// - 4 CTX mode
// - LM Index 0 is reserved for local use (code that does not call into other code)
// - Single NBI
// - Single PCIe

/* Set MUPEMemConfig = 1 to inidcate to PE to use 1/2 of CTM for packets */
.init_csr xpb:CTMXpbMap.MuPacketReg.MUPEMemConfig 1


.num_contexts 4

#macro fatal_error(REASON)
.begin
    .reg ctx
    .reg pc
    .reg sts
    .reg time

    local_csr_wr[MAILBOX_0, 0xfe]
    local_csr_rd[TIMESTAMP_LOW]
    immed[time, 0]
    local_csr_wr[MAILBOX_1, time]
    local_csr_rd[ACTIVE_CTX_STS]
    immed[sts, 0]
    alu[ctx, 7, AND, sts]
    local_csr_wr[MAILBOX_2, ctx]
    alu[pc, --, B, sts, <<7]
    alu[pc, --, B, pc, >>15]
    alu[pc, pc, +, 7]
    local_csr_wr[MAILBOX_3, pc]
    ctx_arb[kill]
.end
#endm

// eBPF trampoline (must be first instruction)
br[start#]
br[ebpf_reentry#]
start#:

// enable NN receive config from CTM
.reg ctxs
local_csr_rd[CTX_ENABLES]
immed[ctxs, 0]
alu[ctxs, ctxs, AND~, 0x7]
alu[ctxs, ctxs, OR, 0x2]
alu[ctxs, ctxs, OR, 1, <<30]
local_csr_wr[CTX_ENABLES, ctxs]
local_csr_wr[PSEUDO_RANDOM_NUMBER, 42]

// cache the context bits for T_INDEX
.reg volatile t_idx_ctx
local_csr_rd[ACTIVE_CTX_STS]
immed[t_idx_ctx, 0]
alu[t_idx_ctx, t_idx_ctx, AND, 7]
.reg_addr t_idx_ctx 29 A
alu[t_idx_ctx, --, B, t_idx_ctx, <<7]
