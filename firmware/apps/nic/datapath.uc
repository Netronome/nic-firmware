/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   datapath.uc
 * @brief  Main processing loop for general purpose datapath workers.
 */

#include "global.uc"

#include <nic_basic/nic_stats.h>

#include "actions.uc"
#include "pkt_io.uc"

#define pkt_vec *l$index1
pv_init(pkt_vec, 0)

// kick off processing loop
pkt_io_init(pkt_vec)
br[ingress#]

rx_discards_proto#:
    pv_stats_increment(pkt_vec, EXT_STATS_GLOBAL_RX_DISCARDS_PROTO)
    pkt_io_drop(pkt_vec)
    br[ingress#]

rx_errors_parse#:
    pv_stats_increment(pkt_vec, EXT_STATS_GLOBAL_RX_ERRORS_PARSE)
    br[drop#]

tx_errors_pci#:
    pv_stats_increment(pkt_vec, EXT_STATS_GLOBAL_TX_ERRORS_PCI)
    br[drop#]

tx_errors_offset#:
    pv_stats_increment(pkt_vec, EXT_STATS_TX_ERRORS_OFFSET)
    br[drop#]

rx_discards_mtu#:
    pv_stats_increment_rxtx(pkt_vec, EXT_STATS_RX_DISCARDS_MTU, EXT_STATS_TX_ERRORS_MTU)
    br[drop#]

rx_discards_filter_mac#:
    pv_stats_increment(pkt_vec, EXT_STATS_RX_DISCARDS_FILTER_MAC)
    br[drop#]

rx_discards_no_buf_pci#:
    pv_stats_increment(pkt_vec, EXT_STATS_RX_DISCARDS_NO_BUF_PCI)

drop#:
    pkt_io_drop(pkt_vec)

egress#:
    pkt_io_reorder(pkt_vec)

ingress#:
    pkt_io_rx(pkt_vec)
    actions_load(pkt_vec)

actions#:
    actions_execute(pkt_vec, egress#)

#pragma warning(disable: 4702)
fatal_error("MAIN LOOP EXIT")
