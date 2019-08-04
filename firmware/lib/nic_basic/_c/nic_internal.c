/*
 * Copyright (C) 2014-2019,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          lib/nic/_c/nic_internal.c
 * @brief         Internal data structures
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _LIBNIC_NIC_INTERNAL_C_
#define _LIBNIC_NIC_INTERNAL_C_

//#ifndef CFG_NIC_LIB_DBG_JOURNAL
//#define CFG_NIC_LIB_DBG_JOURNAL 1
//#endif

#include <assert.h>
#include <nfp.h>
#include <stdint.h>
#include <nfp_cluster_target.h>

#include <nfp/me.h>
#include <nfp/mem_atomic.h>
#include <nfp/mem_bulk.h>
#include <std/event.h>
#include <std/reg_utils.h>
#include <std/synch.h>
#include <nfp/pcie.h>

#include <nfp6000/nfp_cls.h>
#include <nfp6000/nfp_event.h>

#include <vnic/shared/nfd_cfg.h>

#include "nic_ctrl.h"
#include "shared/nfp_net_ctrl.h"



#ifdef CFG_NIC_LIB_DBG_CNTRS
/*
 * Debug Counters:
 * @nic_reconfig_cnt        Per ME reconfiguration counter
 * @nic_cnt_rx_pkts         Packets received
 * @nic_cnt_rx_drop_down    Packets dropped due to device disabled
 * @nic_cnt_rx_drop_mtu     Packets dropped due to MTU size check
 * @nic_cnt_rx_csum_err     Packets with checksum errors
 * @nic_cnt_rx_eth_local    Ethernet DA matches local MAC address
 * @nic_cnt_rx_eth_bc       Ethernet broadcast packets
 * @nic_cnt_rx_eth_mc       Ethernet multicast packets
 * @nic_cnt_rx_drop_eth     Packets dropped by L2 filters
 *
 * @nic_cnt_tx_drop_down    Packets dropped due to device disabled
 * @nic_cnt_tx_drop_mtu     Packets dropped due to MTU size check
 */
#define NIC_LIB_CNTR(_x) mem_incr64(_x)
__export __dram uint64_t nic_reconfig_cnt[40];

__export __dram uint64_t nic_cnt_rx_pkts;
__export __dram uint64_t nic_cnt_rx_drop_dev_down;
__export __dram uint64_t nic_cnt_rx_drop_ring_down;
__export __dram uint64_t nic_cnt_rx_drop_mtu;
__export __dram uint64_t nic_cnt_rx_csum_err_l3;
__export __dram uint64_t nic_cnt_rx_csum_err_l4_tcp;
__export __dram uint64_t nic_cnt_rx_csum_err_l4_udp;
__export __dram uint64_t nic_cnt_rx_eth_local;
__export __dram uint64_t nic_cnt_rx_eth_sa_err;
__export __dram uint64_t nic_cnt_rx_eth_drop;
__export __dram uint64_t nic_cnt_rx_eth_drop_mc;
__export __dram uint64_t nic_cnt_rx_eth_drop_da;

__export __dram uint64_t nic_cnt_tx_drop_down;
__export __dram uint64_t nic_cnt_tx_drop_mtu;
#else
#define NIC_LIB_CNTR(_me)
#endif


#define CREATE_JOURNAL(name)                                    \
    EMEM0_QUEUE_ALLOC(name##_rnum, global);                     \
    _NFP_CHIPRES_ASM(.alloc_mem name##_mem emem0 global         \
                     SZ_2M SZ_2M);                              \
    _NFP_CHIPRES_ASM(.init_mu_ring name##_rnum name##_mem);     \
    __shared __gpr unsigned int dbg_##name##_rnum;              \
    __shared __gpr mem_ring_addr_t dbg_##name##_mem;

#define INIT_JOURNAL(name)                              \
    do {                                                \
        dbg_##name##_rnum = _link_sym(name##_rnum);     \
            dbg_##name##_mem = mem_ring_get_addr(       \
                (__dram void *)_link_sym(name##_mem));  \
    } while(0)

/* RX debugging */
#if defined(CFG_NIC_LIB_DBG_JOURNAL)

#define NIC_LIB_DBG(name, _x)                                 \
    mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _x)
#define NIC_LIB_DBG4(name, _a, _b, _c, _d)                           \
    do {                                                                \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _a); \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _b); \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _c); \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _d); \
    } while (0)
