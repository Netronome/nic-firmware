/*
 * Copyright (C) 2015 Netronome, Inc. All rights reserved.
 *
 * @file          apps/nic/tx_offload.c
 * @brief         API implementations of task offloading for the tx path.
 */

#include <infra/infra.h>
#include <net/csum.h>
#include <nic/nic.h>
#include <nic/pcie_desc.h>
#include <nfp/me.h>
#include <std/reg_utils.h>
#include <vnic/pci_in.h>

#include "nic.h"

#define MAX_IP4_ID 0xFFFF

/* TODO: Move to flowenv? */
enum {
    TCP_FLG_FIN = 1,
    TCP_FLG_SYN = 2,
    TCP_FLG_RST = 4,
    TCP_FLG_PSH = 8,
    TCP_FLG_ACK = 16,
    TCP_FLG_URG = 32,
    TCP_FLG_ECE = 64,
    TCP_FLG_CWR = 128
};

/**
 * Modify TCP Seq Num. Will require later csum recalculation.
 *
 * @param hdrs     Cache with the TCP header to modify.
 * @param meta     Metadata for NIC app.
 * @param h_work   Header to modify; HDR_O_TCP or HDR_I_TCP.
 *
 * @return         Returns 0 on success.
 */
__intrinsic static int
tx_tsk_set_tcp_seq(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
                   unsigned h_work)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __gpr int ret = 0;

    if (h_work & HDR_O_TCP) {
        hdrs->o_tcp.seq += (((uint32_t)in_desc->mss) *
        (in_desc->lso_seq_cnt - 1));
    } else if (h_work & HDR_I_TCP) {
        hdrs->i_tcp.seq += (((uint32_t)in_desc->mss) *
        (in_desc->lso_seq_cnt - 1));
    } else {
        ret = NIC_TX_DROP;
    }

    return ret;
}

/**
 * Set TCP Flags. If this is the last packet of the LSO stream,
 * does not clear FIN, RST and PSH if they are set. Otherwise clears them.
 * Will require later csum recalculation.
 *
 * @param hdrs     Cache with the TCP header to modify.
 * @param meta     Metadata for NIC app.
 * @param h_work   Header to modify; HDR_O_TCP or HDR_I_TCP.
 *
 * @return         Returns 0 on success.
 */
__intrinsic static int
tx_tsk_set_tcp_flags(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
                     unsigned h_work)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __gpr int ret = 0;

    /* Preserve all flags if last LSO packet. Otherwise don't
     * preserve FIN, RST and PSH. */
    __gpr uint8_t flag_mask = (in_desc->lso_end) ?
        ~(uint8_t)0 : ~(uint8_t)(TCP_FLG_FIN | TCP_FLG_RST | TCP_FLG_PSH);

    if (h_work & HDR_O_TCP)
        hdrs->o_tcp.flags = hdrs->o_tcp.flags & flag_mask;
    else if (h_work & HDR_I_TCP)
        hdrs->i_tcp.flags = hdrs->i_tcp.flags & flag_mask;
    else
        ret = NIC_TX_DROP;

    return ret;
}

/**
 * Set IPv4 Total Length. Will require later csum recalculation.
 *
 * @param hdrs      Cache with the IPv4 header to modify.
 * @param meta      Metadata for NIC app.
 * @param h_work    Header to modify, HDR_O_IP4 or HDR_I_IP4
 *
 * @return          Returns 0 on success.
 */
__intrinsic static int
tx_tsk_set_ipv4_len(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
                    unsigned h_work)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __gpr uint16_t offset;
    __gpr int ret = 0;

    if (h_work & HDR_O_IP4) {
        offset = hdrs->offsets[HDR_OFF_O_L3];
        hdrs->o_ip4.len = in_desc->data_len - offset;
    } else if (h_work & HDR_I_IP4) {
        offset = hdrs->offsets[HDR_OFF_I_L3];
        hdrs->i_ip4.len = in_desc->data_len - offset;
    } else {
        ret = NIC_TX_DROP;
    }

    return ret;
}

