/*
 * Copyright 2014-2015 Netronome Systems, Inc. All rights reserved.
 *
 * @file          lib/nic/pcie_desc.h
 * @brief         Definition of the various descriptors used with PCIe/NIC
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __PCIE_DESC_H
#define __PCIE_DESC_H

/*
 * ALL DATA STRUCTURE DEFINITIONS ARE ASSUMED TO BE BIG-ENDIAN!
 */

#define PCIE_ME_DESC_SIZE               16
#define PCIE_ME_DESC_SIZE_LW            4
#define PCIE_HOST_RX_DESC_SIZE          8
#define PCIE_HOST_RX_DESC_SIZE_LW       2
#define PCIE_HOST_TX_DESC_SIZE          16
#define PCIE_HOST_TX_DESC_SIZE_LW       4

#define PCIE_HOST_RX_RSS_PREPEND_SIZE   8

#if !defined(__NFP_LANG_ASM)

/*
 * TX/PCI.OUT descriptor definition
 */

/**
 * Flags in the host TX descriptor
 *
 * @PCIE_DESC_TX_CSUM            Perform checksum offload
 * @PCIE_DESC_TX_IP4_CSUM        Add IPv4 Checksum, inner if ENCAP is set
 * @PCIE_DESC_TX_TCP_CSUM        Add TCP checksum, inner if ENCAP is set
 * @PCIE_DESC_TX_UDP_CSUM        Add UDP checksum, inner if ENCAP is set
 * @PCIE_DESC_TX_VLAN            Insert 16bit TCI (VLAN) from descriptor
 * @PCIE_DESC_TX_LSO             Packet is LSO.
 * @PCIE_DESC_TX_ENCAP           Packet is encapsulated
 * @PCIE_DESC_TX_O_IP4_CSUM      Calculate Outer IPv4 checksum if
 *                               ENCAP is set and outer L3 header is IPv4.
 *                               Must not be set if outer is IPv6
 */
#define PCIE_DESC_TX_CSUM        (1 << 7)
#define PCIE_DESC_TX_IP4_CSUM    (1 << 6)
#define PCIE_DESC_TX_TCP_CSUM    (1 << 5)
#define PCIE_DESC_TX_UDP_CSUM    (1 << 4)
#define PCIE_DESC_TX_VLAN        (1 << 3)
#define PCIE_DESC_TX_LSO         (1 << 2)
#define PCIE_DESC_TX_ENCAP       (1 << 1)
#define PCIE_DESC_TX_O_IP4_CSUM  (1 << 0)

/**
 * LSO related definitions (for @lso member of TX descriptor)
 *
 * @PCIE_DESC_TX_LSO_SET_FIN         Set the FIN flag in last frame
 * @PCIE_DESC_TX_LSO_SET_PSH         Set the PSH flag in last frame
 * @PCIE_DESC_TX_LSO_MSS             Extract/Add MSS value from LSO field
 */
#define PCIE_DESC_TX_LSO_SET_FIN     (1 << 15)
#define PCIE_DESC_TX_LSO_SET_PSH     (1 << 14)
#define PCIE_DESC_TX_LSO_MSS(_x)     (_x & 0x3fff)
#define PCIE_DESC_TX_LSO_MSS_of(_x)  (_x & 0x3fff)


/**
 * TX descriptor format
 *
 * Format of the TX descriptor from the host's perspective.  The
 * descriptor mostly contains the host DMA address as well as length,
 * flags and VLAN offload fields. The TX descriptor supports gather
 * DMA with the @eop flag indicating the end of packet, as well as
 * LSO/TSO.
 */
struct pcie_in_host_desc {
    union {
        struct {
            unsigned eop:1;             /* End of packet. */
            unsigned offset:7;          /* Offset in buffer where pkt starts */
            unsigned dma_len:16;        /* Length to DMA for this desc */
            unsigned dma_addr_hi:8;     /* High bits of host buffer address */

            unsigned dma_addr_lo;       /* Low 32bit of host buffer address */

            unsigned flags:8;           /* TX Flags, see @PCIE_DESC_TX_* */
            unsigned lso_seq_cnt:8;     /* Segment #X of N total */
            unsigned lso_end:1;         /* Last packet in a series of LSO packets */
            unsigned sp0:1;
            unsigned mss:14;            /* LSO information, see above */

            unsigned data_len:16;       /* Length of frame + meta data */
            unsigned vlan:16;           /* VLAN tag to add if indicated */
        };
        unsigned __raw[4];
    };
};


/**
 * Descriptor passed from host driver to the application MEs
 */
