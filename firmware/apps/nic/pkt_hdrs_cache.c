/*
 * Copyright 2014-2015 Netronome, Inc.
 *
 * @file          apps/nic/pkt_hdrs_cache.c
 * @brief         Utility functions to cache packet headers in LM
 */


#include <nfp.h>
#include <stdint.h>

#include <nfp/mem_bulk.h>

#include <net/eth.h>
#include <net/gre.h>
#include <net/ip.h>
#include <net/tcp.h>
#include <net/udp.h>
#include <net/hdr_ext.h>

#include <std/reg_utils.h>

#include <nfp_net_ctrl.h>

#include "nic.h"

/*
 * Read a packet header and extract/store useful information in a
 * struct pkt_hdrs.  The function minimises DRAM accesses by reading in
 * packet data from DRAM in chunks of 64Bytes (it actually expects the
 * first read to have been performed and the local copy (@pkt_buf) to
 * be pre-populated.  This seems somewhat asymmetric but it allows to
 * perform some initial checks on the packet header in the calling
 * code.
 *
 * This function takes two sets of arguments:
 * - @buf_addr is the start address of the packet buffer in DRAM and
 *   @buf_off is the offset from where the current local chunk was
 *   extracted from.
 * - @pkt_buf and @cur_off describe the local copy/chunk of the packet
 *   header.  @pkt_buf contains the data and @cur_off is the offset
 *   into this buffer from where to extract the next header.
 *
 * It populates the header cache pointed to by @hc.
 *
 * This function currently copies the local copy of the packet header
 * chunk into LM (@src_buf/@src_off) to allow for best/easiest access
 * by the header extract functions.  Once the header extract library
 * supports extraction from transfer registers we may skip this step.
 *
 * Note, although we get passed in an array of __xread uint32_t
 * *pkt_buf we use a local variable, @tmp_buf to read in additional
 * bytes for the packet header as otherwise the compiler seems to
 * barf in some cases...
 */
