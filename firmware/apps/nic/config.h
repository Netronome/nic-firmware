/*
 * Copyright 2015 Netronome, Inc.
 *
 * @file          apps/nic/config.h
 * @brief         Infrastructure configuration for the NIC application.
 */

#ifndef __APP_CONFIG_H__
#define __APP_CONFIG_H__

#include <platform.h>

/*
 * RX/TX configuration
 * - Set pkt offset the NBI uses
 * - Set the number of bytes the MAC prepends data into
 * - Configure RX checksum offload so the wire can validate checksums
 */
#define PKT_NBI_OFFSET           64
#define MAC_PREPEND_BYTES        8
#define HOST_PREPEND_BYTES       0
#define CFG_RX_CSUM_PREPEND

/*
 * NBI configuration
 */
/* DMA */
#define NBI_PKT_PREPEND_BYTES    MAC_PREPEND_BYTES
#define NBI_DMA_BP0_BLQ_TARGET   0,0
#define NBI_DMA_BP1_BLQ_TARGET   0,0
#define NBI_DMA_BP2_BLQ_TARGET   0,0
#define NBI_DMA_BP3_BLQ_TARGET   0,0
#define NBI_DMA_BP4_BLQ_TARGET   0,0
#define NBI_DMA_BP5_BLQ_TARGET   0,0
#define NBI_DMA_BP6_BLQ_TARGET   0,0
#define NBI_DMA_BP7_BLQ_TARGET   0,0
/* We use 2 islands for RX. Configure their CTM buffers for RX */
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND0   0,0,0
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND1   0,0,0
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND2   1,256,127
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND3   1,256,127
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND4   0,0,0
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND5   0,0,0
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND6   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND0   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND1   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND2   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND3   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND4   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND5   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND6   0,0,0
/* TM */
#define NBI_TM_NUM_SEQUENCERS    1
#define NBI_TM_ENABLE_SEQUENCER0 1

/* Determine the NBI TM queue depth based on port configuration. */
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 <= 1
    /* 1-port Configuration. */
    #define NS_PLATFORM_NBI_TM_0_QSIZE 9  /* 2^9 packet buffers per queue */
#elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 <= 2
    /* 2-port Configuration. */
    #define NS_PLATFORM_NBI_TM_0_QSIZE 8  /* 2^8 packet buffers per queue */
#elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 <= 4
    /* 3- or 4-port Configuration. */
    #define NS_PLATFORM_NBI_TM_0_QSIZE 7  /* 2^7 packet buffers per queue */
#elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 <= 8
    /* 5- to 8-port Configuration. */
    #define NS_PLATFORM_NBI_TM_0_QSIZE 6  /* 2^6 packet buffers per queue */
#else
    /* Unsupported configuration */
    #error "No support for more than 8 ports per MAC/NBI island"
#endif

#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 <= 1
    /* 1-port Configuration. */
    #define NS_PLATFORM_NBI_TM_1_QSIZE 9  /* 2^9 packet buffers per queue */
#elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 <= 2
    /* 2-port Configuration. */
    #define NS_PLATFORM_NBI_TM_1_QSIZE 8  /* 2^8 packet buffers per queue */
#elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 <= 4
    /* 3- or 4-port Configuration. */
    #define NS_PLATFORM_NBI_TM_1_QSIZE 7  /* 2^7 packet buffers per queue */
#elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 <= 8
    /* 5- to 8-port Configuration. */
    #define NS_PLATFORM_NBI_TM_1_QSIZE 6  /* 2^6 packet buffers per queue */
#else
    /* Unsupported configuration */
    #error "No support for more than 8 ports per MAC/NBI island"
#endif

