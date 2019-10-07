/*
 * Copyright 2014-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_control_lib.c
 * @brief         Functions used during vNIC reconfig.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef APP_CONTROL_LIB_C
#define APP_CONTROL_LIB_C

#include <assert.h>
#include <nfp.h>
#include <nfp_chipres.h>

#include <platform.h>

#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp/macstats.h>
#include <nfp/remote_me.h>
#include <nfp/tmq.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_mac.h>
#include <nfp6000/nfp_me.h>
#include <nfp6000/nfp_nbi_tm.h>

#include <std/synch.h>
#include <std/reg_utils.h>
#include <vnic/shared/nfd_cfg.h>
#include <vnic/svc/msix.h>
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>
#include <vnic/shared/nfd_vf_cfg_iface.h>

#include <shared/nfp_net_ctrl.h>

#include <link_state/link_ctrl.h>
#include <link_state/link_state.h>
#include <nic_basic/nic_basic.h>

#include <npfw/catamaran_app_utils.h>

#include <vnic/nfd_common.h>

#include "app_config_tables.h"
#include "ebpf.h"
#include "config.h"
#include "app_mac_vlan_config_cmsg.h"
#include "maps/cmsg_map_types.h"
#include "nic_tables.h"
#include "trng.h"


#define TMQ_DRAIN_RETRIES      15
/* Translate port speed to link rate encoding */
__intrinsic static unsigned int
port_speed_to_link_rate(unsigned int port_speed)
{
    unsigned int link_rate;

    switch (port_speed) {
    case 1:
        link_rate = NFP_NET_CFG_STS_LINK_RATE_1G;
        break;
    case 10:
        link_rate = NFP_NET_CFG_STS_LINK_RATE_10G;
        break;
    case 25:
        link_rate = NFP_NET_CFG_STS_LINK_RATE_25G;
        break;
    case 40:
        link_rate = NFP_NET_CFG_STS_LINK_RATE_40G;
        break;
    case 50:
        link_rate = NFP_NET_CFG_STS_LINK_RATE_50G;
        break;
    case 100:
        link_rate = NFP_NET_CFG_STS_LINK_RATE_100G;
        break;
    default:
        link_rate = NFP_NET_CFG_STS_LINK_RATE_UNSUPPORTED;
        break;
    }

    return link_rate;
}

static void
disable_port_tx_datapath(unsigned int nbi, unsigned int start_q,
                         unsigned int end_q)
{
    unsigned int q_num;

    /* Disable the NBI TM queues to prevent any packets from being enqueued. */
    for (q_num = start_q; q_num <= end_q; ++q_num) {
        nbi_tm_disable_queue(nbi, q_num);
    }
}


static void
enable_port_tx_datapath(unsigned int nbi, unsigned int start_q,
                        unsigned int end_q)
{
    unsigned int q_num;

    /* Re-enable the NBI TM queues. */
    for (q_num = start_q; q_num <= end_q; ++q_num) {
        nbi_tm_enable_queue(nbi, q_num);
    }
}


__inline void
process_pf_reconfig_wait_link_up(uint32_t port)
{
    __gpr int i;
    /* Verify link up and RX enabled, give up after 2 seconds */
    for (i = 0; i < 10; ++i) {
        int rx_enabled = mac_eth_check_rx_enable(NS_PLATFORM_MAC(port),
                NS_PLATFORM_MAC_CORE(port),
                NS_PLATFORM_MAC_CORE_SERDES_LO(port));
        int link_up    = mac_eth_port_link_state(NS_PLATFORM_MAC(port),
                NS_PLATFORM_MAC_SERDES_LO(port),
                (NS_PLATFORM_PORT_SPEED(port) > 1) ? 0 : 1);

        /* Wait a minimal settling time after querying MAC */
        sleep(200 * NS_PLATFORM_TCLK * 1000); // 200ms

        if (rx_enabled && link_up)
            break;
    }
}

