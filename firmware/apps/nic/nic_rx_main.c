/*
 * Copyright 2015 Netronome, Inc.
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
 * @file          apps/nic/nic_rx_main.c
 * @brief         Receive from wire send to host main NIC application
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
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>

#include "nfd_user_cfg.h"
#include "nic.h"

/* default options */
#ifndef CFG_RX_CSUM_PREPEND
#error "Assumes that RX Checksum offload is defined"
#endif


/* Global variable for the header cache.  If this is declared locally,
 * the compiler register allocator barfs on running out of registers
 * for some reason... */
__lmem struct pkt_hdrs hdrs;
__lmem struct pkt_encap encap;

__intrinsic void static
build_txd(__nnr const struct pkt_rx_desc *rxd,
          __nnr struct pkt_tx_desc *txd,
          __gpr uint16_t len,
          __gpr int16_t offset,
          uint8_t qid, unsigned int vnic)
{
    /* Various fields from TX desc come directly from RX desc */
    txd->nbi = rxd->nbi;
    txd->seqr = rxd->seqr;
    txd->seq = rxd->seq;

    /* Update the start and length of the packet after all modifications */
    txd->offset = offset;
    txd->nbi.len = len;

    /*
     * Fields used when sending to host
     */
    /* Copy over application metadata, used when sending to host */
    txd->app0 = rxd->app0;
    txd->app1 = rxd->app1;

    /* Copy the RSS queue selected */
    txd->dest = qid;

    txd->vnic = vnic;

    /* try send pkt once then give up*/
    txd->retry_count = 0;
}