#define PRINTDBG(name, _a)                                 \
    mem_ring_journal(dbg_##name##_rnum, dbg_##name##_mem, _a, 4)
#else
#define NIC_LIB_DBG(name, _x)
#define NIC_LIB_DBG4(name, _a, _b, _c, _d)
#define PRINTDBG(name, _a)
#endif


#if defined(CFG_NIC_LIB_DBG_JOURNAL)
CREATE_JOURNAL(libnic_dbg);
#endif


/*
 * Create mask for VPort
 */
#define VPORT_MASK(_vp) (1ull << (_vp))

/**
 * Boolean comparison of the first x elements of two arrays of the same
 * memory type
 */
#define _REG_CMP_1(_type, _a, _b)                                           \
    (((_type)_a)[0] == ((_type)_b)[0])

#define _REG_CMP_2(_type, _a, _b)                                           \
    _REG_CMP_1(_type, _a, _b) &&                                            \
    (((_type)_a)[1] == ((_type)_b)[1])

#define _REG_CMP_3(_type, _a, _b)                                           \
    _REG_CMP_2(_type, _a, _b) &&                                            \
    (((_type)_a)[2] == ((_type)_b)[2])

/**
 * Boolean comparisons between two of the same memory type.
 *
 * Note the memory type is keyed off the first array argument @ref _a
 *
 * @param _n    The number of indices that should be compared
 * @param _a    The first array - used to key the mem type
 * @param _b    The second array
 */
#define REG_CMPC(_n, _a, _b)                                                \
    ((__is_in_lmem(_a)) ? _REG_CMP_##_n(__lmem uint8_t *, _a, _b)           \
                        : _REG_CMP_##_n(__gpr  uint8_t *, _a, _b))
#define REG_CMPS(_n, _a, _b)                                                \
    ((__is_in_lmem(_a)) ? _REG_CMP_##_n(__lmem uint16_t *, _a, _b)          \
                        : _REG_CMP_##_n(__gpr  uint16_t *, _a, _b))
#define REG_CMPL(_n, _a, _b)                                                \
    ((__is_in_lmem(_a)) ? _REG_CMP_##_n(__lmem uint32_t *, _a, _b)          \
                        : _REG_CMP_##_n(__gpr  uint32_t *, _a, _b))
#define REG_CMPLL(_n, _a, _b)                                               \
    ((__is_in_lmem(_a)) ? _REG_CMP_##_n(__lmem uint64_t *, _a, _b)          \
                        : _REG_CMP_##_n(__gpr  uint64_t *, _a, _b))

#define UINT8_REG(_a) ((__is_in_lmem(_a)) ? ((__lmem uint8_t *)_a)          \
                                          : ((__gpr  uint8_t *)_a))
#define UINT16_REG(_a) ((__is_in_lmem(_a)) ? ((__lmem uint16_t *)_a)        \
                                           : ((__gpr  uint16_t *)_a))
#define UINT32_REG(_a) ((__is_in_lmem(_a)) ? ((__lmem uint32_t *)_a)        \
                                           : ((__gpr  uint32_t *)_a))
#define UINT64_REG(_a) ((__is_in_lmem(_a)) ? ((__lmem uint64_t *)_a)        \
                                           : ((__gpr  uint64_t *)_a))

#define NIC_IS_BC_ADDR(_a) \
    (UINT16_REG(_a)[0] == 0xffff && UINT16_REG(_a)[1] == 0xffff &&          \
     UINT16_REG(_a)[2] == 0xffff)

#define NIC_IS_MC_ADDR(_a) ((__is_in_lmem(_a)) ? \
      (((__lmem struct eth_addr *)_a)->a[0] & NET_ETH_GROUP_ADDR) \
    : (((__gpr struct eth_addr *)_a)->a[0] & NET_ETH_GROUP_ADDR))

/*
 * Struct describing the current state of the NIC endpoint.
 *
 * RN: We could probably make this a little smaller if there is a
 * pressure on LM.  Both the bar pointer and the outq can be by other
 * means.
 */
struct nic_local_state {
    uint32_t control[NVNICS];      /* 0x000: Cache of NFP_NET_CFG_CTRL */

    uint64_t tx_ring_en[NVNICS];  /* 0x004: Cache of NFP_NET_CFG_TXRS_ENABLE */
    uint64_t rx_ring_en[NVNICS];        /* 0x00c: Cache of NFP_NET_CFG_RXRS_ENABLE */

