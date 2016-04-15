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
 * @file          lib/infra_basic/libinfra_basic.c
 * @brief         Functions to interface with the infrastructure blocks
 *
 * This file contains the interface to the infra structure blocks.  It
 * currently only defines the application side of the interface and
 * only provide the interface in MicroC.
 *
 * It's main purpose is to hide the details of receiving and transmitting
 * packets from the application code. Regardless of the source a packet is,
 * a generic RX descriptor is returned. Similarly a generic TX descriptor
 * is used to send to any destination.
 *
 */

/* Disable GRO if not explictly enabled */
#ifndef GRO_NUM_BLOCKS
#define GRO_NUM_BLOCKS      0
#endif

#ifndef GRO_CTX_PER_BLOCK
#define GRO_CTX_PER_BLOCK   8
#endif

#include <assert.h>
#include <nfp.h>
#include <stdint.h>

/* Library Includes */
#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp6000/nfp_me.h>
#include <std/reg_utils.h>

/* Blocks */
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>

/* TODO includes should be of the format <lib|block>/header */
#include <gro_cli.h>

#include <blm/blm.h>

#include <infra_basic/infra_basic.h>
#include <shared/nfd_common.h>

/* GRO can not run if we enable DMA drops */
#if (GRO_NUM_BLOCKS > 0 && defined NBI_DMA_BP_DROP_ENABLE)
    #if (NBI_DMA_BP_DROP_ENABLE != 0)
            #error "DMA DROP must be disabled when GRO is used"
    #endif
#endif

/*
 * Defines
 */

/* The smallest CTM buffer size that can be allocated is 256B */
#define MIN_CTM_TYPE        PKT_CTM_SIZE_256
#define MIN_CTM_SIZE        (256 << MIN_CTM_TYPE)

/* TODO - get at runtime, or at least load time. Can get per packet using
 * pkt_status_read or from DMA engine, see EAS DMA 2.2.4.6 NbiDmaBPCfg Reg */
#define CTM_SPLIT_LEN       3

/* Only support single NFD work queue */
#define NFD_IN_WQ           0

/* CTM credit management, required for RX from host. Use all of CTM RX */
#define MAX_CREDITS         255
#define CTM_ALLOC_ERR       0xffffffff

#define MIN(x, y)   (x > y) ? y : x

/* XXX assuming that isl 0 indicates that there is no CTM component
 *     (as NFD does)  */
#define PKT_HAS_CTM(pkt) (pkt.isl != 0)

#ifndef PCI
#define PCI                 0
#endif
#ifndef VNIC
#define VNIC                0
#endif
#ifndef NBI
#define NBI                 0
#endif

#define MAC_CHAN_PER_PORT   8
#define TMQ_PER_PORT        (MAC_CHAN_PER_PORT * 2 * 8)

#define MAC_TO_PORT(x)      (x / (MAC_CHAN_PER_PORT * 2))
#define PORT_TO_TMQ(x)      (x * TMQ_PER_PORT)

/*
 * Global variables
 */
__export __shared __cls struct ctm_pkt_credits ctm_credits =
    {MAX_CREDITS, MAX_CREDITS};


/*
 * Static Functions
 */

/**
 * Convert NBI RX descriptor to generic RX descriptor
 */
__intrinsic static void
nbirxd_to_rxd(__xread const struct nbi_meta_catamaran *nbi_ind,
              __nnr struct pkt_rx_desc *rxd)
{
    /* Ensure pkt_rx_desc is zero before populating it */
    reg_zero(rxd, sizeof(struct pkt_rx_desc));

    rxd->nbi = nbi_ind->pkt_info;
    rxd->seq = nbi_ind->seq;
    rxd->seqr = nbi_ind->seqr;

    rxd->src = MAC_TO_PORT(nbi_ind->port);
}

/**
 * Convert NFD RX descriptor to generic RX descriptor
 */
