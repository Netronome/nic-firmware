/*
 * Copyright 2015-2016 Netronome Systems, Inc. All rights reserved.
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
 * SPDX-License-Identifier: BSD-2-Clause
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
#include <platform.h>
#include <stdint.h>

/* Library Includes */
#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp/cls.h>
#include <nfp6000/nfp_me.h>
#include <std/cntrs.h>
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

/* Debug counters */
#define INFRA_CNTR_RX_FROM_WIRE         0
#define INFRA_CNTR_ERR_FROM_WIRE        1
#define INFRA_CNTR_RX_FROM_HOST         2
#define INFRA_CNTR_ERR_FROM_HOST        3
#define INFRA_CNTR_TX_TO_WIRE_DROP      4
#define INFRA_CNTR_TX_TO_WIRE           5
#define INFRA_CNTR_TX_TO_HOST           6
#define INFRA_CNTR_TX_TO_HOST_DROP      7
#define INFRA_CNTR_ERR_TO_HOST          8

#ifdef INFRA_CNTRS_ENABLE
__shared __gpr uint32_t infra_cntrs_base;
    CNTRS64_DECLARE(vr_infra_dbg_cntrs, 32, __emem);
    #define INFRA_CNTR_INC(_cntr) \
                    cntr64_incr(infra_cntrs_base, _cntr)
    #define INFRA_CNTRS_SET_BASE(_base)  \
                    (_base) = cntr64_get_addr(vr_infra_dbg_cntrs)
#else
    #define INFRA_CNTR_INC(_cntr)
    #define INFRA_CNTRS_SET_BASE(_base)
#endif

#if VR_DEBUG
DBG_JOURNAL_DECLARE(infra_journal);
#define IDBG(_x) JDBG(infra_journal, _x)
#define IDBG_TYPE(_type, _x) JDBG_TYPE(infra_journal, _type, _x)
#else /* VR_DEBUG */
#define IDBG(_val)
#define IDBG_TYPE(_type, _x)
#endif /* VR_DEBUG */

struct pkt_handle {
    union {
        struct {
            uint8_t ph_isl;
            uint8_t pad;
            uint16_t ph_pnum;
        };
        uint32_t __raw;
    };
};


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
#define ME_CTM_ALLOC_MAX_BUF_CREDITS    64
#define ME_CTM_ALLOC_MAX_PKT_CREDITS    256
#define CTM_ALLOC_ERR                   0xffffffff

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

/*
 * Global variables
 */
INFRA_STATE_TYPE struct pkt_meta Pkt;

__export __shared __cls struct ctm_pkt_credits ctm_credits =
    {ME_CTM_ALLOC_MAX_PKT_CREDITS, ME_CTM_ALLOC_MAX_BUF_CREDITS};


/*
 * Static Functions
 */

/* The table that holds the indirect modification scripts per packet
 * offset.
 * This table is declared and initialized in "init_pms.uc".
 */
#include "pms_decl.c"   /* declares PM_DEL_SCRIPTS */

/* Some definitions */
#define PMS_STRUCT_SIZE_LW              4
#define PMS_STRUCT_SIZE                 (PMS_STRUCT_SIZE_LW << 2)

#if (__REVISION_MIN < __REVISION_B0)
    #define PMS_SCRIPT_OFS_MIN      8       // Length field = 0
    #define PMS_SCRIPT_OFS_MAX      56      // Length field = 6
#elif (__REVISION_MIN < __REVISION_C0)
    #define PMS_SCRIPT_OFS_MIN      32      // Length field = 3
    #define PMS_SCRIPT_OFS_MAX      120     // Length field = 14
#else
    #warning "Unsupported chip revision" __REVISION_MIN __REVISION_MAX
#endif
#define PMS_DEL_PKT_OFS_MIN     (PMS_SCRIPT_OFS_MIN + 8)
#define PMS_DEL_PKT_OFS_MAX     (PMS_SCRIPT_OFS_MAX + (7 * 16) + 16)
#define PMS_DEL_PKT_OFS_STEP    2

