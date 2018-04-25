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

#include <nic.h>
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

#include <shared/nfp_net_ctrl.h>

#include <link_state/link_ctrl.h>
#include <link_state/link_state.h>
#include <nic_basic/nic_basic.h>

#include <npfw/catamaran_app_utils.h>

#include <vnic/nfd_common.h>

#include "app_config_tables.h"
#include "ebpf.h"

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

/* APP Master CTXs assignments - 4 context mode */
#define APP_MASTER_CTX_CONFIG_CHANGES   0
#define APP_MASTER_CTX_MAC_STATS        2
#define APP_MASTER_CTX_PERQ_STATS       4
#define APP_MASTER_CTX_LINK_STATE       6


/* Address of the PF Control BAR */


/* Number of PFs and VFs supported. */
#define NUM_PFS_VFS (NFD_MAX_PFS + NFD_MAX_VFS)

/* Current value of NFP_NET_CFG_CTRL (shared between all contexts) */
/* TODO does NS_PLATFORM_NUM_PORTS equal NFD_MAX_PFS?
 * If so should NFD_MAX_PFS be used below? */
__shared __lmem volatile uint32_t nic_control_word[NS_PLATFORM_NUM_PORTS +
                                                   NFD_MAX_CTRL];


/* Current state of the link state and the pending interrupts. */
#define LS_ARRAY_LEN           ((NUM_PFS_VFS + 31) >> 5)
#define LS_IDX(_vnic)          ((_vnic) >> 5)
#define LS_SHF(_vnic)          ((_vnic) & 0x1f)
#define LS_MASK(_vnic)         (0x1 << LS_SHF(_vnic))
#define LS_READ(_state, _vnic) ((_state[LS_IDX(_vnic)] >> LS_SHF(_vnic)) & 0x1)

#define LS_CLEAR(_state, _vnic)                   \
    do {                                          \
        _state[LS_IDX(_vnic)] &= ~LS_MASK(_vnic); \
    } while (0)
#define LS_SET(_state, _vnic)                    \
    do {                                         \
        _state[LS_IDX(_vnic)] |= LS_MASK(_vnic); \
    } while (0)

__shared __lmem uint32_t vs_current[LS_ARRAY_LEN];
__shared __lmem uint32_t ls_current[LS_ARRAY_LEN];
__shared __lmem uint32_t pending[LS_ARRAY_LEN];

