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
    unsigned long long rx_uc_pkts;
    unsigned long long rx_mc_pkts;
    unsigned long long rx_bc_pkts;

    unsigned long long tx_discards;
    unsigned long long tx_errors;
    unsigned long long tx_uc_octets;
    unsigned long long tx_mc_octets;
    unsigned long long tx_bc_octets;
    unsigned long long tx_uc_pkts;
    unsigned long long tx_mc_pkts;
    unsigned long long tx_bc_pkts;
};
/* Export for debug visibility */
__export __shared __imem struct nic_port_stats_extra nic_stats_extra[NVNICS];

/*
 * Global declarations for MAC Statistics
 */

/* How often to update the control BAR stats (in cycles) */
#define MAC_STATS_CNTRS_INTERVAL 0x10000
/* Divider for the TM queue drop counters accumulate */
#define TMQ_CNTRS_ACCUM_RATE_DIV 4

/* The MAC stats in the Control BAR are only a subset of the stats
 * maintained by the MACs.  We accumulate the whole stats in MU space. */
__export __shared __imem struct macstats_port_accum nic_mac_cntrs_accum[24];

/* TM Q drop counters. */
__export __shared __align8 __imem uint64_t          \
    nic_tmq_drop_cntr_accum[NS_PLATFORM_NUM_PORTS];

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

/* enable getting the MAC stats */
#define ACC_MAC_STATS

#ifndef ACC_MAC_STATS
#define EXTRA_CNT_INCR(cntr)        mem_incr64(cntr)
#else
#define EXTRA_CNT_INCR(cntr)
#endif

/*
 * Functions for updating the counters
 */

__intrinsic void
nic_rx_cntrs(int port, void *da, int len)
{
    if (NIC_IS_MC_ADDR(da)) {

        /* Broadcast addresses are Multicast addresses too */
        if (NIC_IS_BC_ADDR(da)) {
            mem_add64_imm(len, &nic_stats_extra[port].rx_bc_octets);
            EXTRA_CNT_INCR(&nic_stats_extra[port].rx_bc_pkts);
        } else {
            mem_add64_imm(len, &nic_stats_extra[port].rx_mc_octets);
            EXTRA_CNT_INCR(&nic_stats_extra[port].rx_mc_pkts);
        }
    } else {
        mem_add64_imm(len, &nic_stats_extra[port].rx_uc_octets);
        EXTRA_CNT_INCR(&nic_stats_extra[port].rx_uc_pkts);
    }
}

__intrinsic void
nic_tx_cntrs(int port, void *da, int len)
{
    if (NIC_IS_MC_ADDR(da)) {

        /* Broadcast addresses are Multicast addresses too */
        if (NIC_IS_BC_ADDR(da)) {
            mem_add64_imm(len, &nic_stats_extra[port].tx_bc_octets);
            EXTRA_CNT_INCR(&nic_stats_extra[port].tx_bc_pkts);
        } else {
            mem_add64_imm(len, &nic_stats_extra[port].tx_mc_octets);
            EXTRA_CNT_INCR(&nic_stats_extra[port].tx_mc_pkts);
        }
    } else {
        mem_add64_imm(len, &nic_stats_extra[port].tx_uc_octets);
        mem_incr64(&nic_stats_extra[port].tx_uc_pkts);
    }

}

__intrinsic void
nic_rx_ring_cntrs(void *meta, uint16_t len, uint32_t port, uint32_t qid)
{
    SIGNAL sig;
    uint32_t nfd_q;

    nfd_q = nfd_out_map_queue(port, qid);

    __nfd_out_cnt_pkt(NIC_PCI, nfd_q, len, ctx_swap, &sig);
}

__intrinsic void
nic_tx_ring_cntrs(void *meta, uint32_t port, uint32_t qid)
{
    SIGNAL sig;
    uint32_t nfd_q;
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;

    nfd_q = NFD_BUILD_NATQ(port, qid);

    __nfd_in_cnt_pkt(NIC_PCI, nfd_q, in_desc->data_len, ctx_swap, &sig);
}

__intrinsic
void nic_rx_error_cntr(int port)
{
    mem_incr64(&nic_stats_extra[port].rx_errors);
}

__intrinsic
void nic_tx_error_cntr(int port)
{
    mem_incr64(&nic_stats_extra[port].tx_errors);
}

__intrinsic
void nic_rx_discard_cntr(int port)
{
    mem_incr64(&nic_stats_extra[port].rx_discards);
}

__intrinsic
void nic_tx_discard_cntr(int port)
{
    mem_incr64(&nic_stats_extra[port].tx_discards);
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

    /* Accumulate the port statistics for each port. */
    for (i = 0; i < NS_PLATFORM_NUM_PORTS; ++i) {
        macstats_port_accum(
            NS_PLATFORM_MAC(i), NS_PLATFORM_MAC_SERDES_LO(i),
            &nic_mac_cntrs_accum[NS_PLATFORM_MAC_SERDES_LO(i)]);
    }
}

