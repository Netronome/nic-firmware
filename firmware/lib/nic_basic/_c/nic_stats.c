/*
 * Copyright 2015-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          lib/nic/_c/nic_stats.c
 * @brief         Implementation for additional stats
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _LIBNIC_NIC_STATS_C_
#define _LIBNIC_NIC_STATS_C_

#include <nfp/macstats.h>
#include <nfp/me.h>
#include <nfp/mem_atomic.h>
#include <nfp/mem_bulk.h>
#include <nfp/tmq.h>
#include <std/cntrs.h>

#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_out.h>

#include "nic_stats.h"

/* How often to update the control BAR stats (in cycles) */
#define STATS_INTERVAL 0x20000

typedef struct {
    uint64_t rx_discards; // head drops
    uint64_t tx_discards; // TMQ drops
    uint64_t rx_errors; // RxPIfInErrors
    uint64_t tx_errors; // TxPifOutErrors
} mac_drops_t;


typedef struct {
	uint64_t rx_pkts;
	uint64_t rx_bytes;
	uint64_t tx_pkts;
	uint64_t tx_bytes;
} nfd_qstats_t;

// working stats
__shared __align8 __imem struct macstats_port_accum _mac_stats[NS_PLATFORM_NUM_PORTS];
__shared __align8 __imem struct macstats_head_drop_accum _mac_stats_head_drop;
__lmem __shared mac_drops_t _mac_drops[NS_PLATFORM_NUM_PORTS] = { 0 };
__lmem __shared nic_stats_vnic_t _vnic_stats;

// result stats
__export __shared __emem struct macstats_port_accum mac_stats[24];

#define MIN(x, y) ((x) > (y)) ? (y) : (x)

static void mac_stats_accumulate(void)
{
    __mem uint64_t *stat;
    __xread uint64_t head_drops;
    __xread uint32_t tmq_drop[2];
    __xread uint64_t read_block[8];
    __xwrite uint64_t write_block[8];
    __gpr uint32_t i;
    __gpr uint32_t offset;
    __gpr uint32_t port;
    __gpr uint32_t size;
    __gpr uint32_t tmq_cnt;
    __gpr uint32_t channel;
    SIGNAL s1, s2;

    /* accumulate the statistics for each port. */
    macstats_head_drop_accum(0, 0, 0xfff, &_mac_stats_head_drop);
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        channel = NS_PLATFORM_MAC_SERDES_LO(port);
        macstats_port_accum(NS_PLATFORM_MAC(port), channel, &_mac_stats[port]);

        mem_read_atomic(&head_drops,
			&_mac_stats_head_drop.ports_drop[port],
			sizeof(head_drops));
        _mac_drops[port].rx_discards = swapw64(head_drops);

        for (i = NS_PLATFORM_NBI_TM_QID_LO(port);
             i <= NS_PLATFORM_NBI_TM_QID_HI(port);
             ++i) {
            tmq_cnt_read(NS_PLATFORM_MAC(port), &tmq_cnt, i, 1);
            _mac_drops[port].tx_discards += (uint64_t) tmq_cnt;
        }

        /* copy from atomic MAC stats to bulk host symbol */
        assert(sizeof(read_block) == sizeof(write_block));
        for (offset = 0;
	     offset < sizeof(struct macstats_port_accum);
	     offset += sizeof(write_block)) {
	    size = sizeof(read_block) / 2;
	    __mem_read_atomic(&read_block,
			      ((__mem char *) &_mac_stats[port]) + offset,
			      size, size, sig_done, &s1);
            __mem_read_atomic(&read_block[size / 8],
			      ((__mem char *) &_mac_stats[port]) + offset + size,
			      size, size, sig_done, &s2);
	    wait_for_all(&s1, &s2);

	    for (i = 0; i < sizeof(write_block) / 8; ++i) {
		stat = ((__mem uint64_t *) &_mac_stats[port]) + offset / 8 + i;
		if (stat == &_mac_stats[port].RxMacHeadDrop)
                    write_block[i] = swapw64(_mac_drops[port].rx_discards);
		else if (stat == &_mac_stats[port].TxQueueDrop)
                    write_block[i] = swapw64(_mac_drops[port].tx_discards);
		else {
		    if (stat == &_mac_stats[port].TxPIfOutErrors)
			_mac_drops[port].tx_errors = swapw64(read_block[i]);
                    else if (stat == &_mac_stats[port].RxPIfInErrors)
			_mac_drops[port].rx_errors = swapw64(read_block[i]);
		    write_block[i] = read_block[i];
		}
	    }

	    size = MIN(sizeof(write_block),
		       sizeof(struct macstats_port_accum) - offset);
	    /* host ABI expects sparse table of stats indexed by base channel */
	    mem_write64(&write_block,
			((__mem char *) &mac_stats[channel]) + offset,
			size);
	}
    }
}


