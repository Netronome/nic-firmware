/**
 * Copyright (C) 2015-2016,  Netronome Systems, Inc.  All rights reserved.
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
 * @file          nfd_user_cfg.h
 * @brief         File for specifying user configuration parameters
 */
#ifndef _NFD_USER_CFG_H_
#define _NFD_USER_CFG_H_

/* Include BLM defines for BLM_NBI8_BLQ0_EMU_Q_BASE */
#if !defined(__NFP_LANG_ASM)
#include <blm/blm.h>
#endif

#include <platform.h>

#if NS_PLATFORM_NUM_PORTS > 1
#if NS_PLATFORM_NUM_PORTS > 8  /* NS_PLATFORM_NUM_PORTS > 8 */

#ifndef NFD_MAX_PF_QUEUES
#define NFD_MAX_PF_QUEUES       4
#endif

#elif NS_PLATFORM_NUM_PORTS > 4  /* 4 < NS_PLATFORM_NUM_PORTS <= 8 */

#ifndef NFD_MAX_PF_QUEUES
#define NFD_MAX_PF_QUEUES       8
#endif

#elif NS_PLATFORM_NUM_PORTS > 2  /* 2 < NS_PLATFORM_NUM_PORTS <= 4 */

#ifndef NFD_MAX_PF_QUEUES
#define NFD_MAX_PF_QUEUES       16
#endif

#else /* NS_PLATFORM_NUM_PORTS = 2 */

#ifndef NFD_MAX_PF_QUEUES
#define NFD_MAX_PF_QUEUES       32
#endif

#endif

#ifndef NFD_MAX_VF_QUEUES
#define NFD_MAX_VF_QUEUES       0
#endif

#ifndef NFD_MAX_VFS
#define NFD_MAX_VFS             0
#endif

#ifndef NFD_MAX_PFS
#define NFD_MAX_PFS             NS_PLATFORM_NUM_PORTS
#endif

#else /* NS_PLATFORM_NUM_PORTS <= 1 */

#ifndef NFD_MAX_VF_QUEUES
#define NFD_MAX_VF_QUEUES       1
#endif

#ifndef NFD_MAX_PF_QUEUES
#define NFD_MAX_PF_QUEUES       32
#endif

#ifndef NFD_MAX_PFS
#define NFD_MAX_PFS             1
#endif

/* No VFs needed */
#ifndef NFD_MAX_VFS
#define NFD_MAX_VFS             0
#endif

#endif

/* Configure VF expansion BARs to access the NFP, this seems to be required
 * even when just using the PF */
#define NFD_VNIC_VF

/* Use a service ME which will handle MSIX generation when enabled */
#define USE_SVC_ME

#define NFD_PCIE0_EMEM          emem0

#define NFD_IN_DATA_OFFSET      128

/* Number of credits allocated per VNIC queue */
#ifndef NFD_QUEUE_CREDITS
#define NFD_QUEUE_CREDITS       256
#endif

/* Configuration mechanism defines */
#define NFD_CFG_MAX_MTU         9216

#define NFD_CFG_VF_CAP                                            \
    (NFP_NET_CFG_CTRL_ENABLE   | NFP_NET_CFG_CTRL_PROMISC |       \
     NFP_NET_CFG_CTRL_RXCSUM   | NFP_NET_CFG_CTRL_TXCSUM |        \
     NFP_NET_CFG_CTRL_RSS      | NFP_NET_CFG_CTRL_RSS2 |          \
     NFP_NET_CFG_CTRL_MSIXAUTO | NFP_NET_CFG_CTRL_CSUM_COMPLETE | \
     NFP_NET_CFG_CTRL_GATHER   | NFP_NET_CFG_CTRL_LSO2 |          \
     NFP_NET_CFG_CTRL_IRQMOD)

