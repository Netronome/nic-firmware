/*
 * Copyright 2015-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          config.h
 * @brief         Infrastructure configuration for the NIC application.
 *
 * SPDX-License-Identifier: BSD-2-Clause
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
#define PKT_NBI_OFFSET           128
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
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND0   1,255,51
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND1   1,255,51
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND2   1,255,51
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND3   1,255,51
#define NBI0_DMA_BPE_CONFIG_ME_ISLAND4   1,255,51
#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
    #define NBI0_DMA_BPE_CONFIG_ME_ISLAND5   1,255,51
    #define NBI0_DMA_BPE_CONFIG_ME_ISLAND6   1,255,51
#else
    #define NBI0_DMA_BPE_CONFIG_ME_ISLAND5   0,0,0
    #define NBI0_DMA_BPE_CONFIG_ME_ISLAND6   0,0,0
#endif
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND0   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND1   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND2   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND3   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND4   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND5   0,0,0
#define NBI1_DMA_BPE_CONFIG_ME_ISLAND6   0,0,0
/* TM */
#define NBI_TM_NUM_SEQUENCERS    7
#define NBI_TM_ENABLE_SEQUENCER1 1
#define NBI_TM_ENABLE_SEQUENCER2 1
#define NBI_TM_ENABLE_SEQUENCER3 1
#define NBI_TM_ENABLE_SEQUENCER4 1
#define NBI_TM_ENABLE_SEQUENCER5 1
#define NBI_TM_ENABLE_SEQUENCER6 1