__intrinsic void
pkt_hdrs_read(__addr40 char * buf_addr, uint32_t buf_off,
              __xread uint32_t *pkt_buf, int cur_off,
              __lmem struct pkt_hdrs *hc,
              __lmem struct pkt_encap *ec, int tunnel,
              __lmem uint16_t *vxlan_ports)
{
    __shared __lmem uint32_t src_buf[16];
    __gpr int src_off = cur_off;
    __gpr int res;
    __gpr int next_proto;
    __gpr int len;
    int i;

    /* Clear the important parts of the local packet header structure */
    hc->present = 0;
    hc->dirty = 0;
    reg_zero(&hc->offsets, sizeof(hc->offsets));

    /* Copy packet buffer from xread to lmem for easier extract */
    reg_cp(src_buf, pkt_buf, sizeof(src_buf));

    /* Note we don't bother checking if the header fits for the first
     * few headers as they are guaranteed to be in the first 64 -
     * (PKT_START_OFF + NET_CSUM_PREPEND_LEN) bytes. */

    /* Ethernet */
    hc->present |= HDR_O_ETH;
    hc->offsets[HDR_OFF_O_ETH] = buf_off;

    res = he_eth(src_buf, src_off, &hc->o_eth);
    len = HE_RES_LEN_of(res);
    next_proto = HE_RES_PROTO_of(res);

    buf_off += len;
    src_off += len;

    if (next_proto == HE_UNKNOWN)
        goto out_done;

    /* VLAN */
    if (next_proto == HE_8021Q) {
        hc->present |= HDR_O_VLAN;
        hc->offsets[HDR_OFF_O_VLAN] = buf_off;

        res = he_vlan(src_buf, src_off, &hc->o_vlan);
        len = HE_RES_LEN_of(res);
        next_proto = HE_RES_PROTO_of(res);

        buf_off += len;
        src_off += len;

        if (next_proto == HE_UNKNOWN)
            goto out_done;
    }

    /* IP */
    if (next_proto == HE_IP4) {
        hc->present |= HDR_O_IP4;
        hc->offsets[HDR_OFF_O_L3] = buf_off;

        res = he_ip4(src_buf, src_off, &hc->o_ip4);
        len = HE_RES_LEN_of(res);
        next_proto = HE_RES_PROTO_of(res);

    } else if (next_proto == HE_IP6) {
        if (!he_ip6_fit(sizeof(src_buf), src_off)) {
            /* Reload cache. buf_off is starting offset for the next
             * header and this is likely to be a unaligned read. */

            mem_read64(pkt_buf, (__addr40 void *)
                       ((uint64_t) buf_addr + buf_off), sizeof(src_buf));

            reg_cp(src_buf, pkt_buf, sizeof(src_buf));
            src_off = 0;
        }
        hc->present |= HDR_O_IP6;
        hc->offsets[HDR_OFF_O_L3] = buf_off;

        res = he_ip6(src_buf, src_off, &hc->o_ip6);
        len = HE_RES_LEN_of(res);
        next_proto = HE_RES_PROTO_of(res);
        /* TODO: Handle IPv6 extension headers! */
    }

    buf_off += len;
    src_off += len;

    if (next_proto == HE_UNKNOWN)
        goto out_done;

    /* From here on, we need to check if @pkt_buf still has enough
     * bytes in it for the next header. */
    if (((next_proto == HE_TCP) && !he_tcp_fit(sizeof(src_buf), src_off)) ||
        ((next_proto == HE_UDP) && !he_udp_fit(sizeof(src_buf), src_off)) ||
        ((next_proto == HE_GRE) && !he_gre_fit(sizeof(src_buf), src_off))) {
        /* Reload cache. buf_off is starting offset for the next
         * header and this is likely to be a unaligned read. */

        mem_read64(pkt_buf, (__addr40 void *)
                   ((uint64_t) buf_addr + buf_off), sizeof(src_buf));


        reg_cp(src_buf, pkt_buf, sizeof(src_buf));
        src_off = 0;
    }

    if (next_proto == HE_TCP) {
        hc->present |= HDR_O_TCP;
        hc->offsets[HDR_OFF_O_L4] = buf_off;

        res = he_tcp(src_buf, src_off, &hc->o_tcp);
        len = HE_RES_LEN_of(res);
        next_proto = HE_RES_PROTO_of(res);

    } else if (next_proto == HE_UDP) {
        hc->present |= HDR_O_UDP;
        hc->offsets[HDR_OFF_O_L4] = buf_off;

        res = he_udp(src_buf, src_off, &hc->o_udp, NET_VXLAN_PORT);
        len = HE_RES_LEN_of(res);

        if (tunnel)
            /* if the driver says it is an tunnel pkt (TX) then at this
             * point has to be VXLAN, regardless of outer UDP dport */
            next_proto = HE_VXLAN;
        else
            if (vxlan_ports) {
                /* RX path */
                next_proto = HE_NONE;
                for (i = 0; i < NFP_NET_N_VXLAN_PORTS; i++) {
                    if (vxlan_ports[i] && (vxlan_ports[i] == hc->o_udp.dport)) {
                        next_proto = HE_VXLAN;
                        break;
                    }
                }
            }

        if (next_proto == HE_VXLAN) {
            buf_off += len;
            src_off += len;

            if (!he_vxlan_fit(sizeof(src_buf), src_off)) {
                /* Reload cache. buf_off is starting offset for the next
                 * header and this is likely to be a unaligned read. */

                mem_read64(pkt_buf, (__addr40 void *)
                           ((uint64_t) buf_addr + buf_off), sizeof(src_buf));


                reg_cp(src_buf, pkt_buf, sizeof(src_buf));
                src_off = 0;
            }

            hc->present |= HDR_E_VXLAN;
            hc->offsets[HDR_OFF_ENCAP] = buf_off;

            res = he_vxlan(src_buf, src_off, &ec->vxlan);
            len = HE_RES_LEN_of(res);
            next_proto = HE_RES_PROTO_of(res);

            goto process_inner;
        }
    } else if (next_proto == HE_GRE) {
        hc->offsets[HDR_OFF_ENCAP] = buf_off;

        res = he_gre(src_buf, src_off, &ec->gre);
        len = HE_RES_LEN_of(res);
        next_proto = HE_RES_PROTO_of(res);

        /* only support NVGRE */
        if ((next_proto != HE_ETHER) || !(NET_GRE_IS_NVGRE(ec->gre.flags)))
            goto out_done;

        hc->present |= HDR_E_NVGRE;

        he_gre_nvgre(src_buf, src_off, &ec->nvgre);

        /* note: len was returned by he_gre(), not he_gre_nvgre()*/
    process_inner:
        buf_off += len;
        src_off += len;

        /* Start processing inner */
        if (!he_eth_fit(sizeof(src_buf), src_off)) {
            /* Reload cache. buf_off is starting offset for the next
             * header and this is likely to be a unaligned read. Note
             * that there is a 2B offset added so that he_ip4 does an
             * aligned memcpy */

            mem_read64(pkt_buf, (__addr40 void *)
                       ((uint64_t) buf_addr + buf_off), sizeof(src_buf));

            reg_cp(src_buf, pkt_buf, sizeof(src_buf));
            src_off = 0;
        }

        hc->present |= HDR_I_ETH;
        hc->offsets[HDR_OFF_I_ETH] = buf_off;

        res = he_eth(src_buf, src_off, &hc->i_eth);
        len = HE_RES_LEN_of(res);
        next_proto = HE_RES_PROTO_of(res);

        buf_off += len;
        src_off += len;

        if (next_proto == HE_UNKNOWN)
            goto out_done;

        /* inner VLAN */
        if (next_proto == HE_8021Q) {
            hc->present |= HDR_I_VLAN;
            hc->offsets[HDR_OFF_I_VLAN] = buf_off;

            res = he_vlan(src_buf, src_off, &hc->i_vlan);
            len = HE_RES_LEN_of(res);
            next_proto = HE_RES_PROTO_of(res);

            buf_off += len;
            src_off += len;

            if (next_proto == HE_UNKNOWN)
                goto out_done;
        }

        /* read inner IP so that it is aligned in xfer regs */
        mem_read64(pkt_buf, (__addr40 void *) ((uint64_t) buf_addr + buf_off),
                   sizeof(src_buf));

        reg_cp(src_buf, pkt_buf, sizeof(src_buf));
        src_off = 0;

        /* inner IP */
        if (next_proto == HE_IP4) {
            hc->present |= HDR_I_IP4;
            hc->offsets[HDR_OFF_I_L3] = buf_off;

            res = he_ip4(src_buf, src_off, &hc->i_ip4);
            len = HE_RES_LEN_of(res);
            next_proto = HE_RES_PROTO_of(res);

        } else if (next_proto == HE_IP6) {
            hc->present |= HDR_I_IP6;
            hc->offsets[HDR_OFF_I_L3] = buf_off;

            res = he_ip6(src_buf, src_off, &hc->i_ip6);
            len = HE_RES_LEN_of(res);
            next_proto = HE_RES_PROTO_of(res);
            /* TODO: Handle IPv6 extension headers! */
        }

        buf_off += len;
        src_off += len;

        if (next_proto == HE_UNKNOWN)
            goto out_done;

        if (((next_proto == HE_TCP) && !he_tcp_fit(sizeof(src_buf), src_off)) ||
            ((next_proto == HE_UDP) && !he_udp_fit(sizeof(src_buf), src_off))) {
            /* Reload cache. buf_off is starting offset for the next
             * header and this is likely to be a unaligned read. */

            mem_read64(pkt_buf, (__addr40 void *)
                       ((uint64_t) buf_addr + buf_off), sizeof(src_buf));

            reg_cp(src_buf, pkt_buf, sizeof(src_buf));
            src_off = 0;
        }

        if (next_proto == HE_TCP) {
            hc->present |= HDR_I_TCP;
            hc->offsets[HDR_OFF_I_L4] = buf_off;

            res = he_tcp(src_buf, src_off, &hc->i_tcp);
            len = HE_RES_LEN_of(res);
            next_proto = HE_RES_PROTO_of(res);

        } else if (next_proto == HE_UDP) {
            hc->present |= HDR_I_UDP;
            hc->offsets[HDR_OFF_I_L4] = buf_off;

            res = he_udp(src_buf, src_off, &hc->i_udp, 0);
            len = HE_RES_LEN_of(res);
            next_proto = HE_RES_PROTO_of(res);
        }

    }

    buf_off += len;
    src_off += len;

out_done:
    /* Stash away where the payload starts */
    hc->payload_off = buf_off;
}