__intrinsic static int8_t
proc_from_wire(int port,
               __nnr struct pkt_rx_desc *rxd,
               __nnr struct pkt_tx_desc *txd)
{
    /*
     * pkt_start holds the CTM address that is the start of the packet
     * including MAC_PREPEND_BYTES. To get the start of the pkt data, do
     * pkt_start + MAC_PREPEND_BYTES. pkt_cache stores a window of the pkt
     * that is of current interest.
     */
    __addr40 char *pkt_start;
    __xread uint32_t pkt_cache[16];
    __gpr int16_t offset, plen;
    uint32_t qid;

    __gpr uint32_t csum_prepend;
    __gpr uint8_t err, ret;
    __gpr uint16_t vlan;
    __gpr int rss_flags;
    __gpr uint32_t hash, hash_type;
    __gpr int unused, vport;
    __xwrite uint32_t tmp[2];
    __gpr uint64_t out_vport_mask;
    void *app_meta;
    /* use temporary rxd in __gpr for app_meta only */
    __gpr struct pkt_rx_desc rxd_tmp;
    __lmem uint16_t *vxlan_ports;
    __lmem void *sa, *da;

    reg_cp(&rxd_tmp, (void *) rxd, sizeof(struct pkt_rx_desc));
    app_meta = (void*)&(rxd_tmp.app0);

    /* Ensure local variables are zero before populating them */
    reg_zero(txd, sizeof(struct pkt_tx_desc));
    plen = pkt_len(rxd);
    offset = 0;

    /* Check if interface is up as well MTU */
    err = nic_rx_l1_checks(port);
    if (err == NIC_RX_DROP)
        goto err_out;

    /* Read first batch of bytes from the start of packet. Align the
     * potential IP header in the packet to a word boundary by start
     * reading from the start of packet. */
    pkt_start = pkt_ptr(rxd, offset);
    mem_read64(pkt_cache, pkt_start - PKT_START_OFF, sizeof(pkt_cache));

    /* read the MAC parsing info for CSUM (first 4B are timestamp) */
    csum_prepend = pkt_csum_read(pkt_cache, PKT_START_OFF + 4);

    /* MTU check */
    err = nic_rx_mtu_check(port, csum_prepend, plen - MAC_PREPEND_BYTES);
    if (err == NIC_RX_DROP)
        goto err_out;

    NIC_APP_DBG_APP(nic_app_dbg_journal, 0x1234);
    NIC_APP_DBG_APP(nic_app_dbg_journal, csum_prepend);

    /* Checksum checks. */
    err = nic_rx_csum_checks(port, csum_prepend, app_meta);
    if (err == NIC_RX_DROP)
        goto err_out;

    /* Strip the CSUM and timestamp prepend, this is not transferred to host */
    offset += MAC_PREPEND_BYTES;
    plen -= MAC_PREPEND_BYTES;

    /* If there was a checksum error but we are in promisc mode, ie
     * nic_rx_csum_checks() returned NIC_RX_CSUM_BAD, don't parse
     * the packet.  It might be garbage. */
    if (err == NIC_RX_CSUM_BAD)
        goto pkt_out;

    vxlan_ports = nic_rx_vxlan_ports();

    /* Parse/Extract the header fields we are interested in */
    pkt_hdrs_read(pkt_start, offset,
                  pkt_cache, offset + PKT_START_OFF, &hdrs, &encap, 0,
                  vxlan_ports);
    /* Perform checks & filtering */
    err = nic_rx_l2_checks(port, &hdrs.o_eth.src, &hdrs.o_eth.dst);
    if (err)
        goto err_out;

    ret = rx_check_inner_csum(port, &hdrs, &encap, rxd, app_meta, csum_prepend);
    if (ret == NIC_RX_DROP) {
        if (nic_rx_promisc(port)) {
            err = NIC_RX_CSUM_BAD;
            goto pkt_out;
        } else {
            err = NIC_RX_DROP;
            goto err_out;
        }
    }


    /* Strip VLAN if present and configured.
     * Copy the Ethernet Type, move the Ethernet header by
     * NET_8021Q_LEN, remove VLAN header, mark the Ethernet header
     * as dirty, and adjust the meta data. */
    vlan = 0;
    if (hdrs.present & HDR_O_VLAN) {

        vlan = NET_ETH_TCI_VID_of(hdrs.o_vlan.tci);

        ret = nic_rx_vlan_strip(port, hdrs.o_vlan.tci, app_meta);
        if (ret) {
            hdrs.o_eth.type = hdrs.o_vlan.type;
            hdrs.offsets[HDR_OFF_O_ETH] += NET_8021Q_LEN;
            hdrs.present &= ~HDR_O_VLAN;
            hdrs.dirty |= HDR_O_ETH;

            offset += NET_8021Q_LEN;
            plen -= NET_8021Q_LEN;
            NIC_APP_CNTR(&nic_cnt_rx_vlan);
        }
    }

    if (hdrs.present & (HDR_E_NVGRE | HDR_E_VXLAN) &&
        hdrs.present & HDR_I_ETH) {
        sa = &hdrs.i_eth.src;
        da = &hdrs.i_eth.dst;
    } else {
        sa = &hdrs.o_eth.src;
        da = &hdrs.o_eth.dst;
    }
    
    out_vport_mask = nic_switch(NIC_SWITCH_UPLINK, sa, da, vlan, &unused);
    
    if (!out_vport_mask) {
        err = NIC_RX_DROP;
        NIC_APP_CNTR(&nic_cnt_rx_sw_drop);
        goto err_out;
    }
    
    /* XXX assume for now only one VPort is returned */
    vport = ffs64(out_vport_mask);
    
    /* RSS */
    rss_flags = 0;
    if (hdrs.present & HDR_O_IP4)
        rss_flags |= NIC_RSS_IP4;
    if (hdrs.present & HDR_O_IP6)
        rss_flags |= NIC_RSS_IP6;
    if (hdrs.present & HDR_O_TCP)
        rss_flags |= NIC_RSS_TCP;
    if (hdrs.present & HDR_O_UDP)
        rss_flags |= NIC_RSS_UDP;
    if (hdrs.present & HDR_E_NVGRE)
        rss_flags |= NIC_RSS_NVGRE;
    if (hdrs.present & HDR_E_VXLAN)
        rss_flags |= NIC_RSS_VXLAN;
    if ((hdrs.present & HDR_E_NVGRE) || (hdrs.present & HDR_E_VXLAN)) {
        if (hdrs.present & HDR_I_IP4)
            rss_flags |= NIC_RSS_I_IP4;
        if (hdrs.present & HDR_I_IP6)
            rss_flags |= NIC_RSS_I_IP6;
        if (hdrs.present & HDR_I_TCP)
            rss_flags |= NIC_RSS_I_TCP;
        if (hdrs.present & HDR_I_UDP)
            rss_flags |= NIC_RSS_I_UDP;
    }
    
    /* o_ip4/o_ip6 are at the same location so is o_udp, o_tcp */
    hash = nic_rx_rss(port, &hdrs.o_ip4, &hdrs.o_tcp,
                      &hdrs.i_ip4, &hdrs.i_tcp, rss_flags,
                      &hash_type, app_meta, &qid);
    if (hash_type) {
        /* Write Hash value in front of the packet */
        offset -= sizeof(tmp);
        plen += sizeof(tmp);
        tmp[0] = hash_type;
        tmp[1] = hash;
        mem_write8(&tmp, (void *)(pkt_start + offset), sizeof(tmp));
    } else {
        err = nic_switch_rx_defaultq(vport, &qid);
        if (err != NIC_RX_OK)
            goto err_out;
    }

pkt_out:
    /* Flush dirty header to buffer */
    pkt_hdrs_write_back(pkt_start, &hdrs, &encap);

err_out:
    if (err != NIC_RX_DROP) {
        nic_rx_ring_cntrs(app_meta, plen, qid);
    }
    /* XXX do we need to cnt pkt and populate all metadata on drop path? */
    nic_rx_cntrs(port, &hdrs.o_eth.dst, plen);
    nic_rx_finalise_meta(app_meta, plen);
    /* copy back to rxd */
    reg_cp((void *)rxd, &rxd_tmp, sizeof(struct pkt_rx_desc));
    build_txd(rxd, txd, plen, offset, qid, port);
    return err;
}

