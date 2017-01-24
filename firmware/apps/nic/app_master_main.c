/*
 * Copyright 2014-2016 Netronome, Inc.
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
 * @file          app_master_main.c
 * @brief         ME serving as the NFD NIC application master.
 *
 * This implementation only handles one PCIe island.
 */

#include <assert.h>
#include <nfp.h>
#include <nfp_chipres.h>

#include <nic/nic.h>
#include <platform.h>

#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp/macstats.h>
#include <nfp/remote_me.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_mac.h>
#include <nfp6000/nfp_me.h>

#include <std/synch.h>
#include <std/reg_utils.h>

#include "nfd_user_cfg.h"
#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>

#include <shared/nfp_net_ctrl.h>

#include <link_state/link_ctrl.h>
#include <link_state/link_state.h>

#include <npfw/catamaran_app_utils.h>

/*
 * The application master runs on a single ME and performs a number of
 * functions:
 *
 * - Handle configuration changes.  The PCIe MEs (NFD) notify a single
 *   ME (this ME) of any changes to the configuration BAR.  It is then
 *   up to this ME to disseminate these configuration changes to any
 *   application MEs which need to be informed.  On context in this
 *   handles this.
 *
 * - Periodically read and update the stats maintained by the NFP
 *   MACs. The MAC stats can wrap and need to be read periodically.
 *   Furthermore, some of the MAC stats need to be made available in
 *   the Control BAR of the NIC.  One context in the ME handles this.
 *
 * - Maintain per queue counters.  The PCIe MEs (NFD) maintain
 *   counters in some local (fast) memory.  One context in this ME is
 *   periodically updating the corresponding fields in the control
 *   BAR.
 *
 * - Link state change monitoring.  One context in this ME is
 *   monitoring the Link state of the Ethernet port and updates the
 *   Link status bit in the control BAR as well as generating a
 *   interrupt on changes (if configured).
 */


/*
 * General declarations
 */
#ifndef NFD_PCIE0_EMEM
#error "NFD_PCIE0_EMEM must be defined"
#endif

/* APP Master CTXs assignments */
#define APP_MASTER_CTX_CONFIG_CHANGES   0
#define APP_MASTER_CTX_MAC_STATS        1
#define APP_MASTER_CTX_PERQ_STATS       2
#define APP_MASTER_CTX_LINK_STATE       3
#define APP_MASTER_CTX_FREE0            4
#define APP_MASTER_CTX_FREE1            5
#define APP_MASTER_CTX_FREE2            6
#define APP_MASTER_CTX_FREE3            7

/* Address of the PF Control BAR */


/* Current value of NFP_NET_CFG_CTRL (shared between all contexts) */
__shared __lmem volatile uint32_t nic_control_word[NS_PLATFORM_NUM_PORTS];

/*
 * Global declarations for configuration change management
 */

/* The list of all application MEs IDs */
#ifndef APP_MES_LIST
    #error "The list of application MEs IDd must be defined"
#else
    __shared __lmem uint32_t app_mes_ids[] = {APP_MES_LIST};
#endif

__visible SIGNAL nfd_cfg_sig_app_master0;
NFD_CFG_BASE_DECLARE(0);
NFD_FLR_DECLARE;

/* A global synchronization counter to check if all APP MEs has reconfigured */
__export __dram struct synch_cnt nic_cfg_synch;


/*
 * Global declarations for per Q stats updates
 */

/* Sleep cycles between Per-Q counters push */
#define PERQ_STATS_SLEEP            2000

/*
 * Global declarations for Link state change management
 */

/* TODO : REPLACE WITH HEADER FILE DIRECTIVE WHEN AVAILABLE */
__intrinsic extern int msix_pf_send(unsigned int pcie_nr,
                                    unsigned int bar_nr,
                                    unsigned int entry_nr,
                                    unsigned int mask_en);

__intrinsic extern int msix_vf_send(unsigned int pcie_nr,
                                    unsigned int bar_nr, unsigned int vf_nr,
                                    unsigned int entry_nr, unsigned int mask_en);


/* Amount of time between each link status check */
#define LSC_POLL_PERIOD            10000

/* Mutex for accessing MAC registers. */
__shared __gpr volatile int mac_reg_lock = 0;

