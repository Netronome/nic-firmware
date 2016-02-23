/*
 * Copyright 2015 Netronome, Inc.
 *
 * @file          lib/infra_basic/infra_basic.h
 * @brief         Interface to the infrastructure blocks
 *
 */
#ifndef _INFRA_BASIC_H_
#define _INFRA_BASIC_H_

#include <pkt/pkt.h>

/* XXX - These defines are likely redefining existing information, fix */
#define NBI_BUF_META_SZ             2
#define PBUF_META_SIZE              4
#define RX_OUT_LW_CNT               (1 + NBI_BUF_META_SZ + 2)
#define LU_OUT_LW_CNT               (2 + NBI_BUF_META_SZ + 2)

enum infra_src {
    FROM_WIRE,
    FROM_HOST,
};

enum infra_dst {
    TO_WIRE,
    TO_HOST,
    TO_WIRE_DROP,
    TO_HOST_DROP,
};

/**
 * Descriptor structure as handed over from the RX and PI.
 */
struct pkt_rx_desc {
    union {
        struct {
            unsigned seq:16;     /** Sequence number */
            unsigned seqr:3;     /** Sequencer number from NBI or NFD IN */
            unsigned pad0:5;
            unsigned src:8;      /** VF queue if pkt was received from host
                                  *  port if pkt was received from wire */

            struct nbi_meta_pkt_info nbi;

            /* application specific opaque metadata */
            uint32_t app0;
            uint32_t app1;
        };
        uint32_t values[RX_OUT_LW_CNT];
    };
};

/**
 * Descriptor structure to transmit a packet (i.e., passed to RO).
 *
 * Original OVS pkt_tx_desc has been preserved with the NBI meta postpended.
 *
 * XXX Some of these fields are defined in ro.uc.  Need to move them here!
 *
 * XXX either merge nbi_meta_pkt_info into other fields or abandon preserving
 *     the original OVS metadata.
 *
 * retry_count allows the application to control how many times the library
 * will attempt to send before returning an error. Setting a high value could
 * cause head of line blocking.
 */
struct pkt_tx_desc {
    union {
        struct {
            unsigned pad0:1;
            unsigned tx_l3_csum:1;  /** TX L3 CSUM offload 1=enabled */
            unsigned tx_l4_csum:1;  /** TX L4 CSUM offload 1=enabled */
            unsigned seqr:3;     /** Sequencer number from NBI */
            unsigned seq:16;     /** Sequence number */
            signed offset:10;    /** offset in buffer where the data starts */

            unsigned dest:8;     /** VF queue to use when sending to host
                                     port to use when sending to the wire */
            unsigned retry_count:12; /** number of retries before giving up */
            unsigned pad1:12;

            struct nbi_meta_pkt_info nbi;

            /* application specific opaque metadata */
            uint32_t app0;
            uint32_t app1;
        };
        uint32_t values[LU_OUT_LW_CNT];
    };
};

/**
 * Return a pointer to a packet, of 64B of continuous memory. This function
 * should be recalled for each 64B of memory accessed. Offset must be a
 * multiple of 64B.
 */
__intrinsic __addr40 void* pkt_ptr(__nnr const struct pkt_rx_desc *rxd,
                                   const unsigned int offset);

/**
 * Return pointers to the start of the frame (L2 header) in each component.
 *
 * @param rxd           Packet receive descriptor.
 * @param frame_off     Set to start of L2
 * @param ctm_ptr       Output pointer to CTM component of packet (can be 0)
 * @param mem_ptr       Output pointer to mem component of packet (can be 0)
 *
 * If the packet has no CTM component, the CTM pointer will be set to 0.
 */
__intrinsic void pkt_ptrs(__nnr const struct pkt_rx_desc *rxd,
                          unsigned int *frame_off,
                          __addr40 void **ctm_ptr,
                          __addr40 void **mem_ptr);

/**
 * Return CTM split.
 *
 * @return The CTM split. 256 << CTM_SPLIT_LEN gives CTM buffer length in bytes
 */
__intrinsic uint32_t ctm_split();

__intrinsic int16_t pkt_len(__nnr const struct pkt_rx_desc *rxd);

/**
 * Get a packet from the wire or the host and populate a RX descriptor
 *
 * @param src          source for the packet: FROM_WIRE or FROM_HOST
 * @param rxd          RX descriptor to return
 */
__intrinsic void pkt_rx(enum infra_src src, __nnr struct pkt_rx_desc *rxd);

/**
 * Send a packet to the wire or the host.
 *
 * @param dst           destination for packet: TO_WIRE or TO_HOST
 * @param txd           TX descriptor used as input
 *
 * Return 0 on success or -1 after failing to get space on egress queue
 * txd->retry_count times.
 */
__intrinsic int pkt_tx(enum infra_dst dst, __nnr struct pkt_tx_desc *txd);

/**
 * Reinitialise the packet destination
 *
 * In the event that the packet destination looses link, this should be called
 * to reset any internal state for that destination
 *
 * @param dst           packet destination to reinitialise: TO_WIRE or TO_HOST
 */
void reinit_tx(const enum infra_dst dst);

/**
 * Give the packet source an opportunity to be initialised.
 *
 * Will not relinquish context until completed. This should be called by a
 * single context on each ME intending to use pkt_rx
 *
 * @param src           packet source to initialise: FROM_WIRE or FROM_HOST
 */
void init_rx(const enum infra_src src);

/**
 * Give the packet destination an opportunity to be initialised.
 *
 * Will not relinquish context until completed. This should be called by a
 * single context on each ME intending to use pkt_tx
 *
 * @param dst           packet destination to initialise: TO_WIRE or TO_HOST
 */
void init_tx(const enum infra_dst dst);

#endif /* _INFRA_BASIC_H_ */
