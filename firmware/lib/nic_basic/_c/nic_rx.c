/*
 * Copyright 2014-2015 Netronome, Inc.
 *
 * @file          lib/nic/_c/nic_rx.c
 * @brief         NIC receive processing
 */

#ifndef _LIBNIC_NIC_RX_C_
#define _LIBNIC_NIC_RX_C_

#include <nfp.h>
#include <stdint.h>

#include <nfp6000/nfp_mac.h>
#include <nfp6000/nfp_me.h>

#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_out.h>

/* generic register casting to trick the compiler */
#define REGCST __xread

__intrinsic int
nic_rx_l1_checks(int port)
{
    __gpr int ret = NIC_RX_OK;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    /* Only support a single port for now. */
    ctassert(__is_ct_const(port));
    ctassert(port == 0);

   /* Drop if down */
    if (!(nic->control & NFP_NET_CFG_CTRL_ENABLE)) {
        NIC_LIB_CNTR(&nic_cnt_rx_drop_dev_down);
        ret = NIC_RX_DROP;
        goto out;
    }

    /* Drop if no rings configured */
    if (!nic->rx_ring_en) {
        NIC_LIB_CNTR(&nic_cnt_rx_drop_ring_down);
        ret = NIC_RX_DROP;
        goto out;
    }

out:
    return ret;
}


__intrinsic int
nic_rx_mtu_check(int port, uint32_t csum, int frame_len)
{
    __gpr int max_frame_sz;
    __gpr int ret = NIC_RX_OK;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    /* Without VLANs the max frame size is MTU + Ethernet header */
    max_frame_sz = nic->mtu + NET_ETH_LEN;

    /* Add the number of present VLAN tags to the max allowed framesize */
    if (NFP_MAC_RX_CSUM_VLANS_of(csum))
        max_frame_sz += NFP_MAC_RX_CSUM_VLANS_of(csum) * NET_8021Q_LEN;

    /* Drop if frame exceeds MTU */
    if (frame_len > max_frame_sz) {
        nic_rx_error_cntr(port);
        NIC_LIB_CNTR(&nic_cnt_rx_drop_mtu);
        ret = NIC_RX_DROP;
    }

    return ret;
}


#if (NIC_RX_OK != 0)
#error "nic_rx_csum_checks assumes that NIC_RX_OK is zero"
#endif
__intrinsic int
nic_rx_csum_checks(int port, uint32_t csum, void *meta)
{
    __gpr int ret = NIC_RX_OK;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;
    struct pcie_out_pkt_desc *out_desc = (struct pcie_out_pkt_desc *)meta;

    /* Only support a single port for now. */
    ctassert(__is_in_reg_or_lmem(meta));

    if (NFP_MAC_RX_CSUM_L3_SUM_of(csum) == NFP_MAC_RX_CSUM_L3_IPV4_OK) {
        out_desc->flags |= PCIE_DESC_RX_IP4_CSUM;
        out_desc->flags |= PCIE_DESC_RX_IP4_CSUM_OK;
    } else if (NFP_MAC_RX_CSUM_L3_SUM_of(csum) ==
               NFP_MAC_RX_CSUM_L3_IPV4_FAIL) {
        /* L3 checksum is wrong */
        out_desc->flags |= PCIE_DESC_RX_IP4_CSUM;
        NIC_LIB_CNTR(&nic_cnt_rx_csum_err_l3);
        ret = NIC_RX_DROP;
    }

    if (NFP_MAC_RX_CSUM_L4_SUM_of(csum) == NFP_MAC_RX_CSUM_L4_TCP_OK) {
        out_desc->flags |= PCIE_DESC_RX_TCP_CSUM;
        out_desc->flags |= PCIE_DESC_RX_TCP_CSUM_OK;
    }

    if (NFP_MAC_RX_CSUM_L4_SUM_of(csum) == NFP_MAC_RX_CSUM_L4_TCP_FAIL) {
        out_desc->flags |= PCIE_DESC_RX_TCP_CSUM;
        NIC_LIB_CNTR(&nic_cnt_rx_csum_err_l4_tcp);
        ret = NIC_RX_DROP;
    }

    if (NFP_MAC_RX_CSUM_L4_SUM_of(csum) == NFP_MAC_RX_CSUM_L4_UDP_OK) {
        out_desc->flags |= PCIE_DESC_RX_UDP_CSUM;
        out_desc->flags |= PCIE_DESC_RX_UDP_CSUM_OK;
    }

    if (NFP_MAC_RX_CSUM_L4_SUM_of(csum) == NFP_MAC_RX_CSUM_L4_UDP_FAIL) {
        out_desc->flags |= PCIE_DESC_RX_UDP_CSUM;
        NIC_LIB_CNTR(&nic_cnt_rx_csum_err_l4_udp);
        ret = NIC_RX_DROP;
    }

    if (ret == NIC_RX_DROP)
        nic_rx_error_cntr(port);

    /* In promiscuous mode we pass through even errored packets, but
     * we still do the tests above to update the counters. Indicate to
     * the caller that the checksum was bad, though. */
    if (nic->control & NFP_NET_CFG_CTRL_PROMISC && ret == NIC_RX_DROP)
        ret = NIC_RX_CSUM_BAD;

    if (ret != NIC_RX_DROP)
        NIC_LIB_CNTR(&nic_cnt_rx_pkts);

    return ret;
}