struct pcie_in_nfp_desc {
    union {
        struct {
            unsigned flags:8;           /* Flags from TX descriptor */
            unsigned lso_seq_cnt:8;     /* Segment #X of N total */
            unsigned lso_end:1;         /* Last pkt of LSO sequence */
            unsigned sp0:1;
            unsigned mss:14;            /* LSO info from TX descriptor */

            unsigned data_len:16;       /* Data length from TX descriptor */
            unsigned vlan:16;           /* VLAN from TX descriptor */
        };
        unsigned __raw[2];
    };
};



/*
 * RX/PCI.OUT descriptor formats
 */

/**
 * Freelist descriptor
 *
 * Posted by the host on the freelist
 */
struct pcie_out_buf_desc {
    union {
        struct {
            unsigned zero:1;            /* Must be zero */
            unsigned spare:23;
            unsigned dma_addr_hi:8;     /* High bits of the buffer address */

            unsigned dma_addr_lo;       /* Low bits of the buffer address */
        };
        unsigned __raw[2];
    };
};


/**
 * Flags in the RX descriptor
 *
 * @PCIE_DESC_RX_SPARE2
 * @PCIE_DESC_RX_I_IP4_CSUM     Inner IPv4 checksum checked
 * @PCIE_DESC_RX_I_IP4_CSUM_OK  Inner IPv4 checksum correct
 * @PCIE_DESC_RX_I_TCP_CSUM     Inner TCP checksum checked
 * @PCIE_DESC_RX_I_TCP_CSUM_OK  Inner TCP checksum correct
 * @PCIE_DESC_RX_I_UDP_CSUM     Inner UDP checksum checked
 * @PCIE_DESC_RX_I_UDP_CSUM_OK  Inner UDP checksum correct
 * @PCIE_DESC_RX_SPARE
 * @PCIE_DESC_RX_EOP            End of packet. Must be 1 for now
 * @PCIE_DESC_RX_IP4_CSUM       Outer IPv4 checksum checked
 * @PCIE_DESC_RX_IP4_CSUM_OK    Outer IPv4 checksum correct
 * @PCIE_DESC_RX_TCP_CSUM       Outer TCP checksum checked
 * @PCIE_DESC_RX_TCP_CSUM_OK    Outer TCP checksum correct
 * @PCIE_DESC_RX_UDP_CSUM       Outer UDP checksum checked
 * @PCIE_DESC_RX_UDP_CSUM_OK    Outer UDP checksum correct
 * @PCIE_DESC_RX_VLAN           VLAN stripped and added to descriptor
 */
#define PCIE_DESC_RX_SPARE2             (1 << 15)
#define PCIE_DESC_RX_I_IP4_CSUM         (1 << 14)
#define PCIE_DESC_RX_I_IP4_CSUM_OK      (1 << 13)
#define PCIE_DESC_RX_I_TCP_CSUM         (1 << 12)
#define PCIE_DESC_RX_I_TCP_CSUM_OK      (1 << 11)
#define PCIE_DESC_RX_I_UDP_CSUM         (1 << 10)
#define PCIE_DESC_RX_I_UDP_CSUM_OK      (1 <<  9)
#define PCIE_DESC_RX_SPARE              (1 <<  8)

#define PCIE_DESC_RX_EOP                (1 <<  7)
#define PCIE_DESC_RX_IP4_CSUM           (1 <<  6)
#define PCIE_DESC_RX_IP4_CSUM_OK        (1 <<  5)
#define PCIE_DESC_RX_TCP_CSUM           (1 <<  4)
#define PCIE_DESC_RX_TCP_CSUM_OK        (1 <<  3)
#define PCIE_DESC_RX_UDP_CSUM           (1 <<  2)
#define PCIE_DESC_RX_UDP_CSUM_OK        (1 <<  1)
#define PCIE_DESC_RX_VLAN               (1 <<  0)

/**
 * Descriptor to be passed from application MEs to host driver
 */
struct pcie_out_pkt_desc {
    union {
        struct {
            unsigned one:1;             /* Must be set to 1 */
            unsigned meta_len:7;        /* Length of prepended metadata */
            unsigned resevered:8;       /* Reserved field for NFD */
            unsigned data_len:16;       /* Length of the frame + meta data */

            unsigned vlan:16;           /* VLAN if stripped */
            unsigned flags:16;          /* RX flags. See @PCIE_DESC_RX_* */
        };
        unsigned __raw[2];
    };
};

#endif /* !defined(__NFP_LANG_ASM) */

#endif /* __PCIE_DESC_H */
