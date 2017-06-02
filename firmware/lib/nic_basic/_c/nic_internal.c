/*
 * Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          lib/nic/_c/nic_internal.c
 * @brief         Internal data structures
 */

#ifndef _LIBNIC_NIC_INTERNAL_C_
#define _LIBNIC_NIC_INTERNAL_C_

//MARY DBG
#ifndef CFG_NIC_LIB_DBG_JOURNAL
#define CFG_NIC_LIB_DBG_JOURNAL 1
#endif

#include <assert.h>
#include <nfp.h>
#include <stdint.h>

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


NFD_CFG_BASE_DECLARE(NIC_PCI);

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

__export __dram uint64_t mary_dbg_update_bpf=0;
__export __dram uint64_t mary_dbg_reflect_bpf=0;

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

#if NFD_MAX_PFS != 0
    #define NVNICS NFD_MAX_PFS
#else
    #define NVNICS 2
#endif
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

//===========
#include "ebpf.h"

M_CREATE_WQ(m_ebpf_wq0);
M_CREATE_WQ(m_ebpf_wq1);

__shared __lmem uint32_t bpf_mes_ids[] = {APP_BPF_MES_LIST};

__intrinsic int
nic_local_cfg_bpf_is_enabled()
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    return !!(nic->control[0] & NFP_NET_CFG_CTRL_BPF);
}

/* XXX Move to some sort of CT reflect library */
static __intrinsic void
ct_reflect_csr(unsigned int dst_me, unsigned int dst_csr,
               volatile __xwrite void *src_xfer)
{
    SIGNAL sig;
    unsigned int addr;

    /* Where address[29:24] specifies the Island Id of remote ME to write to
     * address[16] is the XferCsrRegSel select bit (0:
     * Transfer Registers, 1: CSR Registers), address[13:10] is
     * the master number (= FPC + 4) within the island to write
     * data to, address[9:2] is the first register address (Register
     * depends upon XferCsrRegSel) to write to. */
	/* dst_me format:  dst(isl,me) =  ((((isl + 32) << 4) + (me + 4)) << 8) */
    addr = (1 << 16) | ((dst_me & 0x3F000)<<12 | ((dst_me & 0xF00)<<2 | (dst_csr & 0xFF)<<2));

    __asm {
        alu[--, --, b, 0];
        ct[reflect_write_sig_init, *src_xfer, addr, 0, 1], ctx_swap[sig];
    };
}


static __intrinsic void
bpf_reflect_to_workers(unsigned int csr_no, __xwrite uint32_t *data_out)
{
    __gpr unsigned int i;
    __gpr unsigned int j;
	__gpr uint32_t data_value;

    ctassert(__is_ct_const(csr_no));

	mem_incr32(&mary_dbg_reflect_bpf);
    for(i = 0; i < sizeof(bpf_mes_ids)/sizeof(uint32_t); i++) {
        ct_reflect_csr(bpf_mes_ids[i], csr_no / 4, data_out);
	}
}