__intrinsic static uint32_t
__pkt_pms_write(__addr40 void *ctm_base, uint32_t pkt_offset,
                __xwrite uint32_t script_wr[PMS_STRUCT_SIZE_LW], SIGNAL *sig,
                __xread uint32_t *readback, SIGNAL *sig2)
{
    __xread uint32_t script_rd[PMS_STRUCT_SIZE_LW];
    uint32_t script_offset;
    uint32_t out_pms_offset;
    uint32_t len0;
    __addr40 char *base;
    __cls char *script_base = (__cls char *)PM_DEL_SCRIPTS;

    // Rebase packet offset and test lower boundary
    pkt_offset = pkt_offset - PMS_DEL_PKT_OFS_MIN;

    script_base += (PMS_STRUCT_SIZE * pkt_offset / PMS_DEL_PKT_OFS_STEP);

    cls_read(script_rd, script_base, PMS_STRUCT_SIZE);

    /* TODO , use reg_cp ?*/
    script_wr[0] = script_rd[0];
    script_wr[1] = script_rd[1];
    script_wr[2] = script_rd[2];
    script_wr[3] = script_rd[3];
    //reg_cp(script, script, sizeof(script));

    //#define PMS_STRUCT_PREPEND_OFS_bf       3, 7, 0     // Max offset for B0 is 120
    out_pms_offset = script_rd[3] & 0xFF;

    //#define PMS_STRUCT_PREPEND_LEN0_bf      3, 9, 8     // Zero based ref_cnt
    len0 = (script_rd[3] >> 8) & 0x3;

    base = (char *)ctm_base + out_pms_offset;
    __mem_write32(script_wr, base, (len0+1) * sizeof(uint32_t),
                  PMS_STRUCT_SIZE, sig_done, sig);
    __mem_read32(readback, base, sizeof(uint32_t), sizeof(uint32_t), sig_done,
                 sig2);

    return out_pms_offset;
}

/*
 * Public Functions
 */

__intrinsic __addr40 void*
pkt_ptr(const unsigned int offset)
{
    __addr40 void *pkt_ptr;
    unsigned abs_off = offset + Pkt.p_offset;

    /* Pkt has CTM component and within CTM offset return CTM, else MU ptr */
    if (abs_off < (256 << Pkt.p_ctm_sz))
        pkt_ptr = pkt_ctm_ptr40(Pkt.p_isl, Pkt.p_pnum, abs_off);
    else
        pkt_ptr = (__addr40 void *)(((uint64_t)Pkt.p_muptr << 11) + abs_off);

    return pkt_ptr;
}

__intrinsic void
pkt_ptrs(unsigned int *frame_off, __addr40 void **ctm_ptr,
        __addr40 void **mem_ptr, const unsigned int offset)
{
    unsigned int abs_off = offset + Pkt.p_offset;
    *frame_off = abs_off;

    /* Pkt has CTM component and within CTM offset return CTM, else MU ptr */
    if (abs_off < (256 << Pkt.p_ctm_sz))
        *ctm_ptr = pkt_ctm_ptr40(Pkt.p_isl, Pkt.p_pnum, abs_off);
    else
        *ctm_ptr = 0;

    *mem_ptr = (__addr40 void *)(((uint64_t)Pkt.p_muptr << 11) + abs_off);
}

__intrinsic uint32_t ctm_split()
{
    /* Find out how big this CTM buffer is.*/
    return CTM_SPLIT_LEN;
}

__intrinsic int
pkt_rx_wire(void)
{
    __xread struct nbi_meta_catamaran nbi_rxd;
    __xread pkt_status_t status;
    int ret = 0;

    pkt_nbi_recv(&nbi_rxd, sizeof(nbi_rxd));
    reg_zero((void *)Pkt.__raw, sizeof(Pkt));
    Pkt.p_seq = nbi_rxd.seq;
    Pkt.p_offset = PKT_NBI_OFFSET;
    Pkt.p_nbi = nbi_rxd.pkt_info;
    Pkt.p_src = PKT_WIRE_PORT(nbi_rxd.meta_type, nbi_rxd.port);
    /* map NBI seqr's 1/2/3/4 to GRO 1/3/5/7 */
    pkt_status_read(0, Pkt.p_pnum, &status);
    Pkt.p_ctm_sz = status.size;

    if (nbi_rxd.seqr != 0) {
        /* pkt is not malformed */
        __critical_path();
        Pkt.p_ro_ctx = (nbi_rxd.seqr << 1) - 1;
        Pkt.p_is_gro_sequenced = 1;
    }

    Pkt.p_orig_len = Pkt.p_len;

    if (nbi_rxd.ie) {
        INFRA_CNTR_INC(INFRA_CNTR_ERR_FROM_WIRE);
        ret = -1;
    } else {
        INFRA_CNTR_INC(INFRA_CNTR_RX_FROM_WIRE);
        __critical_path();
    }

    return ret;
}