__inline void
process_pf_reconfig_tmq_drain(uint32_t port)
{
    __xread struct nfp_nbi_tm_queue_status tmq_status;
    int i, queue, occupied = 1;

    for (i = 0; occupied && i < TMQ_DRAIN_RETRIES; ++i) {
        occupied = 0;
        for (queue = NS_PLATFORM_NBI_TM_QID_LO(port);
                queue <= NS_PLATFORM_NBI_TM_QID_HI(port);
                queue++) {
            tmq_status_read(&tmq_status, NS_PLATFORM_MAC(port), queue, 1);
            if (tmq_status.queuelevel) {
                occupied = 1;
                break;
            }
        }
        sleep(NS_PLATFORM_TCLK * 1000); // 1ms
    }
}
static void
mac_port_enable_rx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);
    unsigned int mac_core      = NS_PLATFORM_MAC_CORE(port);
    unsigned int mac_core_port = NS_PLATFORM_MAC_CORE_SERDES_LO(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_enable_rx(mac_nbi_isl, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


static int
mac_port_disable_rx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);
    unsigned int mac_core      = NS_PLATFORM_MAC_CORE(port);
    unsigned int mac_core_port = NS_PLATFORM_MAC_CORE_SERDES_LO(port);
    unsigned int num_lanes     = NS_PLATFORM_MAC_NUM_SERDES(port);
    int result;

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    result = mac_eth_disable_rx(mac_nbi_isl, mac_core, mac_core_port, num_lanes);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);

    return result;
}


static void
mac_port_enable_tx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    enable_port_tx_datapath(mac_nbi_isl, NS_PLATFORM_NBI_TM_QID_LO(port),
                            NS_PLATFORM_NBI_TM_QID_HI(port));

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


static void
mac_port_disable_tx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    disable_port_tx_datapath(mac_nbi_isl, NS_PLATFORM_NBI_TM_QID_LO(port),
                             NS_PLATFORM_NBI_TM_QID_HI(port));

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


