/*
 * Copyright 2015 Netronome, Inc.
 *
 * @file          apps/nic/nic_tx_main.c
 * @brief         Receive from host send to wire main NIC application
 *
 * This application simply presents the two Ethernet ports of a NFE
 * card as NIC endpoints to the host.
 */

/* Flowenv */
#include <nfp.h>
#include <stdint.h>

#include <nfp/me.h>
#include <nfp6000/nfp_me.h>
#include <nfp/mem_bulk.h>
#include <std/reg_utils.h>

#include <infra_basic/infra_basic.h>
#include <nic_basic/nic_basic.h>
#include <nic_basic/pcie_desc.h>

#include <vnic/shared/nfd_cfg.h>
#include <vnic/shared/nfd_internal.h>
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>

#include "nfd_user_cfg.h"
#include "nic.h"
#include "app_config_tables.h"

/* default options */
#ifndef CFG_RX_CSUM_PREPEND
#error "Assumes that RX Checksum offload is defined"
#endif

/* Global variable for the header cache.  If this is declared locally,
 * the compiler register allocator barfs on running out of registers
 * for some reason... */
__lmem struct pkt_hdrs hdrs;
__lmem struct pkt_encap encap;

#ifdef NFD_IN_LSO_CNTR_ENABLE
static unsigned int nfd_in_lso_cntr_addr = 0;
#endif

/**
 * Transmit processing
 *
 * @param port   Port where the pkt is destined to
 *
 * Packet arrive from the Host and is going to the network.  Note that
 * by using libinfra there is an implicit "struct pkt_meta Pkt"
 */
__intrinsic static int8_t
proc_from_host(int port)
{
    /* pkt_start holds the CTM address that is the start of the packet
     * including MAC_PREPEND_BYTES. To get the start of the pkt data, do
     * pkt_start + MAC_PREPEND_BYTES. pkt_cache stores a window of the pkt
     * that is of current interest.
     */
    __addr40 char *pkt_start;
    __xread uint32_t pkt_cache[16];
    __gpr int32_t offset, plen;

    __gpr uint8_t err, ret;
    unsigned int tx_l3_csum, tx_l4_csum, tunnel;

    __gpr uint16_t tci;

    __gpr uint16_t vlan;
    __gpr int uplink;
    void *app_meta;
    __gpr struct tx_tsk_config offload_cfg;
    struct pcie_in_nfp_desc *in_desc;
    __lmem void *sa, *da;

    app_meta = (void *)&(Pkt.app0);

    reg_zero(&offload_cfg, sizeof(struct tx_tsk_config));
    plen = Pkt.p_orig_len;
    offset = 0;

    NFD_IN_LSO_CNTR_INCR(nfd_in_lso_cntr_addr,
                         NFD_IN_LSO_CNTR_T_ME_ALL_HOST_PKTS);
#ifdef NFD_IN_LSO_CNTR_ENABLE
    in_desc = (struct pcie_in_nfp_desc *)app_meta;

    if (in_desc->flags & PCIE_DESC_TX_LSO) {
        NFD_IN_LSO_CNTR_INCR(nfd_in_lso_cntr_addr,
                             NFD_IN_LSO_CNTR_T_ME_LSO_HOST_PKTS);
        if (in_desc->lso_end) {
            NFD_IN_LSO_CNTR_INCR(nfd_in_lso_cntr_addr,
                                 NFD_IN_LSO_CNTR_T_ME_LAST_LSO_HOST_PKTS);
        }
    }
    else {
        NFD_IN_LSO_CNTR_INCR(nfd_in_lso_cntr_addr,
                             NFD_IN_LSO_CNTR_T_ME_NON_LSO_HOST_PKTS);
    }
#endif

    NIC_APP_CNTR(&nic_cnt_tx_from_host);
    nic_tx_ring_cntrs(app_meta, PKT_PORT_SUBSYS_of(Pkt.p_src),
                      PKT_PORT_QUEUE_of(Pkt.p_src));

    /* No L1 checks as in RX */

    /* Read first batch of bytes from the start of packet. Align the
     * potential IP header in the packet to a word boundary by start
     * reading from the start of packet. */
    pkt_start = pkt_ptr(0);
    mem_read64(pkt_cache, pkt_start - PKT_START_OFF, sizeof(pkt_cache));

    tunnel = nic_tx_encap(app_meta);

    /* Parse/Extract the header fields we are interested in */
    pkt_hdrs_read(pkt_start, offset,
                  pkt_cache, offset + PKT_START_OFF, &hdrs, &encap, tunnel, 0);

    /* This might be a redundant test, the host might always enforce this.
     * A theoretical case is the transient period when MTU is lowered, since
     * FW should be updated before netdev pkts inflight might exceed MTU. But
     * do we care since this is transient?
     */
    err = nic_tx_mtu_check(port, hdrs.present & HDR_O_VLAN, plen);
    if (err == NIC_TX_DROP)
        goto err_out;

    /* Perform LSO if requested */
    err = tx_tsk_fixup(&hdrs, app_meta, &offload_cfg);
    if (err == NIC_TX_DROP)
        goto err_out;

    if (hdrs.dirty & HDR_O_IP4)
        Pkt.p_tx_l3_csum = 1;
    if (hdrs.dirty & HDR_O_TCP && hdrs.o_tcp.sum)
        Pkt.p_tx_l4_csum = 1;
    if (hdrs.dirty & HDR_O_UDP && hdrs.o_udp.sum)
        Pkt.p_tx_l4_csum = 1;

    err = tx_tsk_set_ipv4_csum(&hdrs, app_meta);
    if (err == NIC_TX_DROP)
        goto err_out;

    err = tx_tsk_set_l4_csum(&hdrs, app_meta);
    if (err == NIC_TX_DROP)
        goto err_out;

    /* Add a vlan if requested in the TX descriptor.
     * Fill in VLAN header, indicate VLAN tag presence in Ethernet
     * header, adjust offsets and VLAN presence, mark Ethernet and
     * VLAN header dirty, and adjust meta data.
     *
     * Note, we *assume* that there is space in front of the packet! */
    ret = nic_tx_vlan_add(port, app_meta, &tci);
    if (ret) {
        hdrs.o_vlan.type = hdrs.o_eth.type;
        hdrs.o_vlan.tci = tci;
        hdrs.o_eth.type = NET_ETH_TYPE_TPID;

        hdrs.offsets[HDR_OFF_O_ETH] -= NET_8021Q_LEN;
        hdrs.offsets[HDR_OFF_O_VLAN] =
            hdrs.offsets[HDR_OFF_O_ETH] + NET_ETH_LEN;

        hdrs.present |= HDR_O_VLAN;
        hdrs.dirty |= (HDR_O_ETH | HDR_O_VLAN);

        offset -= NET_8021Q_LEN;
        plen += NET_8021Q_LEN;
        NIC_APP_CNTR(&nic_cnt_tx_vlan);
    }

    vlan = (hdrs.present & HDR_O_VLAN) ?
        NET_ETH_TCI_VID_of(hdrs.o_vlan.tci) : 0;

    if (hdrs.present & (HDR_E_NVGRE | HDR_E_VXLAN) &&
        hdrs.present & HDR_I_ETH) {
        sa = &hdrs.i_eth.src;
        da = &hdrs.i_eth.dst;
    } else {
        sa = &hdrs.o_eth.src;
        da = &hdrs.o_eth.dst;
    }

    /* Checksum offload */
    nic_tx_csum_offload(port, app_meta, &tx_l3_csum, &tx_l4_csum);
    if (tx_l3_csum)
        Pkt.p_tx_l3_csum = 1;
    if (tx_l4_csum)
        Pkt.p_tx_l4_csum = 1;

pkt_out:
    pkt_hdrs_write_back(pkt_start, &hdrs, &encap);
err_out:
    Pkt.p_len = plen;
    Pkt.p_offset += offset;
    Pkt.p_dst = PKT_WIRE_PORT(0, port);
    Pkt.p_is_gro_sequenced = 0;
    nic_tx_cntrs(port, &hdrs.o_eth.dst, plen);

    return err;
}

