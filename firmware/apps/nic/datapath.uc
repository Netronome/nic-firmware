/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   datapath.uc
 * @brief  Main processing loop for general purpose datapath workers.
 */

#include "global.uc"

#include <nic_basic/nic_stats.h>
#define pkt_vec *l$index1

#include "actions.uc"
#include "pkt_io.uc"

.reg act_addr

pv_init(pkt_vec, 0)

// kick off processing loop
pkt_io_init(pkt_vec)
br[ingress#]

drop#:
    pkt_io_drop(pkt_vec)

egress#:
    pkt_io_reorder(pkt_vec)

ingress#:
    pkt_io_rx(act_addr, pkt_vec)
    actions_load(pkt_vec, act_addr)

actions#:
    actions_execute(pkt_vec, egress#)

ebpf_reentry#:
    ebpf_reentry()

#pragma warning(disable: 4702)
fatal_error("MAIN LOOP EXIT")
