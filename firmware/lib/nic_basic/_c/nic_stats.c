/*
 * Copyright 2015 Netronome, Inc.
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
__export __shared __imem
struct nic_port_stats_extra nic_stats_extra[NFD_MAX_VFS];


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
        EXTRA_CNT_INCR(&nic_stats_extra[port].tx_uc_pkts);
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

    nfd_q = nfd_out_map_queue(port, qid);

    __nfd_in_cnt_pkt(NIC_PCI, qid, in_desc->data_len, ctx_swap, &sig);
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

    for (i = 0; i < sizeof(mac0_ports) / 4; i++)
        macstats_port_accum(0, mac0_ports[i],
                            &nic_mac_cntrs_accum[mac0_ports[i]]);
}

__forceinline static void
nic_stats_rx_counters(int port, __xwrite struct cfg_bar_cntrs *write_bar_cntrs)
{
    __gpr  struct cfg_bar_cntrs bar_cntrs = {0};
    __imem struct macstats_port_accum* port_stats;
    __xread uint64_t read_array[8];
    __xread uint64_t read_val;
    __gpr uint32_t i;

    /* TODO: add support for port 1 MAC and TM cntrs */
    if (port == 0) {
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
    }

    mem_read64(read_array, &nic_stats_extra[port].rx_discards,
               sizeof(read_array));
    bar_cntrs.discards += read_array[0];
    bar_cntrs.errors += read_array[1];
    bar_cntrs.uc_octets += read_array[2];
    bar_cntrs.mc_octets += read_array[3];
    bar_cntrs.bc_octets += read_array[4];
    bar_cntrs.mc_frames += read_array[6];
    bar_cntrs.bc_frames += read_array[7];

    /* Accumulated stats */
    bar_cntrs.octets = read_array[2] + read_array[3] + read_array[4];
    bar_cntrs.frames = read_array[5] + read_array[6] + read_array[7];

    *write_bar_cntrs = bar_cntrs;
}

__forceinline static void
nic_stats_tx_counters(int port, __xwrite struct cfg_bar_cntrs *write_bar_cntrs)
{
    __gpr  struct cfg_bar_cntrs bar_cntrs = {0};
    __imem struct macstats_port_accum* port_stats;
    __xread uint64_t read_array[8];
    __xread uint64_t read_val;
    __gpr uint32_t i;

    /* TODO: add support for port 1 MAC and TM cntrs */
    if (port == 0) {
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
    }

    mem_read64(read_array, &nic_stats_extra[port].tx_discards,
               sizeof(read_array));
    bar_cntrs.discards += read_array[0];
    bar_cntrs.errors += read_array[1];
    bar_cntrs.uc_octets += read_array[2];
    bar_cntrs.mc_octets += read_array[3];
    bar_cntrs.bc_octets += read_array[4];
    bar_cntrs.mc_frames += read_array[6];
    bar_cntrs.bc_frames += read_array[7];

    /* Accumulated stats */
    bar_cntrs.octets = read_array[2] + read_array[3] + read_array[4];
    bar_cntrs.frames = read_array[5] + read_array[6] + read_array[7];

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
    for (i = 0; i < NFD_MAX_VFS; i++) {
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
