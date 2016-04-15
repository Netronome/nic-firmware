/*
 * Copyright 2015 Netronome, Inc.
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
 * @file          apps/nic/config.h
 * @brief         Infrastructure configuration for the NIC application.
 */

#ifndef __APP_CONFIG_H__
#define __APP_CONFIG_H__

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
#define NBI_TM_H_0_Q             256  /* 256 TM queues, 64 entries per queue */
#define NBI_TM_H_1_Q             0

/*
 * MAC configuration
 */
#define MAC0_PORTS               0
#define MAC0_CHANNELS            3
#define MAC0_PORTS_LIST          MAC0_PORTS
#define MAC0_CHANNELS_LIST       MAC0_CHANNELS

/*
 * BLM configuration
 */
#include <infra/blm_custom.h>

/*
 * GRO configuration
 */
#define GRO_NUM_BLOCKS           1
#define GRO_CTX_PER_BLOCK        8
#define GRO_REDUCED              0
#define GRO_BLOCK_NUM            0
#define GRO_ISL                  48

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
#define CFG_NIC_LIB_DBG_CNTRS
/* #define CFG_NIC_APP_DBG_JOURNAL */
#define NIC_INTF                0

#endif /* __APP_CONFIG_H__ */