static void
mac_port_enable_tx_flush(unsigned int mac, unsigned int mac_core,
                         unsigned int mac_core_port)
{
    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_enable_tx_flush(mac, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


static void
mac_port_disable_tx_flush(unsigned int mac, unsigned int mac_core,
                          unsigned int mac_core_port)
{
    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_disable_tx_flush(mac, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}
/*
 * Update flags to enable notification of link state change on port to
 * vf vf_vid.
 *
 * Also update the current link state for vf_vid and schedule an interrupt
 */
static void
update_vf_lsc_list(unsigned int port, uint32_t vf_vid, uint32_t control, unsigned int mode)
{
    unsigned int i;
    unsigned int sts_en;
    unsigned int sts_dis;
    __xread uint32_t ctrl_xr;
    __xwrite uint32_t sts_xw;
    uint32_t pf_vid = NFD_PF2VID(port);
    unsigned int idx = LS_IDX(vf_vid);
    unsigned int orig_link_state = LS_READ(ls_current, vf_vid);
    unsigned int pf_link_state = LS_READ(ls_current, pf_vid);
    __mem char *cfg_bar = NFD_CFG_BAR_ISL(NIC_PCI, vf_vid);

    if (control & NFP_NET_CFG_CTRL_ENABLE)
        LS_SET(vs_current, vf_vid);
    else
        LS_CLEAR(vs_current, vf_vid);

    /* Enable notification on selected vf from port */
    if (mode == NFD_VF_CFG_CTRL_LINK_STATE_AUTO)
        LS_SET(vf_lsc_list[port], vf_vid);
    else
        LS_CLEAR(vf_lsc_list[port], vf_vid);

    /* Disable notification to selected vf from other ports */
    for (i = 0; i < NS_PLATFORM_NUM_PORTS; i++) {
        if (i != port)
            LS_CLEAR(vf_lsc_list[i], vf_vid);
    }

    /* Update the link status for the VF. Report the link speed for the VF as
     * that of the PF. */
    if (mode == NFD_VF_CFG_CTRL_LINK_STATE_ENABLE || pf_link_state) {
        LS_SET(ls_current, vf_vid);
        sts_xw = (port_speed_to_link_rate(NS_PLATFORM_PORT_SPEED(port)) <<
              NFP_NET_CFG_STS_LINK_RATE_SHIFT) | 1;
    } else {
        /* Clear the link status to reflect the PF link is down. */
        LS_CLEAR(ls_current, vf_vid);
        sts_xw = (NFP_NET_CFG_STS_LINK_RATE_UNKNOWN <<
                    NFP_NET_CFG_STS_LINK_RATE_SHIFT);
    }

    mem_write32(&sts_xw, cfg_bar + NFP_NET_CFG_STS, sizeof(sts_xw));
    /* Make sure the config BAR is updated before we send
       the notification interrupt */
    mem_read32(&ctrl_xr, cfg_bar + NFP_NET_CFG_CTRL, sizeof(ctrl_xr));

    /* Schedule notification interrupt to be sent from the
       link state change context */
    if (ctrl_xr & NFP_NET_CFG_CTRL_ENABLE) {
        LS_SET(pending, vf_vid);
    }
}

static void
handle_sriov_update()
{
    __xread struct sriov_mb sriov_mb_data;
    __xread struct sriov_cfg sriov_cfg_data;
    __xwrite uint64_t new_mac_addr_wr;
    __xwrite int err_code = 0;
    __emem __addr40 uint8_t *vf_mb_base = nfd_vf_cfg_base(NIC_PCI, 0, NFD_VF_CFG_SEL_MB);
    __emem __addr40 uint8_t *vf_cfg_base;

    mem_read32(&sriov_mb_data, vf_mb_base, sizeof(struct sriov_mb));

    if (sriov_mb_data.update_flags & NFD_VF_CFG_MB_CAP_MAC) {
        vf_cfg_base = nfd_vf_cfg_base(NIC_PCI, sriov_mb_data.vf, NFD_VF_CFG_SEL_VF);
        mem_read32(&sriov_cfg_data, vf_cfg_base, sizeof(struct sriov_cfg));

        reg_cp(&new_mac_addr_wr, &sriov_cfg_data, sizeof(new_mac_addr_wr));
        mem_write8(&new_mac_addr_wr, nfd_cfg_bar_base(NIC_PCI, sriov_mb_data.vf) +
                   NFP_NET_CFG_MACADDR, NFD_VF_CFG_MAC_SZ);
    }

    mem_write8_le(&err_code,
        (__mem void*) (vf_mb_base + NFD_VF_CFG_MB_RET_ofs), 2);
}

static int
process_ctrl_reconfig(uint32_t control, uint32_t vid,
                        struct nfd_cfg_msg *cfg_msg)
{
    __xwrite unsigned int link_state;
    action_list_t acts;

    if (control & ~(NFD_CFG_CTRL_CAP)) {
        cfg_msg->error = 1;
        return 1;
    }

    cfg_act_build_ctrl(&acts, NIC_PCI, vid);
    cfg_act_write_host(NIC_PCI, vid, &acts);

    /* Set link state */
    if (!cfg_msg->error &&
        (control & NFP_NET_CFG_CTRL_ENABLE)) {
        link_state = NFP_NET_CFG_STS_LINK;
    } else {
        link_state = 0;
    }
    mem_write32(&link_state,
                    (NFD_CFG_BAR_ISL(PCIE_ISL, cfg_msg->vid) +
                    NFP_NET_CFG_STS), sizeof link_state);
    return 0;
}


static int
process_pf_reconfig(uint32_t control, uint32_t update, uint32_t vid,
                    uint32_t vnic, struct nfd_cfg_msg *cfg_msg)
{
    uint32_t port = vnic;
    uint32_t veb_up;
    __gpr uint32_t ctx_mode = 1;
    __gpr int i;

    if (control & ~(NFD_CFG_PF_CAP)) {
        cfg_msg->error = 1;
        return 1;
    }

    if (update & ~(NFD_CFG_PF_LEGAL_UPD)) {
        cfg_msg->error = 1;
        return 1;
    }

    if (update & NFP_NET_CFG_UPDATE_BPF) {
        nic_local_bpf_reconfig(&ctx_mode, vid, vnic);
    }

    if (update & NFP_NET_CFG_UPDATE_VF) {
        handle_sriov_update();
    }

    if (control & NFP_NET_CFG_CTRL_ENABLE) {
        veb_up = 0;
        for (i = 0; i < NFD_MAX_VFS; i++) {
            if (nic_control_word[NFD_VF2VID(i)] & NFP_NET_CFG_CTRL_ENABLE) {
                if (cfg_act_vf_up(NIC_PCI, NFD_VF2VID(i),
                            control,
                            nic_control_word[NFD_VF2VID(i)],
                            0)) {
                    cfg_msg->error = 1;
                    return 1;
                }
                veb_up = 1;
            }
        }

        if (cfg_act_pf_up(NIC_PCI, vid, veb_up, control, update)) {
            cfg_msg->error = 1;
            return 1;
        }
    }

    /* Set RX appropriately if NFP_NET_CFG_CTRL_ENABLE changed */
    if ((nic_control_word[vid] ^ control) & NFP_NET_CFG_CTRL_ENABLE) {
        if (control & NFP_NET_CFG_CTRL_ENABLE) {
            /* Permit lsc_check() to bring up RX/TX */
            nic_control_word[cfg_msg->vid] = control;

            /* Swap and give link state thread opportunity to enable RX/TX */
            sleep(50 * NS_PLATFORM_TCLK * 1000); // 50ms

            /* Wait for the MAC to indicate link up. Give up after 2 seconds */
            process_pf_reconfig_wait_link_up(port);
        } else {
            __xread struct nfp_nbi_tm_queue_status tmq_status;
            int i, queue, occupied = 1;

            /* Prevent lsc_check() from overriding RX disable */
            nic_control_word[cfg_msg->vid] = control;

            /* stop receiving packets */
            if (! mac_port_disable_rx(port)) {
                cfg_msg->error = 1;
                return 1;
            }

            /* allow workers to drain RX queue */
            sleep(10 * NS_PLATFORM_TCLK * 1000); // 10ms

            /* stop processing packets: drop action */
            cfg_act_pf_down(NIC_PCI, vid);
            for (i = 0; i < NFD_MAX_VFS; ++i) {
                if (cfg_act_vf_down(NIC_PCI, NFD_VF2VID(i))) {
                    cfg_msg->error = 1;
                    return 1;
                }
            }

            /* wait for TM queues to drain */
            process_pf_reconfig_tmq_drain(port);
        }
    }
    return 0;
}

static int
process_vf_reconfig(uint32_t control, uint32_t update, uint32_t vid,
                    struct nfd_cfg_msg *cfg_msg)
{
    __emem __addr40 uint8_t *vf_cfg_base = NFD_VF_CFG_BASE_LINK(NIC_PCI);
    __xread struct sriov_cfg sriov_cfg_data;
    unsigned int ls_mode;
    uint64_t mac_addr;

    if (control & ~(NFD_CFG_VF_CAP)) {
        cfg_msg->error = 1;
        return 1;
    }

    if (update & ~(NFD_CFG_VF_LEGAL_UPD)) {
        cfg_msg->error = 1;
        return 1;
    }


    mem_read32(&sriov_cfg_data, NFD_VF_CFG_ADDR(vf_cfg_base, NFD_VID2VF(vid)),
               sizeof(struct sriov_cfg));

    /* Set the link state handling control */
    if (control & NFP_NET_CFG_CTRL_ENABLE) {
        /* Retrieve the link state mode for the VF. */
        ls_mode = sriov_cfg_data.ctrl_link_state;

        if (!(nic_control_word[NFD_PF2VID(0)] & NFP_NET_CFG_CTRL_ENABLE)) {
            cfg_msg->error = 1;
            return 1;
        }

        if (cfg_act_vf_up(NIC_PCI, vid,
                    nic_control_word[NFD_PF2VID(0)],
                    control, update)) {
            cfg_msg->error = 1;
            return 1;
        }

        // rebuild PF action list because veb_up state may have changed
        if (cfg_act_pf_up(NIC_PCI, NFD_PF2VID(0), 1,
                    nic_control_word[NFD_PF2VID(0)], 0)) {
            cfg_msg->error = 1;
            return 1;
        }
    } else {
        /* process VFs trying to change its MAC address while the
         * interface is down. Reject non-trusted VFs trying to change
         * the MAC address after the PF set it up
         */
        if (update & NFP_NET_CFG_UPDATE_MACADDR) {
            mac_addr = MAC64_FROM_SRIOV_CFG(sriov_cfg_data);
            if (mac_addr && (!sriov_cfg_data.ctrl_trusted)) {
                cfg_msg->error = 1;
                return 1;
            }
        }

        /* Disable the link when interface is disabled. */
        ls_mode = NFD_VF_CFG_CTRL_LINK_STATE_DISABLE;

        if (cfg_act_vf_down(NIC_PCI, vid)) {
            cfg_msg->error = 1;
            return 1;
        }
    }

    update_vf_lsc_list(0, vid, control, ls_mode);
    return 0;
}
#endif