/**
 * Set IPv6 Payload Length.
 *
 * @param hdrs      Cache with the IPv6 header to modify.
 * @param meta      Metadata for NIC app.
 * @param h_work    Header to modify, HDR_O_IP6 or HDR_I_IP6
 *
 * @return          Returns 0 on success.
 */
__intrinsic static int
tx_tsk_set_ipv6_len(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
                    unsigned h_work)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __gpr uint16_t offset;
    __gpr int ret = 0;

    if (h_work & HDR_O_IP6) {
        offset = hdrs->offsets[HDR_OFF_O_L3];
        hdrs->o_ip6.len = in_desc->data_len - offset - sizeof(struct ip6_hdr);
    } else if (h_work & HDR_I_IP6) {
        offset = hdrs->offsets[HDR_OFF_I_L3];
        hdrs->i_ip6.len = in_desc->data_len - offset - sizeof(struct ip6_hdr);
    } else {
        ret = NIC_TX_DROP;
    }

    return ret;
}

/**
 * Set UDP Payload Length.
 *
 * @param hdrs      Cache with the UDP header to modify.
 * @param meta      Metadata for NIC app.
 * @param h_work    Header to modify, HDR_O_UDP or HDR_I_UDP
 *
 * @return          Returns 0 on success.
 */
__intrinsic static int
tx_tsk_set_udp_len(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
                   unsigned h_work)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __gpr uint16_t offset;
    __gpr int ret = 0;

    if (h_work & HDR_O_UDP) {
        offset = hdrs->offsets[HDR_OFF_O_L4];
        hdrs->o_udp.len = in_desc->data_len - offset;
    } else if (h_work & HDR_I_UDP) {
        offset = hdrs->offsets[HDR_OFF_I_L4];
        hdrs->i_udp.len = in_desc->data_len - offset;
    } else {
        ret = NIC_TX_DROP;
    }

    return ret;
}

/**
 * Increment IP ID field in IPv4 header for LSO.
 * Will require a later csum recalculation.
 *
 * @param hdrs      Cache with the IPv4 header to modify.
 * @param meta      Metadata for NIC app.
 * @param tx_config Contains max ID permitted before wrap.
 * @param h_work    Header to modify, HDR_O_IP4 or HDR_I_IP4
 *
 * @return          Returns 0 on success.
 *
 * @note Uses the lso_seq_cnt field in the metadata to know how much
 *       to add the IP ID.
 */
__intrinsic static int
tx_tsk_incr_ipv4_id(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
                    __gpr struct tx_tsk_config *tx_cfg, unsigned h_work)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __gpr uint32_t id;
    __gpr uint32_t max_id;
    __gpr int ret = 0;

    id = (in_desc->lso_seq_cnt - 1);
    max_id = tx_cfg->ip4_id_max;
    max_id = max_id ? max_id : MAX_IP4_ID;

    if (h_work & HDR_O_IP4) {
        id += (uint32_t)hdrs->o_ip4.id;
        hdrs->o_ip4.id = ((uint16_t)id) & max_id;
    } else if (h_work & HDR_I_IP4) {
        id += (uint32_t)hdrs->i_ip4.id;
        hdrs->i_ip4.id = ((uint16_t)id) & max_id;
    } else {
        ret = NIC_TX_DROP;
    }

    return ret;
}

/**
 * Helper function to reduce code repetition.
 */
__intrinsic static int
ipv4_lso_fixup(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
               __gpr struct tx_tsk_config *tx_cfg, unsigned h_work)
{
    __gpr int ret = NIC_TX_DROP;

    ret = tx_tsk_set_ipv4_len(hdrs, meta, h_work);
    if (ret != 0)
        goto error;
    ret = tx_tsk_incr_ipv4_id(hdrs, meta, tx_cfg, h_work);

error:
    return ret;
}

/**
 * Helper function to reduce code repetition.
 */