__intrinsic int
pkt_rx_host(void)
{
    uint32_t ctm_pnum;
    __xread struct nfd_in_pkt_desc nfd_rxd;
    __xread uint64_t buf_xr[8];
    __xwrite uint64_t buf_xw[8];
    uint16_t i, cpy_end, cpy_start;
    __addr40 void *ctm_ptr;
    __addr40 void *mu_ptr;
    int ret = 0;

    /* First allocate a CTM, this is where TM looks for the buffer
     * metadata and beginning of the packet.  To minimise the amount
     * of data that has to be copied, the smallest CTM packet size
     * is allocated (256B). */

    /* Poll for a CTM packet until one is returned.  Note, if we never
     * get one the thread hangs but nothing is in-process yet anyway,
     * which is why we do this before actually receiving the packet. */
    for (ctm_pnum = CTM_ALLOC_ERR; ctm_pnum == CTM_ALLOC_ERR;)
        ctm_pnum = pkt_ctm_alloc(&ctm_credits, __ISLAND, MIN_CTM_TYPE, 1, 1);

    /* now receive the next packet from host */
    nfd_in_recv(0, NFD_IN_WQ, &nfd_rxd);

    /* TODO: check for error packets */

    reg_zero((void *)Pkt.__raw, sizeof(Pkt));
    nfd_in_fill_meta((void *)&Pkt.p_nbi,
                     (__xread struct nfd_in_pkt_desc *)&nfd_rxd);
    Pkt.p_isl = __ISLAND;
    Pkt.p_pnum = ctm_pnum;
    Pkt.p_seq = nfd_in_get_seqn((__xread struct nfd_in_pkt_desc *)&nfd_rxd);
    Pkt.p_offset = NFD_IN_DATA_OFFSET;

    /* TODO: handle LSO here */
    /* TODO: handle VLAN here */

    Pkt.p_ctm_sz = MIN_CTM_TYPE;
    Pkt.p_ro_ctx = NFD_IN_SEQR_NUM(nfd_rxd.q_num) << 1;
    Pkt.p_orig_len = Pkt.p_len;

    Pkt.p_src = PKT_HOST_PORT_FROMQ(nfd_rxd.intf, NFD_BMQ2NATQ(nfd_rxd.q_num));

    if (nfd_rxd.invalid) {
        INFRA_CNTR_INC(INFRA_CNTR_ERR_FROM_HOST);
        ret = -1;
        goto out;
    } else {
        __critical_path();
    }

    Pkt.app0 = nfd_rxd.__raw[2];
    Pkt.app1 = nfd_rxd.__raw[3];

    cpy_start = NFD_IN_DATA_OFFSET & ~0x3F;
    if ((nfd_rxd.data_len + NFD_IN_DATA_OFFSET) > MIN_CTM_SIZE) {
        Pkt.p_is_split = 1;
        cpy_end = MIN_CTM_SIZE;
    }
    else {
        Pkt.p_is_split = 0;
        cpy_end = nfd_rxd.data_len + NFD_IN_DATA_OFFSET;
    }

#ifdef MU_PTR_DEBUG
    buf_xw[0] = Pkt.p_muptr;
    ctm_ptr = pkt_ctm_ptr40(__ISLAND, ctm_pnum, 0);
    mem_write32(buf_xw, ctm_ptr, sizeof(buf_xw[0]));
#endif

    /* TODO - investigate use of CTM DMA to do data copy or other
     * alternatives to copy rather than read/write 64B of xfer regs.
     * Also might want to overlap next read with previous write I/O.
     */
    for (i = cpy_start; i < cpy_end; i += sizeof(buf_xr)) {
        /* get a handle to both the mu and ctm pkt pointers */
        mu_ptr = (__addr40 void *)(((uint64_t)Pkt.p_muptr << 11) | i);
        ctm_ptr = pkt_ctm_ptr40(__ISLAND, ctm_pnum, i);

        mem_read64(buf_xr, mu_ptr, sizeof(buf_xr));
        reg_cp(buf_xw, buf_xr, sizeof(buf_xw));
        mem_write64(buf_xw, ctm_ptr, sizeof(buf_xw));
    }

    INFRA_CNTR_INC(INFRA_CNTR_RX_FROM_HOST);
out:
    return ret;
}


