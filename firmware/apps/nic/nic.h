/*
 * Copyright (C) 2015 Netronome Systems, Inc. All rights reserved.
 *
 * @file          apps/nic/nic.h
 * @brief         Header file for NIC local functions/declarations
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _APP_NIC_H_
#define _APP_NIC_H_

#include <nfp.h>
#include <stdint.h>

#include <net/eth.h>
#include <net/gre.h>
#include <net/ip.h>
#include <net/tcp.h>
#include <net/udp.h>
#include <net/vxlan.h>
#include <net/hdr_ext.h>

#include <nfp_chipres.h>
#include <nfp/mem_atomic.h>
#include <nfp/mem_ring.h>

/*
 * Debug support
 */

#ifdef CFG_NIC_APP_DBG_CNTRS
#define NIC_APP_CNTR(_x) mem_incr64(_x)
#else
#define NIC_APP_CNTR(_x)
#endif

#define CREATE_JOURNAL(name)                                    \
    EMEM0_QUEUE_ALLOC(name##_rnum, global);                     \
    _NFP_CHIPRES_ASM(.alloc_mem name##_mem emem0 global         \
                     SZ_2M SZ_2M);                              \
    _NFP_CHIPRES_ASM(.init_mu_ring name##_rnum name##_mem);     \
    __shared __gpr unsigned int dbg_##name##_rnum;              \
    __shared __gpr mem_ring_addr_t dbg_##name##_mem;

#define INIT_JOURNAL(name)                              \
    do {                                                \
        dbg_##name##_rnum = _link_sym(name##_rnum);     \
        dbg_##name##_mem = mem_ring_get_addr(           \
            (__dram void *)_link_sym(name##_mem));      \
    } while(0)

/* APP debugging */
#if defined(CFG_NIC_APP_DBG_JOURNAL)

#define NIC_APP_DBG_APP(name, _x)                                 \
    mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _x);
#define NIC_APP_DBG_APP4(name, _a, _b, _c, _d)                           \
    do {                                                                \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _a); \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _b); \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _c); \
        mem_ring_journal_fast(dbg_##name##_rnum, dbg_##name##_mem, _d); \
    } while (0)
#else
#define NIC_APP_DBG_APP(name, _x)
#define NIC_APP_DBG_APP4(name, _a, _b, _c, _d)
#endif

#ifdef CFG_NIC_APP_DBG_JOURNAL
CREATE_JOURNAL(nic_app_dbg_journal);
#endif /* CFG_NIC_APP_DBG */


/*
 * Header extract cache definitions
 */

/*
 * We read packet data from memory into xfer registers at a two byte
 * offset so that the IP header gets aligned to a word boundary (i.e.,
 * xfer register boundary).  This makes the header extraction code
 * more efficient.
 *
 * @PKT_START_OFF         Offset to start of packet buffer in xfer regs
 */
#define PKT_START_OFF           (2)

/* Enum to indicate which fields are present */
enum {
    HDR_O_ETH      = (1 << 0),
    HDR_O_VLAN     = (1 << 1),
    HDR_O_IP4      = (1 << 2),
    HDR_O_IP6      = (1 << 3),
    HDR_O_IP6_EXT  = (1 << 4),
    HDR_O_TCP      = (1 << 5),
    HDR_O_UDP      = (1 << 6),
    HDR_E_NVGRE    = (1 << 7),
    HDR_E_VXLAN    = (1 << 8),
    HDR_I_ETH      = (1 << 9),
    HDR_I_VLAN     = (1 << 10),
    HDR_I_IP4      = (1 << 11),
    HDR_I_IP6      = (1 << 12),
    HDR_I_IP6_EXT  = (1 << 13),
    HDR_I_TCP      = (1 << 14),
    HDR_I_UDP      = (1 << 15),
};

/* Enum to indicate which offset in the offsets array to use for which header */
enum {
    HDR_OFF_O_ETH = 0,
    HDR_OFF_O_VLAN,
    HDR_OFF_O_L3,
    HDR_OFF_O_L4,
    HDR_OFF_ENCAP,
    HDR_OFF_I_ETH,
    HDR_OFF_I_VLAN,
    HDR_OFF_I_L3,
    HDR_OFF_I_L4,
};

/*
 * Structure to cache packet headers.  Keep copies of all the standard
 * headers in a packet as well as the offsets where they are located
 * in the packet buffer in memory.  A bitmask, @present, is
 * maintained, to easily figure out which headers have been cached.  A
 * second bitmask, @dirty, is used to track which packet headers have
 * been modified and require to be written back to memory.
 */
struct pkt_hdrs {
    uint32_t present;           /* Bitmap of present headers */
    uint32_t dirty;             /* Bitmap of dirty headers */

    int16_t offsets[10];         /* Offset in packet buffer for headers */

    struct eth_hdr o_eth;       /* (Outer) Ethernet header */