__intrinsic int
nic_rx_l2_checks(int port, void *sa, void *da)
{
    __gpr int ret = NIC_RX_DROP;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    /* Only support a single port for now. */
    ctassert(__is_ct_const(port));
    ctassert(port == 0);
    ctassert(__is_in_reg_or_lmem(da));

    /* Source address sanity checks */
    if (NIC_IS_MC_ADDR(sa)) {
        NIC_LIB_CNTR(&nic_cnt_rx_eth_sa_err);
        goto out;
    }

    /* Perform destination MAC address checks */
    if (nic->control & NFP_NET_CFG_CTRL_PROMISC) {
        ret = NIC_RX_OK;
        goto out;
    }

    if (NIC_IS_MC_ADDR(da)) {

        /* Broadcast addresses are Multicast address too */
        if (NIC_IS_BC_ADDR(da) && (nic->control & NFP_NET_CFG_CTRL_L2BC)) {
            ret = NIC_RX_OK;
            goto out;
        }

        if (nic->control & NFP_NET_CFG_CTRL_L2MC) {
            ret = NIC_RX_OK;
            goto out;
        }
        NIC_LIB_CNTR(&nic_cnt_rx_eth_drop_mc);
    }

    /* Destination address matches our MAC? */
    if(REG_CMPS(3, da, (void*)nic->mac)) {
        NIC_LIB_CNTR(&nic_cnt_rx_eth_local);
        ret = NIC_RX_OK;
        goto out;
    }

    NIC_LIB_CNTR(&nic_cnt_rx_eth_drop_da);

out:
    if (ret == NIC_RX_DROP) {
        if (nic->control & NFP_NET_CFG_CTRL_PROMISC) {
            ret = NIC_RX_OK;
        } else {
            NIC_LIB_CNTR(&nic_cnt_rx_eth_drop);
        }
    }
    return ret;
}


__intrinsic int
nic_rx_vlan_strip(int port, uint16_t tci, void *meta)
{
    __gpr int ret = 0;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;
    struct pcie_out_pkt_desc *out_desc = (struct pcie_out_pkt_desc *)meta;

    ctassert(__is_in_reg(meta));

    /* If VLAN stripping is disabled, we are done */
    if (!(nic->control & NFP_NET_CFG_CTRL_RXVLAN))
        goto out;

    out_desc->flags |= PCIE_DESC_RX_VLAN;
    out_desc->vlan = tci;
    ret = 1;

out:
    return ret;
}

/**
 * Internal function to build the RSS key
 */