__intrinsic static void
nfdrxd_to_rxd(__xread const struct nfd_in_pkt_desc *nfd_rxd,
              __nnr struct pkt_rx_desc *rxd)
{
    /* Ensure pkt_rx_desc is zero before populating it */
    reg_zero(rxd, sizeof(struct pkt_rx_desc));

    nfd_in_fill_meta(&rxd->nbi, (__xread struct nfd_in_pkt_desc *)nfd_rxd);

    /* NFD TXD has 2 LW of application specific metadata */
    rxd->app0 = nfd_rxd->__raw[2];
    rxd->app1 = nfd_rxd->__raw[3];

    /* Sequence number and Sequencer */
    rxd->seqr = NFD_IN_WQ;
    rxd->seq = nfd_in_get_seqn((__xread struct nfd_in_pkt_desc *)nfd_rxd);

    /* Extract the queue */
    rxd->src = NFD_BMQ2NATQ(nfd_rxd->q_num);
}

/**
 * Convert generic TX descriptor to a GRO TX descriptor
 */
__intrinsic static void
txd_to_grotxd(__nnr const struct pkt_tx_desc *txd,
              __xwrite struct gro_meta_nfd3 *gro_meta,
              uint32_t nfd_q)
{
    __gpr struct nfd_out_input nfd_txd;

    reg_zero(&nfd_txd, sizeof(struct nfd_out_input));
    nfd_out_fill_desc(&nfd_txd, (void*)(&txd->nbi), 0, CTM_SPLIT_LEN,
                      PKT_NBI_OFFSET, 0);

    nfd_out_check_ctm_only(&nfd_txd);

    /* host metadata is the 2nd LW of nfd's rxd */
    nfd_txd.rxd.__raw[0] = txd->app0;
    nfd_txd.rxd.__raw[1] = txd->app1;

    /* add application set pkt offset to support CSUM, RSS */
    nfd_txd.cpp.offset += txd->offset;

    /* Build GRO meta out of the NFD OUT meta */
    gro_cli_nfd_desc2meta(gro_meta, (void *)&nfd_txd, PCI, nfd_q);
}

/**
 * Convert generic TX descriptor to NBI TX descriptor
 * (TM expects the NBI TX descriptor to be at the start of the CTM)
 */
__intrinsic static void
txd_to_nbitxd(__nnr const struct pkt_tx_desc *txd,
              __xwrite struct nbi_meta_pkt_info *nbi_txd)
{
    __addr40 void *ctm_ptr;

    ctm_ptr = pkt_ctm_ptr40(txd->nbi.isl, txd->nbi.pnum, 0);

    *nbi_txd = txd->nbi;
    mem_write64(nbi_txd, ctm_ptr, sizeof(struct nbi_meta_pkt_info));
}

__intrinsic static int
send_to_wire(__nnr struct pkt_tx_desc *txd)
{
    __nnr struct nbi_meta_pkt_info *pi = &(txd->nbi);
    __gpr struct pkt_ms_info msi;
    __addr40 void *mu_ptr;

    __xwrite struct nbi_meta_pkt_info nbi_txd;
    __addr40 void *ctm_ptr;
    __gpr uint32_t ctm_pnum;
    __gpr uint16_t pkt_off = PKT_NBI_OFFSET + txd->offset;
    __gpr uint16_t i;
    __gpr uint16_t cpy_end, cpy_start;
    __gpr enum PKT_CTM_SIZE ctm_buf_size;
    __xread pkt_status_t pkt_status;
    __xread uint64_t buf_xr[8];
    __xwrite uint64_t buf_xw[8];

    /*
     * Allocate CTM if required:
     * If there is no CTM component to this packet make one as this
     * is where TM looks for the buffer metadata and beginning of the
     * packet.
     *
     * To minimise the amount of data to be copied, the smallest CTM
     * packet size is allocated (256B).
     */
    if (PKT_HAS_CTM(txd->nbi) == 0) {

        /* Poll for a CTM packet until one is returned. */
        for (ctm_pnum = CTM_ALLOC_ERR; ctm_pnum == CTM_ALLOC_ERR;) {
            ctm_pnum = pkt_ctm_alloc(&ctm_credits, __ISLAND,
                                     MIN_CTM_TYPE, 0, 0);
        }

        /* TODO - find out if 64B is the most efficient way to copy */
        /* copy content of MU to CTM 64B at a time, starting at the closest
         * 64B boundary  */
        cpy_end = MIN(MIN_CTM_SIZE, pi->len + pkt_off);
        cpy_start = pkt_off & ~0x3F;
        for (i = cpy_start; i < cpy_end; i += sizeof(buf_xr)) {

            /* get a handle to both the mu and ctm pkt pointers */
            mu_ptr = (__addr40 void *)(((uint64_t)pi->muptr << 11) | i);
            ctm_ptr = pkt_ctm_ptr40(__ISLAND, ctm_pnum, i);

            mem_read64(buf_xr, mu_ptr, sizeof(buf_xr));
            reg_cp(buf_xw, buf_xr, sizeof(buf_xw));
            mem_write64(buf_xw, ctm_ptr, sizeof(buf_xw));
        }

        pi->isl = __ISLAND;
        pi->pnum = ctm_pnum;
        pi->split = (pi->len > (MIN_CTM_SIZE - pkt_off)) ? 1 : 0;

        ctm_buf_size = MIN_CTM_TYPE;
    } else {
        pkt_status_read(pi->isl, pi->pnum, &pkt_status);
        ctm_buf_size = pkt_status.size;
    }

    /* Prepare modification script: strip MAC prepend metadata if present */
    ctm_ptr = pkt_ctm_ptr40(pi->isl, pi->pnum, 0);

    /* Write the MAC egress CMD and adjust offset and len accordingly */
    pkt_mac_egress_cmd_write(ctm_ptr, pkt_off, txd->tx_l3_csum,
                             txd->tx_l4_csum);
    pkt_off -= 4;
    pi->len += 4;

    /* Write modification script to closest 8B aligned location at pkt_off */
    msi = pkt_msd_write(ctm_ptr, pkt_off);

    /* Prepare NBI TX metadata: */
    txd_to_nbitxd(txd, &nbi_txd);

    /* Send the packet (seqr and seq copied from the rxd in app) */
    pkt_nbi_send(pi->isl, pi->pnum, &msi, pi->len, NBI,
                 PORT_TO_TMQ(txd->dest), txd->seqr, txd->seq, ctm_buf_size);

    return 0;
}

