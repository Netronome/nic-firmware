/*
 * Copyright (C) 2015 Netronome, Inc. All rights reserved.
 *
 * @file          apps/nic/rx_offload.c
 * @brief         API implementations of task offloading for the rx path.
 */

#include <infra_basic/infra_basic.h>
#include <nic_basic/nic_basic.h>
#include <nic_basic/pcie_desc.h>
#include <net/csum.h>
#include <nfp/me.h>
#include <std/reg_utils.h>
#include <vnic/pci_out.h>
#include <vnic/shared/nfd_cfg.h>

#include "nic.h"

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
    *l3_hdr += l3_off + l3_h_len;
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

    if (ctm_ptr) {
        *ctm_h_ptr = ctm_ptr + l4_off;
        if (ctm_sz >= pkt_len) {
            *ctm_l = pkt_len - l4_off;
            *mem_l = 0;
            *mem_h_ptr = 0;
        } else {
            *ctm_l = ctm_sz - l4_off;
            *mem_l = pkt_len - *ctm_l - l4_off;
            *mem_h_ptr = mem_ptr + l4_off + *ctm_l;
        }
    } else {
        *ctm_l = 0;
        *ctm_h_ptr = 0;
        *mem_l = pkt_len - l4_off;
        *mem_h_ptr = mem_ptr + l4_off;
    }
}

__intrinsic int
rx_check_inner_csum(int port, __lmem struct pkt_hdrs *hdrs,
                     const __nnr struct pkt_rx_desc *rxd, void *meta)
{
    struct pcie_out_pkt_desc *out_desc = (struct pcie_out_pkt_desc *)meta;
    __addr40 char *ctm_ptr;
    __addr40 char *mem_ptr;
    __addr40 char *mem_h_ptr;
    __addr40 char *ctm_h_ptr;
    uint32_t mem_l;
    uint32_t ctm_l;
    unsigned int frame_off;
    __addr40 void *l3_hdr;
    unsigned int csum_copy;
    int ret = 0;
    int ret2 = NIC_RX_OK;

    if (!(hdrs->present & (HDR_I_IP6 | HDR_I_IP4)))
        goto out;

    pkt_ptrs(rxd, &frame_off, &ctm_ptr, &mem_ptr);

    if (hdrs->present & HDR_I_IP6)
        goto inner_l4;

    l3_csum_offset(&l3_hdr, mem_ptr, ctm_ptr, rxd->nbi.len,
                           hdrs->offsets[HDR_OFF_I_L3], hdrs->i_ip4.hl << 2);

    ret = net_csum_ipv4(&hdrs->i_ip4, l3_hdr);
    out_desc->flags |= PCIE_DESC_RX_I_IP4_CSUM;
    if (ret)
        ret2 = NIC_RX_DROP;
    else
        out_desc->flags |= PCIE_DESC_RX_I_IP4_CSUM_OK;

inner_l4:
    if (!(hdrs->present & HDR_I_TCP || hdrs->present & HDR_I_UDP))
        goto out;

    l4_csum_offsets(mem_ptr, ctm_ptr, &mem_h_ptr, &ctm_h_ptr,
                    rxd->nbi.len,
                    hdrs->offsets[HDR_OFF_I_L4], frame_off,
                    &mem_l, &ctm_l);

    if (hdrs->present & HDR_I_TCP) {
        out_desc->flags |= PCIE_DESC_RX_I_TCP_CSUM;
        if (hdrs->present & HDR_I_IP4)
            ret = net_csum_ipv4_tcp(&hdrs->i_ip4,
                                                &hdrs->i_tcp,
                                                ctm_h_ptr, ctm_l,
                                                mem_h_ptr, mem_l);
        else
            ret = net_csum_ipv6_tcp(&hdrs->i_ip6,
                                                &hdrs->i_tcp,
                                                ctm_h_ptr, ctm_l,
                                                mem_h_ptr, mem_l);

        if (!ret)
            out_desc->flags |= PCIE_DESC_RX_I_TCP_CSUM_OK;
    } else if (hdrs->present & HDR_I_UDP) {
        out_desc->flags |= PCIE_DESC_RX_I_UDP_CSUM;
        if (hdrs->present & HDR_I_IP4)
            ret = net_csum_ipv4_udp(&hdrs->i_ip4,
                                                &hdrs->i_udp,
                                                ctm_h_ptr, ctm_l,
                                                mem_h_ptr, mem_l);
        else
            ret = net_csum_ipv6_udp(&hdrs->i_ip6,
                                                &hdrs->i_udp,
                                                ctm_h_ptr, ctm_l,
                                                mem_h_ptr, mem_l);

        if (!ret)
            out_desc->flags |= PCIE_DESC_RX_I_UDP_CSUM_OK;
    }

out:

    if (ret2 == NIC_RX_DROP || ret) {
        nic_rx_error_cntr(port);
        ret2 = NIC_RX_DROP;
    }

    return ret2;
}
