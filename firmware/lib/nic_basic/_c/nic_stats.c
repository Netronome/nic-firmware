/*
 * Copyright 2015 Netronome, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @file          lib/nic/_c/nic_stats.c
 * @brief         Implementation for additional stats
 */

#ifndef _LIBNIC_NIC_STATS_C_
#define _LIBNIC_NIC_STATS_C_

#include <nfp/macstats.h>
#include <nfp/me.h>
#include <nfp/mem_atomic.h>
#include <nfp/mem_bulk.h>
#include <nfp/tmq.h>

#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_out.h>


/*
 * Additional counters for the NIC application
 *
 * Most of the statistics for the NIC are directly based on stats
 * maintained by the MAC.  However, some required stats are either
 * derived counts or software based counts.  This structure defines
 * these additional stats.
 *
 * DO NOT CHANGE THE ORDER!
 */
struct nic_port_stats_extra {
    unsigned long long rx_discards;
    unsigned long long rx_errors;
    unsigned long long rx_uc_octets;
    unsigned long long rx_mc_octets;
    unsigned long long rx_bc_octets;

    unsigned long long tx_discards;
    unsigned long long tx_errors;
    unsigned long long tx_uc_octets;
    unsigned long long tx_mc_octets;
    unsigned long long tx_bc_octets;
};
/* Export for debug visibility */
__export __shared __imem struct nic_port_stats_extra nic_stats_extra;


/*
 * Global declarations for MAC Statistics
 */

/* How often to update the control BAR stats (in cycles) */
#define MAC_STATS_CNTRS_INTERVAL 0x10000
/* Divider for the TM queue drop counters accumulate */
#define TMQ_CNTRS_ACCUM_RATE_DIV 4

/* The list of used Ports per MAC. */
#ifndef MAC0_PORTS_LIST
#error "The list of MAC 0 ports used must be defined"
#else
__shared __lmem uint32_t mac0_ports[] = {MAC0_PORTS_LIST};
#endif

/* The MAC stats in the Control BAR are only a subset of the stats
 * maintained by the MACs.  We accumulate the whole stats in MU space. */
__export __shared __imem struct macstats_port_accum nic_mac_cntrs_accum[24];

/* TM Q drop counter. Currently only one TM Q is used */
__export __shared __align8 __imem uint64_t nic_tmq_drop_cntr_accum = 0;

/* The structure of the counters in the config BAR, used to push the
 * accumulated counters to the config BAR. */
struct cfg_bar_cntrs {
    uint64_t discards;
    uint64_t errors;
    uint64_t octets;
    uint64_t uc_octets;
    uint64_t mc_octets;
    uint64_t bc_octets;
    uint64_t frames;
    uint64_t mc_frames;
    uint64_t bc_frames;
};


/*
 * Functions for updating the counters
 */

__intrinsic void
nic_rx_cntrs(int port, void *da, int len)
{
    /* XXX TODO: support multiple ports */

    if (NIC_IS_MC_ADDR(da)) {

        /* Broadcast addresses are Multicast addresses too */
        if (NIC_IS_BC_ADDR(da)) {
            mem_add64_imm(len, &nic_stats_extra.rx_bc_octets);
        } else {
            mem_add64_imm(len, &nic_stats_extra.rx_mc_octets);
        }
    } else {
        mem_add64_imm(len, &nic_stats_extra.rx_uc_octets);
    }
}

__intrinsic void
nic_tx_cntrs(int port, void *da, int len)
{
    /* XXX TODO: support multiple ports */

    if (NIC_IS_MC_ADDR(da)) {

        /* Broadcast addresses are Multicast addresses too */
        if (NIC_IS_BC_ADDR(da)) {
            mem_add64_imm(len, &nic_stats_extra.tx_bc_octets);
        } else {
            mem_add64_imm(len, &nic_stats_extra.tx_mc_octets);
        }
    } else {
        mem_add64_imm(len, &nic_stats_extra.tx_uc_octets);
    }
}

