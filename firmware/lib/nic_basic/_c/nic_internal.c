/*
 * Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
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
 * @file          lib/nic/_c/nic_internal.c
 * @brief         Internal data structures
 */

#ifndef _LIBNIC_NIC_INTERNAL_C_
#define _LIBNIC_NIC_INTERNAL_C_

#include <assert.h>
#include <nfp.h>
#include <stdint.h>

#include <nfp/me.h>
#include <nfp/mem_atomic.h>
#include <nfp/mem_bulk.h>
#include <std/event.h>
#include <std/reg_utils.h>
#include <std/synch.h>

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
 * @nic_cnt_rx_switch_multi Packets on RX with multiple destination VPorts
 *
 * @nic_cnt_tx_drop_down    Packets dropped due to device disabled
 * @nic_cnt_tx_drop_mtu     Packets dropped due to MTU size check
 * @nic_cnt_rx_switch_int   Packets on TX requested to be send to host
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
__export __dram uint64_t nic_cnt_rx_switch_multi;

__export __dram uint64_t nic_cnt_tx_drop_down;
__export __dram uint64_t nic_cnt_tx_drop_mtu;
__export __dram uint64_t nic_cnt_tx_switch_int;
#else
#define NIC_LIB_CNTR(_me)
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
    uint32_t control;           /* 0x000: Cache of NFP_NET_CFG_CTRL */
    uint32_t control_vf[NFD_MAX_VFS]; /*  NFP_NET_CFG_CTRL of VFs*/

    uint64_t tx_ring_en;        /* 0x004: Cache of NFP_NET_CFG_TXRS_ENABLE */
    uint64_t rx_ring_en;        /* 0x00c: Cache of NFP_NET_CFG_RXRS_ENABLE */
    uint64_t tx_ring_en_vf[NFD_MAX_VFS]; /*Cache of NFP_NET_CFG_TXRS_ENABLE of VFs*/
    uint64_t rx_ring_en_vf[NFD_MAX_VFS]; /*Cache of NFP_NET_CFG_RXRS_ENABLE of VFs*/

    uint32_t mtu;               /* 0x014: Configured MTU */
    uint32_t mac[2];            /* 0x018: Cache of NFP_NET_CFG_MACADDR */
    uint32_t mtu_vf[NFD_MAX_VFS];    /*Configured MTU of VFs*/
    uint32_t mac_vf[NFD_MAX_VFS][2]; /*Cache of NFP_NET_CFG_MACADDR of VFs*/

    /*TODO: per VF value in the following should be added later when needed*/
    uint32_t rss_ctrl;          /* 0x020: Cache of RSS control */
    uint8_t  rss_key[NFP_NET_CFG_RSS_KEY_SZ];  /* 0x024: Cache of RSS key */
    uint8_t  rss_tbl[NFP_NET_CFG_RSS_ITBL_SZ]; /* 0x04c: Cache of RSS ITBL */

    /* Switch local state */
    uint32_t sw_default_rx_vp;  /* 0x0cc: Default VPort */

    uint64_t sw_vp_spoof_en;       /* 0x0d0: Mask for VPs w/ spoofing enabled */
    uint64_t sw_vp_bc_en;          /* 0x0d8: Mask for VPs w/ BC allowed */
    uint64_t sw_vp_mc_promisc_en;  /* 0x0e0: Mask for VPs w/ MC allowed */
    uint64_t sw_vp_vlan_promisc_en;/* 0x0e8: Mask for VPs w/ VLAN promisc set */
    uint64_t sw_vp_promisc_en;     /* 0x0f0: Mask for VPs w/ promisc enabled */
    uint64_t sw_vp_rss_en;         /* 0x0f8: Mask per VPs w/ RSS is enabled */
    uint64_t sw_vp_has_defaultq;   /* 0x100: Does vport have a default Q? */
    uint8_t  sw_txq_to_vport[NFP_NET_TXR_MAX]; /* 0x108: Map of TX Qs to VPs */
    uint8_t  sw_default_rxq[NIC_SWITCH_VPORTS_MAX];
                                               /* 0x148: Default RX Q per VP */
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

/* Prototypes */
__intrinsic void nic_switch_reconfig();

/*
 * Reconfiguration mechanism:
 *
 * One context in the app master ME is the master for the
 * reconfiguration.  It initializes a synchronization counter
 * @nic_cfg_synch to the number of application MEs and signals the
 * application MEs whenever a configuration change happened. The app master
 * also communicates the pci island number and vnic number of the changes
 * config BAR.
 *
 */

/*
 * Initialise the rings and eventfilters/autopushes.
 */
