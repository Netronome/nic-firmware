#include "global.uc"
#include "pkt_io.uc"
#include "actions.uc"

// alloc  pkt_vec[PV_SIZE_LW] in lm
pv_set_lm_idx()
pkt_io_init(pkt_vec)

// kick off processing loop
br[ingress#]

error_rx_nbi#:
    // TODO: no access to port info here, will always increment VNIC errors for VNIC zero
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
    pkt_io_rx(pkt_vec, drop#, error_rx_nbi#, error_rx_nfd#)

actions_execute(pkt_vec, egress#, drop#, error#)

#pragma warning(disable: 4702)
fatal_error("MAIN LOOP EXIT")