    uint32_t mtu[NVNICS];        /* 0x014: Configured MTU */
    uint32_t mac[NVNICS][2];     /* 0x018: Cache of NFP_NET_CFG_MACADDR */

    /*TODO: per VF value in the following should be added later when needed*/
    uint32_t rss_ctrl[NVNICS];          /* 0x020: Cache of RSS control */
/* 0x024: Cache of RSS key */
    uint8_t  rss_key[NVNICS][NFP_NET_CFG_RSS_KEY_SZ];
    uint8_t  rss_tbl[NVNICS][NFP_NET_CFG_RSS_ITBL_SZ]; /* 0x04c: Cache of RSS ITBL */
    uint16_t vxlan_ports[NFP_NET_N_VXLAN_PORTS]; /* 0x188 vxlan ports */

};

/*
 * Global variables (per ME) for NIC related state
 *
 * @nic_lstate:             LM cache of some of the NIC state.
 * @cfg_bar_change_sig:     A visible signal to communicate config changes
 * @cfg_bar_change_info:    A visible xread to communicate config changes info
 * @nic_cfg_synch:          Synchronization counter
 */
__shared __lmem volatile struct nic_local_state nic_lstate;

/* NIC BAR Reconfiguration handling */
struct nic_reconfig_info {
    uint32_t pci:16;
    uint32_t vnic:16;
};
/* NIC configuration change signal and change info from APP master */
__visible SIGNAL cfg_bar_change_sig;
__visible volatile __xread struct nic_reconfig_info cfg_bar_change_info;
__import __dram struct synch_cnt nic_cfg_synch;

__intrinsic uint64_t
swapw64(uint64_t val)
{
    uint32_t tmp;
    tmp = val >> 32;
    return (val << 32) + tmp;
}


/*
 * Initialise the rings and eventfilters/autopushes.
 */
__intrinsic void
nic_local_init(int sig_num, int reg_num)
{
    //__assign_relative_register((void *)&cfg_bar_change_sig, sig_num);
    //__assign_relative_register((void *)&cfg_bar_change_info, reg_num);

#if defined(CFG_NIC_LIB_DBG_JOURNAL)
    INIT_JOURNAL(libnic_dbg);
#endif
}

__intrinsic int
nic_local_cfg_changed() {
    return signal_test(&cfg_bar_change_sig);
}

/*
 * Update local state on re-config
 */
