/*
 * Copyright 2015-2016 Netronome Systems, Inc. All rights reserved.
 *
 * @file          lib/infra_basic/infra_basic.h
 * @brief         Interface to the infrastructure blocks
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#ifndef _INFRA_BASIC_H_
#define _INFRA_BASIC_H_

#include <nfp/mem_ring.h>
#include <pkt/pkt.h>
#include <vnic/nfd_common.h>

#if (__REVISION_MIN < __REVISION_B0)
#error "Unsupported chip type"
#else /* (__REVISION_MIN < __REVISION_B0) */

/*
 * 35 == offset of 3 MU address bits in C0 40-bit addressing
 *   Those 3 bits are:
 *      1b0 | 2bxx for IMU island 28+xx
 *      1b1 | 2bxx for EMU island 24+xx
 * 8 == the right shift of that address in a mem_ring_addr_t
 * 24 == the base island of EMUs in B0
 * 28 == the base island of IMUs in B0
 */
#define MEM_RING_ADDR_TO_MUID(_x) (((_x) >> (35 - 8)) & 0x7)
#define ISL_TO_MUID(_x) \
    (((_x) <= 26) ? (((_x) - 24) | 4) : ((_x) - 28))
#define MUID_TO_MEM_RING_ADDR(_x) ((_x) << (35 - 8))
#define MUID_TO_ISL(_x) \
    (((_x) < 4) ? ((_x) + 28) : (((_x) & 0x3) + 24))

#endif /* (__REVISION_MIN < __REVISION_B0) */

/* XXX - These defines are likely redefining existing information, fix */
#define NBI_BUF_META_SZ             2
#define META_LW_CNT                 (NBI_BUF_META_SZ + 5)

enum {
    PKT_PTYPE_DROP     = 0,
    PKT_PTYPE_WIRE     = 1,
    PKT_PTYPE_HOST     = 2,
    PKT_PTYPE_WQ       = 3,
    PKT_PTYPE_NONE     = 4,
    PKT_PTYPE_DROP_SEQ = 5,
    PKT_PTYPE_DROP_WIRE= 6,
    PKT_PTYPE_DROP_HOST= 7,
};

enum {
    PKT_DROPT_ALL = 0,
    PKT_DROPT_SEQ = 1,
};

#define PKT_PORT_BUILD(_type, _subsys, _queue) \
    (((_type) << 13) | ((_subsys) << 10) | (_queue))

#define PKT_DROP_SEQ \
    PKT_PORT_BUILD(PKT_PTYPE_DROP_SEQ, 0, 0)
#define PKT_DROP_WIRE \
    PKT_PORT_BUILD(PKT_PTYPE_DROP_WIRE, 0, 0)
#define PKT_DROP_HOST \
    PKT_PORT_BUILD(PKT_PTYPE_DROP_HOST, 0, 0)
#define PKT_DROP PKT_DROP_HOST
#define PKT_NOTX \
    PKT_PORT_BUILD(PKT_PTYPE_NONE, 0, 0)
#define PKT_WIRE_PORT(_nbi, _q) \
    PKT_PORT_BUILD(PKT_PTYPE_WIRE, (_nbi), (_q))
#define PKT_HOST_PORT_FROMQ(_pcie, _q) \
    PKT_PORT_BUILD(PKT_PTYPE_HOST, (_pcie), (_q))
#define PKT_HOST_PORT(_pcie, _vf, _q) \
    PKT_HOST_PORT_FROMQ(_pcie, NFD_BUILD_QID((_vf), (_q)))
#define PKT_WQ_PORT(_muid, _q) \
    PKT_PORT_BUILD(PKT_PTYPE_WQ, _muid, _q)
#define PKT_WQ_PORT_BYNAME(_name) \
    PKT_PORT_BUILD(PKT_PTYPE_WQ, \
                   MEM_RING_ADDR_TO_MUID(MEM_RING_GET_MEMADDR(_name)), \
                   MEM_RING_GET_NUM(_name))

#define PKT_PORT_TYPE_of(_port)         (((_port) >> 13) & 0x7)
#define PKT_PORT_SUBSYS_of(_port)       (((_port) >> 10) & 0x7)
#define PKT_PORT_DROPTYPE_of(_port)     ((_port) & 0xff)
#define PKT_PORT_QUEUE_of(_port)        ((_port) & 0xff)
#define PKT_PORT_VNIC_of(_port)         NFD_NATQ2VF((_port) & 0xff)
#define PKT_PORT_WQNUM_of(_port)        ((_port) & 0x3ff)
#define PKT_PORT_MUID_of(_port)         (((_port) >> 10) & 0x7)