#if (NS_PLATFORM_TYPE == NS_PLATFORM_CARBON) || \
    (NS_PLATFORM_TYPE == NS_PLATFORM_CARBON_1x10_1x25)

    #define NBI_TM_ENABLE_SHAPER 1

    /* Rate adjustment to account for oscillator PPM. */
    #define PPM                  1

    #define NBI_TM_L2_SHAPER_START_NUM(_port) \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port))
    #define NBI_TM_L2_SHAPER_END_NUM(_port) \
        (NS_PLATFORM_MAC_CHANNEL_HI(_port))
    #define NBI_TM_L2_SHAPER_RATE(_port)                                       \
        ((NS_PLATFORM_PORT_SPEED(_port) * 100 * 1000 / NS_PLATFORM_PCLK) + PPM)
    #define NBI_TM_L2_SHAPER_THRESHOLD(_port) 0
    #define NBI_TM_L2_SHAPER_OVERSHOOT(_port) 7
    #define NBI_TM_L2_SHAPER_RATE_ADJ(_port)  -20

    #define NBI_TM_L1_SHAPER_NUM(_port)                  \
        (128 + (NS_PLATFORM_MAC_CHANNEL_LO(_port) >> 3))
    #define NBI_TM_L1_SHAPER_RATE(_port)      NBI_TM_L2_SHAPER_RATE(_port)
    /* Note: Adjust rate to account for inter-packet gap, preamble and CRC. */
    #define NBI_TM_L1_SHAPER_THRESHOLD(_port) NBI_TM_L2_SHAPER_THRESHOLD(_port)
    #define NBI_TM_L1_SHAPER_OVERSHOOT(_port) NBI_TM_L2_SHAPER_OVERSHOOT(_port)
    #define NBI_TM_L1_SHAPER_RATE_ADJ(_port)  NBI_TM_L2_SHAPER_RATE_ADJ(_port)

    #define NBI_TM_L0_SHAPER_NUM              144
    #define NBI_TM_L0_SHAPER_THRESHOLD        7
    #define NBI_TM_L0_SHAPER_OVERSHOOT        7
    #define NBI_TM_L0_SHAPER_RATE_ADJ         -20

    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 1
        #define NBI0_TM_L0_SHAPER_RATE (NBI_TM_L1_SHAPER_RATE(0))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 2
        #define NBI0_TM_L0_SHAPER_RATE                            \
            (NBI_TM_L1_SHAPER_RATE(0) + NBI_TM_L1_SHAPER_RATE(1))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 3
        #define NBI0_TM_L0_SHAPER_RATE                             \
            (NBI_TM_L1_SHAPER_RATE(0) + NBI_TM_L1_SHAPER_RATE(1) + \
             NBI_TM_L1_SHAPER_RATE(2))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 4
        #define NBI0_TM_L0_SHAPER_RATE                             \
            (NBI_TM_L1_SHAPER_RATE(0) + NBI_TM_L1_SHAPER_RATE(1) + \
             NBI_TM_L1_SHAPER_RATE(2) + NBI_TM_L1_SHAPER_RATE(3))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 5
        #define NBI0_TM_L0_SHAPER_RATE                             \
            (NBI_TM_L1_SHAPER_RATE(0) + NBI_TM_L1_SHAPER_RATE(1) + \
             NBI_TM_L1_SHAPER_RATE(2) + NBI_TM_L1_SHAPER_RATE(3) + \
             NBI_TM_L1_SHAPER_RATE(4))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 6
        #define NBI0_TM_L0_SHAPER_RATE                             \
            (NBI_TM_L1_SHAPER_RATE(0) + NBI_TM_L1_SHAPER_RATE(1) + \
             NBI_TM_L1_SHAPER_RATE(2) + NBI_TM_L1_SHAPER_RATE(3) + \
             NBI_TM_L1_SHAPER_RATE(4) + NBI_TM_L1_SHAPER_RATE(5))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 7
        #define NBI0_TM_L0_SHAPER_RATE                             \
            (NBI_TM_L1_SHAPER_RATE(0) + NBI_TM_L1_SHAPER_RATE(1) + \
             NBI_TM_L1_SHAPER_RATE(2) + NBI_TM_L1_SHAPER_RATE(3) + \
             NBI_TM_L1_SHAPER_RATE(4) + NBI_TM_L1_SHAPER_RATE(5) + \
             NBI_TM_L1_SHAPER_RATE(6))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_0 == 8
        #define NBI0_TM_L0_SHAPER_RATE                             \
            (NBI_TM_L1_SHAPER_RATE(0) + NBI_TM_L1_SHAPER_RATE(1) + \
             NBI_TM_L1_SHAPER_RATE(2) + NBI_TM_L1_SHAPER_RATE(3) + \
             NBI_TM_L1_SHAPER_RATE(4) + NBI_TM_L1_SHAPER_RATE(5) + \
             NBI_TM_L1_SHAPER_RATE(6) + NBI_TM_L1_SHAPER_RATE(7))
    #endif

    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 1
        #define NBI1_TM_L0_SHAPER_RATE                                   \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 2
        #define NBI1_TM_L0_SHAPER_RATE                                    \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 3
        #define NBI1_TM_L0_SHAPER_RATE                                    \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 4
        #define NBI1_TM_L0_SHAPER_RATE                                    \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 5
        #define NBI1_TM_L0_SHAPER_RATE                                    \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 6
        #define NBI1_TM_L0_SHAPER_RATE                                    \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 7
        #define NBI1_TM_L0_SHAPER_RATE                                    \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6))
    #elif NS_PLATFORM_NUM_PORTS_PER_MAC_1 == 8
        #define NBI1_TM_L0_SHAPER_RATE                                    \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6) + \
            (NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7))
    #endif

    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 0
        #define NBI0_TM_SHAPER_CFG_RANGE0 \
            1,                            \
            NBI_TM_L0_SHAPER_NUM,         \
            NBI_TM_L0_SHAPER_NUM,         \
            NBI0_TM_L0_SHAPER_RATE,       \
            NBI_TM_L0_SHAPER_THRESHOLD,   \
            NBI_TM_L0_SHAPER_OVERSHOOT,   \
            NBI_TM_L0_SHAPER_RATE_ADJ
        #define NBI0_TM_SHAPER_CFG_RANGE1  \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(0),       \
            NBI_TM_L1_SHAPER_NUM(0),       \
            NBI_TM_L1_SHAPER_RATE(0),      \
            NBI_TM_L1_SHAPER_THRESHOLD(0), \
            NBI_TM_L1_SHAPER_OVERSHOOT(0), \
            NBI_TM_L1_SHAPER_RATE_ADJ(0)
        #define NBI0_TM_SHAPER_CFG_RANGE2  \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(0), \
            NBI_TM_L2_SHAPER_END_NUM(0),   \
            NBI_TM_L2_SHAPER_RATE(0),      \
            NBI_TM_L2_SHAPER_THRESHOLD(0), \
            NBI_TM_L2_SHAPER_OVERSHOOT(0), \
            NBI_TM_L2_SHAPER_RATE_ADJ(0)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 1
        #define NBI0_TM_SHAPER_CFG_RANGE3  \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(1),       \
            NBI_TM_L1_SHAPER_NUM(1),       \
            NBI_TM_L1_SHAPER_RATE(1),      \
            NBI_TM_L1_SHAPER_THRESHOLD(1), \
            NBI_TM_L1_SHAPER_OVERSHOOT(1), \
            NBI_TM_L1_SHAPER_RATE_ADJ(1)
        #define NBI0_TM_SHAPER_CFG_RANGE4  \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(1), \
            NBI_TM_L2_SHAPER_END_NUM(1),   \
            NBI_TM_L2_SHAPER_RATE(1),      \
            NBI_TM_L2_SHAPER_THRESHOLD(1), \
            NBI_TM_L2_SHAPER_OVERSHOOT(1), \
            NBI_TM_L2_SHAPER_RATE_ADJ(1)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 2
        #define NBI0_TM_SHAPER_CFG_RANGE5  \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(2),       \
            NBI_TM_L1_SHAPER_NUM(2),       \
            NBI_TM_L1_SHAPER_RATE(2),      \
            NBI_TM_L1_SHAPER_THRESHOLD(2), \
            NBI_TM_L1_SHAPER_OVERSHOOT(2), \
            NBI_TM_L1_SHAPER_RATE_ADJ(2)
        #define NBI0_TM_SHAPER_CFG_RANGE6  \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(2), \
            NBI_TM_L2_SHAPER_END_NUM(2),   \
            NBI_TM_L2_SHAPER_RATE(2),      \
            NBI_TM_L2_SHAPER_THRESHOLD(2), \
            NBI_TM_L2_SHAPER_OVERSHOOT(2), \
            NBI_TM_L2_SHAPER_RATE_ADJ(2)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 3
        #define NBI0_TM_SHAPER_CFG_RANGE7  \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(3),       \
            NBI_TM_L1_SHAPER_NUM(3),       \
            NBI_TM_L1_SHAPER_RATE(3),      \
            NBI_TM_L1_SHAPER_THRESHOLD(3), \
            NBI_TM_L1_SHAPER_OVERSHOOT(3), \
            NBI_TM_L1_SHAPER_RATE_ADJ(3)
        #define NBI0_TM_SHAPER_CFG_RANGE8  \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(3), \
            NBI_TM_L2_SHAPER_END_NUM(3),   \
            NBI_TM_L2_SHAPER_RATE(3),      \
            NBI_TM_L2_SHAPER_THRESHOLD(3), \
            NBI_TM_L2_SHAPER_OVERSHOOT(3), \
            NBI_TM_L2_SHAPER_RATE_ADJ(3)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 4
        #define NBI0_TM_SHAPER_CFG_RANGE9  \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(4),       \
            NBI_TM_L1_SHAPER_NUM(4),       \
            NBI_TM_L1_SHAPER_RATE(4),      \
            NBI_TM_L1_SHAPER_THRESHOLD(4), \
            NBI_TM_L1_SHAPER_OVERSHOOT(4), \
            NBI_TM_L1_SHAPER_RATE_ADJ(4)
        #define NBI0_TM_SHAPER_CFG_RANGE10 \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(4), \
            NBI_TM_L2_SHAPER_END_NUM(4),   \
            NBI_TM_L2_SHAPER_RATE(4),      \
            NBI_TM_L2_SHAPER_THRESHOLD(4), \
            NBI_TM_L2_SHAPER_OVERSHOOT(4), \
            NBI_TM_L2_SHAPER_RATE_ADJ(4)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 5
        #define NBI0_TM_SHAPER_CFG_RANGE11 \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(5),       \
            NBI_TM_L1_SHAPER_NUM(5),       \
            NBI_TM_L1_SHAPER_RATE(5),      \
            NBI_TM_L1_SHAPER_THRESHOLD(5), \
            NBI_TM_L1_SHAPER_OVERSHOOT(5), \
            NBI_TM_L1_SHAPER_RATE_ADJ(5)
        #define NBI0_TM_SHAPER_CFG_RANGE12 \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(5), \
            NBI_TM_L2_SHAPER_END_NUM(5),   \
            NBI_TM_L2_SHAPER_RATE(5),      \
            NBI_TM_L2_SHAPER_THRESHOLD(5), \
            NBI_TM_L2_SHAPER_OVERSHOOT(5), \
            NBI_TM_L2_SHAPER_RATE_ADJ(5)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 6
        #define NBI0_TM_SHAPER_CFG_RANGE13 \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(6),       \
            NBI_TM_L1_SHAPER_NUM(6),       \
            NBI_TM_L1_SHAPER_RATE(6),      \
            NBI_TM_L1_SHAPER_THRESHOLD(6), \
            NBI_TM_L1_SHAPER_OVERSHOOT(6), \
            NBI_TM_L1_SHAPER_RATE_ADJ(6)
        #define NBI0_TM_SHAPER_CFG_RANGE14 \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(6), \
            NBI_TM_L2_SHAPER_END_NUM(6),   \
            NBI_TM_L2_SHAPER_RATE(6),      \
            NBI_TM_L2_SHAPER_THRESHOLD(6), \
            NBI_TM_L2_SHAPER_OVERSHOOT(6), \
            NBI_TM_L2_SHAPER_RATE_ADJ(6)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_0 > 7
        #define NBI0_TM_SHAPER_CFG_RANGE15 \
            1,                             \
            NBI_TM_L1_SHAPER_NUM(7),       \
            NBI_TM_L1_SHAPER_NUM(7),       \
            NBI_TM_L1_SHAPER_RATE(7),      \
            NBI_TM_L1_SHAPER_THRESHOLD(7), \
            NBI_TM_L1_SHAPER_OVERSHOOT(7), \
            NBI_TM_L1_SHAPER_RATE_ADJ(7)
        #define NBI0_TM_SHAPER_CFG_RANGE16 \
            1,                             \
            NBI_TM_L2_SHAPER_START_NUM(7), \
            NBI_TM_L2_SHAPER_END_NUM(7),   \
            NBI_TM_L2_SHAPER_RATE(7),      \
            NBI_TM_L2_SHAPER_THRESHOLD(7), \
            NBI_TM_L2_SHAPER_OVERSHOOT(7), \
            NBI_TM_L2_SHAPER_RATE_ADJ(7)
    #endif

    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 0
        #define NBI1_TM_SHAPER_CFG_RANGE0 \
            1,                            \
            NBI_TM_L0_SHAPER_NUM,         \
            NBI_TM_L0_SHAPER_NUM,         \
            NBI1_TM_L0_SHAPER_RATE,       \
            NBI_TM_L0_SHAPER_THRESHOLD,   \
            NBI_TM_L0_SHAPER_OVERSHOOT,   \
            NBI_TM_L0_SHAPER_RATE_ADJ
        #define NBI1_TM_SHAPER_CFG_RANGE1                                    \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0)
        #define NBI1_TM_SHAPER_CFG_RANGE2                                    \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 0)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 1
        #define NBI1_TM_SHAPER_CFG_RANGE3                                    \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1)
        #define NBI1_TM_SHAPER_CFG_RANGE4                                    \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 1)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 2
        #define NBI1_TM_SHAPER_CFG_RANGE5                                    \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2)
        #define NBI1_TM_SHAPER_CFG_RANGE6                                    \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 2)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 3
        #define NBI1_TM_SHAPER_CFG_RANGE7                                    \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3)
        #define NBI1_TM_SHAPER_CFG_RANGE8                                    \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 3)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 4
        #define NBI1_TM_SHAPER_CFG_RANGE9                                    \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4)
        #define NBI1_TM_SHAPER_CFG_RANGE10                                   \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 4)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 5
        #define NBI1_TM_SHAPER_CFG_RANGE11                                   \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5)
        #define NBI1_TM_SHAPER_CFG_RANGE12                                   \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 5)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 6
        #define NBI1_TM_SHAPER_CFG_RANGE13                                   \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6)
        #define NBI1_TM_SHAPER_CFG_RANGE14                                   \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 6)
    #endif
    #if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 7
        #define NBI1_TM_SHAPER_CFG_RANGE15                                   \
            1,                                                               \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7),       \
            NBI_TM_L1_SHAPER_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7),       \
            NBI_TM_L1_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7),      \
            NBI_TM_L1_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7), \
            NBI_TM_L1_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7), \
            NBI_TM_L1_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7)
        #define NBI1_TM_SHAPER_CFG_RANGE16                                   \
            1,                                                               \
            NBI_TM_L2_SHAPER_START_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7), \
            NBI_TM_L2_SHAPER_END_NUM(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7),   \
            NBI_TM_L2_SHAPER_RATE(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7),      \
            NBI_TM_L2_SHAPER_THRESHOLD(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7), \
            NBI_TM_L2_SHAPER_OVERSHOOT(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7), \
            NBI_TM_L2_SHAPER_RATE_ADJ(NS_PLATFORM_NUM_PORTS_PER_MAC_0 + 7)
    #endif