static void
update_vnic_queue_stat(nfd_qstats_t *nfd,
	               uint32_t *vnic_stat, uint32_t queue_stat,
		       unsigned int pkts,
		       unsigned long long bytes)
{
    if (nic_stats_vnic_mask[queue_stat] & NIC_STATS_VNIC_MASK_PKTS)
	    _vnic_stats.__raw[(*vnic_stat)++] += pkts;
    if (nic_stats_vnic_mask[queue_stat] & NIC_STATS_VNIC_MASK_BYTES)
	    _vnic_stats.__raw[(*vnic_stat)++] += bytes;
    switch (queue_stat) {
    case NIC_STATS_QUEUE_RX_IDX:
        _vnic_stats.rx_uc_pkts += pkts;
        _vnic_stats.rx_uc_bytes += bytes;
	nfd->rx_pkts += pkts;
	nfd->rx_bytes += bytes;
        break;
    case NIC_STATS_QUEUE_RX_BC_IDX:
    case NIC_STATS_QUEUE_RX_MC_IDX:
	_vnic_stats.rx_pkts += pkts;
	_vnic_stats.rx_bytes += bytes;
	nfd->rx_pkts += pkts;
	nfd->rx_bytes += bytes;
	break;
    case NIC_STATS_QUEUE_RX_UC_IDX:
    case NIC_STATS_QUEUE_TX_UC_IDX:
	break;
    case NIC_STATS_QUEUE_TX_IDX:
	_vnic_stats.tx_uc_pkts += pkts;
	_vnic_stats.tx_uc_bytes += bytes;
	nfd->tx_pkts += pkts;
	nfd->tx_bytes += bytes;
	break;
    case NIC_STATS_QUEUE_TX_BC_IDX:
    case NIC_STATS_QUEUE_TX_MC_IDX:
	_vnic_stats.tx_pkts += pkts;
        _vnic_stats.tx_bytes += bytes;
	nfd->tx_pkts += pkts;
	nfd->tx_bytes += bytes;
        break;
    case NIC_STATS_QUEUE_RX_DISCARD_ACT_IDX:
    case NIC_STATS_QUEUE_RX_DISCARD_ADDR_IDX:
    case NIC_STATS_QUEUE_RX_DISCARD_MRU_IDX:
    case NIC_STATS_QUEUE_RX_DISCARD_PCI_IDX:
    case NIC_STATS_QUEUE_BPF_DISCARD_IDX:
	_vnic_stats.rx_discards += pkts;
	break;
    case NIC_STATS_QUEUE_RX_ERROR_VEB_IDX:
	_vnic_stats.rx_errors += pkts;
    case NIC_STATS_QUEUE_TX_DISCARD_ACT_IDX:
	_vnic_stats.tx_discards += pkts;
	break;
    case NIC_STATS_QUEUE_TX_ERROR_LSO_IDX:
    case NIC_STATS_QUEUE_TX_ERROR_PCI_IDX:
    case NIC_STATS_QUEUE_TX_ERROR_MTU_IDX:
    case NIC_STATS_QUEUE_TX_ERROR_NO_CTM_IDX:
    case NIC_STATS_QUEUE_TX_ERROR_OFFSET_IDX:
	_vnic_stats.tx_errors += pkts;
	break;
    case NIC_STATS_QUEUE_BPF_TX_IDX:
        _vnic_stats.tx_pkts += pkts;
        _vnic_stats.tx_bytes += bytes;
        break;
    default:
	break;
    }
}