__intrinsic void
__nic_rx_rss_build_key(void *l3, void *l4, int flags, uint32_t rss_ctrl,
                       __nnr uint32_t *key, __gpr int *size, __gpr int *type)
{
    /* can not use *size directly */
    int size2 = *size;

    if (flags & NIC_RSS_IP4) {
        if (((REGCST struct ip4_hdr *)l3)->frag &
            (NET_IP_FLAGS_MF | NET_IP_FRAG_OFF_MASK)) {
            /* This frame is part of a IP fragment. Dig around the header */
            if (((((REGCST struct ip4_hdr *)l3)->proto == NET_IP_PROTO_TCP) &&
                 (rss_ctrl & NFP_NET_CFG_RSS_IPV4_TCP)) ||
                ((((REGCST struct ip4_hdr *)l3)->proto == NET_IP_PROTO_UDP) &&
                 (rss_ctrl & NFP_NET_CFG_RSS_IPV4_UDP)) ||
                (rss_ctrl & NFP_NET_CFG_RSS_IPV4)) {

                key[0] = ((REGCST struct ip4_hdr *)l3)->src;
                key[1] = ((REGCST struct ip4_hdr *)l3)->dst;
                size2 = 8;
                *type = NFP_NET_RSS_IPV4;
            }
        } else if ((flags & NIC_RSS_TCP) &&
                   (rss_ctrl & NFP_NET_CFG_RSS_IPV4_TCP)) {
            key[0] = ((REGCST struct ip4_hdr *)l3)->src;
            key[1] = ((REGCST struct ip4_hdr *)l3)->dst;
            reg_cp(&key[2], l4, 4);
            size2 = 12;
            *type = NFP_NET_RSS_IPV4_TCP;
        } else if ((flags & NIC_RSS_UDP) &&
                   (rss_ctrl & NFP_NET_CFG_RSS_IPV4_UDP)) {
            key[0] = ((REGCST struct ip4_hdr *)l3)->src;
            key[1] = ((REGCST struct ip4_hdr *)l3)->dst;
            reg_cp(&key[2], l4, 4);
            size2 = 12;
            *type = NFP_NET_RSS_IPV4_UDP;
        } else if (rss_ctrl & NFP_NET_CFG_RSS_IPV4) {
            key[0] = ((REGCST struct ip4_hdr *)l3)->src;
            key[1] = ((REGCST struct ip4_hdr *)l3)->dst;
            size2 = 8;
            *type = NFP_NET_RSS_IPV4;
        }

    } else if (flags & NIC_RSS_IP6) {
        /* XXX Handle IPv6 frag stuff */
        if (flags & NIC_RSS_FRAG) {
            if (((flags & NIC_RSS_TCP) &&
                 (rss_ctrl & NFP_NET_CFG_RSS_IPV6_TCP)) ||
                ((flags & NIC_RSS_UDP) &&
                 (rss_ctrl & NFP_NET_CFG_RSS_IPV6_UDP)) ||
                (rss_ctrl & NFP_NET_CFG_RSS_IPV4)) {
                size2 = 2 * sizeof(struct in6_addr);
                reg_cp(key, &((REGCST struct ip6_hdr *)l3)->src, size2);
                *type = NFP_NET_RSS_IPV6;
            }
        } else if ((flags & NIC_RSS_TCP) &&
                   (rss_ctrl & NFP_NET_CFG_RSS_IPV6_TCP)) {
            size2 = 2 * sizeof(struct in6_addr);
            reg_cp(key, &((REGCST struct ip6_hdr *)l3)->src, size2);
            reg_cp(&key[size2 >> 2], l4, 4);
            size2 += 4;
            *type = NFP_NET_RSS_IPV6_TCP;
        } else if ((flags & NIC_RSS_UDP) &&
                   (rss_ctrl & NFP_NET_CFG_RSS_IPV6_UDP)) {
            size2 = 2 * sizeof(struct in6_addr);
            reg_cp(key, &((REGCST struct ip6_hdr *)l3)->src, size2);
            reg_cp(&key[size2 >> 2], l4, 4);
            size2 += 4;
            *type = NFP_NET_RSS_IPV6_UDP;
        } else if (rss_ctrl & NFP_NET_CFG_RSS_IPV6) {
            size2 = 2 * sizeof(struct in6_addr);
            reg_cp(key, &((REGCST struct ip6_hdr *)l3)->src, size2);
            *type = NFP_NET_RSS_IPV6;
        }
    }

    *size = size2;
}

/*
 * RSS is a little more complicated as it seems.  The function does a
 * number of things, worth a note
 *
 * - IPv4 and IPv6 are handled separately so that we can use compile
 *   time constants as indices when building the key.
 * - We need to handle logically ORed RSS configurations even though
 *   Linux does not seem to support it.
 * - If TCP/UDP is configured but the packet is fragmented the hash must
 *   only be calculated based on the src/dst IP address so that all
 *   frags go to the same queue.
 *   + For IPv4 packets we look at fragment bits in the header and
 *     then at the protocol field instead of relying on the flags
 *     passed in.  This is because the header extract code does not
 *     indicate the next protocol when a frame contains a IP fragment.
 *   + XXX TODO IPv6 fragments
 * - The code below can almost certainly be optimised more in terms of
 *   instructions count, but it's already hard to read/follow the
 *   logic as it is.  We can probably also do further optimisations by
 *   using the same layout for flags and rss_ctrl flags.
 */
