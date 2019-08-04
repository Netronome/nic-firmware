/**
 * Copyright (C) 2016-2017,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          link_ctrl.c
 * @brief         Code for configuring the Ethernet link.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include <assert.h>
#include <nfp/me.h>
#include <nfp/remote_me.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_mac.h>
#include <nfp6000/nfp_mac_csr_synch.h>
#include <nfp6000/nfp_nbi_tm.h>

#include <link_state/link_ctrl.h>


/* Maximum Ethernet ports per MAC core */
#define MAX_ETH_PORTS_PER_MAC_CORE 12

/* Maximum number of MAC cores per MAC island */
#define MAX_MAC_CORES_PER_MAC_ISL  2

/* Maximum number of MAC islands supported on the NFP */
#define MAX_MAC_ISLANDS_PER_NFP    2

/* Macro to convert MAC core port to MAC port. */
#define MAC_CORE_PORT_TO_MAC_PORT(_core, _core_port)      \
    ((_core) * MAX_ETH_PORTS_PER_MAC_CORE + (_core_port))


/* Address of the MAC Ethernet port configuration register */
#define MAC_CONF_ADDR(_isl, _core, _core_port)    \
    (NFP_MAC_XPB_OFF(_isl) | NFP_MAC_ETH(_core) | \
     NFP_MAC_ETH_SEG_CMD_CONFIG(_core_port))

/* Addresses of the MAC enqueue inhibit registers */
#define MAC_EQ_INH_ADDR(_isl)                                  \
    (NFP_MAC_XPB_OFF(_isl) | NFP_MAC_CSR | NFP_MAC_CSR_EQ_INH)
#define MAC_EQ_INH_DONE_ADDR(_isl)                                  \
    (NFP_MAC_XPB_OFF(_isl) | NFP_MAC_CSR | NFP_MAC_CSR_EQ_INH_DONE)


/* Maximum number of NBI islands supported on the NFP */
#define MAX_NBI_ISLANDS_PER_NFP    2

/* Maximum number of TM queues per NBI */
#define MAX_TM_QUEUES_PER_NBI_ISL  1024

/* Address of the NBI TM queue configuration register */
#define NBI_TM_Q_CFG_ADDR(_isl, _q)                    \
    (NFP_NBI_TM_XPB_OFF(_isl) | NFP_NBI_TM_QUEUE_REG | \
     NFP_NBI_TM_QUEUE_CONFIG(_q))

/* Source ID for sync ME commands. */
/* Note: This value is completely arbitrary and does not affect anything. */
#define LINK_CTRL_SYNC_CMD_ID 1

/* Command word to issue to sync ME. */
#define LINK_CTRL_SYNC_CMD(_isl, _core, _core_port, _cmd_code, _recache) \
    ((LINK_CTRL_SYNC_CMD_ID << 24) | (((_recache) & 1)     << 16) |      \
     (((_isl) & 1)          << 15) | (((_core) & 1)        << 14) |      \
     (((_core_port) & 0x3f) << 8)  | (((_cmd_code) & 0xff) << 0))


/* *** MAC CSR Sync ME Functions *** */

#define MAX_NUM_MBOXES 4

static __intrinsic uint32_t
mailbox_addr(unsigned int mbox_num)
{
    uint32_t addr;

    /* Check the parameter */
    ctassert(mbox_num < MAX_NUM_MBOXES);

    switch (mbox_num) {
    case 0:
        addr = local_csr_mailbox_0;
        break;
    case 1:
        addr = local_csr_mailbox_1;
        break;
    case 2:
        addr = local_csr_mailbox_2;
        break;
    case 3:
        addr = local_csr_mailbox_3;
        break;
    default:
        addr = 0xffffffff;
        break;
    }

    return addr;
}