__intrinsic void
pkt_rx_wq(int ring_num, mem_ring_addr_t ring_addr)
{
    __xread struct pkt_handle xph;
    __xread struct pkt_meta xpm;
    __addr40 void *p;

    mem_workq_add_thread(ring_num, ring_addr, &xph, sizeof(xph));
    p = pkt_ctm_ptr40(xph.ph_isl, xph.ph_pnum, 0);
    mem_read32(&xpm, p, sizeof(xpm));
    Pkt = xpm;
    Pkt.p_is_gro_sequenced = 0;
    Pkt.p_dst = PKT_DROP;
}


__intrinsic void
drop_packet(__xwrite struct gro_meta_drop *gmeta)
{
    blm_buf_free(Pkt.p_muptr, Pkt.p_bls);

    if (!Pkt.p_is_gro_sequenced)
#ifdef INFRA_HANDLE_REMOTE_PACKETS
    pkt_ctm_free(Pkt.p_isl, Pkt.p_pnum);
#else /* INFRA_HANDLE_REMOTE_PACKETS */
    pkt_ctm_free(0, Pkt.p_pnum);
#endif /* INFRA_HANDLE_REMOTE_PACKETS */

    if (Pkt.p_is_gro_sequenced)
        gro_cli_build_drop_ctm_buf_meta(gmeta, Pkt.p_isl, Pkt.p_pnum);
}