/* Macros for local mutexes. */
#define LOCAL_MUTEX_LOCK(_mutex) \
    do {                         \
        while (_mutex)           \
            ctx_swap();          \
        _mutex = 1;              \
    } while (0)
#define LOCAL_MUTEX_UNLOCK(_mutex) \
    do {                           \
        _mutex = 0;                \
    } while (0)


/* Carbon flow-control settings. */
#define CARBON_FLOWCTL_ISL               1
#define CARBON_FLOWCTL_ME                3
#define CARBON_FLOWCTL_MBOX0_CFG         0x25
#define CARBON_FLOWCTL_MBOX1_CFG_DISABLE (~0)
#define CARBON_FLOWCTL_MBOX1_CFG_ENABLE  0x20


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

/*
 * Config change management.
 *
 * - Periodically check for configuration changes. If changed:
 * - Set up the mechanism to notify (a shared bit mask)
 * - Ping all application MEs (using @ct_reflect_data())
 * - Wait for them to acknowledge the change
 * - Acknowledge config change to PCIe MEs.
 */

/* XXX Move to some sort of CT reflect library */
/*
 * Note: The transfer register number is an absolute number, that is, not
 *       relative to the ME context number.  In general, the formula to
 *       calculate an absolute transfer register number is as follows:
 *
 *           dst_xfer = (dst_ctx * 32) + "relative transfer register number"
 *
 * TODO - Need to work on solution to make xfer register context-relative,
 *        rather than absolute.
 */
__intrinsic static void
ct_reflect_data(unsigned int dst_me, unsigned int dst_ctx,
                unsigned int dst_xfer, unsigned int sig_no,
                volatile __xwrite void *src_xfer, size_t size)
{
    unsigned int addr;
    unsigned int count = (size >> 2);
    struct nfp_mecsr_cmd_indirect_ref_0 indirect;
    struct nfp_mecsr_prev_alu prev_alu;

    ctassert(__is_ct_const(size));

    /* Where address[29:24] specifies the Island Id of remote ME
     * to write to, address[16] is the XferCsrRegSel select bit (0:
     * Transfer Registers, 1: CSR Registers), address[13:10] is
     * the master number (= FPC + 4) within the island to write
     * data to, address[9:2] is the first register address (Register
     * depends upon XferCsrRegSel) to write to. */
    addr = ((dst_me & 0x3F0)<<20 | ((dst_me & 0xF)<<10 | (dst_xfer & 0xFF)<<2));

    indirect.__raw = 0;
    indirect.signal_ctx = dst_ctx;
    indirect.signal_num = sig_no;
    local_csr_write(local_csr_cmd_indirect_ref_0, indirect.__raw);

    prev_alu.__raw = 0;
    prev_alu.ov_sig_ctx = 1;
    prev_alu.ov_sig_num = 1;

    /* Reflect the value and signal the remote ME */
    __asm {
        alu[--, --, b, prev_alu.__raw];
        ct[reflect_write_sig_remote, *src_xfer, addr, 0, \
           __ct_const_val(count)], indirect_ref;
    };
}


#if NS_PLATFORM_TYPE == NS_PLATFORM_CARBON

__inline static void
carbon_flow_control_disable()
{
    unsigned int port;

    /* Check to see if all ports are disabled. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        /* Do not disable flow-control if any port is enabled. */
        if (nic_control_word[port] & NFP_NET_CFG_CTRL_ENABLE)
            return;
    }

    /* Disable the flow-control ME. */
    remote_csr_write(CARBON_FLOWCTL_ISL, CARBON_FLOWCTL_ME,
                     local_csr_mailbox_1, CARBON_FLOWCTL_MBOX1_CFG_DISABLE);
}


__inline static void
carbon_flow_control_enable()
{
    /* Enable the flow-control ME. */
    remote_csr_write(CARBON_FLOWCTL_ISL, CARBON_FLOWCTL_ME,
                     local_csr_mailbox_1, CARBON_FLOWCTL_MBOX1_CFG_ENABLE);
    remote_csr_write(CARBON_FLOWCTL_ISL, CARBON_FLOWCTL_ME,
                     local_csr_mailbox_0, CARBON_FLOWCTL_MBOX0_CFG);
}

#endif /* NS_PLATFORM_TYPE == NS_PLATFORM_CARBON */