static __intrinsic void
issue_sync_me_cmd(unsigned int mac_isl, unsigned int mac_core,
                  unsigned int mac_core_port, unsigned int cmd_code,
                  unsigned int force_recache)
{
    SIGNAL sig;
    __xwrite uint32_t cmd_xw = LINK_CTRL_SYNC_CMD(mac_isl, mac_core,
                                                  mac_core_port, cmd_code,
                                                  force_recache);
    uint32_t ring_isl = ARB_CLS_BASE_ADDR_Hi32;
    uint32_t ring_num = ARB_CLS_RING_NUM << 2;

    __asm cls[ring_workq_add_work, cmd_xw, ring_isl, <<8, ring_num, 1], \
        ctx_swap[sig];
}


__intrinsic void
mac_csr_sync_recache(unsigned int mac_isl,
                     unsigned int mac_core,
                     unsigned int mac_core_port)
{
    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    issue_sync_me_cmd(mac_isl, mac_core, mac_core_port,
                      ARB_CODE_ETH_CMD_CFG_RECACHE, 0);
}


__intrinsic void
mac_csr_sync_start(uint32_t disable_gpio_poll)
{
    remote_csr_write(ARB_ME_ISLAND, ARB_ME_ID,
                     mailbox_addr(ARB_FW_DEBUG_MBOX), disable_gpio_poll);
    remote_csr_write(ARB_ME_ISLAND, ARB_ME_ID,
                     mailbox_addr(ARB_FW_KICKSTART_MBOX), ARB_FW_KICKSTART);
    remote_csr_write(ARB_ME_ISLAND, ARB_ME_ID,
                     mailbox_addr(ARB_FW_QUIESCE_MBOX), ARB_RESUME);
}


/* *** MAC RX Enable/Disable Functions *** */

__intrinsic int
mac_eth_check_rx_enable(unsigned int mac_isl, unsigned int mac_core,
                        unsigned int mac_core_port)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Read the configuration register for the port. */
    mac_conf_addr = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf      = xpb_read(mac_conf_addr);

    return ((mac_conf & NFP_MAC_ETH_SEG_CMD_CONFIG_RX_ENABLE) ? 1 : 0);
}


__intrinsic int
mac_eth_disable_rx(unsigned int mac_isl, unsigned int mac_core,
                   unsigned int mac_core_port, unsigned int num_lanes)
{
    uint32_t mac_inhibit;
    uint32_t mac_inhibit_addr;
    uint32_t mac_inhibit_done;
    uint32_t mac_inhibit_done_addr;
    uint32_t mac_port_mask;
    uint32_t i = 0;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);
    assert((mac_core_port + num_lanes - 1) < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Enable the MAC RX enqueue inhibit. */
    mac_inhibit_addr  = MAC_EQ_INH_ADDR(mac_isl);
    mac_port_mask     = (((1 << num_lanes) - 1) <<
                         MAC_CORE_PORT_TO_MAC_PORT(mac_core, mac_core_port));
    mac_inhibit       = xpb_read(mac_inhibit_addr);
    mac_inhibit      |= mac_port_mask;
    xpb_write(mac_inhibit_addr, mac_inhibit);

    /* Poll until the MAC inhibit takes effect. */
    mac_inhibit_done_addr = MAC_EQ_INH_DONE_ADDR(mac_isl);

    do {
        mac_inhibit_done  = xpb_read(mac_inhibit_done_addr);
        mac_inhibit_done &= mac_port_mask;
    } while (mac_inhibit_done != mac_port_mask);

    /* Clear the MAC RX enable for the port. */
    issue_sync_me_cmd(mac_isl, mac_core, mac_core_port,
                      ARB_CODE_ETH_CMD_CFG_DISABLE_RX, 0);


    /* Verify that the MAC RX is disabled for the port. */
    for (i = 0; i < 10; ++i) {
        if (! mac_eth_check_rx_enable(mac_isl, mac_core, mac_core_port))
	    break;
        sleep(10 * NS_PLATFORM_TCLK * 1000); // 10ms
    }

    /* Disable the MAC RX enqueue inhibit. */
    mac_inhibit &= ~mac_port_mask;
    xpb_write(mac_inhibit_addr, mac_inhibit);

    return i < 10;
}


