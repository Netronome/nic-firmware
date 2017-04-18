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
    ctx_arb[kill] ; __LINE
.end
#endm

#include "pkt_io.uc"
#include "actions.uc"

#define PKT_COUNTER_ENABLE
#include "pkt_counter.uc"
#include "app_config_instr.h"

pkt_counter_decl(drop)
pkt_counter_decl(err_act)
pkt_counter_decl(err_rx_nbi)
pkt_counter_decl(err_rx_nfd)

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
    pkt_counter_incr(err_rx_nbi)
    br[count_drop#]

error_rx_nfd#:
    pkt_counter_incr(err_rx_nfd)
    br[count_drop#]

/*
error_act#:
    pkt_counter_incr(err_act)
*/

count_drop#:
    pkt_counter_incr(drop)

silent_drop#:
    pkt_io_drop(pkt_vec)

egress#:
    pkt_io_reorder(pkt_vec)

ingress#:
    pkt_io_rx(pkt_vec, error_rx_nbi#, error_rx_nfd#)

    actions_execute(pkt_vec, egress#, count_drop#, silent_drop#, error_act#)

#pragma warning(disable: 4702)
fatal_error("MAIN LOOP EXIT")
