/*
 * Copyright 2014-2017 Netronome, Inc.
 *
 * @file          app_master_main.c
 * @brief         ME serving as the NFD NIC application master.
 *
 * This implementation only handles one PCIe island.
 */


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
#include "nfd_user_cfg.h"
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

#include "app_mac_vlan_config_cmsg.h"
#include "maps/cmsg_map_types.h"
#include "nic_tables.h"
#include "trng.h"

#include "app_private.c"
#include "app_control_lib.c"

/*
 * The application master runs on a single ME and performs a number of
 * functions:
 *
 * - Handle configuration changes.  The PCIe MEs (NFD) notify a single
 *   ME (this ME) of any changes to the configuration BAR.  It is then
 *   up to this ME to disseminate these configuration changes to any
 *   application MEs which need to be informed.  One context in this
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

/* APP Master CTXs assignments - 4 context mode */
#define APP_MASTER_CTX_CONFIG_CHANGES   0
#define APP_MASTER_CTX_MAC_STATS        2
#define APP_MASTER_CTX_PERQ_STATS       4
#define APP_MASTER_CTX_LINK_STATE       6

/*
 * Global declarations for configuration change management
 */

/* The list of all application MEs IDs */
#ifndef APP_MES_LIST
    #error "The list of application MEs IDd must be defined"
#else
    __shared __lmem uint32_t app_mes_ids[] = {APP_MES_LIST};
#endif


SIGNAL nfd_cfg_sig_app_master0;
__xread struct nfd_cfg_msg cfg_msg_rd0;
NFD_CFG_BASE_DECLARE(0);
NFD_VF_CFG_DECLARE(NIC_PCI)
NFD_FLR_DECLARE;
MSIX_DECLARE;

/* config change message */
struct nfd_cfg_msg cfg_msg;

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
/* Amount of time between each link status check */
#define LSC_POLL_PERIOD            10000

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CARBON) || \
    (NS_PLATFORM_TYPE == NS_PLATFORM_CARBON_1x10_1x25)

#define DISABLE_GPIO_POLL 0

#else /* NS_PLATFORM_TYPE != NS_PLATFORM_CARBON */

#define DISABLE_GPIO_POLL 1

#endif /* NS_PLATFORM_TYPE != NS_PLATFORM_CARBON */

/* Link rate */
#define   NFP_NET_CFG_STS_LINK_RATE_SHIFT 1
#define   NFP_NET_CFG_STS_LINK_RATE_MASK  0xF
#define   NFP_NET_CFG_STS_LINK_RATE       \
            (NFP_NET_CFG_STS_LINK_RATE_MASK << NFP_NET_CFG_STS_LINK_RATE_SHIFT)
#define   NFP_NET_CFG_STS_LINK_RATE_UNSUPPORTED   0
#define   NFP_NET_CFG_STS_LINK_RATE_UNKNOWN       1
#define   NFP_NET_CFG_STS_LINK_RATE_1G            2
#define   NFP_NET_CFG_STS_LINK_RATE_10G           3
#define   NFP_NET_CFG_STS_LINK_RATE_25G           4
#define   NFP_NET_CFG_STS_LINK_RATE_40G           5
#define   NFP_NET_CFG_STS_LINK_RATE_50G           6
#define   NFP_NET_CFG_STS_LINK_RATE_100G          7


__intrinsic void nic_local_epoch();


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