__intrinsic static int
send_to_host(__nnr struct pkt_tx_desc *txd)
{
    __gpr int err = -1;
    uint32_t poll_count = 0;
    uint32_t nfd_q;
    __gpr uint32_t credit;
    __xwrite struct gro_meta_nfd3 gro_meta;

    nfd_q = nfd_out_map_queue(txd->vnic, txd->dest);
    while (1) {
        credit = nfd_out_get_credit(PCI, nfd_q, 1);
        if (credit)
            break;

        poll_count++;
        if (poll_count > txd->retry_count)
            break;
        ctx_swap();
    }

    /* Indicates the retries were exceeded, its time to give up */
    if (poll_count > txd->retry_count)
        goto out;

    /* Build a GRO descriptor */
    txd_to_grotxd(txd, &gro_meta, nfd_q);

    /* Use the ingress NBI sequencer as the GRO CTX number.
     * The sequencer coming from NBI is hard coded to 1-4 for good
     * packets while sequencer 0 is used for errors. Currently we do not
     * handle the error cases. */
    gro_cli_send((void *)&gro_meta, txd->seqr, txd->seq);
    err = 0; /* if we got here no errors were encountered */

out:
    return err;
}


/*
 * Public Functions
 */

__intrinsic __addr40 void*
pkt_ptr(__nnr const struct pkt_rx_desc *rxd, const unsigned int offset)
{
    __addr40 void *pkt_ptr;
    int abs_off = offset + PKT_NBI_OFFSET;

    /* offset needs to be a multiple of 64 */
    if(offset & 0x3F)
        halt();

    /* Pkt has CTM component and within CTM offset return CTM, else MU ptr */
    if (PKT_HAS_CTM(rxd->nbi) && abs_off < (256 << CTM_SPLIT_LEN))
        pkt_ptr = pkt_ctm_ptr40(rxd->nbi.isl, rxd->nbi.pnum,abs_off);
    else
        pkt_ptr = (__addr40 void *)(((uint64_t)rxd->nbi.muptr << 11)
                                    | abs_off);

    return pkt_ptr;
}

__intrinsic void
pkt_ptrs(__nnr const struct pkt_rx_desc *rxd, unsigned int *frame_off,
         __addr40 void **ctm_ptr, __addr40 void **mem_ptr)
{
    *frame_off = PKT_NBI_OFFSET;

    if (PKT_HAS_CTM(rxd->nbi)) {
        *ctm_ptr = pkt_ctm_ptr40(rxd->nbi.isl, rxd->nbi.pnum,
                                 PKT_NBI_OFFSET);
    } else {
        *ctm_ptr = 0;
    }

    *mem_ptr =
        (__addr40 void *)(((uint64_t)rxd->nbi.muptr << 11) | PKT_NBI_OFFSET);
}