__intrinsic void
nic_rx_ring_cntrs(void *meta, uint16_t len, uint8_t qid)
{
    SIGNAL sig;

    __nfd_out_cnt_pkt(NIC_PCI, qid, len, ctx_swap, &sig);
}

__intrinsic void
nic_tx_ring_cntrs(void *meta, uint8_t qid)
{
    SIGNAL sig;
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;

    __nfd_in_cnt_pkt(NIC_PCI, qid, in_desc->data_len, ctx_swap, &sig);
}

__intrinsic
void nic_rx_error_cntr(int port)
{
    /* XXX TODO: support multiple ports */

    mem_incr64(&nic_stats_extra.rx_errors);
}

__intrinsic
void nic_tx_error_cntr(int port)
{
    /* XXX TODO: support multiple ports */

    mem_incr64(&nic_stats_extra.tx_errors);
}

__intrinsic
void nic_rx_discard_cntr(int port)
{
    /* XXX TODO: support multiple ports */

    mem_incr64(&nic_stats_extra.rx_discards);
}

__intrinsic
void nic_tx_discard_cntr(int port)
{
    /* XXX TODO: support multiple ports */

    mem_incr64(&nic_stats_extra.tx_discards);
}


/*
 * Handle stats gathering and updating
 */


/*
 * Handle MAC statistics
 *
 * - Periodically read the stats from the MAC and accumulate them in
 *   memory (@mac_stats_accumulate()).
 *
 * - Periodically update a subset of MAC counters int the control BAR
 *   (@mac_stats_update_control_bar()).  This is done by reading the
 *   accumulated MAC stats from memory (@mac_stats_rx_counters() and
 *   @mac_stats_tx_counters()).
 */

__forceinline static void
mac_stats_accumulate(void)
{
    __gpr uint32_t i;

    for (i = 0; i < sizeof(mac0_ports) / 4; i++)
        macstats_port_accum(0, mac0_ports[i],
                            &nic_mac_cntrs_accum[mac0_ports[i]]);
}

__forceinline static void
nic_stats_rx_counters(__xwrite struct cfg_bar_cntrs *write_bar_cntrs)
{
    __gpr  struct cfg_bar_cntrs bar_cntrs = {0};
    __imem struct macstats_port_accum* port_stats;
    __xread uint64_t read_array[5];
    __xread uint64_t read_val;
    __gpr uint32_t i;

    for (i = 0; i < sizeof(mac0_ports) / 4; i++) {
        port_stats = &nic_mac_cntrs_accum[mac0_ports[i]];

        mem_read64(&read_val, &port_stats->RxPIfInErrors, sizeof(read_val));
        bar_cntrs.errors += read_val;
        mem_read64(&read_val, &port_stats->RxPIfInOctets, sizeof(read_val));
        bar_cntrs.octets += read_val;
        mem_read64(&read_val, &port_stats->RxPStatsPkts, sizeof(read_val));
        bar_cntrs.frames += read_val;
        mem_read64(&read_val, &port_stats->RxPIfInMultiCastPkts,
                   sizeof(read_val));
        bar_cntrs.mc_frames += read_val;
        mem_read64(&read_val, &port_stats->RxPIfInBroadCastPkts,
                   sizeof(read_val));
        bar_cntrs.bc_frames += read_val;

    }

    mem_read64(read_array, &nic_stats_extra.rx_discards, sizeof(read_array));
    bar_cntrs.discards   += read_array[0];
    bar_cntrs.errors     += read_array[1];
    bar_cntrs.uc_octets  += read_array[2];
    bar_cntrs.mc_octets  += read_array[3];
    bar_cntrs.bc_octets  += read_array[4];

    *write_bar_cntrs = bar_cntrs;
}