static void update_vnic_bar_stats(uint32_t vid)
{
    __xwrite uint64_t write_block[9];

    write_block[0] = swapw64(_vnic_stats.rx_discards);
    write_block[1] = swapw64(_vnic_stats.rx_errors);
    write_block[2] = swapw64(_vnic_stats.rx_bytes);
    write_block[3] = swapw64(_vnic_stats.rx_uc_bytes);
    write_block[4] = swapw64(_vnic_stats.rx_mc_bytes);
    write_block[5] = swapw64(_vnic_stats.rx_bc_bytes);
    write_block[6] = swapw64(_vnic_stats.rx_pkts);
    write_block[7] = swapw64(_vnic_stats.rx_mc_pkts);
    write_block[8] = swapw64(_vnic_stats.rx_bc_pkts);
    mem_write64(&write_block,
		NFD_CFG_BAR_ISL(NIC_PCI, vid) +
		NFP_NET_CFG_STATS_RX_DISCARDS,
		sizeof(write_block));

    write_block[0] = swapw64(_vnic_stats.tx_discards);
    write_block[1] = swapw64(_vnic_stats.tx_errors);
    write_block[2] = swapw64(_vnic_stats.tx_bytes);
    write_block[3] = swapw64(_vnic_stats.tx_uc_bytes);
    write_block[4] = swapw64(_vnic_stats.tx_mc_bytes);
    write_block[5] = swapw64(_vnic_stats.tx_bc_bytes);
    write_block[6] = swapw64(_vnic_stats.tx_pkts);
    write_block[7] = swapw64(_vnic_stats.tx_mc_pkts);
    write_block[8] = swapw64(_vnic_stats.tx_bc_pkts);
    mem_write64(&write_block,
		NFD_CFG_BAR_ISL(NIC_PCI, vid) +
		NFP_NET_CFG_STATS_TX_DISCARDS,
		sizeof(write_block));

    write_block[0] = swapw64(_vnic_stats.bpf_pass_pkts);
    write_block[1] = swapw64(_vnic_stats.bpf_pass_bytes);
    write_block[2] = swapw64(_vnic_stats.bpf_discard_pkts);
    write_block[3] = swapw64(_vnic_stats.bpf_discard_bytes);
    write_block[4] = swapw64(_vnic_stats.bpf_tx_pkts);
    write_block[5] = swapw64(_vnic_stats.bpf_tx_bytes);
    write_block[6] = swapw64(_vnic_stats.bpf_abort_pkts);
    write_block[7] = swapw64(_vnic_stats.bpf_abort_bytes);
    mem_write64(&write_block,
		NFD_CFG_BAR_ISL(NIC_PCI, vid) +
		NFP_NET_CFG_STATS_APP0_FRAMES,
		64);
}


static void vnic_stats_remap(__lmem uint64_t *dst_stat,
					   __lmem uint64_t *dst_total,
					   __lmem uint64_t *src_stat,
					   __lmem uint64_t *src_total)
{
    if (*src_total)
	    *src_total -= *src_stat;
    if (*dst_total)
	    *dst_total += *src_stat;
    *dst_stat += *src_stat;
    *src_stat = 0;
}