__inline static void
disable_port_tx_datapath(unsigned int nbi, unsigned int start_q,
                         unsigned int end_q)
{
    unsigned int q_num;

    /* Disable the NBI TM queues to prevent any packets from being enqueued. */
    for (q_num = start_q; q_num <= end_q; ++q_num) {
        nbi_tm_disable_queue(nbi, q_num);
    }
}


__inline static void
enable_port_tx_datapath(unsigned int nbi, unsigned int start_q,
                        unsigned int end_q)
{
    unsigned int q_num;

    /* Re-enable the NBI TM queues. */
    for (q_num = start_q; q_num <= end_q; ++q_num) {
        nbi_tm_enable_queue(nbi, q_num);
    }
}


__inline static void
mac_port_disable_rx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);
    unsigned int mac_core      = NS_PLATFORM_MAC_CORE(port);
    unsigned int mac_core_port = NS_PLATFORM_MAC_CORE_SERDES_LO(port);
    unsigned int num_lanes     = NS_PLATFORM_MAC_NUM_SERDES(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_disable_rx(mac_nbi_isl, mac_core, mac_core_port, num_lanes);

    /* Disable the port TX. */
    disable_port_tx_datapath(mac_nbi_isl, NS_PLATFORM_NBI_TM_QID_LO(port),
                             NS_PLATFORM_NBI_TM_QID_HI(port));

    /* Flush TX datapath to prevent stranding any packets. */
    mac_eth_enable_tx_flush(mac_nbi_isl, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


__inline static void
mac_port_disable_tx_flush(unsigned int mac, unsigned int mac_core,
                          unsigned int mac_core_port)
{
    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_disable_tx_flush(mac, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


__inline static void
mac_port_enable_rx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);
    unsigned int mac_core      = NS_PLATFORM_MAC_CORE(port);
    unsigned int mac_core_port = NS_PLATFORM_MAC_CORE_SERDES_LO(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    /* Re-enable TX datapath before enabling RX datapath. */
    mac_eth_disable_tx_flush(mac_nbi_isl, mac_core, mac_core_port);

    /* Enable the port TX. */
    enable_port_tx_datapath(mac_nbi_isl, NS_PLATFORM_NBI_TM_QID_LO(port),
                            NS_PLATFORM_NBI_TM_QID_HI(port));

    mac_eth_enable_rx(mac_nbi_isl, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


__inline static void
mac_port_enable_tx_flush(unsigned int mac, unsigned int mac_core,
                         unsigned int mac_core_port)
{
    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_enable_tx_flush(mac, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


static void
cfg_changes_loop(void)
{
    struct nfd_cfg_msg cfg_msg;
    __xread unsigned int cfg_bar_data[2];
    volatile __xwrite uint32_t cfg_pci_vnic;
    __gpr int i;
    uint32_t port;

    /* Initialisation */
    nfd_cfg_init_cfg_msg(&nfd_cfg_sig_app_master0, &cfg_msg);

    for (;;) {
        nfd_cfg_master_chk_cfg_msg(&cfg_msg, &nfd_cfg_sig_app_master0, 0);

        if (cfg_msg.msg_valid) {

            port = cfg_msg.vnic;
            /* read in the first 64bit of the Control BAR */
            mem_read64(cfg_bar_data, NFD_CFG_BAR_ISL(NIC_PCI, port),
                       sizeof cfg_bar_data);

            /* Reflect the pci island and the vnic number to remote MEs */
            cfg_pci_vnic = (NIC_PCI << 16) | port;
            /* Reset the configuration ack counter */
            synch_cnt_dram_reset(&nic_cfg_synch,
                                 sizeof(app_mes_ids)/sizeof(uint32_t));
            /* Signal all APP MEs about a config change */
            for(i = 0; i < sizeof(app_mes_ids)/sizeof(uint32_t); i++) {
                ct_reflect_data(app_mes_ids[i], APP_ME_CONFIG_CTX,
                                APP_ME_CONFIG_XFER_NUM,
                                APP_ME_CONFIG_SIGNAL_NUM,
                                &cfg_pci_vnic, sizeof cfg_pci_vnic);
            }

            /* Set RX appropriately if NFP_NET_CFG_CTRL_ENABLE changed */
            if ((nic_control_word[port] ^ cfg_bar_data[0]) &
                    NFP_NET_CFG_CTRL_ENABLE) {

                if (cfg_bar_data[0] & NFP_NET_CFG_CTRL_ENABLE) {
                    /* Enable the MAC RX. */
                    mac_port_enable_rx(port);
                } else {
                    /* Inhibit and disable the MAC RX. */
                    mac_port_disable_rx(port);
                }
            }

            /* Save the control word */
            nic_control_word[port] = cfg_bar_data[0];

#if NS_PLATFORM_TYPE == NS_PLATFORM_CARBON
            /* Check if enabling or disabling the flow-control mechanism. */
            if (nic_control_word[port] & NFP_NET_CFG_CTRL_ENABLE)
                carbon_flow_control_enable();
            else
                carbon_flow_control_disable();
#endif

            /* Wait for all APP MEs to ack the config change */
            synch_cnt_dram_wait(&nic_cfg_synch);

            /* Complete the message */
            cfg_msg.msg_valid = 0;
            nfd_cfg_app_complete_cfg_msg(NIC_PCI, &cfg_msg,
                                         NFD_CFG_BASE_LINK(NIC_PCI),
                                         &nfd_cfg_sig_app_master0);
        }

        ctx_swap();
    }
    /* NOTREACHED */
}


/*
 * Handle per Q statistics
 *
 * - Periodically push TX and RX queue counters maintained by the PCIe
 *   MEs to the control BAR.
 */
static void
perq_stats_loop(void)
{
    SIGNAL rxq_sig;
    SIGNAL txq_sig;
    unsigned int rxq;
    unsigned int txq;

    /* Initialisation */
    nfd_in_recv_init();
    nfd_out_send_init();

    for (;;) {
        for (txq = 0;
             txq < ((NFD_MAX_VFS * NFD_MAX_VF_QUEUES) +
                    (NFD_MAX_PFS * NFD_MAX_PF_QUEUES));
             txq++) {
            __nfd_out_push_pkt_cnt(NIC_PCI, txq, ctx_swap, &txq_sig);
            sleep(PERQ_STATS_SLEEP);
        }

        for (rxq = 0;
             rxq < ((NFD_MAX_VFS * NFD_MAX_VF_QUEUES) +
                    (NFD_MAX_PFS * NFD_MAX_PF_QUEUES));
             rxq++) {
            __nfd_in_push_pkt_cnt(NIC_PCI, rxq, ctx_swap, &rxq_sig);
            sleep(PERQ_STATS_SLEEP);           
        }
    }
    /* NOTREACHED */
}

/*
 * Link state change handling
 *
 * - Periodically check the Link state (@lsc_check()) and update the
 *   status word in the control BAR.
 * - If the link state changed, try to send an interrupt (@lsc_send()).
 * - If the MSI-X entry has not yet been configured, ignore.
 * - If the interrupt is masked, set the pending flag and try again later.
 */

/* Send an LSC MSI-X. return 0 if done or 1 if pending */
__inline static int
lsc_send(int nic_intf)
{
    __mem char *nic_ctrl_bar = NFD_CFG_BAR_ISL(NIC_PCI, nic_intf);
    unsigned int automask;
    __xread unsigned int tmp;
    __gpr unsigned int entry;
    __xread uint32_t mask_r;
    __xwrite uint32_t mask_w;

    int ret = 0;

    mem_read32_le(&tmp, nic_ctrl_bar + NFP_NET_CFG_LSC, sizeof(tmp));
    entry = tmp & 0xff;

    /* Check if the entry is configured. If not return (nothing pending) */
    if (entry == 0xff)
        goto out;

    /* Work out which masking mode we should use */
    automask = nic_control_word[nic_intf] & NFP_NET_CFG_CTRL_MSIXAUTO;

    /* If we don't auto-mask, check the ICR */
    if (!automask) {
        mem_read32_le(&mask_r, nic_ctrl_bar + NFP_NET_CFG_ICR(entry),
                      sizeof(mask_r));
        if (mask_r & 0x000000ff) {
            ret = 1;
            goto out;
        }
        mask_w = NFP_NET_CFG_ICR_LSC;
        mem_write8_le(&mask_w, nic_ctrl_bar + NFP_NET_CFG_ICR(entry), 1);
    }

    ret = msix_pf_send(NIC_PCI + 4, PCIE_CPP2PCIE_LSC, entry, automask);

out:
    return ret;
}

/* Check the Link state and try to generate an interrupt if it changed.
 * Return 0 if everything is fine, or 1 if there is pending interrupt. */
__inline static int
lsc_check(__gpr unsigned int *ls_current, int nic_intf)
{
    __mem char *nic_ctrl_bar = NFD_CFG_BAR_ISL(NIC_PCI, nic_intf);
    __gpr enum link_state ls;
    __gpr int changed = 0;
    __xwrite uint32_t sts;
    __gpr int ret = 0;

    /* XXX Only check link state once the device is up.  This is
     * temporary to avoid a system crash when the MAC gets reset after
     * FW has been loaded. */
    if (!(nic_control_word[nic_intf] & NFP_NET_CFG_CTRL_ENABLE)) {
        ls = LINK_DOWN;
        goto skip_link_read;
    } else {
        __critical_path();
    }

    /* Read the current link state and if it changed set the bit in
     * the control BAR status */
    ls = mac_eth_port_link_state(NS_PLATFORM_MAC(nic_intf),
                                 NS_PLATFORM_MAC_SERDES_LO(nic_intf));

    if (ls != *ls_current)
        changed = 1;
    *ls_current = ls;

    if (changed) {
        if (ls == LINK_DOWN) {
            /* Prevent MAC TX datapath from stranding any packets. */
            mac_port_enable_tx_flush(NS_PLATFORM_MAC(nic_intf),
                                     NS_PLATFORM_MAC_CORE(nic_intf),
                                     NS_PLATFORM_MAC_CORE_SERDES_LO(nic_intf));
        } else {
            /* Re-enable MAC TX datapath. */
            mac_port_disable_tx_flush(
                NS_PLATFORM_MAC(nic_intf), NS_PLATFORM_MAC_CORE(nic_intf),
                NS_PLATFORM_MAC_CORE_SERDES_LO(nic_intf));
        }
    }

skip_link_read:
    /* Make sure the status bit reflects the link state. Write this
     * every time to avoid a race with resetting the BAR state. */
    if (ls == LINK_DOWN) {
        sts = (NFP_NET_CFG_STS_LINK_RATE_UNKNOWN <<
               NFP_NET_CFG_STS_LINK_RATE_SHIFT) | 0;
    } else {
        sts = (port_speed_to_link_rate(NS_PLATFORM_PORT_SPEED(nic_intf)) <<
               NFP_NET_CFG_STS_LINK_RATE_SHIFT) | 1;
    }
    mem_write32(&sts, nic_ctrl_bar + NFP_NET_CFG_STS, sizeof(sts));

    /* If the link state changed, try to send in interrupt */
    if (changed)
        ret = lsc_send(nic_intf);

out:
    return ret;
}

static void
lsc_loop(void)
{
    __gpr int port;
    __gpr unsigned int temp_ls;
    /* This is the per-port state information. */
    __lmem unsigned int ls_current[NS_PLATFORM_NUM_PORTS];
    __lmem unsigned int pending[NS_PLATFORM_NUM_PORTS];
    __gpr int lsc_count = 0;

    /* Set the initial port state. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        temp_ls = LINK_DOWN;
        pending[port] = lsc_check(&temp_ls, port);
        ls_current[port] = temp_ls;
    }

    /* Need to handle pending interrupts more frequent than we need to
     * check for link state changes.  To keep it simple, have a single
     * timer for the pending handling and maintain a counter to
     * determine when to also check for linkstate. */
    for (;;) {
        sleep(LSC_POLL_PERIOD);
        ++lsc_count;

        for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
            if (pending[port])
                pending[port] = lsc_send(port);
        }

        if (lsc_count > 19) {
            lsc_count = 0;
            for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
                temp_ls = ls_current[port];
                pending[port] = lsc_check(&temp_ls, port);
                ls_current[port] = temp_ls;
            }
        }
    }
    /* NOTREACHED */
}

int
main(void)
{
    switch (ctx()) {
    case APP_MASTER_CTX_CONFIG_CHANGES:
        init_catamaran_chan2port_table();
        cfg_changes_loop();
        break;
    case APP_MASTER_CTX_MAC_STATS:
        nic_stats_loop();
        break;
    case APP_MASTER_CTX_PERQ_STATS:
        perq_stats_loop();
        break;
    case APP_MASTER_CTX_LINK_STATE:
        lsc_loop();
        break;
    default:
        ctx_wait(kill);
    }
    /* NOTREACHED */
}