    uint16_t payload_off;       /* Offset into packet buffer (in DRAM)
                                 * where the payload of the packet starts */

    struct vlan_hdr o_vlan;     /* (Outer) VLAN header */

    union {
        struct ip4_hdr o_ip4;   /* (Outer) IPv4 header, or */
        struct ip6_hdr o_ip6;   /* (Outer) IPv6 header */
    };

    union {
        struct tcp_hdr o_tcp;   /* (Outer) TCP header, or */
        struct udp_hdr o_udp;   /* (Outer) UDP header */
    };

    struct eth_hdr i_eth;       /* (Inner) Ethernet header */

    struct vlan_hdr i_vlan;     /* (Inner) VLAN header */

    union {
        struct ip4_hdr i_ip4;   /* (Inner) IPv4 header, or */
        struct ip6_hdr i_ip6;   /* (Inner) IPv6 header */
    };

    union {
        struct tcp_hdr i_tcp;   /* (Inner) TCP header, or */
        struct udp_hdr i_udp;   /* (Inner) UDP header */
    };
};

struct pkt_encap {
    union {
        struct {
            struct gre_hdr gre;
            struct nvgre_ext_hdr nvgre;
        };
        struct vxlan_hdr vxlan;
    };
};


/**
 * Populate a header cache from xfer registers
 *
 * @buf_addr     Buffer address in DRAM
 * @buf_off      Offset from buf_addr where packet starts
 * @pkt_buf      An array with the first 64B or so of the packet data
 * @cur_off      Offset into @pkt_buf where packet starts
 * @hc           Header cache where to place the data
 * @ec           Encapsulation header cache where to place the data
 * @encap        Flag set for encapsulated packets
 */
__intrinsic void pkt_hdrs_read(__addr40 char * buf_addr, uint32_t buf_off,
                               __xread uint32_t *pkt_buf, int cur_off,
                               __lmem struct pkt_hdrs *hc,
                               __lmem struct pkt_encap *ec, int encap,
                               __lmem uint16_t *vxlan_ports);

/**
 * Write back any dirty (modified) packet headers
 *
 * @buf_addr     Buffer address in DRAM
 * @hc           Header cache
 * @ec           Encapsulation header cache
 */
__intrinsic void pkt_hdrs_write_back(__addr40 char * buf_addr,
                                     __lmem struct pkt_hdrs *hc,
                                     __lmem struct pkt_encap *ec);

/*
 * RX offloads definitions
 */

/**
 * Check inner csums. If this packet has not been encapsulated in a
 * tunnel or overlay, does nothing.
 *
 * @param port      Input port (physical network interface)
 * @param hdrs      Header cache containing the IPv4 header
 *                  to modify.
 * @param encap     Encap header cache
 * @param len       Packet length
 * @param meta      Metadata for NIC app.
 * @param csum      Checksum prepend word
 *
 */
__intrinsic int rx_check_inner_csum(int port, __lmem struct pkt_hdrs *hdrs,
                                    __lmem struct pkt_encap *encap, int len,
                                    void *meta, uint32_t csum);

/*
 * TX offloads definitions
 */

__packed struct tx_tsk_config {
    union {
        __packed struct {
            unsigned int  sp0:16;
            unsigned int  ip4_id_max:16; /* Wrap IPv4 ID after this value */
        };
        unsigned int __raw;
    };
};

/**
 * Entry point for task offload and LSO; to keep NIC app main
 * short, we put all of the logic for these in here.
 * Examine flags and use header cache to determine what needs
 * to be fixed in the packet, based on what offloads have been
 * requested. Calls tx_tsk_* API’s to do the work. Reports back what
 * headers will need to have their csums recalculated.
 *
 * @param hdrs     Cache with the header to modify.
 * @param meta     Metadata for NIC app.
 * @param tx_cfg   The configuration for the offloads.
 *
 * @return         Returns 0 on success.
 *
 * @note           This API will not calculate checksums. That
 *                 is saved for the main app., in case other packet
 *                 modifications need to happen later.
 */
__intrinsic int tx_tsk_fixup(__lmem struct pkt_hdrs *hdrs, __gpr void *meta,
                             __gpr struct tx_tsk_config *tx_cfg);

/**
 * Sets IPv4 csums. If this packet has not been encapsulated in a
 * tunnel or overlay, does nothing. If descriptor flags say to calculate
 * inner csum, does so.
 *
 * @param hdrs      Header cache containing the IPv4 header
 *                  to modify.
 * @param meta      Metadata for NIC app.
 *
 * @return          Returns 0 on success.
 *
 */
__intrinsic int tx_tsk_set_ipv4_csum(__lmem struct pkt_hdrs *hdrs, void *meta);

__intrinsic int tx_tsk_set_l4_csum(__lmem struct pkt_hdrs *hdrs, void *meta);

#endif /* _APP_NIC_H_ */