__intrinsic uint32_t ctm_split()
{
    /* Find out how big this CTM buffer is.*/
    return CTM_SPLIT_LEN;
}

__intrinsic int16_t
pkt_len(__nnr const struct pkt_rx_desc *rxd)
{
    return rxd->nbi.len;
}

__intrinsic void
pkt_rx(enum infra_src src, __nnr struct pkt_rx_desc *rxd)
{
    __xread struct nbi_meta_catamaran nbi_rxd;

    SIGNAL nfd_rx_sig;
    __xread struct nfd_in_pkt_desc nfd_rxd;
    uint32_t nfd_q = NFD_IN_WQ;

    switch (src) {
    case FROM_WIRE:
        pkt_nbi_recv(&nbi_rxd, sizeof(nbi_rxd));
        nbirxd_to_rxd(&nbi_rxd, rxd);
        break;

    case FROM_HOST:
        __nfd_in_recv(PCI, nfd_q, &nfd_rxd, sig_done, &nfd_rx_sig);
        wait_for_all(&nfd_rx_sig);
        nfdrxd_to_rxd(&nfd_rxd, rxd);
        break;

    /* unsupported modes */
    default:
        halt();
    }
}

__intrinsic int
pkt_tx(enum infra_dst dst, __nnr struct pkt_tx_desc *txd)
{
    __gpr int err = 0;

    __nnr struct nbi_meta_pkt_info *pi = &(txd->nbi);
    __gpr enum PKT_CTM_SIZE ctm_buf_size;
    __addr40 void *mu_ptr;
    __xwrite struct gro_meta_drop drop_meta;
    __gpr struct pkt_ms_info msi = {0,0}; /* dummy msi for wire RX failures */

    switch (dst) {
    case TO_WIRE:
        err = send_to_wire(txd);
        break;

    case TO_HOST:
        err = send_to_host(txd);
        break;

    case TO_WIRE_DROP:
        /* Notify the NBI to ignore the packets sequence number */
        ctm_buf_size = MIN_CTM_TYPE;
        pkt_nbi_drop_seq(pi->isl, pi->pnum, &msi, pi->len, 0, 0,
                         txd->seqr, txd->seq, ctm_buf_size);

        /* Free the pkt by releasing the CTM and MU */
        if (PKT_HAS_CTM(txd->nbi))
            pkt_ctm_free(pi->isl, pi->pnum);
        mu_ptr = (__addr40 void *)((uint64_t)pi->muptr << 11);
        blm_buf_free(blm_buf_ptr2handle(mu_ptr), pi->bls);
        break;

    case TO_HOST_DROP:
        /* Tell GRO to skip the packets sequence number and drop pkt's CTM */
        gro_cli_build_drop_ctm_buf_meta(&drop_meta, pi->isl, pi->pnum);
        gro_cli_send((void *)&drop_meta, txd->seqr, txd->seq);

        /* GRO frees the pkt's CTM for us, so just cleanup MU component */
        mu_ptr = (__addr40 void *)((uint64_t)pi->muptr << 11);
        blm_buf_free(blm_buf_ptr2handle(mu_ptr), pi->bls);

        break;

    /* unsupported modes */
    default:
        halt();
    }

out:
    return err;
}

void
reinit_tx(const enum infra_dst dst)
{
    /* Reinitialise the packet destination */
    switch (dst) {
    case TO_WIRE:
        break;

    case TO_HOST:
        break;

    default:
        halt();
    }
}

void
init_rx(const enum infra_src src)
{
    /* Give the packet source an opportunity to be initialised if required */
    switch (src) {
    case FROM_WIRE:
        break;

    case FROM_HOST:
        nfd_in_recv_init();
        break;

    default:
        halt();
    }
}

void
init_tx(const enum infra_dst dst)
{
    /* Give the packet destination an opportunity to be initialised */
    switch (dst) {
    case TO_WIRE:
        break;

    case TO_HOST:
        nfd_out_send_init();
        gro_cli_init();
        break;

    default:
        halt();
    }
}

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