__forceinline static void
nic_stats_tx_counters(__xwrite struct cfg_bar_cntrs *write_bar_cntrs)
{
    __gpr  struct cfg_bar_cntrs bar_cntrs = {0};
    __imem struct macstats_port_accum* port_stats;
    __xread uint64_t read_array[5];
    __xread uint64_t read_val;
    __gpr uint32_t i;

    for (i = 0; i < sizeof(mac0_ports) / 4; i++) {
        port_stats = &nic_mac_cntrs_accum[mac0_ports[i]];

        mem_read64(&read_val, &port_stats->TxPIfOutErrors, sizeof(read_val));
        bar_cntrs.errors += read_val;
        mem_read64(&read_val, &port_stats->TxPIfOutOctets, sizeof(read_val));
        bar_cntrs.octets += read_val;
        mem_read64(&read_val, &port_stats->TxFramesTransmittedOK,
                   sizeof(read_val));
        bar_cntrs.frames += read_val;
        mem_read64(&read_val, &port_stats->TxPIfOutMultiCastPkts,
                   sizeof(read_val));
        bar_cntrs.mc_frames += read_val;
        mem_read64(&read_val, &port_stats->TxPIfOutBroadCastPkts,
                   sizeof(read_val));
        bar_cntrs.bc_frames += read_val;
    }

    mem_read64(read_array, &nic_stats_extra.tx_discards, sizeof(read_array));
    bar_cntrs.discards   += read_array[0];
    bar_cntrs.errors     += read_array[1];
    bar_cntrs.uc_octets  += read_array[2];
    bar_cntrs.mc_octets  += read_array[3];
    bar_cntrs.bc_octets  += read_array[4];

    /* Update the discards counter with possible TM drops. */
    mem_read_atomic(read_array, &nic_tmq_drop_cntr_accum, sizeof(uint64_t));
    bar_cntrs.discards   += read_array[0];

    *write_bar_cntrs = bar_cntrs;
}

__forceinline static void
nic_stats_update_control_bar(void)
{
    __mem char *nic_ctrl_bar = NFD_CFG_BAR_ISL(NIC_PCI, NIC_INTF);
    __xwrite struct cfg_bar_cntrs write_bar_cntrs;

    nic_stats_rx_counters(&write_bar_cntrs);

    mem_write64(&write_bar_cntrs, nic_ctrl_bar + NFP_NET_CFG_STATS_RX_DISCARDS,
                sizeof(write_bar_cntrs));

    nic_stats_tx_counters(&write_bar_cntrs);

    mem_write64(&write_bar_cntrs, nic_ctrl_bar + NFP_NET_CFG_STATS_TX_DISCARDS,
                sizeof(write_bar_cntrs));
}

/*
 * Handle TM per-q drop counters.
 *
 * - Periodically read the drop counters from the TM and accumulate them in
 *   memory (@tmq_drops_accumulate()).
 */
 __forceinline static void
nic_tmq_drops_accumulate(void)
{
    __gpr uint32_t tmq_cntr;
    __xwrite uint64_t write_val;

    /* Only one Q (#0) is currently used */
    tmq_cnt_read(0, &tmq_cntr, 0, 1);

    /* Fix word ordering */
    write_val = ((uint64_t)tmq_cntr << 32);
    mem_add64(&write_val, &nic_tmq_drop_cntr_accum, sizeof(uint64_t));
}

void
nic_stats_loop(void)
{
    SIGNAL sig;
    __gpr uint32_t alarms = 0;

    set_alarm(MAC_STATS_CNTRS_INTERVAL, &sig);

    for (;;) {
        /* Accumulate the MAC statistics. */
        mac_stats_accumulate();

        /* Push the accumulated counters to the config BAR. */
        if (signal_test(&sig)) {
            /* Accumulate the per-q TM drop counters. */
            if ((alarms & (TMQ_CNTRS_ACCUM_RATE_DIV-1)) == 0)
                nic_tmq_drops_accumulate();
            alarms++;

            nic_stats_update_control_bar();
            set_alarm(MAC_STATS_CNTRS_INTERVAL, &sig);
        }
        ctx_swap();
    }
    /* NOTREACHED */
}

#endif /* _LIBNIC_NIC_STATS_C_ */