__intrinsic void
nic_local_reconfig(uint32_t *enable_changed)
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;
    __xread uint32_t mtu;
    __xread uint32_t tmp2[2];
    __xread uint64_t ring_en[2];
    __xread uint32_t nic_mac[2];
    __xread uint32_t rss_ctrl[2];
    __xread uint64_t rss_key[NFP_NET_CFG_RSS_KEY_SZ / sizeof(uint64_t)];
    __xread uint64_t rss_tbl[(NFP_NET_CFG_RSS_ITBL_SZ / 2) / sizeof(uint64_t)];
    __xread uint16_t vxlan_ports[NFP_NET_N_VXLAN_PORTS];
    __gpr uint32_t update;
    __gpr uint32_t newctrl;
    __emem __addr40 uint8_t *bar_base;
    __gpr uint32_t vnic;
    __lmem void *ptr;

    /* Code assumes certain arrangement and sizes */
    ctassert(NFP_NET_CFG_RXRS_ENABLE == NFP_NET_CFG_TXRS_ENABLE + 8);
    ctassert(NFP_NET_CFG_RSS_KEY_SZ == 40);
    ctassert(NFP_NET_CFG_RSS_ITBL_SZ == 128);

    *enable_changed = 0;

    /* Need to read the update word from the BAR */

    /* Calculate the relevant configuration BAR base address */
    switch (cfg_bar_change_info.pci) {
    case 0:
        bar_base = NFD_CFG_BAR_ISL(0, cfg_bar_change_info.vnic);
        break;
    default:
        halt();
    }

    vnic = cfg_bar_change_info.vnic;

    /* Read the ctrl(0) + update(1) words */
    mem_read64(&tmp2, (__mem void*)(bar_base + NFP_NET_CFG_CTRL), sizeof(tmp2));
    newctrl = tmp2[0];
    update = tmp2[1];

     /* Handle general updates */
    if (update & NFP_NET_CFG_UPDATE_GEN) {
        /* Check if link global enable changed */
        if ((nic->control[vnic] ^ newctrl) & NFP_NET_CFG_CTRL_ENABLE) {
            *enable_changed = 1;
        }
        if (!(newctrl & NFP_NET_CFG_CTRL_ENABLE)) {
            /* NIC got disabled, zero control and we are done */
            nic->control[vnic] = 0;
            nic->rss_ctrl[vnic] = 0;
            goto reconfig_done;
        }

        /* MTU */
        mem_read32(&mtu, (__mem void*)(bar_base + NFP_NET_CFG_MTU),
                   sizeof(mtu));
        nic->mtu[vnic] = mtu;

        /* MAC Address */
        mem_read64(nic_mac, (__mem void*)(bar_base + NFP_NET_CFG_MACADDR),
                   sizeof(nic_mac));

        ptr = &(nic->mac[vnic]);
        reg_cp(ptr, nic_mac, 8);

        /* Stash away new control to activate */
        nic->control[vnic] = newctrl;
    }

    /* Handle Ring reconfiguration.
     * (This assume we advertise NFP_NET_CFG_CTRL_RINGCFG) */
    if (update & NFP_NET_CFG_UPDATE_RING) {

        /* Read TX/RX ring status */
        mem_read64(&ring_en,
                   (__mem void*)(bar_base + NFP_NET_CFG_TXRS_ENABLE),
                   sizeof(ring_en));
        nic->tx_ring_en[vnic] = swapw64(ring_en[0]);
        nic->rx_ring_en[vnic] = swapw64(ring_en[1]);
    }

     /* Handle MAC address updates */
    if (update & NFP_NET_CFG_UPDATE_MACADDR) {
        /* MAC Address */
        mem_read64(nic_mac, (__mem void*)(bar_base + NFP_NET_CFG_MACADDR),
                   sizeof(nic_mac));

        ptr = &(nic->mac[vnic]);
        reg_cp(ptr, nic_mac, 8);
    }

    /* Handle RSS re-config */
    if (update & NFP_NET_CFG_UPDATE_RSS &&
        nic->control[vnic] & NFP_NET_CFG_CTRL_RSS) {

        mem_read64(rss_ctrl, bar_base + NFP_NET_CFG_RSS_CTRL,
                   sizeof(rss_ctrl));

        /* Read RSS key and table. Table requires two reads*/
        mem_read64(rss_key, bar_base + NFP_NET_CFG_RSS_KEY,
                   NFP_NET_CFG_RSS_KEY_SZ);
        ptr = &(nic->rss_key[vnic]);
        reg_cp(ptr, rss_key, NFP_NET_CFG_RSS_KEY_SZ);

        mem_read64_swap(rss_tbl, bar_base + NFP_NET_CFG_RSS_ITBL,
            sizeof(rss_tbl));
        ptr = &(nic->rss_tbl[vnic]);
        reg_cp(ptr, rss_tbl, sizeof(rss_tbl));

        mem_read64_swap(rss_tbl,
            bar_base + NFP_NET_CFG_RSS_ITBL + sizeof(rss_tbl),
                        sizeof(rss_tbl));
        ptr = (void *) &(nic->rss_tbl[vnic][sizeof(rss_tbl)]);
        reg_cp(ptr, rss_tbl, sizeof(rss_tbl));

        /* Write control word to activate */
        nic->rss_ctrl[vnic] = rss_ctrl[0];
    }

    /* VXLAN reconfig */
    if (update & NFP_NET_CFG_UPDATE_VXLAN &&
        nic->control[vnic] & NFP_NET_CFG_CTRL_VXLAN) {

        mem_read64(vxlan_ports, bar_base + NFP_NET_CFG_VXLAN_PORT,
                   sizeof(vxlan_ports));
        reg_cp((void*)nic->vxlan_ports, vxlan_ports, sizeof(vxlan_ports));
    }

reconfig_done:
        return;
}

void
nic_local_reconfig_done()
{
    /* Ack the configuration change to APP master */
    synch_cnt_dram_ack(&nic_cfg_synch);
}

#include "ebpf.h"

__intrinsic int
nic_local_cfg_bpf_is_enabled()
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    return !!(nic->control[0] & NFP_NET_CFG_CTRL_BPF);
}