#endif

#if NS_PLATFORM_TYPE == NS_PLATFORM_BERYLLIUM_4x10_1x40

    #define NS_PLATFORM_NBI_TM_10G_QSIZE 6  /* 2^6 packet buffers per queue */
    #define NS_PLATFORM_NBI_TM_40G_QSIZE 8  /* 2^8 packet buffers per queue */

    /* Initialize the NBI TM queues associated with each port. */
    #define NBI0_TM_Q_CFG_RANGE0              \
        1,                                    \
        NS_PLATFORM_NBI_TM_QID_LO(0),         \
        NS_PLATFORM_NBI_TM_QID_HI(0),         \
        NS_PLATFORM_NBI_TM_10G_QSIZE
    #define NBI0_TM_Q_CFG_RANGE1              \
        1,                                    \
        NS_PLATFORM_NBI_TM_QID_LO(1),         \
        NS_PLATFORM_NBI_TM_QID_HI(1),         \
        NS_PLATFORM_NBI_TM_10G_QSIZE
    #define NBI0_TM_Q_CFG_RANGE2              \
        1,                                    \
        NS_PLATFORM_NBI_TM_QID_LO(2),         \
        NS_PLATFORM_NBI_TM_QID_HI(2),         \
        NS_PLATFORM_NBI_TM_10G_QSIZE
    #define NBI0_TM_Q_CFG_RANGE3              \
        1,                                    \
        NS_PLATFORM_NBI_TM_QID_LO(3),         \
        NS_PLATFORM_NBI_TM_QID_HI(3),         \
        NS_PLATFORM_NBI_TM_10G_QSIZE
    #define NBI0_TM_Q_CFG_RANGE4              \
        1,                                    \
        NS_PLATFORM_NBI_TM_QID_LO(4),         \
        NS_PLATFORM_NBI_TM_QID_HI(4),         \
        NS_PLATFORM_NBI_TM_40G_QSIZE