#define TMQ_DRAIN_RETRIES      15

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
MSIX_DECLARE;

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
mac_port_enable_rx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);
    unsigned int mac_core      = NS_PLATFORM_MAC_CORE(port);
    unsigned int mac_core_port = NS_PLATFORM_MAC_CORE_SERDES_LO(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_enable_rx(mac_nbi_isl, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
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

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


__inline static void
mac_port_enable_tx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    enable_port_tx_datapath(mac_nbi_isl, NS_PLATFORM_NBI_TM_QID_LO(port),
                            NS_PLATFORM_NBI_TM_QID_HI(port));

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


__inline static void
mac_port_disable_tx(unsigned int port)
{
    unsigned int mac_nbi_isl   = NS_PLATFORM_MAC(port);

    LOCAL_MUTEX_LOCK(mac_reg_lock);

    disable_port_tx_datapath(mac_nbi_isl, NS_PLATFORM_NBI_TM_QID_LO(port),
                             NS_PLATFORM_NBI_TM_QID_HI(port));

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


__inline static void
mac_port_disable_tx_flush(unsigned int mac, unsigned int mac_core,
                          unsigned int mac_core_port)
{
    LOCAL_MUTEX_LOCK(mac_reg_lock);

    mac_eth_disable_tx_flush(mac, mac_core, mac_core_port);

    LOCAL_MUTEX_UNLOCK(mac_reg_lock);
}


static void
cfg_changes_loop(void)
{
    struct nfd_cfg_msg cfg_msg;
    __xread unsigned int cfg_bar_data[2];
    /* out volatile __xwrite uint32_t cfg_pci_vnic; */
    __gpr int i;
    uint32_t vid, type, vnic, port;
    uint32_t update;
    uint32_t control;
    __gpr uint32_t ctx_mode = 1;
    __emem __addr40 uint8_t *bar_base;

    /* Initialisation */
    MSIX_INIT_ISL(NIC_PCI);

    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        mac_port_disable_rx(port);
    }

    nfd_cfg_init_cfg_msg(&nfd_cfg_sig_app_master0, &cfg_msg);
    nic_local_init(0, 0);		/* dummy regs right now */

    /* Wait for MAC disable and NN registers to come up in reflect mode */
    sleep((NS_PLATFORM_TCLK * 1000000) / 20); // 50ms

    init_nn_tables();
    upd_slicc_hash_table();

    for (;;) {
        nfd_cfg_master_chk_cfg_msg(&cfg_msg, &nfd_cfg_sig_app_master0, 0);

        if (cfg_msg.msg_valid) {

            vid = cfg_msg.vid;
            /* read in the first 64bit of the Control BAR */
            mem_read64(cfg_bar_data, NFD_CFG_BAR_ISL(NIC_PCI, vid),
                       sizeof cfg_bar_data);

            control = cfg_bar_data[0];
            update = cfg_bar_data[1];

            NFD_VID2VNIC(type, vnic, vid);

            if (type == NFD_VNIC_TYPE_CTRL) {
                /* For now just set the link on. */
                /* TODO figure out what else is required */
                __xwrite unsigned int link_state;

                nic_control_word[vid] = control;

                /* Set link state */
                if (!cfg_msg.error &&
                    (control & NFP_NET_CFG_CTRL_ENABLE)) {
                    link_state = NFP_NET_CFG_STS_LINK;
                } else {
                    link_state = 0;
                }
	        app_config_port(vid, control, update);	/* write cmsg instr */
    		upd_slicc_hash_table();

                mem_write32(&link_state,
                            (NFD_CFG_BAR_ISL(PCIE_ISL, cfg_msg.vid) +
                             NFP_NET_CFG_STS),
                            sizeof link_state);
            } else if (type == NFD_VNIC_TYPE_PF) {
                port = vnic;

                if (update & NFP_NET_CFG_UPDATE_BPF) {
	            nic_local_bpf_reconfig(&ctx_mode, vid, vnic);
                }

                if (control & NFP_NET_CFG_CTRL_ENABLE) {
                    app_config_port(vid, control, update);
                    nic_local_epoch();
                }

                /* Set RX appropriately if NFP_NET_CFG_CTRL_ENABLE changed */
                if ((nic_control_word[vid] ^ control) & NFP_NET_CFG_CTRL_ENABLE) {
                    if (control & NFP_NET_CFG_CTRL_ENABLE) {
			mac_port_enable_tx(port);

                        /* Wait for config to stabilize */
                        sleep(10 * NS_PLATFORM_TCLK * 1000); // 10ms

                        mac_port_enable_rx(port);
                    } else {
			__xread struct nfp_nbi_tm_queue_status tmq_status;
			int i, queue, occupied = 1;

			/* stop receiving packets */
                        mac_port_disable_rx(port);
                        app_config_port_down(vid);
                        nic_local_epoch();

			/* wait for TM queues to drain */
			for (i = 0; occupied && i < TMQ_DRAIN_RETRIES; ++i) {
				occupied = 0;
				for (queue = NS_PLATFORM_NBI_TM_QID_LO(port);
				     queue <= NS_PLATFORM_NBI_TM_QID_HI(port);
				     queue++) {
					tmq_status_read(&tmq_status,
							NS_PLATFORM_MAC(port),
							queue, 1);
					if (tmq_status.queuelevel) {
						occupied = 1;
						break;
					}
				}
				sleep(NS_PLATFORM_TCLK * 1000); // 1ms
			}

			mac_port_disable_tx(port);
                    }
                }

                /* Save the control word */
                nic_control_word[vid] = control;
            } else {
                    /* This is an error, VFs aren't supported yet */
            }

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

/* Send an LSC MSI-X. return 0 if done or 1 if pending */
__inline static int
lsc_send(int port)
{
    __mem char *nic_ctrl_bar;
    unsigned int automask;
    __xread unsigned int tmp;
    __gpr unsigned int entry;
    __xread uint32_t mask_r;
    __xwrite uint32_t mask_w;
    uint32_t vid;
    int ret = 0;

    vid = NFD_PF2VID(port);
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

    ret = msix_pf_send(NIC_PCI + 4, PCIE_CPP2PCIE_LSC, entry, automask);

out:
    return ret;
}

/* Check the Link state and try to generate an interrupt if it changed. */
__inline static void lsc_check(int port)
{
    __mem char *nic_ctrl_bar;
    __gpr enum link_state ls;
    __gpr enum link_state vs;
    __gpr int changed = 0;
    __xwrite uint32_t sts;
    __gpr int ret = 0;
    uint32_t vid;

    vid = NFD_PF2VID(port);
    nic_ctrl_bar = NFD_CFG_BAR_ISL(NIC_PCI, vid);

    /* link state according to MAC */
    ls = mac_eth_port_link_state(NS_PLATFORM_MAC(port),
				 NS_PLATFORM_MAC_SERDES_LO(port),
                                 (NS_PLATFORM_PORT_SPEED(port) > 1) ? 0 : 1);

    /* link state according to VNIC */
    vs = nic_control_word[vid] & NFP_NET_CFG_CTRL_ENABLE;

    if (ls != LS_READ(ls_current, port)) {
        changed = 1;
        if (ls)
            LS_SET(ls_current, port);
        else
            LS_CLEAR(ls_current, port);
    }

    if (vs != LS_READ(vs_current, port)) {
	changed = 1;
	if (vs)
	    LS_SET(vs_current, port);
	else {
            /* a disabled VNIC overrides MAC link state */
            ls = LINK_DOWN;
	    LS_CLEAR(vs_current, port);
	}
    }

    if (changed) {
        if (ls == LINK_DOWN) {
            /* Prevent MAC TX datapath from stranding any packets. */
            mac_port_enable_tx_flush(NS_PLATFORM_MAC(port),
                                     NS_PLATFORM_MAC_CORE(port),
                                     NS_PLATFORM_MAC_CORE_SERDES_LO(port));
        } else {
            /* Re-enable MAC TX datapath. */
            mac_port_disable_tx_flush(
                NS_PLATFORM_MAC(port), NS_PLATFORM_MAC_CORE(port),
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
    }
    mem_write32(&sts, nic_ctrl_bar + NFP_NET_CFG_STS, sizeof(sts));

    /* If the link state changed, try to send in interrupt */
    if (changed || LS_READ(pending, port)) {
        if (lsc_send(port))
            LS_SET(pending, port);
        else
            LS_CLEAR(pending, port);
    }
}

static void
lsc_loop(void)
{
    __gpr int port;
    __gpr int lsc_count = 0;

    /* Set the initial port state. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        lsc_check(port);
    }

    /* Need to handle pending interrupts more frequent than we need to
     * check for link state changes.  To keep it simple, have a single
     * timer for the pending handling and maintain a counter to
     * determine when to also check for linkstate. */
    for (;;) {
        sleep(LSC_POLL_PERIOD);
        ++lsc_count;

        for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
            if (LS_READ(pending, port)) {
                if (lsc_send(port))
                    LS_SET(pending, port);
                else
                    LS_CLEAR(pending, port);
            }
        }

        if (lsc_count > 19) {
            lsc_count = 0;
            for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
                lsc_check(port);
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
        mac_csr_sync_start(DISABLE_GPIO_POLL);
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