__intrinsic int
pkt_tx(void)
{
    __xwrite union gro_meta gmeta;
    __xwrite struct nbi_meta_pkt_info info;
    __xwrite uint32_t xmac;
    __xwrite uint32_t xpms[PMS_STRUCT_SIZE_LW];
    __addr40 void *p;
    SIGNAL info_sig;
    SIGNAL mac_sig;
    SIGNAL pms_sig;
    __xread uint32_t pms_readback;
    SIGNAL pms_sig2;
    __gpr struct pkt_ms_info msi = {0,0}; /* dummy msi for wire RX failures */

    int ss;
    int outq;
    uint16_t flags;
    uint32_t pmoff;
    uint32_t offset;
    uint32_t len;
    int ret = 0;

    ss = PKT_PORT_SUBSYS_of(Pkt.p_dst);
    outq = PKT_PORT_QUEUE_of(Pkt.p_dst);

    switch(PKT_PORT_TYPE_of(Pkt.p_dst))
    {
    case PKT_PTYPE_WIRE:
        /* Write packet meta to front */
        p = pkt_ctm_ptr40(Pkt.p_isl, Pkt.p_pnum, 0);
        info = Pkt.p_nbi;
        __mem_write64(&info, p, sizeof(info), sizeof(info), sig_done,
                      &info_sig);

        /* Write MAC prepend info */
        offset = Pkt.p_offset;
        len = Pkt.p_len;
        __pkt_mac_egress_cmd_write(p, offset, Pkt.p_tx_l3_csum,
                                   Pkt.p_tx_l4_csum, &xmac, sig_done, &mac_sig);
        offset -= 4;
        len += 4;

        /* Write mod script */
        pmoff = offset;
        offset = __pkt_pms_write(p, offset, xpms, &pms_sig, &pms_readback,
                                 &pms_sig2);
        /* wait for all the I/O operations to complete */
        wait_for_all(&info_sig, &mac_sig, &pms_sig, &pms_sig2);

        outq = NS_PLATFORM_NBI_TM_QID_LO(outq);
        if (Pkt.p_is_gro_sequenced) {
            gro_cli_build_nbi_meta(&gmeta.nbi, __ISLAND, Pkt.p_pnum,
                                   Pkt.p_ctm_sz, offset,
                                   len + pmoff, ss, outq);
        } else {
            msi.len_adj = pmoff;
            msi.off_enc = (offset >> 3) - 1;
            pkt_nbi_send(__ISLAND, Pkt.p_pnum, &msi, len, ss, outq,
                         Pkt.p_ro_ctx, Pkt.p_seq, Pkt.p_ctm_sz);
        }
        INFRA_CNTR_INC(INFRA_CNTR_TX_TO_WIRE);
        break;

    case PKT_PTYPE_HOST:
        if (!nfd_out_get_credit(ss, outq, 1)) {
            drop_packet(&gmeta.drop);
            ret = -1;
            INFRA_CNTR_INC(INFRA_CNTR_ERR_TO_HOST);
            break;
        } else {
            __gpr struct nfd_out_input noi;

            reg_zero(&noi, sizeof(noi));
            nfd_out_fill_desc(&noi, (void *)&Pkt.p_nbi, 0, Pkt.p_ctm_sz,
                              Pkt.p_offset, 0);
            nfd_out_check_ctm_only(&noi);
#if 0
            /* populate RX offload flags if present */
            flags = PCIE_DESC_RX_EOP;
            if (Pkt.p_rx_l3_csum_present) {
                flags |= PCIE_DESC_RX_I_IP4_CSUM;
                if (Pkt.p_rx_l3_csum_ok)
                    flags |= PCIE_DESC_RX_I_IP4_CSUM_OK;
            }
            if (Pkt.p_rx_l4_csum_present) {
                if (Pkt.p_rx_l4_tcp) {
                    flags |= PCIE_DESC_RX_I_TCP_CSUM;
                    if (Pkt.p_rx_l4_csum_ok)
                        flags |= PCIE_DESC_RX_I_TCP_CSUM_OK;
                } else {
                    flags |= PCIE_DESC_RX_I_UDP_CSUM;
                    if (Pkt.p_rx_l4_csum_ok)
                        flags |= PCIE_DESC_RX_I_UDP_CSUM_OK;
                }

            }
            nfd_out_dummy_vlan(&noi, 0, flags);
#endif
            noi.rxd.dd = 1;     /* stupidity */

            noi.rxd.__raw[0] = Pkt.app0;
            noi.rxd.__raw[1] = Pkt.app1;

            if (Pkt.p_is_gro_sequenced)
                gro_cli_nfd_desc2meta(&gmeta.nfd, &noi, ss, outq);
            else
                nfd_out_send(ss, outq, &noi);

            INFRA_CNTR_INC(INFRA_CNTR_TX_TO_HOST);
        }
        break;

    case PKT_PTYPE_WQ: {
        struct pkt_handle ph;
        __xwrite struct pkt_meta xwq;
        xwq = Pkt;
        p = pkt_ctm_ptr40(Pkt.p_isl, Pkt.p_pnum, 0);
        mem_write32(&xwq, p, sizeof(xwq));
        ph.__raw = 0;
        ph.ph_isl = Pkt.p_isl;
        ph.ph_pnum = Pkt.p_pnum;
        if (Pkt.p_is_gro_sequenced) {
            gro_cli_build_workq_meta1(&gmeta.memq, MUID_TO_ISL(ss), outq,
                                      ph.__raw);
        } else {
            uint32_t ma = MUID_TO_MEM_RING_ADDR(ss);
            __xwrite struct pkt_handle xph = ph;
            mem_workq_add_work(outq, ma, &xph, sizeof(xph));
        }
    } break;

    case PKT_PTYPE_NONE:
        goto done;

    case PKT_PTYPE_DROP_SEQ:
        gro_cli_build_drop_seq_meta(&gmeta.drop);
        break;

        INFRA_CNTR_INC(INFRA_CNTR_TX_TO_WIRE_DROP);
        break;

    case PKT_PTYPE_DROP_HOST:
        drop_packet(&gmeta.drop);
        INFRA_CNTR_INC(INFRA_CNTR_TX_TO_HOST_DROP);
        break;

    case PKT_PTYPE_DROP_WIRE:
/* Notify the NBI to ignore the packets sequence number */
        pkt_nbi_drop_seq(Pkt.p_isl, Pkt.p_pnum, &msi, Pkt.p_len, 0, 0,
                         Pkt.p_ro_ctx, Pkt.p_seq, Pkt.p_ctm_sz);

        drop_packet(&gmeta.drop);
        INFRA_CNTR_INC(INFRA_CNTR_TX_TO_WIRE_DROP);
        break;

    default:
        halt();
        break;
    }

    if (Pkt.p_is_gro_sequenced)
        gro_cli_send(&gmeta, Pkt.p_ro_ctx, Pkt.p_seq);
done:
    return ret;
}


void
init_tx()
{
    INFRA_CNTRS_SET_BASE(infra_cntrs_base);
    nfd_in_recv_init();
}


void
init_rx()
{
    INFRA_CNTRS_SET_BASE(infra_cntrs_base);
    nfd_out_send_init();
    gro_cli_init();
}

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