#define NFD_CFG_PF_CAP                                            \
    (NFP_NET_CFG_CTRL_ENABLE   | NFP_NET_CFG_CTRL_PROMISC |       \
     NFP_NET_CFG_CTRL_RXCSUM   | NFP_NET_CFG_CTRL_TXCSUM |        \
     NFP_NET_CFG_CTRL_RSS      | NFP_NET_CFG_CTRL_RSS2 |          \
     NFP_NET_CFG_CTRL_MSIXAUTO | NFP_NET_CFG_CTRL_CSUM_COMPLETE | \
     NFP_NET_CFG_CTRL_GATHER   | NFP_NET_CFG_CTRL_LSO2 |          \
     NFP_NET_CFG_CTRL_IRQMOD | \
	 NFP_NET_CFG_CTRL_BPF)

#define NFD_RSS_HASH_FUNC NFP_NET_CFG_RSS_CRC32

#define NFD_CFG_RING_EMEM       emem0

/* NIC APP ME context handling configuration changes to the config BAR */
#define APP_ME_CONFIG_CTX 0
/* Signal number used for APP MASTER to NIC APP MEs signaling of
 * configuration changes to the config BAR */
#define APP_ME_CONFIG_SIGNAL_NUM 11
/* Xfer number used for APP MASTER to NIC APP MEs signaling of
 * configuration changes to the config BAR - holds pci island and
 * vnic number */
#define APP_ME_CONFIG_XFER_NUM 11


/* PCI.IN block defines */
#define NFD_IN_BLM_REG_BLS      1
#define NFD_IN_BLM_REG_POOL     BLM_NBI8_BLQ1_EMU_QID
#define NFD_IN_BLM_REG_SIZE     (10 * 1024)
#define NFD_IN_BLM_JUMBO_BLS    1
#define NFD_IN_BLM_JUMBO_POOL   BLM_NBI8_BLQ1_EMU_QID
#define NFD_IN_BLM_JUMBO_SIZE   (10 * 1024)
#define NFD_IN_BLM_RADDR        __LoadTimeConstant("__addr_emem0")
#define NFD_IN_HAS_ISSUE0       1
#define NFD_IN_HAS_ISSUE1       1
#define NFD_IN_ISSUE_DMA_QSHIFT 1
#define NFD_IN_ISSUE_DMA_QXOR   0

/* NFD_IN_WQ_SZ must be large enough to hold an nfd_in_pkt_desc (16B) for each
 * MU in the system. BLM_NBI8_BLQ0_Q_SIZE is the max number of MUs in the
 * system * MU descr size (4B). So NFD_IN_WQ_SZ = (BLM_NBI8_BLQ0_Q_SIZE/4)*16
 */
#define NFD_IN_WQ_SZ           ((BLM_NBI8_BLQ0_Q_SIZE/4) * 16)

/* Optional defines */
#define NFD_IN_ADD_SEQN
#define NFD_IN_NUM_WQS          1

#define NFD_IN_NUM_SEQRS        2
#define NFD_IN_SEQR_QSHIFT      0

/* PCI.OUT block defines */
#define NFD_OUT_BLM_POOL_START  BLM_NBI8_BLQ0_EMU_QID
#define NFD_OUT_BLM_RADDR       __LoadTimeConstant("__addr_emem0")
#define NFD_OUT_BLM_RADDR_UC    __ADDR_EMEM0

/* Set either NFP_CACHED or HOST_ISSUED credits
 * Only NFP_CACHED are officially supported currently */
/* #define NFD_OUT_CREDITS_HOST_ISSUED */
#define NFD_OUT_CREDITS_NFP_CACHED

/* NFD_OUT_RING_SZ must be set to hold double the maximum number of credits
 * that might be issued at any time. */
#define NFD_OUT_RING_SZ         (2 * 16 * 64 * NFD_QUEUE_CREDITS)

#define NFD_OUT_RX_OFFSET       NFP_NET_CFG_RX_OFFSET_DYNAMIC

#define NFD_BPF_CAPABLE        1
#define NFD_BPF_START_OFF   2000
#define NFD_BPF_DONE_OFF     799

#define NFD_NET_APP_TYPE (2)

#endif /* !_NFD_USER_CFG_H_ */
