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
#include "nic_stats.h"

/* How often to update the control BAR stats (in cycles) */
#define STATS_ACCUMULATE_INTERVAL 0x20000
#define STATS_AGGREGATE_DIVISOR 32

#include "ext_stats.c"

typedef struct {
    union {
        struct macstats_port_accum stats;
        uint64_t __raw[64];
    };
} mac_stats_t;

typedef struct {
    union {
        struct {
            uint64_t rx_discards;
            uint64_t rx_errors;
            uint64_t rx_octets;
            uint64_t rx_uc_octets;
            uint64_t rx_mc_octets;
            uint64_t rx_bc_octets;
            uint64_t rx_frames;
            uint64_t rx_mc_frames;
            uint64_t rx_bc_frames;

            uint64_t tx_discards;
            uint64_t tx_errors;
            uint64_t tx_octets;
            uint64_t tx_uc_octets;
            uint64_t tx_mc_octets;
            uint64_t tx_bc_octets;
            uint64_t tx_frames;
            uint64_t tx_mc_frames;
            uint64_t tx_bc_frames;

            uint64_t app0_frames;
            uint64_t app0_bytes;
            uint64_t app1_frames;
            uint64_t app1_bytes;
            uint64_t app2_frames;
            uint64_t app2_bytes;
            uint64_t app3_frames;
            uint64_t app3_bytes;
        };
        uint64_t __raw[26];
    };
} bar_stats_t;

typedef struct {
    union {
        struct {
            unsigned long long rx_discards;
            unsigned long long rx_discards_proto;
            unsigned long long rx_errors;
            unsigned long long rx_errors_parse;
            unsigned long long rx_octets;
            unsigned long long rx_frames;
            unsigned long long tx_discards;
            unsigned long long tx_errors;
            unsigned long long tx_errors_pci;
            unsigned long long tx_octets;
            unsigned long long tx_frames;
        };
        unsigned long long __raw[11];
    };
} global_stats_t;

// working stats
__export __shared __align8 __imem mac_stats_t _mac_stats[24];
__export __shared __align8 __imem struct macstats_head_drop_accum _mac_stats_head_drop;
__export __shared __align8 __imem uint64_t _tmq_stats_drop[NS_PLATFORM_NUM_PORTS];

// result stats
__export __shared __emem mac_stats_t mac_stats[24];

__forceinline static void stats_accumulate(void)
{
    __gpr uint32_t    port;
    __gpr uint32_t    qid;
    __gpr uint32_t    tmq_cnt;
    __gpr uint64_t    tmq_port_drop_cnt;
    __xwrite uint32_t cnt_xw[2];

    /* Accumulate the port statistics for each port. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        macstats_port_accum(NS_PLATFORM_MAC(port),
            NS_PLATFORM_MAC_SERDES_LO(port),
            &_mac_stats[NS_PLATFORM_MAC_SERDES_LO(port)].stats);

        tmq_port_drop_cnt = 0;

        for (qid = NS_PLATFORM_NBI_TM_QID_LO(port);
             qid < NS_PLATFORM_NBI_TM_QID_HI(port);
             ++qid) {
            tmq_cnt_read(NS_PLATFORM_MAC(port), &tmq_cnt, qid, 1);
            tmq_port_drop_cnt += (uint64_t)tmq_cnt;
        }

        /* Store the per-port NBI TM queue drop count. */
        cnt_xw[0] = tmq_port_drop_cnt;
        cnt_xw[1] = 0;
        mem_add64(&cnt_xw[0], &_tmq_stats_drop[port], sizeof(cnt_xw));
    }
    macstats_head_drop_accum(0, 0, 0xfff, &_mac_stats_head_drop);
}

__lmem __shared ext_stats_t vnic_stats_work;
__lmem __shared mac_stats_t mac_stats_work;
__lmem __shared global_stats_t global_stats_work;
__lmem __shared bar_stats_t bar_stats_work;