/* Initialize the NBI TM queues associated with each port. */
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 0
    #define NBI0_TM_Q_CFG_RANGE0      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(0), \
        NS_PLATFORM_NBI_TM_QID_HI(0), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 1
    #define NBI0_TM_Q_CFG_RANGE1      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(1), \
        NS_PLATFORM_NBI_TM_QID_HI(1), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 2
    #define NBI0_TM_Q_CFG_RANGE2      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(2), \
        NS_PLATFORM_NBI_TM_QID_HI(2), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 3
    #define NBI0_TM_Q_CFG_RANGE3      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(3), \
        NS_PLATFORM_NBI_TM_QID_HI(3), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 4
    #define NBI0_TM_Q_CFG_RANGE4      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(4), \
        NS_PLATFORM_NBI_TM_QID_HI(4), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 5
    #define NBI0_TM_Q_CFG_RANGE5      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(5), \
        NS_PLATFORM_NBI_TM_QID_HI(5), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 6
    #define NBI0_TM_Q_CFG_RANGE6      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(6), \
        NS_PLATFORM_NBI_TM_QID_HI(6), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 7
    #define NBI0_TM_Q_CFG_RANGE7      \
        1,                            \
        NS_PLATFORM_NBI_TM_QID_LO(7), \
        NS_PLATFORM_NBI_TM_QID_HI(7), \
        NS_PLATFORM_NBI_TM_0_QSIZE
#endif

#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 0
    #define NBI1_TM_Q_CFG_RANGE0                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 0), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 0), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 1
    #define NBI1_TM_Q_CFG_RANGE1                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 1), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 1), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 2
    #define NBI1_TM_Q_CFG_RANGE2                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 2), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 2), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 3
    #define NBI1_TM_Q_CFG_RANGE3                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 3), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 3), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 4
    #define NBI1_TM_Q_CFG_RANGE4                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 4), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 4), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 5
    #define NBI1_TM_Q_CFG_RANGE5                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 5), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 5), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 6
    #define NBI1_TM_Q_CFG_RANGE6                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 6), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 6), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 7
    #define NBI1_TM_Q_CFG_RANGE7                                          \
        1,                                                                \
        (NS_PLATFORM_NBI_TM_QID_LO(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 7), \
        (NS_PLATFORM_NBI_TM_QID_HI(NS_PLATFORM_NUM_PORTS_PER_MAC_0) + 7), \
        NS_PLATFORM_NBI_TM_1_QSIZE
#endif

/*
 * BLM configuration
 */
#include <infra/blm_custom.h>


/*
 * GRO configuration
 * Note: GRO_NUM_BLOCKS is expected to be passed in via a -D
 *       GRO_CTX_PER_BLOCK is computed based on GRO_NUM_BLOCKS
 */
#define GRO_ISL					36

/* Ingress sequencer numbers (1/2/3/4) for packets from the wire will be
   mapped to GRO CTX numbers 1/3/5/7; those for packets from NFD (0/1/2/3)
   will be mapped to GRO CTX numbers 0/2/4/6.  So we need 8 GRO CTX's
   total.  The number of GRO blocks is expected to be passed in from the
   build via -D define, so we need to calculate GRO CTX's per block so
   that we always have (at least) 8.
*/
#ifndef GRO_NUM_BLOCKS
    #error "GRO_NUM_BLOCKS must be defined"
#endif

#if (GRO_NUM_BLOCKS > 8)
    #define GRO_CTX_PER_BLOCK       1
    #warning "Cannot properly configure GRO, GRO_NUM_BLOCKS is" GRO_NUM_BLOCKS "GRO_CTX_PER_BLOCK set to" GRO_CTX_PER_BLOCK
#elseif (GRO_NUM_BLOCKS < 1)
    #error "Cannot properly configure GRO, GRO_NUM_BLOCKS must be >0 but is set to" GRO_NUM_BLOCKS
#else
    #define GRO_CTX_PER_BLOCK (8/GRO_NUM_BLOCKS)
#endif

/*
 * NFD configuration
 */
#define PCIE_ISL                0
#define PCI                     PCIE_ISL
#define NIC_PCI                 PCIE_ISL
#define NFD_OUT_SB_WQ_NUM       15

/*
 * Application configuration
 */
/* #define CFG_NIC_LIB_DBG_CNTRS */
/* #define CFG_NIC_LIB_DBG_JOURNAL */
/* #define CFG_NIC_APP_DBG_JOURNAL */
#define NIC_INTF                0

#endif /* __APP_CONFIG_H__ */