/*
 * This function writes any locally updated packet headers back to DRAM.
 *
 * It currently is not very efficient as it writes back a header at a
 * time.  It would be better to combine the writes as much as
 * possible.  However, this may not be as straight forward if IP
 * options are present or if some headers are unmodified.  The best
 * way to optimise this is to implement special handling for a number
 * of common cases (eth, vlan, ipv4 (no option), tcp/udp) and use the
 * slow fallback implementation below in other case.
 *
 * Note, this should probably also be extended to support pre-pending
 * of data.  This is needed both for RX and TX.  For RX we need to
 * prepend the RSS hash and for TX we need to prepend the csum control
 * word.
 */
__intrinsic void
pkt_hdrs_write_back(__addr40 char * buf_addr, __lmem struct pkt_hdrs *hc,
                    __lmem struct pkt_encap *ec)
{
    __xwrite uint32_t buf[16];

    if (hc->dirty & HDR_O_ETH) {
        /* The '+ 2' rounds up the size of the Ethernet to a full 32bit*/
        reg_cp(buf, &hc->o_eth, 16);

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_O_ETH],
                   sizeof(hc->o_eth));

        hc->dirty &= ~HDR_O_ETH;
    }

    if (hc->dirty & HDR_O_VLAN) {
        reg_cp(buf, &hc->o_vlan, sizeof(hc->o_vlan));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_O_VLAN],
                   sizeof(hc->o_vlan));

        hc->dirty &= ~HDR_O_VLAN;
    }

    if (hc->dirty & HDR_O_IP4) {
        reg_cp(buf, &hc->o_ip4, sizeof(hc->o_ip4));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_O_L3],
                   sizeof(hc->o_ip4));

        hc->dirty &= ~HDR_O_IP4;
    }

    if (hc->dirty & HDR_O_IP6) {
        reg_cp(buf, &hc->o_ip6, sizeof(hc->o_ip6));
        /* The IPv6 header is multiples of 64bits, use mem_write64 here */
        mem_write64(buf, buf_addr + hc->offsets[HDR_OFF_O_L3],
                   sizeof(hc->o_ip6));

        hc->dirty &= ~HDR_O_IP6;
    }

    if (hc->dirty & HDR_O_TCP) {
        reg_cp(buf, &hc->o_tcp, sizeof(hc->o_tcp));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_O_L4],
                   sizeof(hc->o_tcp));

        hc->dirty &= ~HDR_O_TCP;
    }

    if (hc->dirty & HDR_O_UDP) {
        reg_cp(buf, &hc->o_udp, sizeof(hc->o_udp));
        /* The UDP header is multiples of 64bits, use mem_write64 here */
        mem_write64(buf, buf_addr + hc->offsets[HDR_OFF_O_L4],
                   sizeof(hc->o_udp));

        hc->dirty &= ~HDR_O_UDP;
    }

    if (hc->dirty & HDR_E_NVGRE) {
        reg_cp(buf, &ec->gre, sizeof(ec->gre));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_ENCAP],
                   sizeof(ec->gre));

        reg_cp(buf, &ec->nvgre, sizeof(ec->nvgre));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_ENCAP] +
                   sizeof(struct gre_hdr), sizeof(ec->nvgre));

        hc->dirty &= ~HDR_E_NVGRE;
    }

    if (hc->dirty & HDR_E_VXLAN) {
        reg_cp(buf, &ec->vxlan, sizeof(ec->vxlan));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_ENCAP],
                   sizeof(ec->vxlan));
        hc->dirty &= ~HDR_E_VXLAN;
    }

    if (hc->dirty & HDR_I_ETH) {
        /* The '+ 2' rounds up the size of the Ethernet to a full 32bit*/
        reg_cp(buf, &hc->i_eth, 16);

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_I_ETH],
                   sizeof(hc->i_eth));

        hc->dirty &= ~HDR_I_ETH;
    }

    if (hc->dirty & HDR_I_VLAN) {
        reg_cp(buf, &hc->i_vlan, sizeof(hc->i_vlan));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_I_VLAN],
                   sizeof(hc->i_vlan));

        hc->dirty &= ~HDR_I_VLAN;
    }

    if (hc->dirty & HDR_I_IP4) {
        reg_cp(buf, &hc->i_ip4, sizeof(hc->i_ip4));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_I_L3],
                   sizeof(hc->i_ip4));

        hc->dirty &= ~HDR_I_IP4;
    }

    if (hc->dirty & HDR_I_IP6) {
        reg_cp(buf, &hc->i_ip6, sizeof(hc->i_ip6));
        /* The IPv6 header is multiples of 64bits, use mem_write64 here */
        mem_write64(buf, buf_addr + hc->offsets[HDR_OFF_I_L3],
                   sizeof(hc->i_ip6));

        hc->dirty &= ~HDR_I_IP6;
    }

    if (hc->dirty & HDR_I_TCP) {
        reg_cp(buf, &hc->i_tcp, sizeof(hc->i_tcp));

        mem_write8(buf, buf_addr + hc->offsets[HDR_OFF_I_L4],
                   sizeof(hc->i_tcp));

        hc->dirty &= ~HDR_I_TCP;
    }

    if (hc->dirty & HDR_I_UDP) {
        reg_cp(buf, &hc->i_udp, sizeof(hc->i_udp));
        /* The UDP header is multiples of 64bits, use mem_write64 here */
        mem_write64(buf, buf_addr + hc->offsets[HDR_OFF_I_L4],
                   sizeof(hc->i_udp));

        hc->dirty &= ~HDR_I_UDP;
    }
}