__intrinsic static int
tcp_lso_fixup(__lmem struct pkt_hdrs *hdrs, __gpr void *meta, unsigned h_work)
{
    __gpr int ret = NIC_TX_DROP;

    ret = tx_tsk_set_tcp_seq(hdrs, meta, h_work);
    if (ret != 0)
        goto error;

    ret = tx_tsk_set_tcp_flags(hdrs, meta, h_work);

error:
    return ret;
}

/**
 * Calculate L3 offsets required for checksum functions.
 *
 * @param l3_hdr       Is set to packet's start of L3 header
 * @param mem_ptr      Start of packet in emem
 * @param ctm_ptr      Start of packet in ctm
 * @param frame_off    Offset to start of L2
 * @param l3_off       Offset from start of frame to start of L3 header
 * @param l3_h_len     Length of l3 header
 */
__intrinsic static void
l3_csum_offset(__addr40 char **l3_hdr, __addr40 char *mem_ptr,
               __addr40 char *ctm_ptr, uint32_t frame_off, uint32_t l3_off,
               uint32_t l3_h_len)
{
    uint32_t ctm_sz = (256 << ctm_split()) - frame_off;

    if (ctm_ptr != 0 && (frame_off + l3_off + l3_h_len) <= ctm_sz)
       *l3_hdr = ctm_ptr;
    else
        *l3_hdr = mem_ptr;

    *l3_hdr += l3_off;
}

/**
 * Calculate L4 offsets required for checksum functions.
 *
 * @param mem_ptr      Start of packet in emem
 * @param ctm_ptr      Start of packet in ctm
 * @param mem_h_ptr    Is set to start of mem L4 after ctm portion
 * @param ctm_h_ptr    Is set to start of ctm L4
 * @param pkt_len      Length of entire frame, starting at L2 header
 * @param l4_off       Offset from start of frame to start of L4 header
 * @param frame_off    The offset to start of L2
 * @param mem_l        Is set to the length of data pointed to by mem_h_ptr
 * @param ctm_l        Is set to the length of data pointed to by ctm_h_ptr
 */
__intrinsic static void
l4_csum_offsets(__addr40 char *mem_ptr, __addr40 char *ctm_ptr,
                __addr40 char **mem_h_ptr, __addr40 char **ctm_h_ptr,
                uint32_t pkt_len, uint32_t l4_off, uint32_t frame_off,
                uint32_t *mem_l, uint32_t *ctm_l)
{
    uint32_t ctm_sz = (256 << ctm_split()) - frame_off;

    /* this is how the code should look like but somehow it generates
     * unintended mem[read8's
     */
#if 0
    if (ctm_ptr) {
        *ctm_h_ptr = ctm_ptr + l4_off;
        if (ctm_sz >= pkt_len) {
            *ctm_l = pkt_len - l4_off;
            *mem_l = 0;
            *mem_h_ptr = 0;
        } else {
            *ctm_l = ctm_sz - l4_off;
            *mem_l = pkt_len - *ctm_l - l4_off;
            *mem_h_ptr = *mem_ptr + l4_off + *ctm_l;
        }
    } else {
        *ctm_l = 0;
        *ctm_h_ptr = 0;
        *mem_l = pkt_len - l4_off;
        *mem_h_ptr = mem_ptr + l4_off;
    }
#else
    *ctm_l = 0;
    *ctm_h_ptr = 0;
    *mem_l = pkt_len - l4_off;
    *mem_h_ptr = mem_ptr + l4_off;
#endif
}