static __intrinsic void
update_bpf_prog(__gpr uint32_t *ctx_mode, __emem __addr40 uint8_t *bar_base)
{
    __xread uint32_t host_mem_bpf_cfg[3];
    __xread uint32_t data[2];
    __xwrite uint32_t data_out;
    __gpr unsigned int addr_hi;
    __gpr unsigned int addr_lo;
    __gpr unsigned int i;
    __gpr unsigned int tmp;


/* test dump to mailbox */
    data_out = 0xbeef;
    bpf_reflect_to_workers(0x170, &data_out);	/*Mailbox0*/

#if 0
    /* Disable the contexts */
    data_out = 0;
    bpf_reflect_to_workers(0x18, &data_out);	/*CtxEnables.CtxEnables*/
#endif

#if 0
    for (i = 0; i < 8; i++) {
        /* Select the contexts for indirect access */
        data_out = i;
        bpf_reflect_to_workers(0x20, &data_out);	/* CSRCtxPtr.CtxSelect*/

        /* Set the PC to 0 */
        data_out = 0;
        bpf_reflect_to_workers(0x40, &data_out);	/* IndCtxStatus */

        /* Clear the wake events (0x1 is volunatary swap). */
        data_out = 1;
        bpf_reflect_to_workers(0x50, &data_out);	/* IndCtxWkpEvt */
    }
#endif

    mem_read32(host_mem_bpf_cfg, bar_base + NFP_NET_CFG_BPF_SIZE - 2,
               sizeof host_mem_bpf_cfg);

    /* Note: data from the BAR comes in 4B-swapped; low is high, high is low */
    i = host_mem_bpf_cfg[0] >> 16;
    addr_lo = host_mem_bpf_cfg[1];
    addr_hi = host_mem_bpf_cfg[2];

    pcie_c2p_barcfg_set(0 /*pci_isl0*/, PCIE_CPP2PCIE_BPF_LOAD,
                        addr_hi, addr_lo, 0);

    addr_lo >>= 3;
	NIC_LIB_DBG(libnic_dbg, i);

    /* Set instr pointer to 'start' and enable writing. */
    tmp = 0x80000000 + NFD_BPF_START_OFF;
	data_out = tmp;
    bpf_reflect_to_workers(0x00, &data_out);
	NIC_LIB_DBG(libnic_dbg, tmp);


    while (i--) {
        pcie_read(&data, 4, PCIE_CPP2PCIE_BPF_LOAD,
                  addr_hi, addr_lo << 3, sizeof(data));

        addr_lo++;
        addr_hi += addr_lo >> 29;

        data_out = data[0];
        bpf_reflect_to_workers(0x04, &data_out);	/* Ustore data lower */

        data_out = data[1];
        bpf_reflect_to_workers(0x08, &data_out);	/* Ustore data upper, write to control store, incr ustore addr*/

		NIC_LIB_DBG(libnic_dbg, data[0]);
		NIC_LIB_DBG(libnic_dbg, data[1]);
    }

    data_out = 0;
    bpf_reflect_to_workers(0x00, &data_out);		/* normal mode */

#if 0
    *ctx_mode = 0;
    data_out = 0x80105502;		/* InUseContexts=1,4 contexts, NNreceiveConfig=2 */
    bpf_reflect_to_workers(0x18, &data_out);	/* CtxEnables */
#endif

    return;
}

static __intrinsic void
nic_bpf_kill_threads(__gpr uint32_t *ctx_mode,
                     unsigned int rnum, mem_ring_addr_t raddr)
{
    __xwrite uint32_t work[EBPF_WQ_E_N];
    __xread uint32_t response[EBPF_WQ_E_N];
    __gpr unsigned int wsize = sizeof(work);
    __gpr unsigned int i;

    work[0] = 0;
    /* Hand out the "killer" work items */
    for (i = 0; i < BPF_NUM_MES << (2 + *ctx_mode); i++) {
        work[1] = i;
        mem_workq_add_work(rnum, raddr, work, wsize);
    }
    i--;

    /* 'i' is now max work id */
    do {
        i++;
        work[1] = i;
        mem_workq_add_work(rnum, raddr, work, wsize);

        mem_workq_add_thread(rnum, raddr, response, wsize);
    } while (response[1] != i);
}

__intrinsic void
nic_local_bpf_reconfig(__gpr uint32_t *ctx_mode, uint32_t port)
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;
    __xread uint32_t tmp2[2];
    __emem __addr40 uint8_t *bar_base;

    /* Need to read the update word from the BAR */

    /* Calculate the relevant configuration BAR base address */
    bar_base = NFD_CFG_BAR_ISL(NIC_PCI,port);

#if 0
        nic_bpf_kill_threads(ctx_mode, _link_sym(m_ebpf_wq0_rnum),
                             mem_ring_get_addr((__emem void *)_link_sym(m_ebpf_wq0_mem)));
        nic_bpf_kill_threads(ctx_mode, _link_sym(m_ebpf_wq1_rnum),
                             mem_ring_get_addr((__emem void *)_link_sym(m_ebpf_wq1_mem)));
#endif

		mem_incr32(&mary_dbg_update_bpf);

        update_bpf_prog(ctx_mode, bar_base);

    return;
}


//==========

#endif /* _LIBNIC_NIC_INTERNAL_C_ */
/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