static __intrinsic void
ct_write_nn(unsigned int isl, unsigned int me, unsigned int nn_idx, unsigned int val)
{
    SIGNAL sig;
    unsigned int addr;
    unsigned int __xwrite xfer;

    addr = (isl << 24) | (me << 17) | (1 << 9) | (nn_idx << 2);
    xfer = val;

    __asm {
        ct[ctnn_write, xfer, addr, 0, 1], ctx_swap[sig];
    };
}

/* XXX Move to some sort of CT reflect library */
static __intrinsic unsigned int
ct_read_csr(unsigned int isl, unsigned int me, unsigned int csr_addr)
{
    SIGNAL sig;
    unsigned int addr;
    unsigned int ret;
    unsigned int __xread xfer;

    addr = (isl << 24) | (1 << 16) | (me << 10) | csr_addr;

    __asm {
        ct[reflect_read_sig_init, xfer, addr, 0, 1], ctx_swap[sig];
    };

    ret = xfer;

    return ret;
}


static __intrinsic void
ct_write_csr(unsigned int isl, unsigned int me, unsigned int csr_addr, unsigned int val)
{
    SIGNAL sig;
    unsigned int addr;
    unsigned int __xwrite xfer;

    addr = (isl << 24) | (1 << 16) | (me << 10) | csr_addr;
    xfer = val;

    __asm {
        ct[reflect_write_sig_init, xfer, addr, 0, 1], ctx_swap[sig];
    };
}


static __intrinsic void
ct_signal(unsigned int isl, unsigned int me, unsigned int ctx, unsigned int signal)
{
    unsigned int addr;

    addr = (isl << 24) | (me << 9) | (ctx << 6) | (signal << 2);

    __asm {
        ct[interthread_signal, --, 0, addr, --];
    };
}

#define PKT_IO_SIG_EPOCH        8
#define PKT_IO_SIG_NBI          9
#define PKT_IO_SIG_NFD          10
#define PKT_IO_SIG_NFD_RETRY    11
#define PKT_IO_SIG_RESUME       12
#define PKT_IO_SIG_QUIESCE_NBI  13
#define PKT_IO_SIG_QUIESCE_NFD  14

#define ME_CSR_USTORE_ADDR      0x00
#define ME_CSR_USTORE_DATA_LO   0x04
#define ME_CSR_USTORE_DATA_HI   0x08
#define ME_CSR_CTX_ENABLES      0x18
#define ME_CSR_CTX_PTR          0x20
#define ME_CSR_IND_CTX_STS      0x40
#define ME_CSR_IND_CTX_SGL_EVT  0x48
#define ME_CSR_IND_CTX_WKP_EVT  0x50

__shared __lmem uint32_t dp_mes_ids[] = { APP_MES_LIST };