static void
cfg_changes_loop(void)
{
    __xread unsigned int cfg_bar_data[2];
    /* out volatile __xwrite uint32_t cfg_pci_vnic; */
    uint32_t vid, type, vnic;
    uint32_t update;
    uint32_t control;
    __emem __addr40 uint8_t *bar_base;

    for (;;) {
        cfg_msg.error = 0;
        nfd_cfg_master_chk_cfg_msg(NIC_PCI, &cfg_msg, &cfg_msg_rd0,
                                   &nfd_cfg_sig_app_master0);

        if (cfg_msg.msg_valid && !cfg_msg.error) {
            vid = cfg_msg.vid;
            /* read in the first 64bit of the Control BAR */
            mem_read64(cfg_bar_data, NFD_CFG_BAR_ISL(NIC_PCI, vid),
                       sizeof cfg_bar_data);

            control = cfg_bar_data[0];
            update = cfg_bar_data[1];

            NFD_VID2VNIC(type, vnic, vid);

            if (type == NFD_VNIC_TYPE_CTRL) {
                if (process_ctrl_reconfig(control, vid, &cfg_msg))
                    goto error;

            } else if (type == NFD_VNIC_TYPE_PF) {
                if (process_pf_reconfig(control, update, vid, vnic, &cfg_msg))
                    goto error;

            } else if (type == NFD_VNIC_TYPE_VF) {
                if (process_vf_reconfig(control, update, vid, &cfg_msg))
                    goto error;
            }

            nic_control_word[cfg_msg.vid] = control;
error:
            /* Complete the message */
            cfg_msg.msg_valid = 0;
            nfd_cfg_app_complete_cfg_msg(NIC_PCI, &cfg_msg,
                                         NFD_CFG_BASE_LINK(NIC_PCI));
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
             txq < (NFD_TOTAL_VFQS + NFD_TOTAL_CTRLQS + NFD_TOTAL_PFQS);
             txq++) {
            __nfd_out_push_pkt_cnt(NIC_PCI, txq, ctx_swap, &txq_sig);
            sleep(PERQ_STATS_SLEEP);
        }

        for (rxq = 0;
             rxq < (NFD_TOTAL_VFQS + NFD_TOTAL_CTRLQS + NFD_TOTAL_PFQS);
             rxq++) {
            __nfd_in_push_pkt_cnt(NIC_PCI, rxq, ctx_swap, &rxq_sig);
            sleep(PERQ_STATS_SLEEP);
        }

        nic_local_epoch();
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

/* Send an LSC MSI-X. return 0 if done or 1 if pending. vid corresponds to
   either a pf or a vf */
static int
lsc_send(int vid)
{
    __mem char *nic_ctrl_bar;
    unsigned int automask;
    __xread unsigned int tmp;
    __gpr unsigned int entry;
    __xread uint32_t mask_r;
    __xwrite uint32_t mask_w;
    int ret = 0;

    nic_ctrl_bar = NFD_CFG_BAR_ISL(NIC_PCI, vid);

    mem_read32_le(&tmp, nic_ctrl_bar + NFP_NET_CFG_LSC, sizeof(tmp));
    entry = tmp & 0xff;

    /* Check if the entry is configured. If not return (nothing pending) */
    if (entry == 0xff)
        goto out;

    /* Work out which masking mode we should use */
    automask = nic_control_word[vid] & NFP_NET_CFG_CTRL_MSIXAUTO;

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

    ret = msix_pf_send(NIC_PCI, PCIE_CPP2PCIE_LSC, entry, automask);

out:
    return ret;
}

/* Check for VFs that should receive an interrupt for a link state change,
   update the link status, and try to generate an interrupt */
static void
lsc_check_vf(int port, enum link_state ls)
{
    __mem char *vf_ctrl_bar;
    unsigned int vf_vid;
    __xwrite uint32_t sts;
    __xread uint32_t ctrl;

    for (vf_vid = 0; vf_vid < NVNICS; vf_vid++) {
        /* Check if the VF should be receiving an interrupt. */
        if (NFD_VID_IS_VF(vf_vid) && LS_READ(vf_lsc_list[port], vf_vid)) {
            /* Update the link state status. Report the link speed for the
               VF as that of the PF. */
            if (ls == LINK_UP) {
                LS_SET(ls_current, vf_vid);
                sts = (port_speed_to_link_rate(NS_PLATFORM_PORT_SPEED(port)) <<
                      NFP_NET_CFG_STS_LINK_RATE_SHIFT) | 1;
            } else {
                LS_CLEAR(ls_current, vf_vid);
                sts = (NFP_NET_CFG_STS_LINK_RATE_UNKNOWN <<
                NFP_NET_CFG_STS_LINK_RATE_SHIFT);
            }

            vf_ctrl_bar = NFD_CFG_BAR_ISL(NIC_PCI, vf_vid);
            mem_write32(&sts, vf_ctrl_bar + NFP_NET_CFG_STS, sizeof(sts));
            /* Make sure the config BAR is updated before we send
               the notification interrupt */
            mem_read32(&ctrl, vf_ctrl_bar + NFP_NET_CFG_CTRL, sizeof(ctrl));

            /* Send the interrupt. */
            if (lsc_send(vf_vid))
                LS_SET(pending, vf_vid);
            else
                LS_CLEAR(pending, vf_vid);
        }
    }
}

/* Check the Link state and try to generate an interrupt if it changed. */
static
void lsc_check(int port)
{
    __mem char *nic_ctrl_bar;
    __gpr enum link_state ls;
    __gpr enum link_state vs;
    __gpr int changed = 0;
    __xwrite uint32_t sts;
    __xread uint32_t ctrl;
    __gpr int ret = 0;
    uint32_t pf_vid;

    /* Update pf corresponding to port */
    pf_vid = NFD_PF2VID(port);
    nic_ctrl_bar = NFD_CFG_BAR_ISL(NIC_PCI, pf_vid);

    /* link state according to MAC */
    ls = mac_eth_port_link_state(NS_PLATFORM_MAC(port),
                                    NS_PLATFORM_MAC_SERDES_LO(port),
                                    (NS_PLATFORM_PORT_SPEED(port) > 1) ? 0 : 1);

    /* link state according to VNIC */
    vs = nic_control_word[pf_vid] & NFP_NET_CFG_CTRL_ENABLE;

    if (ls != LS_READ(ls_current, pf_vid)) {
        changed = 1;
        if (ls)
            LS_SET(ls_current, pf_vid);
        else
            LS_CLEAR(ls_current, pf_vid);
    }

    if (vs != LS_READ(vs_current, pf_vid)) {
        changed = 1;
        if (vs)
            LS_SET(vs_current, pf_vid);
        else {
            /* a disabled VNIC overrides MAC link state */
            ls = LINK_DOWN;
            LS_CLEAR(vs_current, pf_vid);
        }
    }

    if (changed) {
        if (ls == LINK_DOWN) {
            /* Prevent MAC TX datapath from stranding any packets. */
            mac_port_enable_tx_flush(NS_PLATFORM_MAC(port),
                                     NS_PLATFORM_MAC_CORE(port),
                                     NS_PLATFORM_MAC_CORE_SERDES_LO(port));
        } else if (vs) {
            mac_port_enable_rx(port);
            mac_port_enable_tx(port);
            mac_port_disable_tx_flush(NS_PLATFORM_MAC(port),
                                      NS_PLATFORM_MAC_CORE(port),
                                      NS_PLATFORM_MAC_CORE_SERDES_LO(port));
        }
    }

    /* Make sure the status bit reflects the link state. Write this
     * every time to avoid a race with resetting the BAR state. */
    if (ls == LINK_DOWN) {
        sts = (NFP_NET_CFG_STS_LINK_RATE_UNKNOWN <<
               NFP_NET_CFG_STS_LINK_RATE_SHIFT) | 0;
    } else {
        sts = (port_speed_to_link_rate(NS_PLATFORM_PORT_SPEED(port)) <<
               NFP_NET_CFG_STS_LINK_RATE_SHIFT) | 1;
        /* ugly hack: be forceful if unexpected RX state occurs */
        if (vs && ! mac_eth_check_rx_enable(NS_PLATFORM_MAC(port),
                                            NS_PLATFORM_MAC_CORE(port),
                                            NS_PLATFORM_MAC_CORE_SERDES_LO(port))) {
	    mac_port_enable_rx(port);
            mac_port_enable_tx(port);
            mac_port_disable_tx_flush(
                NS_PLATFORM_MAC(port), NS_PLATFORM_MAC_CORE(port),
                NS_PLATFORM_MAC_CORE_SERDES_LO(port));
	}
    }
    mem_write32(&sts, nic_ctrl_bar + NFP_NET_CFG_STS, sizeof(sts));
    /* Make sure the config BAR is updated before we send
       the notification interrupt */
    mem_read32(&ctrl, nic_ctrl_bar + NFP_NET_CFG_CTRL, sizeof(ctrl));

    /* If the link state changed, try to send in interrupt */
    if (changed || LS_READ(pending, pf_vid)) {
        if (lsc_send(pf_vid))
            LS_SET(pending, pf_vid);
        else
            LS_CLEAR(pending, pf_vid);

        /* Now, notify the VFs that follow the port's link state. */
        if (changed)
           lsc_check_vf(port, ls);
    }
}

static void
lsc_loop(void)
{
    __gpr int vid;
    __gpr int port;
    __gpr int lsc_count = 0;

    /* Set the initial port state. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; port++) {
        lsc_check(port);
    }

    /* Need to handle pending interrupts more frequent than we need to
     * check for link state changes.  To keep it simple, have a single
     * timer for the pending handling and maintain a counter to
     * determine when to also check for linkstate. */
    for (;;) {
        sleep(LSC_POLL_PERIOD);
        lsc_count++;

        for (vid = 0; vid < NVNICS; vid++) {
            if (LS_READ(pending, vid)) {
                if (lsc_send(vid))
                    LS_SET(pending, vid);
                else
                    LS_CLEAR(pending, vid);
            }
        }

        if (lsc_count > 19) {
            lsc_count = 0;
            for (port = 0; port < NS_PLATFORM_NUM_PORTS; port++) {
                lsc_check(port);
            }
        }
    }
    /* NOTREACHED */
}

/*
 * Generate random Ethernet addresses (MAC) to all VFs, the MAC addresses
 * are not multicast and has the local assigned bit set.
 */
static void
init_vfs_random_macs(void)
{
    uint32_t vf, i;
    int try;
    uint32_t mac_hi;
    uint32_t mac_lo;
    __gpr uint64_t mac64;
    __shared __lmem uint32_t sriov_act_list[NIC_MAC_VLAN_RESULT_SIZE_LW];
    __emem __addr40 uint8_t *vf_cfg_base = NFD_VF_CFG_BASE_LINK(NIC_PCI);
    __emem __addr40 uint8_t *vf_base;
    __gpr struct sriov_cfg sriov_cfg_data;
    __xread struct sriov_cfg sriov_cfg_data_rd;
    __xwrite struct sriov_cfg sriov_cfg_data_wr;
    __xread unsigned int cfg_bar_data[2];
    __mem char *cfg_bar;

    reg_zero(sriov_act_list, sizeof(sriov_act_list));

    /* Start generating the MAC addresses */
    for (vf = 0; NFD_MAX_VFS && vf < NFD_MAX_VFS; vf++) {
        /* make several attempts to acquire a locally unique MAC */
        for (try = 0; try < 10; ++try) {
            trng_rd64(&mac_hi, &mac_lo);

            /* Make sure no Multicast */
            mac_hi &= 0xFEFFFFFF;

            /* Local assigned bit set */
            mac_hi |= 0x02000000;

            mac_lo = mac_lo >> 16;

            /* check previoust VFs for duplicates */
            for (i = 0; i <= vf; ) {
                vf_base = NFD_VF_CFG_ADDR(vf_cfg_base, i++);
                mem_read32(&sriov_cfg_data_rd, vf_base, sizeof(struct sriov_cfg));

                if (sriov_cfg_data_rd.mac_hi == mac_hi &&
                    sriov_cfg_data_rd.mac_lo == mac_lo)
                    break;
            }

            /* retry if previous VF matches */
            if (i != vf + 1)
                continue;

            /* Write the generated MAC into NFD's rtsym */
            reg_cp(&sriov_cfg_data, &sriov_cfg_data_rd,
                    sizeof(struct sriov_cfg));
            sriov_cfg_data.mac_hi = mac_hi;
            sriov_cfg_data.mac_lo = mac_lo;
            reg_cp(&sriov_cfg_data_wr, &sriov_cfg_data,
                    sizeof(struct sriov_cfg));
            mem_write32(&sriov_cfg_data_wr, vf_base, sizeof(struct sriov_cfg));

            /* write the MAC to the VF BAR so it is ready to use even
             * without an FLR */
            mem_write8(&sriov_cfg_data_wr, NFD_CFG_BAR_ISL(NIC_PCI, vf) +
                       NFP_NET_CFG_MACADDR, NFD_VF_CFG_MAC_SZ);

            /* All went well, no need to try again */
            break;
        }
    }
}

static void
init_msix(void)
{
    /* Initialisation */
    MSIX_INIT_ISL(NIC_PCI);
}

static void
mac_rx_disable(void)
{
    uint32_t port;
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        mac_port_disable_rx(port);
    }
    /* Wait for MAC disable and NN registers to come up in reflect mode */
    sleep((NS_PLATFORM_TCLK * 1000000) / 20); // 50ms
}

static void
init_nic(void)
{
    nic_local_init(0, 0);       /* dummy regs right now */

    init_nn_tables();
    upd_slicc_hash_table();
}

int
main(void)
{

    switch (ctx()) {
    case APP_MASTER_CTX_CONFIG_CHANGES:
        /* WARNING!
         * nfd_cfg_init_cfg_msg() introduces the live range for the remote
         * signal, call it before anything else that might reuse the signal
         */
	nfd_cfg_master_init_cfg_msg(NIC_PCI, &cfg_msg, &cfg_msg_rd0,
                                    &nfd_cfg_sig_app_master0);
        trng_init();
        init_catamaran_chan2port_table();
        init_vfs_random_macs();
        init_msix();
        mac_csr_sync_start(DISABLE_GPIO_POLL);
        mac_rx_disable();
        init_nic();
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