#else /* Default NBI TM configuration. */

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

#endif /* Default NBI TM configuration. */

/*
 * BLM configuration
 */
#include "blm_custom.h"


/*
 * GRO configuration
 * Note: GRO_NUM_BLOCKS is expected to be passed in via a -D
 *       GRO_CTX_PER_BLOCK is computed based on GRO_NUM_BLOCKS
 */
#define GRO_ISL				48

/* Ingress sequencer numbers (0/1/2/3/4) for packets from the wire will
   be mapped to GRO CTX numbers 0/2/3/4/5; those for packets from NFD
   (0/1) will be mapped to GRO CTX numbers 8/9/10/11/12/13/14/15.  So
   we need 16 GRO CTX's total.  The number of GRO blocks is expected
   to be passed in from the build via -D define, so we need to calculate
   GRO CTX's per block so that we always have (at least) 16.
*/
#ifndef GRO_NUM_BLOCKS
    #error "GRO_NUM_BLOCKS must be defined"
#endif

#if (GRO_NUM_BLOCKS > 16)
    #define GRO_CTX_PER_BLOCK       1
    #warning "Cannot properly configure GRO, GRO_NUM_BLOCKS is" GRO_NUM_BLOCKS "GRO_CTX_PER_BLOCK set to" GRO_CTX_PER_BLOCK
#elif (GRO_NUM_BLOCKS < 1)
    #error "Cannot properly configure GRO, GRO_NUM_BLOCKS must be >0 but is set to" GRO_NUM_BLOCKS
#else
    #define GRO_CTX_PER_BLOCK (16/GRO_NUM_BLOCKS)
#endif

/*
 * NFD configuration
 */
#define PCI                     0
#define NIC_PCI                 0
#define NFD_OUT_SB_WQ_NUM       15

/*
 * Application configuration
 */
/* #define CFG_NIC_LIB_DBG_CNTRS */
/* #define CFG_NIC_LIB_DBG_JOURNAL */
/* #define CFG_NIC_APP_DBG_JOURNAL */
#define NIC_INTF                0

#endif /* __APP_CONFIG_H__ */