__forceinline static void stats_aggregate()
{
    __xread uint32_t read_block[8];
    __xwrite uint32_t write_block[16];
    __mem char *addr;
    __mem char *bar_end;
    int size;
    __xread uint32_t tmq_drop[2];
    __xread uint32_t mac_head_drop[2];
    uint32_t port;
    uint32_t bar_stat;
    uint32_t block_stat;
    uint32_t vnic_stat;
    uint32_t mac_stat;
    uint32_t global_stat;
    uint32_t vid;
    uint64_t tmp;

    __imem ext_stats_t *__vnic_stats = (__imem ext_stats_t *) __link_sym("__ext_stats");
    __imem ext_stats_t *vnic_stats = (__imem ext_stats_t *) __link_sym("_ext_stats_phy_data");

    // read "global" VNIC 0 stats using atomic engine
    global_stat = 0;
    for (addr = (__mem char *) &__vnic_stats[0].global_rx_discards;
         addr < (__mem char *) &__vnic_stats[1];
         addr += sizeof(read_block)) {

        mem_read_atomic(&read_block, addr, sizeof(read_block));
        block_stat = 0;
        while (global_stat < sizeof(global_stats_work) / 8 && block_stat < sizeof(read_block) / 4) {
             global_stats_work.__raw[global_stat++] = read_block[block_stat++] + (((uint64_t) read_block[block_stat++]) << 32);
        }
    }

    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        // read MAC stats using atomic engine
        mac_stat = 0;
        for (addr = (__mem char *) &_mac_stats[NS_PLATFORM_MAC_SERDES_LO(port)];
             addr < (__mem char *) &_mac_stats[NS_PLATFORM_MAC_SERDES_LO(port) + 1];
             addr += sizeof(read_block)) {

            mem_read_atomic(&read_block, addr, sizeof(read_block));
            block_stat = 0;
            while (mac_stat < sizeof(mac_stats_work) / 8 && block_stat < sizeof(read_block) / 4) {
                mac_stats_work.__raw[mac_stat++] = read_block[block_stat++] + (((uint64_t) read_block[block_stat++]) << 32);
            }
        }

        sleep(10000);

        // read VNIC stats using atomic engine
        vnic_stat = 0;
        for (addr = (__mem char *) &__vnic_stats[port + 1];
             addr < (__mem char *) &__vnic_stats[port + 2];
             addr += sizeof(read_block)) {

            mem_read_atomic(&read_block, addr, sizeof(read_block));
            block_stat = 0;
            while (vnic_stat < sizeof(vnic_stats_work) / 8 && block_stat < sizeof(read_block) / 4) {
                vnic_stats_work.__raw[vnic_stat++] = read_block[block_stat++] + (((uint64_t) read_block[block_stat++]) << 32);
            }
        }

        mem_read_atomic(&tmq_drop[0], &_tmq_stats_drop[port], sizeof(tmq_drop));
        vnic_stats_work.tx_discards_tm += (((uint64_t) tmq_drop[1]) << 32) + tmq_drop[0];

        mem_read_atomic(&mac_head_drop[0], &_mac_stats_head_drop.ports_drop[port], sizeof(mac_head_drop));

        mac_stats_work.stats.RxMacHeadDrop += (((uint64_t) mac_head_drop[1]) << 32) + mac_head_drop[0];
        vnic_stats_work.rx_discards_no_buf_mac = mac_stats_work.stats.RxMacHeadDrop;

        vnic_stats_work.tx_frames += mac_stats_work.stats.TxFramesTransmittedOK;
        if (vnic_stats_work.tx_frames >= mac_stats_work.stats.TxPauseMacCtlFramesTransmitted)
            vnic_stats_work.tx_frames -= mac_stats_work.stats.TxPauseMacCtlFramesTransmitted;
        else
            vnic_stats_work.tx_frames = 0;
        vnic_stats_work.tx_uc_frames += mac_stats_work.stats.TxPIfOutUniCastPkts;
        vnic_stats_work.tx_mc_frames += mac_stats_work.stats.TxPIfOutMultiCastPkts;
        vnic_stats_work.tx_bc_frames += mac_stats_work.stats.TxPIfOutBroadCastPkts;
        vnic_stats_work.tx_octets += mac_stats_work.stats.TxPIfOutOctets;
        if (vnic_stats_work.tx_octets >= 64 * mac_stats_work.stats.TxPauseMacCtlFramesTransmitted)
            vnic_stats_work.tx_octets -= 64 * mac_stats_work.stats.TxPauseMacCtlFramesTransmitted;
        else
            vnic_stats_work.tx_octets = 0;
        vnic_stats_work.tx_errors += mac_stats_work.stats.TxPIfOutErrors;

        vnic_stats_work.rx_frames += mac_stats_work.stats.RxFramesReceivedOK;
        if (vnic_stats_work.rx_frames >= mac_stats_work.stats.RxPauseMacCtlFrames)
            vnic_stats_work.rx_frames -= mac_stats_work.stats.RxPauseMacCtlFrames;
        else
            vnic_stats_work.rx_frames = 0;
        vnic_stats_work.rx_uc_frames += mac_stats_work.stats.RxPIfInUniCastPkts;
        vnic_stats_work.rx_mc_frames += mac_stats_work.stats.RxPIfInMultiCastPkts;
        vnic_stats_work.rx_bc_frames += mac_stats_work.stats.RxPIfInBroadCastPkts;
        vnic_stats_work.rx_octets += mac_stats_work.stats.RxPIfInOctets;
        if (vnic_stats_work.rx_octets >= 64 * mac_stats_work.stats.RxPauseMacCtlFrames)
            vnic_stats_work.rx_octets -= 64 * mac_stats_work.stats.RxPauseMacCtlFrames;
        else
            vnic_stats_work.rx_octets = 0;
        vnic_stats_work.rx_errors += mac_stats_work.stats.RxPIfInErrors;

        vnic_stats_work.rx_discards += vnic_stats_work.rx_discards_policy;
        vnic_stats_work.rx_discards += vnic_stats_work.rx_discards_filter_mac;
        vnic_stats_work.rx_discards += vnic_stats_work.rx_discards_mtu;
        vnic_stats_work.rx_discards += vnic_stats_work.rx_discards_no_buf_pci;
        vnic_stats_work.rx_discards += vnic_stats_work.rx_discards_no_buf_mac;
        vnic_stats_work.rx_mc_octets += 4 * vnic_stats_work.rx_mc_frames;
        vnic_stats_work.rx_bc_octets += 4 * vnic_stats_work.rx_bc_frames;
        vnic_stats_work.rx_uc_octets += vnic_stats_work.rx_octets;
        if (vnic_stats_work.rx_uc_octets >= vnic_stats_work.rx_mc_octets)
            vnic_stats_work.rx_uc_octets -= vnic_stats_work.rx_mc_octets;
        else
            vnic_stats_work.rx_uc_octets = 0;
        if (vnic_stats_work.rx_uc_octets >= vnic_stats_work.rx_bc_octets)
            vnic_stats_work.rx_uc_octets -= vnic_stats_work.rx_bc_octets;
        else
            vnic_stats_work.rx_uc_octets = 0;

        vnic_stats_work.tx_discards += vnic_stats_work.tx_discards_policy;
        vnic_stats_work.tx_discards += vnic_stats_work.tx_discards_tm;
        vnic_stats_work.tx_errors += vnic_stats_work.tx_errors_mtu;
        vnic_stats_work.tx_errors += vnic_stats_work.tx_errors_offset;
        vnic_stats_work.tx_mc_octets += 4 * vnic_stats_work.tx_mc_frames;
        vnic_stats_work.tx_bc_octets += 4 * vnic_stats_work.tx_bc_frames;
        vnic_stats_work.tx_uc_octets += vnic_stats_work.tx_octets;
        if (vnic_stats_work.tx_uc_octets >= vnic_stats_work.tx_mc_octets)
            vnic_stats_work.tx_uc_octets -= vnic_stats_work.tx_mc_octets;
        else
            vnic_stats_work.tx_uc_octets = 0;
        if (vnic_stats_work.tx_uc_octets >= vnic_stats_work.tx_bc_octets)
            vnic_stats_work.tx_uc_octets -= vnic_stats_work.tx_bc_octets;
        else
            vnic_stats_work.tx_uc_octets = 0;

        vnic_stats_work.bpf_pass_octets += 4 * vnic_stats_work.bpf_pass_frames;
        vnic_stats_work.bpf_drop_octets += 4 * vnic_stats_work.bpf_drop_frames;
        vnic_stats_work.bpf_tx_octets += 4 * vnic_stats_work.bpf_tx_frames;
        vnic_stats_work.bpf_abort_octets += 4 * vnic_stats_work.bpf_abort_frames;

        vid = NFD_VNIC2VID(NFD_VNIC_TYPE_PF, port);
	addr = NFD_CFG_BAR_ISL(NIC_PCI, vid) + NFP_NET_CFG_STATS_RX_UC_OCTETS;
        mem_read32(&read_block, addr, 8);
        tmp = read_block[0] + (((uint64_t) read_block[1]) << 32);
        if (vnic_stats_work.rx_uc_octets < tmp) {
            vnic_stats_work.rx_uc_octets = tmp;
        }
        vid = NFD_VNIC2VID(NFD_VNIC_TYPE_PF, port);
	addr = NFD_CFG_BAR_ISL(NIC_PCI, vid) + NFP_NET_CFG_STATS_TX_UC_OCTETS;
        mem_read32(&read_block, addr, 8);
        tmp = read_block[0] + (((uint64_t) read_block[1]) << 32);
        if (vnic_stats_work.tx_uc_octets < tmp) {
            vnic_stats_work.tx_uc_octets = tmp;
        }

        bar_stats_work.rx_discards = vnic_stats_work.rx_discards;
        bar_stats_work.rx_errors = vnic_stats_work.rx_errors;
        bar_stats_work.rx_octets = vnic_stats_work.rx_octets;
        bar_stats_work.rx_uc_octets = vnic_stats_work.rx_uc_octets;
        bar_stats_work.rx_mc_octets = vnic_stats_work.rx_mc_octets;
        bar_stats_work.rx_bc_octets = vnic_stats_work.rx_bc_octets;
        bar_stats_work.rx_frames = vnic_stats_work.rx_frames;
        bar_stats_work.rx_mc_frames = vnic_stats_work.rx_mc_frames;
        bar_stats_work.rx_bc_frames = vnic_stats_work.rx_bc_frames;

        bar_stats_work.tx_discards = vnic_stats_work.tx_discards;
        bar_stats_work.tx_errors = vnic_stats_work.tx_errors;
        bar_stats_work.tx_octets = vnic_stats_work.tx_octets;
        bar_stats_work.tx_uc_octets = vnic_stats_work.tx_uc_octets;
        bar_stats_work.tx_mc_octets = vnic_stats_work.tx_mc_octets;
        bar_stats_work.tx_bc_octets = vnic_stats_work.tx_bc_octets;
        bar_stats_work.tx_frames = vnic_stats_work.tx_frames;
        bar_stats_work.tx_mc_frames = vnic_stats_work.tx_mc_frames;
        bar_stats_work.tx_bc_frames = vnic_stats_work.tx_bc_frames;

        bar_stats_work.app0_frames = vnic_stats_work.bpf_pass_frames;
        bar_stats_work.app0_bytes = vnic_stats_work.bpf_pass_octets;
        bar_stats_work.app1_frames = vnic_stats_work.bpf_drop_frames;
        bar_stats_work.app1_bytes = vnic_stats_work.bpf_drop_octets;
        bar_stats_work.app2_frames = vnic_stats_work.bpf_tx_frames;
        bar_stats_work.app2_bytes = vnic_stats_work.bpf_tx_octets;
        bar_stats_work.app3_frames = vnic_stats_work.bpf_abort_frames;
        bar_stats_work.app3_bytes = vnic_stats_work.bpf_abort_frames;

	global_stats_work.rx_discards += vnic_stats_work.rx_discards +
                                         vnic_stats_work.global_rx_discards +
                                         vnic_stats_work.global_rx_discards_proto;
        global_stats_work.rx_discards_proto += vnic_stats_work.global_rx_discards_proto;
        global_stats_work.rx_errors += vnic_stats_work.rx_errors +
                                       vnic_stats_work.global_rx_errors +
                                       vnic_stats_work.global_rx_errors_parse;
        global_stats_work.rx_octets += vnic_stats_work.rx_octets +
                                       vnic_stats_work.global_rx_octets;
        global_stats_work.rx_frames += vnic_stats_work.rx_frames +
                                       vnic_stats_work.global_rx_frames;
        global_stats_work.tx_discards += vnic_stats_work.tx_discards +
                                         vnic_stats_work.global_tx_discards;
        global_stats_work.tx_errors += vnic_stats_work.tx_errors +
                                       vnic_stats_work.global_tx_errors +
                                       vnic_stats_work.global_tx_errors_pci;
        global_stats_work.tx_errors_pci += vnic_stats_work.global_tx_errors_pci;
        global_stats_work.tx_octets += vnic_stats_work.tx_octets +
                                       vnic_stats_work.global_tx_octets;
        global_stats_work.tx_frames += vnic_stats_work.tx_frames +
                                       vnic_stats_work.global_tx_frames;

        // write MAC stats using bulk engine
        mac_stat = 0;
        for (addr = (__mem char *) &mac_stats[NS_PLATFORM_MAC_SERDES_LO(port)];
             addr < (__mem char *) &mac_stats[NS_PLATFORM_MAC_SERDES_LO(port) + 1];
             addr += sizeof(write_block)) {

            block_stat = 0;
            while (block_stat < sizeof(write_block) / 4 && mac_stat < sizeof(mac_stats_work) / 8) {
                write_block[block_stat++] = mac_stats_work.__raw[mac_stat];
                write_block[block_stat++] = mac_stats_work.__raw[mac_stat++] >> 32;
            }
            mem_write32(&write_block, addr, sizeof(write_block));
        }

        // write VNIC stats using bulk engine (stop before globals)
        vnic_stat = 0;
        for (addr = (__mem char *) &vnic_stats[port];
             addr < (__mem char *) &vnic_stats[port].global_rx_discards;
             addr += sizeof(write_block)) {

            block_stat = 0;
            while (block_stat < sizeof(write_block) / 4 && vnic_stat < sizeof(vnic_stats_work) / 8) {
                write_block[block_stat++] = vnic_stats_work.__raw[vnic_stat];
                write_block[block_stat++] = vnic_stats_work.__raw[vnic_stat++] >> 32;
            }
            size = ((__mem char *) &vnic_stats[port].global_rx_discards) - addr;
            if (size > sizeof(write_block)) {
                size = sizeof(write_block);
            }
            mem_write32(&write_block, addr, size);
        }

        // write bar stats using bulk engine
        vid = NFD_VNIC2VID(NFD_VNIC_TYPE_PF, port);
        bar_end = NFD_CFG_BAR_ISL(NIC_PCI, vid) + NFP_NET_CFG_STATS_APP3_BYTES + 8;
        bar_stat = 0;
        for (addr = NFD_CFG_BAR_ISL(NIC_PCI, vid) + NFP_NET_CFG_STATS_RX_DISCARDS;
             addr < bar_end; addr += sizeof(write_block)) {

            block_stat = 0;
            while (block_stat < sizeof(write_block) / 4 && bar_stat < sizeof(bar_stats_work) / 8) {
                write_block[block_stat++] = bar_stats_work.__raw[bar_stat];
                write_block[block_stat++] = bar_stats_work.__raw[bar_stat++] >> 32;
            }
            size = bar_end - addr;
            if (size > sizeof(write_block)) {
                size = sizeof(write_block);
            }
            mem_write32(&write_block, addr, size);
        }
    }

    // disaggregate global statistics
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        global_stat = 0;
        for (addr = (__mem char *) &vnic_stats[port].global_rx_discards;
             addr < (__mem char *) &vnic_stats[port + 1];
             addr += sizeof(write_block)) {

            block_stat = 0;
            while (block_stat < sizeof(write_block) / 4 && global_stat < sizeof(global_stats_work) / 8) {
                write_block[block_stat++] = global_stats_work.__raw[global_stat];
                write_block[block_stat++] = global_stats_work.__raw[global_stat++] >> 32;
            }
            size = ((__mem char *) &vnic_stats[port + 1]) - addr;
            if (size > sizeof(write_block)) {
                size = sizeof(write_block);
            }
            mem_write32(&write_block, addr, size);
        }
    }
}

void
nic_stats_loop(void)
{
    SIGNAL sig;
    __gpr uint32_t alarms = 0;

    set_alarm(STATS_ACCUMULATE_INTERVAL, &sig);

    for (;;) {
        if (signal_test(&sig)) {
            stats_accumulate();

            if ((alarms & (STATS_AGGREGATE_DIVISOR-1)) == 0) {
                stats_aggregate();
            }
            alarms++;

            set_alarm(STATS_ACCUMULATE_INTERVAL, &sig);
        }
        ctx_swap();
    }
    /* NOTREACHED */
}

#endif /* _LIBNIC_NIC_STATS_C_ */