__intrinsic void
mac_eth_enable_rx(unsigned int mac_isl, unsigned int mac_core,
                  unsigned int mac_core_port)
{
    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Set the MAC RX enable for the port. */
    issue_sync_me_cmd(mac_isl, mac_core, mac_core_port,
                      ARB_CODE_ETH_CMD_CFG_ENABLE_RX, 0);

    return;
}


/* *** MAC TX Flush Enable/Disable Functions *** */

__intrinsic int
mac_eth_check_tx_flush_enable(unsigned int mac_isl, unsigned int mac_core,
                              unsigned int mac_core_port)
{
    uint32_t mac_conf;
    uint32_t mac_conf_addr;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Read the configuration register for the port. */
    mac_conf_addr = MAC_CONF_ADDR(mac_isl, mac_core, mac_core_port);
    mac_conf      = xpb_read(mac_conf_addr);

    return ((mac_conf & NFP_MAC_ETH_SEG_CMD_CONFIG_TX_FLUSH) ? 1 : 0);
}


__intrinsic void
mac_eth_disable_tx_flush(unsigned int mac_isl, unsigned int mac_core,
                         unsigned int mac_core_port)
{
    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Clear the MAC TX flush enable for the port. */
    issue_sync_me_cmd(mac_isl, mac_core, mac_core_port,
                      ARB_CODE_ETH_CMD_CFG_DISABLE_FLUSH, 0);

    return;
}


__intrinsic void
mac_eth_enable_tx_flush(unsigned int mac_isl, unsigned int mac_core,
                        unsigned int mac_core_port)
{
    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(mac_core < MAX_MAC_CORES_PER_MAC_ISL);
    assert(mac_core_port < MAX_ETH_PORTS_PER_MAC_CORE);

    /* Set the MAC TX flush enable for the port. */
    issue_sync_me_cmd(mac_isl, mac_core, mac_core_port,
                      ARB_CODE_ETH_CMD_CFG_ENABLE_FLUSH, 0);

    return;
}


/* *** NBI TM Queue Enable/Disable Functions *** */

__intrinsic void
nbi_tm_disable_queue(unsigned int nbi_isl, unsigned int tm_q)
{
    uint32_t tm_q_cfg;
    uint32_t tm_q_cfg_addr;

    /* Check the parameters */
    assert(nbi_isl < MAX_NBI_ISLANDS_PER_NFP);
    assert(tm_q < MAX_TM_QUEUES_PER_NBI_ISL);

    /* Clear the NBI TM queue enable. */
    tm_q_cfg_addr  = NBI_TM_Q_CFG_ADDR(nbi_isl, tm_q);
    tm_q_cfg       = xpb_read(tm_q_cfg_addr);
    tm_q_cfg      &= ~NFP_NBI_TM_QUEUE_CONFIG_QUEUEENABLE;
    xpb_write(tm_q_cfg_addr, tm_q_cfg);
}


__intrinsic void
nbi_tm_enable_queue(unsigned int nbi_isl, unsigned int tm_q)
{
    uint32_t tm_q_cfg;
    uint32_t tm_q_cfg_addr;

    /* Check the parameters */
    assert(nbi_isl < MAX_NBI_ISLANDS_PER_NFP);
    assert(tm_q < MAX_TM_QUEUES_PER_NBI_ISL);

    /* Set the NBI TM queue enable. */
    tm_q_cfg_addr  = NBI_TM_Q_CFG_ADDR(nbi_isl, tm_q);
    tm_q_cfg       = xpb_read(tm_q_cfg_addr);
    tm_q_cfg      |= NFP_NBI_TM_QUEUE_CONFIG_QUEUEENABLE;
    xpb_write(tm_q_cfg_addr, tm_q_cfg);
}