void
main()
{
    /* This application ME handles packet received from the HOST and sent to
     * the WIRE.
     * */

    __gpr uint32_t ctxs;
    __gpr uint32_t port;
    uint32_t enable_changed;

    __gpr int8_t ret;

    /* Configuration and initialization */
    if (ctx() == 0) {
        /* disable all other contexts */
        ctxs = local_csr_read(local_csr_ctx_enables);
        ctxs &= ~NFP_MECSR_CTX_ENABLES_CONTEXTS(0xfe);
        /* enable NN receive config from CTM  */
        ctxs &= ~0x000007;
        ctxs |= 0x02;
        local_csr_write(local_csr_ctx_enables, ctxs);

        init_tx();
        nic_local_init(APP_ME_CONFIG_SIGNAL_NUM, APP_ME_CONFIG_XFER_NUM);

#ifdef CFG_NIC_APP_DBG_JOURNAL
        /* XXX This is initialised by every app ME. Fixit! */
        INIT_JOURNAL(nic_app_dbg_journal);
#endif

        /* reenable all other contexts */
        ctxs = local_csr_read(local_csr_ctx_enables);
        ctxs |= NFP_MECSR_CTX_ENABLES_CONTEXTS(0xff);
        local_csr_write(local_csr_ctx_enables, ctxs);
    } else {
        /* Other threads. Bruce does 3 ctx_arb here. Not sure why */
        ctx_wait(voluntary);
        ctx_wait(voluntary);
        ctx_wait(voluntary);
    }

#ifdef NFD_IN_LSO_CNTR_ENABLE
    /* get the location of LSO statistics */
    if (nfd_in_lso_cntr_addr == 0) {
        nfd_in_lso_cntr_addr = cntr64_get_addr((__mem void *)nfd_in_lso_cntrs);
    }
#endif

    /* CTX 0 sole purpose is to service config changes */
    if (ctx() == 0) {
        for (;;) {
            /* Check for BAR Configuration changes and reinit TX if needed */
            if (nic_local_cfg_changed()) {
                nic_local_reconfig(&enable_changed);
                nic_local_reconfig_done();
            }

            ctx_swap();
        }
    }

    /* Work is performed by non CTX 0 threads */
    for (;;) {
        ret = pkt_rx_host();
        if (ret < 0) {
            Pkt.p_dst = PKT_DROP_WIRE;
            goto send_packet;
        } else {
            __critical_path();
        }
#if NS_PLATFORM_NUM_PORTS > 1
        port = PKT_PORT_QUEUE_of(Pkt.p_src) / NFD_MAX_PF_QUEUES;
#else
        port = 0;
#endif

        /* Do TX processing on packet and populate the TX descriptor */
        ret = proc_from_host(port);
        if (ret) {
            NFD_IN_LSO_CNTR_INCR(nfd_in_lso_cntr_addr,
                          NFD_IN_LSO_CNTR_T_ME_FM_HOST_PROC_TO_WIRE_DROP);
            Pkt.p_dst = PKT_DROP_WIRE;
            nic_tx_discard_cntr(port);
        }

    send_packet:
        /* Send the packet to wire */
        pkt_tx();
        NFD_IN_LSO_CNTR_INCR(nfd_in_lso_cntr_addr,
                             NFD_IN_LSO_CNTR_T_ME_FM_HOST_PKT_TX_TO_WIRE);
    }
}

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