static void vnic_stats_accumulate()
{
    __xread uint64_t read_block[8];
    __xwrite uint64_t write_block[8];
    unsigned int pkts;
    unsigned long long bytes;
    uint64_t delta;
    uint32_t i;
    uint32_t offset;
    uint32_t port;
    uint32_t queue;
    uint32_t size;
    uint32_t stat;
    uint32_t vid;
    nfd_qstats_t nfd_stats;
    struct pkt_cntr_addr addr;
    SIGNAL s1, s2;

    __imem nic_stats_queue_t *stats_queue = (__imem nic_stats_queue_t *) __link_sym("_nic_stats_queue");
    __emem nic_stats_vnic_t *stats_vnic = (__emem nic_stats_vnic_t *) __link_sym("_nic_stats_vnic");

    for (vid = 0; vid < NVNICS; ++vid) {

        /* read existing VNIC stats using bulk engine */
        for (offset = 0;
	     offset < sizeof(nic_stats_vnic_t);
	     offset += sizeof(read_block)) {
	    size = MIN(sizeof(read_block), sizeof(nic_stats_vnic_t) - offset);
            mem_read64(&read_block, ((__emem char *) &stats_vnic[vid]) + offset, size);
            for (i = 0; i < size / 8; ++i) {
	        _vnic_stats.__raw[(offset / 8) + i] = swapw64(read_block[i]);
            }
        }

        for (queue = 0; queue < NFD_VID_MAXQS(vid); ++queue) {
	    stat = 0;
            nfd_stats.rx_pkts = 0;
	    nfd_stats.rx_bytes = 0;
	    nfd_stats.tx_pkts = 0;
	    nfd_stats.tx_bytes = 0;

	    addr = pkt_cntr_get_addr(&stats_queue[NFD_VID2NATQ(vid, queue)]);
            for (i = 0; i < NIC_STATS_QUEUE_COUNT; ++i) {
		pkt_cntr_read_and_clr(addr, i, 0, &pkts, &bytes);
		update_vnic_queue_stat(&nfd_stats, &stat, i, pkts, bytes);
            }

	    /* update NFD per queue VNIC stats */
            write_block[0] = swapw64(nfd_stats.rx_pkts);
            write_block[1] = swapw64(nfd_stats.rx_bytes);
            write_block[2] = swapw64(nfd_stats.tx_pkts);
            write_block[3] = swapw64(nfd_stats.tx_bytes);
            __mem_add64(&write_block[0],
                        NFD_CFG_BAR_ISL(NIC_PCI, vid) +
	                NFP_NET_CFG_RXR_STATS(queue),
	                16, 16, sig_done, &s1);
            __mem_add64(&write_block[2],
                        NFD_CFG_BAR_ISL(NIC_PCI, vid) +
                        NFP_NET_CFG_TXR_STATS(queue),
                        16, 16, sig_done, &s2);
            wait_for_all(&s1, &s2);

	    /* RX is TX for these PCIe queue exceptions */
	    if (queue < (1 << 8)) {
		vnic_stats_remap(&_vnic_stats.tx_discard_act_pkts, &_vnic_stats.tx_discards,
				 &_vnic_stats.rx_discard_act_pkts, &_vnic_stats.rx_discards);

		vnic_stats_remap(&_vnic_stats.tx_discard_act_bytes, &_vnic_stats.tx_discards,
				 &_vnic_stats.rx_discard_act_bytes, &_vnic_stats.rx_discards);
	    }
	}

	if (NFD_VID_IS_PF(vid)) {
	    /* add stats for the associated NBI ingress queue  */
	    stat = 0;
	    port = NFD_VID2PF(vid);
	    addr = pkt_cntr_get_addr(&stats_queue[(1 << 8) + port]);
            for (i = 0; i < NIC_STATS_QUEUE_COUNT; ++i) {
	        pkt_cntr_read_and_clr(addr, i, 0, &pkts, &bytes);
		update_vnic_queue_stat(&nfd_stats, &stat, i, pkts, bytes);
            }

	    /* incorporate MAC drops into PF VNIC stats */
	    delta = _mac_drops[port].rx_discards - _vnic_stats.rx_discard_mac_pkts;
	    _vnic_stats.rx_discard_mac_pkts += delta;
	    _vnic_stats.rx_discards += delta;

	    delta = _mac_drops[port].rx_errors - _vnic_stats.rx_error_mac_pkts;
	    _vnic_stats.rx_error_mac_pkts += delta;
	    _vnic_stats.rx_errors += delta;

	    delta = _mac_drops[port].tx_discards - _vnic_stats.tx_discard_mac_pkts;
	    _vnic_stats.tx_discard_mac_pkts += delta;
	    _vnic_stats.tx_discards += delta;

	    delta = _mac_drops[port].tx_errors - _vnic_stats.tx_error_mac_pkts;
	    _vnic_stats.tx_error_mac_pkts += delta;
	    _vnic_stats.tx_errors += delta;
	}

	update_vnic_bar_stats(vid);

        /* write VNIC stats using bulk engine */
        for (offset = 0;
	     offset < sizeof(nic_stats_vnic_t);
	     offset += sizeof(write_block)) {
            for (i = 0; i < sizeof(write_block) / 8; ++i) {
	        write_block[i] = swapw64(_vnic_stats.__raw[(offset / 8) + i]);
            }

	    size = MIN(sizeof(write_block), sizeof(nic_stats_vnic_t) - offset);
            mem_write64(&write_block, ((__emem char *) &stats_vnic[vid]) + offset, size);
        }
    }

}


void
nic_stats_loop(void)
{
    SIGNAL sig;
    uint32_t alarms = 0;

    set_alarm(STATS_INTERVAL, &sig);

    for (;;) {
        if (signal_test(&sig)) {
            mac_stats_accumulate();
            vnic_stats_accumulate();

            set_alarm(STATS_INTERVAL, &sig);
        }
        ctx_swap();
    }
    /* NOTREACHED */
}

#endif /* _LIBNIC_NIC_STATS_C_ */