__intrinsic uint32_t
nic_rx_rss(int vport, void *o_l3, void *o_l4,
           void *i_l3, void *i_l4, int flags,
           void *hash_type, void *meta, uint8_t *qid)
{
    __nnr uint32_t key[9];
    __gpr size_t size = 0;
    __gpr uint32_t type = 0;
    __gpr uint32_t h;
    uint32_t rss_ctrl;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;
    struct pcie_out_pkt_desc *out_desc = (struct pcie_out_pkt_desc *)meta;

    rss_ctrl = nic->rss_ctrl;

    /* Only support a single port for now. */
    ctassert(__is_in_reg_or_lmem(o_l3));
    ctassert(__is_in_reg_or_lmem(o_l4));
    ctassert(__is_in_reg_or_lmem(i_l3));
    ctassert(__is_in_reg_or_lmem(i_l4));
    ctassert(__is_in_reg(meta));

    if (!(nic->control & NFP_NET_CFG_CTRL_RSS))
        goto no_rss;

    /* If switch enabled and no RSS configured for VPort */
    if ((nic->control & NFP_NET_CFG_CTRL_L2SWITCH) &&
        !(nic->sw_vp_rss_en & VPORT_MASK(vport)))
        goto no_rss;

    /* From here we assume only one VPort supports RSS */

    if (!rss_ctrl)
        goto no_rss;

    if (((nic->control & NFP_NET_CFG_CTRL_NVGRE) &&
         (flags & NIC_RSS_NVGRE)) ||
        ((nic->control & NFP_NET_CFG_CTRL_VXLAN) &&
         (flags & NIC_RSS_VXLAN))) {
        if ((flags & NIC_RSS_I_TCP) || (flags & NIC_RSS_I_UDP)) {
            if (flags & NIC_RSS_I_IP4) {
                flags |= NIC_RSS_IP4;
                flags &= ~NIC_RSS_IP6;
            }
            if (flags & NIC_RSS_I_IP6) {
                flags |= NIC_RSS_IP6;
                flags &= ~NIC_RSS_IP4;
            }
            if (flags & NIC_RSS_I_TCP) {
                flags |= NIC_RSS_TCP;
                flags &= ~NIC_RSS_UDP;
            }
            if (flags & NIC_RSS_I_UDP) {
                flags |= NIC_RSS_UDP;
                flags &= ~NIC_RSS_TCP;
            }
            __nic_rx_rss_build_key(i_l3, i_l4, flags, rss_ctrl, key,
                                   &size, &type);
            goto key_ready;
        } else {
            flags &= ~ NIC_RSS_TCP;
            flags &= ~ NIC_RSS_UDP;
            /* build key at 'key_outer' */
        }
    }

key_outer:
    __nic_rx_rss_build_key(o_l3, o_l4, flags, rss_ctrl, key,
                               &size, &type);
key_ready:
    if (size == 0)
        goto no_rss;

    h = hash_toeplitz(key, size,
                      (void*)nic->rss_key, HASH_TOEPLITZ_SECRET_KEY_SZ);
    out_desc->flags |= PCIE_DESC_RX_RSS;
    out_desc->meta_len += PCIE_HOST_RX_RSS_PREPEND_SIZE;
    *qid = nic->rss_tbl[h & NFP_NET_CFG_RSS_MASK_of(nic->rss_ctrl)];
    *(uint32_t *)hash_type = type;
    return h;

no_rss:
    *qid = 0;
    *(uint32_t *)hash_type = 0;
    return 0;
}

__intrinsic void
nic_rx_finalise_meta(void *meta, uint16_t len)
{
    struct pcie_out_pkt_desc *out_desc = (struct pcie_out_pkt_desc *)meta;
    ctassert(__is_in_reg_or_lmem(meta));

    /* Data length is original length plus any added meta data */
    out_desc->data_len = len;
    out_desc->one = 1;

    /* We don't support scatter DMA, so set EOP unconditionally */
    out_desc->flags |= PCIE_DESC_RX_EOP;
}

__intrinsic void *
nic_rx_vxlan_ports()
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    return &nic->vxlan_ports;
}

__intrinsic int
nic_rx_promisc()
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    return nic->control & NFP_NET_CFG_CTRL_PROMISC;
}

#endif /* _LIBNIC_NIC_RX_C_ */
/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