__intrinsic int
tx_tsk_fixup(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
             __gpr struct tx_tsk_config *tx_cfg)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __gpr int ret = 0;

    if (in_desc->flags & PCIE_DESC_TX_LSO) {

#if (NFD_IN_BLM_JUMBO_BLS != NFD_IN_BLM_REG_BLS)
        /* LSO packets always MU buffers from the jumbo_store,
         * sourced from NFD_IN_BLM_JUMBO_POOL.  All packets are
         * first assigned a BLS based on their size but PCI.IN
         * API calls.  Hence the BLS must be replaced for LSO
         * packets.  In the special case that
         * NFD_IN_BLM_JUMBO_BLS and NFD_IN_BLM_REG_BLS are the
         * same, we can skip this step.
         * XXX swapping the BLS must happen for all paths, including
         * drop paths. */
        in_desc->bls = NFD_IN_BLM_JUMBO_BLS;
#endif
        if (hdrs->present & HDR_O_IP4) {
            ret = ipv4_lso_fixup(hdrs, meta, tx_cfg, HDR_O_IP4);
            if (ret != 0)
                goto error;
            hdrs->dirty |= HDR_O_IP4;
        } else if (hdrs->present & HDR_O_IP6) {
            ret = tx_tsk_set_ipv6_len(hdrs, meta, HDR_O_IP6);
            if (ret != 0)
                goto error;
            hdrs->dirty |= HDR_O_IP6;
        }

        if (hdrs->present & HDR_O_TCP) {
            ret = tcp_lso_fixup(hdrs, meta, HDR_O_TCP);
            if (ret != 0)
                goto error;
            hdrs->dirty |= HDR_O_TCP;
        } else if (hdrs->present & HDR_O_UDP) {
            if ((ret =
                tx_tsk_set_udp_len(hdrs, meta, HDR_O_UDP)) != 0)
                goto error;
            hdrs->dirty |= HDR_O_UDP;
        }

        if (hdrs->present & HDR_I_IP4) {
            ret = ipv4_lso_fixup(hdrs, meta, tx_cfg, HDR_I_IP4);
            if (ret != 0)
                goto error;
            hdrs->dirty |= HDR_I_IP4;
        } else if (hdrs->present & HDR_I_IP6) {
            ret = tx_tsk_set_ipv6_len(hdrs, meta, HDR_I_IP6);
            if (ret != 0)
                goto error;
            hdrs->dirty |= HDR_I_IP6;
        }

        if (hdrs->present & HDR_I_TCP) {
            ret = tcp_lso_fixup(hdrs, meta, HDR_I_TCP);
            if (ret != 0)
                goto error;
            hdrs->dirty |= HDR_I_TCP;
        }
    }

    /*
     * else,
     * NVGRE and VXLAN Task Offload basically amount to checksum offloads at
     * this point in time. These will be handled later by the checksum
     * functions.
     */

error:
    return ret;
}

__intrinsic int
tx_tsk_set_ipv4_csum(__lmem struct pkt_hdrs *hdrs,
                     const __nnr struct pkt_rx_desc *rxd, void *meta)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __addr40 char *ctm_ptr;
    __addr40 char *mem_ptr;
    unsigned int frame_off;
    __addr40 void *l3_hdr;

    pkt_ptrs(rxd, &frame_off, &ctm_ptr, &mem_ptr);

    /*
     * If csum offload is enabled, then it only refers to inner headers if
     * the encapsulation flags is set.
     */
    if (hdrs->dirty & HDR_I_IP4 ||
        (in_desc->flags & PCIE_DESC_TX_CSUM &&
         in_desc->flags & PCIE_DESC_TX_ENCAP)) {
        if (hdrs->present & HDR_I_IP4) {
            l3_csum_offset(&l3_hdr, mem_ptr, ctm_ptr, in_desc->data_len,
                           hdrs->offsets[HDR_OFF_I_L3], hdrs->i_ip4.hl << 2);

            hdrs->i_ip4.sum = 0;
            hdrs->i_ip4.sum = net_csum_ipv4(&hdrs->i_ip4, l3_hdr);
            hdrs->i_ip4.sum = hdrs->i_ip4.sum ? hdrs->i_ip4.sum : 0xFFFF;
            hdrs->dirty |= HDR_I_IP4;
       }
    }

    return 0;
}