static __intrinsic void
update_bpf_prog(__gpr uint32_t *ctx_mode, __emem __addr40 uint8_t *bar_base, uint32_t vnic)
{
    __xread uint32_t host_mem_bpf_cfg[3];
    __xread uint32_t data[2];
    __gpr uint32_t data_out;
    __gpr unsigned int addr_hi;
    __gpr unsigned int addr_lo;
    __gpr unsigned int i;
    __gpr unsigned int words;
    __gpr unsigned int isl;
    __gpr unsigned int me;
    __gpr unsigned int ctx;
    __gpr unsigned int wkp_mask;
    __gpr unsigned int ctx_enables;

    for (i = 0; i < sizeof(dp_mes_ids) / sizeof(uint32_t); i++) {
        isl = dp_mes_ids[i] >> 4;
        me = dp_mes_ids[i] & 0xf;

        // signal threads to go quiescent
        for (ctx = 0; ctx < 8; ctx = ctx + 2) {
            ct_signal(isl, me, ctx, PKT_IO_SIG_QUIESCE_NBI);
            ct_signal(isl, me, ctx, PKT_IO_SIG_QUIESCE_NFD);
        }
        sleep(10000);

        // force any remaining threads to quiesce
        do {
            ctx_enables = ct_read_csr(isl, me, ME_CSR_CTX_ENABLES);
            ctx_enables &= 0xffff00ff;
            ct_write_csr(isl, me, ME_CSR_CTX_ENABLES, ctx_enables);
            sleep(250);
            for (ctx = 0; ctx < 8; ctx += 2) {
                ct_write_csr(isl, me, ME_CSR_CTX_PTR, ctx);
                wkp_mask = ct_read_csr(isl, me, ME_CSR_IND_CTX_WKP_EVT);
                if (! (wkp_mask & ((1 << PKT_IO_SIG_EPOCH) | (1 << PKT_IO_SIG_RESUME))))
                    ctx_enables |= (1 << (8 + ctx));
            }
            if (ctx_enables & 0xff00) {
                ct_write_csr(isl, me, ME_CSR_CTX_ENABLES, ctx_enables);
                sleep(1000); // shorter wait, will wait again if necessary
            }
        }
        while (ctx_enables & 0xff00);

        // safe to write BPF code store
        mem_read32(host_mem_bpf_cfg, bar_base + NFP_NET_CFG_BPF_SIZE - 2, sizeof host_mem_bpf_cfg);

        // note: data from the BAR comes in 4B-swapped; low is high, high is low
        words = host_mem_bpf_cfg[0] >> 16;
        addr_lo = host_mem_bpf_cfg[1];
        addr_hi = host_mem_bpf_cfg[2];

        pcie_c2p_barcfg_set(0 /*pci_isl0*/, PCIE_CPP2PCIE_BPF_LOAD, addr_hi, addr_lo, 0);

        addr_lo >>= 3;

        // set instr pointer to 'start' and enable writing. */
        data_out = 0x80000000 + NFD_BPF_START_OFF + vnic * NFD_BPF_MAX_LEN;
        ct_write_csr(isl, me, ME_CSR_USTORE_ADDR, data_out);

        while (words--) {
            pcie_read(&data, 4, PCIE_CPP2PCIE_BPF_LOAD, addr_hi, addr_lo << 3, sizeof(data));

            addr_lo++;
            addr_hi += addr_lo >> 29;
            NIC_LIB_DBG(libnic_dbg, isl);
            NIC_LIB_DBG(libnic_dbg, me);
            data_out = data[0];
            NIC_LIB_DBG(libnic_dbg, data_out);
            ct_write_csr(isl, me, ME_CSR_USTORE_DATA_LO, data_out);
            data_out = data[1];
            NIC_LIB_DBG(libnic_dbg, data_out);
            ct_write_csr(isl, me, ME_CSR_USTORE_DATA_HI, data_out);
        }

        // normal mode
        data_out = 0;
        ct_write_csr(isl, me, ME_CSR_USTORE_ADDR, data_out);

        sleep(500);

        ctx_enables = ct_read_csr(isl, me, ME_CSR_CTX_ENABLES);
        ct_write_csr(isl, me, ME_CSR_CTX_ENABLES, ctx_enables | 0x5500);

        sleep(500);

        // kick off threads again
        for (ctx = 0; ctx < 8; ctx += 2) {
            ct_signal(isl, me, ctx, PKT_IO_SIG_RESUME);
        }
   }

    return;
}

__intrinsic void
nic_local_bpf_reconfig(__gpr uint32_t *ctx_mode, uint32_t vid, uint32_t vnic)
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;
    __xread uint32_t tmp2[2];
    __emem __addr40 uint8_t *bar_base;

    /* Need to read the update word from the BAR */

    /* Calculate the relevant configuration BAR base address */
    bar_base = NFD_CFG_BAR_ISL(NIC_PCI, vid);

    update_bpf_prog(ctx_mode, bar_base, vnic);

    return;
}

#define EPOCH_NN_IDX 127
__shared __lmem uint32_t epoch = 0;

__intrinsic void
nic_local_epoch() {
    __gpr unsigned int i;
    __gpr unsigned int isl;
    __gpr unsigned int me;
    __gpr unsigned int ctx;
    __gpr unsigned int sig_mask;

    epoch++;

    for (i = 0; i < sizeof(dp_mes_ids) / sizeof(uint32_t); i++) {
        isl = dp_mes_ids[i] >> 4;
        me = dp_mes_ids[i] & 0xf;

        for (ctx = 0; ctx < 8; ctx = ctx + 2) {
            ct_signal(isl, me, ctx, PKT_IO_SIG_EPOCH);
        }

        do {
            sleep(250);
            sig_mask = 0;
            for (ctx = 0; ctx < 8; ctx += 2) {
                ct_write_csr(isl, me, ME_CSR_CTX_PTR, ctx);
                sig_mask |= ct_read_csr(isl, me, ME_CSR_IND_CTX_SGL_EVT);
            }
        }
        while (sig_mask & (1 << PKT_IO_SIG_EPOCH));

        ct_write_nn(isl, me, EPOCH_NN_IDX, epoch);
    }
}

#endif /* _LIBNIC_NIC_INTERNAL_C_ */
/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