__intrinsic void
nic_local_init(int sig_num, int reg_num)
{
    __assign_relative_register((void *)&cfg_bar_change_sig, sig_num);
    __assign_relative_register((void *)&cfg_bar_change_info, reg_num);
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
    uint32_t vnic_id;
    int i;
    __emem __addr40 uint8_t *bar_base;

    /* Code assumes certain arrangement and sizes */
    ctassert(NFP_NET_CFG_RXRS_ENABLE == NFP_NET_CFG_TXRS_ENABLE + 8);
    ctassert(NFP_NET_CFG_RSS_KEY_SZ == 40);
    ctassert(NFP_NET_CFG_RSS_ITBL_SZ == 128);

    *enable_changed = 0;

    /* Need to read the update word from the BAR */

    /* Calculate the relevant configuration BAR base address */
    switch (cfg_bar_change_info.pci) {
    case 0:
        vnic_id = cfg_bar_change_info.vnic;
        bar_base = NFD_CFG_BAR_ISL(0, cfg_bar_change_info.vnic);
        break;
    default:
        halt();
    }

    /* Read the ctrl(0) + update(1) words */
    mem_read64(&tmp2, (__mem void*)(bar_base + NFP_NET_CFG_CTRL), sizeof(tmp2));
    newctrl = tmp2[0];
    update = tmp2[1];

     /* Handle general updates */
    if (update & NFP_NET_CFG_UPDATE_GEN) {
        /* Check if link global enable changed */
        if ((nic->control ^ newctrl) & NFP_NET_CFG_CTRL_ENABLE) {
            *enable_changed = 1;
        }
        if ((vnic_id < NFD_MAX_VFS) & 
            (nic->control_vf[vnic_id] ^ newctrl) & 
            NFP_NET_CFG_CTRL_ENABLE) {
            *enable_changed = 1;
        } 

        if (!(newctrl & NFP_NET_CFG_CTRL_ENABLE)) {
            /* NIC got disabled, zero control and we are done */
            nic->control = 0;
            nic->rss_ctrl = 0;
            goto reconfig_done;
        }

        /* MTU */
        mem_read32(&mtu, (__mem void*)(bar_base + NFP_NET_CFG_MTU),
                   sizeof(mtu));
        nic->mtu = mtu;
        if (vnic_id < NFD_MAX_VFS) {
            nic->mtu_vf[vnic_id] = mtu;
        } 

        /* MAC Address */
        mem_read64(nic_mac, (__mem void*)(bar_base + NFP_NET_CFG_MACADDR),
                   sizeof(nic_mac));
        nic->mac[0] = nic_mac[0];
        nic->mac[1] = nic_mac[1];
        if (vnic_id < NFD_MAX_VFS) {
            nic->mac_vf[vnic_id][0] = nic_mac[0];
            nic->mac_vf[vnic_id][1] = nic_mac[1];
        } 

        /* Stash away new control to activate */
        nic->control = newctrl;
        if (vnic_id < NFD_MAX_VFS) {
            nic->control_vf[vnic_id] = mtu;
        } 
    }

    /* Handle Ring reconfiguration.
     * (This assume we advertise NFP_NET_CFG_CTRL_RINGCFG) */
    if (update & NFP_NET_CFG_UPDATE_RING) {

        /* Read TX/RX ring status */
        mem_read64(&ring_en,
                   (__mem void*)(bar_base + NFP_NET_CFG_TXRS_ENABLE),
                   sizeof(ring_en));
        nic->tx_ring_en = swapw64(ring_en[0]);
        nic->rx_ring_en = swapw64(ring_en[1]);
        if (vnic_id < NFD_MAX_VFS) {
            nic->tx_ring_en_vf[vnic_id] = swapw64(ring_en[0]);
            nic->rx_ring_en_vf[vnic_id] = swapw64(ring_en[1]);
        } 
    }

    /* Handle RSS re-config */
    if (update & NFP_NET_CFG_UPDATE_RSS &&
        nic->control & NFP_NET_CFG_CTRL_RSS) {

        mem_read64(rss_ctrl, bar_base + NFP_NET_CFG_RSS_CTRL,
                   sizeof(rss_ctrl));

        /* Read RSS key and table. Table requires two reads*/
        mem_read64(rss_key, bar_base + NFP_NET_CFG_RSS_KEY,
                   sizeof(rss_key));
        reg_cp((void*)nic->rss_key, rss_key, sizeof(rss_key));

        mem_read64_swap(rss_tbl, bar_base + NFP_NET_CFG_RSS_ITBL,
                        sizeof(rss_tbl));
        reg_cp((void*)nic->rss_tbl, rss_tbl, sizeof(rss_tbl));

        mem_read64_swap(rss_tbl,
                        bar_base + NFP_NET_CFG_RSS_ITBL + sizeof(rss_tbl),
                        sizeof(rss_tbl));
        reg_cp((void*)(nic->rss_tbl + sizeof(rss_tbl)), rss_tbl,
               sizeof(rss_tbl));

        /* Write control word to activate */
        nic->rss_ctrl = rss_ctrl[0];
    }

    /* Switch reconfiguration */
    if (update & NFP_NET_CFG_UPDATE_L2SWITCH &&
        nic->control & NFP_NET_CFG_CTRL_L2SWITCH) {
        nic_switch_reconfig();
    }

    /* VXLAN reconfig */
    if (update & NFP_NET_CFG_UPDATE_VXLAN &&
        nic->control & NFP_NET_CFG_CTRL_VXLAN) {

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


#endif /* _LIBNIC_NIC_INTERNAL_C_ */
/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