int
tx_tsk_set_l4_csum(__lmem struct pkt_hdrs *hdrs,
                   __nnr const struct pkt_rx_desc *rxd,
                   void *meta)
{
    __gpr struct pcie_in_nfp_desc *in_desc =
                                    (__gpr struct pcie_in_nfp_desc *)meta;
    __addr40 char *ctm_ptr;
    __addr40 char *mem_ptr;
    unsigned int frame_off;

    __addr40 char *mem_h_ptr;
    __addr40 char *ctm_h_ptr;
    uint32_t mem_l;
    uint32_t ctm_l;

    __gpr uint32_t flag_mask = 0;

    int ret = 0;

    pkt_ptrs(rxd, &frame_off, &ctm_ptr, &mem_ptr);

    /* don't support CTM yet, somehow l4_csum_offsets generates
     * mem[read8's */
    if (ctm_ptr)
        halt();
    /*
     * If csum offload is enabled, then it only refers to inner
     * headers if the encapsulation flag is set. However, we always
     * need to calculate the csum if the inner L4 header is dirty.
     */
    if ((hdrs->dirty & (HDR_I_TCP | HDR_I_UDP)) ||
        (in_desc->flags & PCIE_DESC_TX_CSUM &&
         in_desc->flags & PCIE_DESC_TX_ENCAP)) {
        if (hdrs->dirty & HDR_I_TCP || (hdrs->present & HDR_I_TCP &&
                in_desc->flags & PCIE_DESC_TX_TCP_CSUM)) {
            /* do TCP csum if either inner TCP is dirty or both the fw
             * and the driver are aware there is inner TCP */
            l4_csum_offsets(mem_ptr, ctm_ptr, &mem_h_ptr, &ctm_h_ptr,
                            in_desc->data_len,
                            hdrs->offsets[HDR_OFF_I_L4], frame_off,
                            &mem_l, &ctm_l);

            NIC_APP_DBG_APP(nic_app_dbg_journal, 0xAB);
            NIC_APP_DBG_APP(nic_app_dbg_journal, hdrs->i_tcp.sum);

            hdrs->i_tcp.sum = 0;
            if (hdrs->present & HDR_I_IP4) {
                hdrs->i_tcp.sum = net_csum_ipv4_tcp(&hdrs->i_ip4,
                                                    &hdrs->i_tcp,
                                                    ctm_h_ptr, ctm_l,
                                                    mem_h_ptr, mem_l);
            } else {
                hdrs->i_tcp.sum = net_csum_ipv6_tcp(&hdrs->i_ip6,
                                                    &hdrs->i_tcp,
                                                    ctm_h_ptr, ctm_l,
                                                    mem_h_ptr, mem_l);
            }
            hdrs->dirty |= HDR_I_TCP;
            hdrs->i_tcp.sum = hdrs->i_tcp.sum ? hdrs->i_tcp.sum : 0xFFFF;

            NIC_APP_DBG_APP(nic_app_dbg_journal, 0xCD);
            NIC_APP_DBG_APP(nic_app_dbg_journal, hdrs->i_tcp.sum);

        } else if (hdrs->dirty & HDR_I_UDP || (hdrs->present & HDR_I_UDP &&
                       in_desc->flags & PCIE_DESC_TX_UDP_CSUM)) {
            l4_csum_offsets(mem_ptr, ctm_ptr, &mem_h_ptr, &ctm_h_ptr,
                            in_desc->data_len,
                            hdrs->offsets[HDR_OFF_I_L4], frame_off,
                            &mem_l, &ctm_l);

            hdrs->i_udp.sum = 0;
            if (hdrs->present & HDR_I_IP4) {
                hdrs->i_udp.sum = net_csum_ipv4_udp(&hdrs->i_ip4,
                                                    &hdrs->i_udp,
                                                    ctm_h_ptr, ctm_l,
                                                    mem_h_ptr, mem_l);
            } else {
                hdrs->i_udp.sum = net_csum_ipv6_udp(&hdrs->i_ip6,
                                                    &hdrs->i_udp,
                                                    ctm_h_ptr, ctm_l,
                                                    mem_h_ptr, mem_l);
            }
            hdrs->dirty |= HDR_I_UDP;
            hdrs->i_udp.sum = hdrs->i_udp.sum ? hdrs->i_udp.sum : 0xFFFF;
        }
    }

error:
    return ret;
}