__forceinline static void
nic_stats_rx_counters(int port, __xwrite struct cfg_bar_cntrs *write_bar_cntrs)
{
    __gpr  struct cfg_bar_cntrs bar_cntrs = {0};
    __imem struct macstats_port_accum* port_stats;
    __xread uint64_t read_array[8];
    __xread uint64_t read_val;

#ifdef ACC_MAC_STATS
    /* Retrieve the corresponding MAC port stats. */
    if (port < NS_PLATFORM_NUM_PORTS) {
        port_stats = &nic_mac_cntrs_accum[NS_PLATFORM_MAC_SERDES_LO(port)];

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
#endif

    mem_read64(read_array, &nic_stats_extra[port].rx_discards,
               sizeof(read_array));
    bar_cntrs.discards += read_array[0];
    bar_cntrs.errors += read_array[1];
    bar_cntrs.uc_octets += read_array[2];
    bar_cntrs.mc_octets += read_array[3];
    bar_cntrs.bc_octets += read_array[4];
#ifndef ACC_MAC_STATS
    bar_cntrs.mc_frames += read_array[6];
    bar_cntrs.bc_frames += read_array[7];
#endif

    /* Accumulated stats */
    bar_cntrs.octets = read_array[2] + read_array[3] + read_array[4];
#ifndef  ACC_MAC_STATS
    bar_cntrs.frames = read_array[5] + read_array[6] + read_array[7];
#endif

    *write_bar_cntrs = bar_cntrs;
}

__forceinline static void
nic_stats_tx_counters(int port, __xwrite struct cfg_bar_cntrs *write_bar_cntrs)
{
    __gpr  struct cfg_bar_cntrs bar_cntrs = {0};
    __imem struct macstats_port_accum* port_stats;
    __xread uint64_t read_array[8];
    __xread uint64_t read_val;

#ifdef ACC_MAC_STATS
    /* Retrieve the corresponding MAC port stats. */
    if (port < NS_PLATFORM_NUM_PORTS) {
        port_stats = &nic_mac_cntrs_accum[NS_PLATFORM_MAC_SERDES_LO(port)];

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

        /* Accumulate the TM Q drops */
        mem_read64(&read_val, &nic_tmq_drop_cntr_accum[port], sizeof(uint64_t));
        bar_cntrs.discards += read_val;
    }
#endif

    mem_read64(read_array, &nic_stats_extra[port].tx_discards,
               sizeof(read_array));
    bar_cntrs.discards += read_array[0];
    bar_cntrs.errors += read_array[1];
    bar_cntrs.uc_octets += read_array[2];
    bar_cntrs.mc_octets += read_array[3];
    bar_cntrs.bc_octets += read_array[4];
#ifndef ACC_MAC_STATS
    bar_cntrs.mc_frames += read_array[6];
    bar_cntrs.bc_frames += read_array[7];
#endif

    /* Accumulated stats */
    bar_cntrs.octets = read_array[2] + read_array[3] + read_array[4];
#ifndef  ACC_MAC_STATS
    bar_cntrs.frames = read_array[5] + read_array[6] + read_array[7];
#else
    bar_cntrs.frames = read_array[5] + bar_cntrs.mc_frames + bar_cntrs.bc_frames;
#endif


    *write_bar_cntrs = bar_cntrs;
}

__forceinline static void
nic_stats_update_control_bar(void)
{
    __mem char *vf_bar;
    __xwrite struct cfg_bar_cntrs write_bar_cntrs;
    int i;

    /* TODO: optimize this loop with nic_stats_rx/tx_counters
     * reading more than one vnic/vf/port at once
     */
    for (i = 0; i < NVNICS; i++) {
        vf_bar = NFD_CFG_BAR_ISL(NIC_PCI, i);

        nic_stats_rx_counters(i, &write_bar_cntrs);
        mem_write64(&write_bar_cntrs, vf_bar + NFP_NET_CFG_STATS_RX_DISCARDS,
                    sizeof(write_bar_cntrs));

        nic_stats_tx_counters(i, &write_bar_cntrs);
        mem_write64(&write_bar_cntrs, vf_bar + NFP_NET_CFG_STATS_TX_DISCARDS,
                    sizeof(write_bar_cntrs));
    }
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
    __gpr uint32_t    port;
    __gpr uint32_t    qid;
    __gpr uint32_t    tmq_cnt;
    __gpr uint64_t    tmq_port_drop_cnt;
    __xwrite uint64_t cnt_xw;

    /* Accumulate the NBI TM queue drop counts for each port. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        /* Accumulate the NBI TM queue drop counts associated with the port. */
        tmq_port_drop_cnt = 0;

        for (qid = NS_PLATFORM_NBI_TM_QID_LO(port);
             qid < NS_PLATFORM_NBI_TM_QID_HI(port);
             ++qid) {
            tmq_cnt_read(NS_PLATFORM_MAC(port), &tmq_cnt, qid, 1);
            tmq_port_drop_cnt += (uint64_t)tmq_cnt;
        }

        /* Store the per-port NBI TM queue drop count. */
        cnt_xw = tmq_port_drop_cnt;
        mem_add64(&cnt_xw, &nic_tmq_drop_cntr_accum[port], sizeof(uint64_t));
    }
}

void
nic_stats_loop(void)
{
    SIGNAL sig;
    __gpr uint32_t alarms = 0;

    set_alarm(MAC_STATS_CNTRS_INTERVAL, &sig);

    for (;;) {
#ifdef ACC_MAC_STATS
        /* Accumulate the MAC statistics. */
        mac_stats_accumulate();
#endif

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
