/* Optimization and simplifying assumptions */
// - 4 CTX mode
// - LM Index 0 is reserved for local use (code that does not call into other code)
// - Single NBI
// - Single PCIe

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

#include "pkt_io.uc"
#include "actions.uc"

// enable NN receive config from CTM
.reg ctxs
local_csr_rd[CTX_ENABLES]
immed[ctxs, 0]
alu[ctxs, ctxs, AND~, 0x7]
alu[ctxs, ctxs, OR, 0x2]
local_csr_wr[CTX_ENABLES, ctxs]

// cache the context bits for T_INDEX
.reg volatile t_idx_ctx
local_csr_rd[ACTIVE_CTX_STS]
immed[t_idx_ctx, 0]
alu[t_idx_ctx, t_idx_ctx, AND, 7]
alu[t_idx_ctx, --, B, t_idx_ctx, <<7]

.reg pkt_vec[PV_SIZE_LW]
pkt_io_init(pkt_vec)

// kick off processing loop
br[ingress#]

error_rx_nbi#:
    // TODO: no access to port info here, will always increment VNIC errors for VNIC zero
    pv_stats_select(pkt_vec, PV_STATS_TX)
    pv_stats_incr_error(pkt_vec)
    pkt_io_drop(pkt_vec)
    br[ingress#]

error_rx_nfd#:
    // TODO: no access to port info here, will always increment VNIC errors for VNIC zero
    pv_stats_select(pkt_vec, PV_STATS_TX)

error#:
    pv_stats_incr_error(pkt_vec)

drop#:
    pv_stats_incr_discard(pkt_vec)
    pkt_io_drop(pkt_vec)

egress#:
    pkt_io_reorder(pkt_vec)

ingress#:
    pkt_io_rx(pkt_vec, error_rx_nbi#, error_rx_nfd#)

actions_execute(pkt_vec, egress#, drop#, error#)

#pragma warning(disable: 4702)
fatal_error("MAIN LOOP EXIT")