void
main()
{
    /* This application ME handles packet received from the WIRE and sent to
     * the HOST.
     * */

    __gpr uint32_t ctxs;
    __nnr struct pkt_rx_desc rxd;
    __nnr struct pkt_tx_desc txd;
    uint32_t enable_changed;

    __gpr int8_t ret;

    /* Configuration and initialization */
    if (ctx() == 0) {
        /* disable all other contexts */
        ctxs = local_csr_read(local_csr_ctx_enables);
        ctxs &= ~NFP_MECSR_CTX_ENABLES_CONTEXTS(0xfe);
        local_csr_write(local_csr_ctx_enables, ctxs);

        init_rx(FROM_WIRE);
        init_tx(TO_HOST);
        nic_local_init(APP_ME_CONFIG_SIGNAL_NUM, APP_ME_CONFIG_XFER_NUM);

#ifdef CFG_NIC_APP_DBG_JOURNAL
        /* XXX This is initialised by every app ME. Fixit! */
        INIT_JOURNAL(nic_app_dbg_journal);
#endif
        reinit_tx(TO_HOST);

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

    /* CTX 0 sole purpose is to service config changes */
    if (ctx() == 0) {
        for (;;) {
            /* Check for BAR Configuration changes and reinit TX if needed */
            if (nic_local_cfg_changed()) {

                nic_local_reconfig(&enable_changed);
                if (enable_changed) {
                    reinit_tx(TO_HOST);
                }
                nic_local_reconfig_done();
            }

            ctx_swap();
        }
    }

    /* Work is performed by non CTX 0 threads */
    for (;;) {
        /* Receive a packet from the wire */
        pkt_rx(FROM_WIRE, &rxd);

        /* Do RX processing on packet and populate the TX descriptor */
        ret = proc_from_wire(rxd.src, &rxd, &txd);
        if (ret == NIC_RX_DROP) {
            pkt_tx(TO_HOST_DROP, &txd);
            nic_rx_discard_cntr(NIC_INTF);
            continue;
        }

        /* Attempt to send and drop if we encountered an error */
        ret = pkt_tx(TO_HOST, &txd);
        if (ret) {
            pkt_tx(TO_HOST_DROP, &txd);
            nic_rx_discard_cntr(NIC_INTF);
            continue;
        }
    }
}

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
