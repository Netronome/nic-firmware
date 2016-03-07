/*
 * Copyright (C) 2015 Netronome, Inc. All rights reserved.
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
 * @file          apps/nic/rx_offload.c
 * @brief         API implementations of task offloading for the rx path.
 */

#include <infra_basic/infra_basic.h>
#include <nfp6000/nfp_mac.h>
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
                    __lmem struct pkt_encap *encap,
                    const __nnr struct pkt_rx_desc *rxd, void *meta,
                    uint32_t csum)
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
    uint32_t csum_copy, opt_size;
    int ret = 0;
    __gpr int ret2 = NIC_RX_OK;
    __xread uint32_t ip_opts[10];
    SIGNAL read_sig;

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
    if (hdrs->present & HDR_I_TCP)
        out_desc->flags |= PCIE_DESC_RX_I_TCP_CSUM;
    else if (hdrs->present & HDR_I_UDP)
        out_desc->flags |= PCIE_DESC_RX_I_UDP_CSUM;
    else
        goto out;

    if ((hdrs->present & HDR_E_VXLAN) && (hdrs->present & HDR_I_IP4)) {
        /* VXLAN pkts got outer UDP and so our MAC provides the outer
         * UDP csum for us to use to verify the inner TCP/UDP csum
         * TODO: support IPv6
         * TODO: improve this check, faster without the MAC sum?
         */
        csum_copy = NFP_MAC_RX_CSUM_CSUM_of(csum);

        /* Subtract/sum the bits that the outer UDP csum has that are
         * not included in the inner TCP/UDP csum:
         */

        /* 1: the outer pseudo header */
        csum_copy = ones_sum_add(csum_copy, hdrs->o_ip4.src);
        csum_copy = ones_sum_add(csum_copy, hdrs->o_ip4.dst);
        csum_copy = ones_sum_add(csum_copy, hdrs->o_ip4.proto);
        csum_copy = ones_sum_add(csum_copy,
                                 hdrs->o_ip4.len - (hdrs->o_ip4.hl * 4));

        /* 2: outer UDP header */
        csum_copy = ones_sum_add(csum_copy, hdrs->o_udp.sport);
        csum_copy = ones_sum_add(csum_copy, hdrs->o_udp.dport);
        csum_copy = ones_sum_add(csum_copy, hdrs->o_udp.len);

        /* 3: VXLAN encap */
        csum_copy = ones_sum_add(csum_copy, ((__lmem uint32_t *) encap)[0]);
        csum_copy = ones_sum_add(csum_copy, ((__lmem uint32_t *) encap)[1]);

        /* 4: inner Ethernet */
        csum_copy = ones_sum_add(csum_copy,
                                 ((__lmem uint32_t *) &hdrs->i_eth)[0]);
        csum_copy = ones_sum_add(csum_copy,
                                 ((__lmem uint32_t *) &hdrs->i_eth)[1]);
        csum_copy = ones_sum_add(csum_copy,
                                 ((__lmem uint32_t *) &hdrs->i_eth)[2]);
        csum_copy = ones_sum_add(csum_copy, hdrs->i_eth.type);


        if (hdrs->present & HDR_I_VLAN)
            csum_copy = ones_sum_add(csum_copy,
                                     ((__lmem uint32_t *) &hdrs->i_vlan)[0]);

        /* TODO: use the inner IP sum? */
        csum_copy = ones_sum_add(csum_copy,
                                 ((__lmem uint16_t *) &hdrs->i_ip4)[0]);
        csum_copy = ones_sum_add(csum_copy, hdrs->i_ip4.hl * 4);
        csum_copy = ones_sum_add(csum_copy,
                                 ((__lmem uint32_t *) &hdrs->i_ip4)[1]);
        csum_copy = ones_sum_add(csum_copy, hdrs->i_ip4.ttl << 8);
        csum_copy = ones_sum_add(csum_copy,
                                 ((__lmem uint16_t *) &hdrs->i_ip4)[5]);

        opt_size = hdrs->i_ip4.hl - NET_IP4_LEN32;
        if (opt_size > 0) {
            opt_size = opt_size * sizeof(uint32_t);
            ((__addr40 uint8_t*)l3_hdr) -= opt_size;
            /* The read size must be a mult of 8 bytes */
            __mem_read64(ip_opts, l3_hdr, (opt_size + 7) & 0x78,
                         sizeof(ip_opts), ctx_swap, &read_sig);
            csum_copy = ones_sum_add(csum_copy,
                                     ones_sum_warr(ip_opts, opt_size));
              __implicit_read(ip_opts);
        }

        ret = (~ones_sum_fold16(csum_copy)) & 0xFFFF;
        if (hdrs->present & HDR_I_TCP) {
            if (!ret) {
                out_desc->flags |= PCIE_DESC_RX_I_TCP_CSUM_OK;

            }
        } else if (hdrs->present & HDR_I_UDP) {
            if (!ret) {
                out_desc->flags |= PCIE_DESC_RX_I_UDP_CSUM_OK;
            }
        }

    } else {
        /* no VXLAN so no csum from the MAC to optimize the calc */
        l4_csum_offsets(mem_ptr, ctm_ptr, &mem_h_ptr, &ctm_h_ptr,
                        rxd->nbi.len,
                        hdrs->offsets[HDR_OFF_I_L4], frame_off,
                        &mem_l, &ctm_l);

        if (hdrs->present & HDR_I_TCP) {
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
    }
out:

    if (ret2 == NIC_RX_DROP || ret) {
        nic_rx_error_cntr(port);
        ret2 = NIC_RX_DROP;
    }

    return ret2;
}