struct pkt_meta {
    union {
        struct {
            struct nbi_meta_pkt_info p_nbi;

            unsigned p_seq:16;     /* Sequence number */
            unsigned p_offset:16;  /* offset in buffer where the data starts */

            unsigned p_ctm_sz:2;
            unsigned p_ro_ctx:6;   /* Reorder context from NBI or NFD IN */
            unsigned p_is_gro_sequenced:1;
            unsigned p_rx_l3_csum_present:1; /* checksum flags related to inner packet */
            unsigned p_rx_l3_csum_ok:1;
            unsigned p_rx_l4_csum_present:1;
            unsigned p_rx_l4_csum_ok:1;
            unsigned p_rx_l4_tcp:1;
            unsigned p_tx_l3_csum:1;
            unsigned p_tx_l4_csum:1;
            unsigned p_rx_lso:1;
            unsigned p_wq_type:1;
            unsigned p_orig_len:14;

            unsigned p_src:16;
            unsigned p_dst:16;

            /* application specific opaque metadata */
            uint32_t app0;
            uint32_t app1;
        };
        uint32_t __raw[META_LW_CNT];
    };
};

#define p_isl p_nbi.isl
#define p_pnum p_nbi.pnum
#define p_bls p_nbi.bls
#define p_len p_nbi.len
#define p_is_split p_nbi.split
#define p_muptr p_nbi.muptr


#ifndef INFRA_STATE_TYPE
#define INFRA_STATE_TYPE
#endif /* INFRA_STATE_TYPE */

/* Thread-local packet metadata: let compiler pick where to put it. */
INFRA_STATE_TYPE extern struct pkt_meta Pkt;

/**
 * Return a pointer to a packet, of 64B of continuous memory. This function
 * should be recalled for each 64B of memory accessed. Offset must be a
 * multiple of 64B.
 */
__intrinsic __addr40 void* pkt_ptr(const unsigned int offset);

/**
 * Return pointers to the start of the frame (L2 header) in each component.
 *
 * @param frame_off     Set to start of L2
 * @param ctm_ptr       Output pointer to CTM component of packet (can be 0)
 * @param mem_ptr       Output pointer to mem component of packet (can be 0)
 * @param offset       The required offset from the start of the packet
 *
 * If the packet has no CTM component, the CTM pointer will be set to 0.
 */
__intrinsic void pkt_ptrs(unsigned int *frame_off, __addr40 void **ctm_ptr,
                          __addr40 void **mem_ptr, const unsigned int offset);

/**
 * Return CTM split.
 *
 * @return The CTM split. 256 << CTM_SPLIT_LEN gives CTM buffer length in bytes
 */
__intrinsic uint32_t ctm_split();

/**
 * Get a packet from the wire and populate a RX descriptor
 */
__intrinsic int pkt_rx_wire(void);

/**
 * Get a packet from the host and populate a RX descriptor
 */
__intrinsic int pkt_rx_host(void);

/**
 * Get a packet from a work queue
 *
 * @param ring_num      The work queue ring number
 * @param ring_addr     The work queue ring mem address
 */
__intrinsic void pkt_rx_wq(int ring_num, mem_ring_addr_t ring_addr);

/**
 * Send a packet to the wire or the host.
 */
__intrinsic int pkt_tx(void);

/**
 * Give the packet source an opportunity to be initialised.
 *
 * Will not relinquish context until completed. This should be called by a
 * single context on each ME intending to use pkt_rx
 */
void init_rx(void);

/**
 * Give the packet destination an opportunity to be initialised.
 *
 * Will not relinquish context until completed. This should be called by a
 * single context on each ME intending to use pkt_tx
 */
void init_tx(void);

/**
 * Return pointers to the start of the frame (L2 header) in each component.
 *
 * @param frame_off	Returned offset of the start of the packet
 * @param ctm_ptr       Output pointer to CTM component of packet (can be 0)
 * @param mem_ptr       Output pointer to mem component of packet (can be 0)
 * @param offset	The required offset from the start of the packet
 *
 * If the packet has no CTM component, the CTM pointer will be set to 0.
 */
__intrinsic void pkt_ptrs(unsigned int *frame_off, __addr40 void **ctm_ptr,
			  __addr40 void **mem_ptr, const unsigned int offset);

#endif /* _INFRA_BASIC_H_ */
