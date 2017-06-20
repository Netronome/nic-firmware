#include "global.uc"

#include "actions.uc"
#include "pkt_io.uc"

#define pkt_vec *l$index1
pv_init(pkt_vec, 0)

// kick off processing loop
pkt_io_init(pkt_vec)
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
    actions_load(pkt_vec)

actions#:
    actions_execute(pkt_vec, egress#, drop#, error#)

#pragma warning(disable: 4702)
fatal_error("MAIN LOOP EXIT")
