/*
 * Copyright 2015 Netronome, Inc.
 *
 * @file          lib/nic/_c/nic_stats.c
 * @brief         Implementation for additional stats
 */

#ifndef _LIBNIC_NIC_STATS_H_
#define _LIBNIC_NIC_STATS_H_

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
#if defined(__NFP_LANG_MICROC)
struct nic_port_bpf_stats {
    unsigned long long abort_pkts;		/* ebpf abort */
    unsigned long long abort_bytes;
    unsigned long long drop_pkts;		/* ebpf drop */
    unsigned long long drop_bytes;
    unsigned long long pass_pkts;
    unsigned long long pass_bytes;
    unsigned long long tx_pkts;		/* ebpf redir */
    unsigned long long tx_bytes;
};

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

    struct nic_port_bpf_stats ebpf;
};

__asm {
    .alloc_mem _nic_stats_extra imem+0 global 1024 256
}

#elif defined(__NFP_LANG_ASM)

.alloc_mem _nic_stats_extra imem+0 global 1024 256


#endif

#endif
