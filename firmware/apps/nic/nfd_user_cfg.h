/**
 * Copyright (C) 2015-2019, Netronome Systems, Inc.  All rights reserved.
 *
 * @file          nfd_user_cfg.h
 * @brief         File for specifying NFD user configuration parameters
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _NFD_USER_CFG_H_
#define _NFD_USER_CFG_H_

/* Include BLM defines for BLM_NBI8_BLQ0_EMU_Q_BASE */
#if !defined(__NFP_LANG_ASM)
#include <blm/blm.h>
#endif

#include <platform.h>
#include <flavors.h>

#define NFD_USE_OVERSUBSCRIPTION
#define NFD_OUT_ALWAYS_FREE_CTM
#define NFD_OUT_ADD_ZERO_TKT
#if ((NS_FLAVOR_TYPE == NS_FLAVOR_SRIOV) || \
        (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50))
    #define NFD_OUT_SKIP_FREE_BLQ 3
#endif

/* The absolute max number of VNICs we can support */
#define NVNICS_ABSOLUTE_MAX 64

#if NS_PLATFORM_NUM_PORTS > 8  /* NS_PLATFORM_NUM_PORTS > 8 */

    #if (NS_FLAVOR_TYPE == NS_FLAVOR_SRIOV)
        #ifndef NFD_MAX_VFS
        #define NFD_MAX_VFS             40
        #endif
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       2
        #endif
    #else
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       4
        #endif
    #endif

#elif NS_PLATFORM_NUM_PORTS > 4  /* 4 < NS_PLATFORM_NUM_PORTS <= 8 */

    #if (NS_FLAVOR_TYPE == NS_FLAVOR_SRIOV)
        #ifndef NFD_MAX_VFS
        #define NFD_MAX_VFS             48
        #endif
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       2
        #endif
    #else
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       8
        #endif
    #endif

#elif NS_PLATFORM_NUM_PORTS > 2  /* 2 < NS_PLATFORM_NUM_PORTS <= 4 */

    #if (NS_FLAVOR_TYPE == NS_FLAVOR_SRIOV)
        #ifndef NFD_MAX_VFS
        #define NFD_MAX_VFS             48
        #endif
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       4
        #endif
    #else
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       16
        #endif
    #endif

#elif NS_PLATFORM_NUM_PORTS > 1 /* NS_PLATFORM_NUM_PORTS = 2 */

    #if (NS_FLAVOR_TYPE == NS_FLAVOR_SRIOV)
        #ifndef NFD_MAX_VFS
        #define NFD_MAX_VFS             48
        #endif
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       8
        #endif
    #else
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       32
        #endif
    #endif

#else

    #if (NS_FLAVOR_TYPE == NS_FLAVOR_SRIOV)
        #ifndef NFD_MAX_VFS
        #define NFD_MAX_VFS             56
        #endif
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       8
        #endif
    #else
        #ifndef NFD_MAX_PF_QUEUES
        #define NFD_MAX_PF_QUEUES       64
        #endif
    #endif

#endif

#ifndef NFD_MAX_VFS
#define NFD_MAX_VFS             0
#endif

#ifndef NFD_MAX_VF_QUEUES
    #if (NFD_MAX_VFS != 0)
        #define NFD_MAX_VF_QUEUES   1
    #else
        #define NFD_MAX_VF_QUEUES   0
    #endif
#endif

#ifndef NFD_MAX_PFS
#define NFD_MAX_PFS             NS_PLATFORM_NUM_PORTS
#endif

#define NFD_PCIE0_EMEM          emem0

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)

    #define NFD_PCIE1_EMEM          emem0
    #define NFD_PCIE2_EMEM          emem0
    #define NFD_PCIE3_EMEM          emem0

    #define NFD_OUT_FL_BUFS_PER_QUEUE       256
    #define NFD_PCIE0_FL_CACHE_MEM          pcie0.ctm
    #define NFD_PCIE1_FL_CACHE_MEM          pcie1.ctm
    #define NFD_PCIE2_FL_CACHE_MEM          pcie2.ctm
    #define NFD_PCIE3_FL_CACHE_MEM          pcie3.ctm

#else
    #define NFD_OUT_FL_BUFS_PER_QUEUE      1024
    #define NFD_PCIE0_FL_CACHE_MEM         emem0_cache_upper
#endif

#define NFD_IN_DATA_OFFSET      128

/* Number of credits allocated per VNIC queue */
#ifndef NFD_QUEUE_CREDITS
#define NFD_QUEUE_CREDITS       256
#endif

/* Configuration mechanism defines */
#define NFD_CFG_MAX_MTU         9216

#define NFD_CFG_VF_CAP                                             \
    (NFP_NET_CFG_CTRL_ENABLE    | NFP_NET_CFG_CTRL_PROMISC |       \
     NFP_NET_CFG_CTRL_RXCSUM    | NFP_NET_CFG_CTRL_TXCSUM |        \
     NFP_NET_CFG_CTRL_MSIXAUTO  | NFP_NET_CFG_CTRL_CSUM_COMPLETE | \
     NFP_NET_CFG_CTRL_GATHER    | NFP_NET_CFG_CTRL_LSO |           \
     NFP_NET_CFG_CTRL_IRQMOD    | NFP_NET_CFG_CTRL_VXLAN)

#define NFD_CFG_VF_LEGAL_UPD \
    (NFP_NET_CFG_UPDATE_GEN     | NFP_NET_CFG_UPDATE_RING |        \
     NFP_NET_CFG_UPDATE_MSIX    | NFP_NET_CFG_UPDATE_RESET |       \
     NFP_NET_CFG_UPDATE_IRQMOD  | NFP_NET_CFG_UPDATE_MACADDR |     \
     NFP_NET_CFG_UPDATE_VXLAN)

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)

#define NFD_CFG_PF_CAP                                             \
    (NFP_NET_CFG_CTRL_ENABLE    | \
     NFP_NET_CFG_CTRL_RXCSUM    | NFP_NET_CFG_CTRL_TXCSUM |        \
     NFP_NET_CFG_CTRL_RSS       | NFP_NET_CFG_CTRL_RSS2 |          \
     NFP_NET_CFG_CTRL_MSIXAUTO  | NFP_NET_CFG_CTRL_CSUM_COMPLETE | \
     NFP_NET_CFG_CTRL_GATHER    | NFP_NET_CFG_CTRL_LSO |           \
     NFP_NET_CFG_CTRL_IRQMOD    | NFP_NET_CFG_CTRL_BPF |           \
     NFP_NET_CFG_CTRL_LIVE_ADDR | NFP_NET_CFG_CTRL_VXLAN |         \
     NFP_NET_CFG_CTRL_NVGRE)

#else

#define NFD_CFG_PF_CAP                                             \
    (NFP_NET_CFG_CTRL_ENABLE    | NFP_NET_CFG_CTRL_PROMISC |       \
     NFP_NET_CFG_CTRL_RXCSUM    | NFP_NET_CFG_CTRL_TXCSUM |        \
     NFP_NET_CFG_CTRL_RSS       | NFP_NET_CFG_CTRL_RSS2 |          \
     NFP_NET_CFG_CTRL_MSIXAUTO  | NFP_NET_CFG_CTRL_CSUM_COMPLETE | \
     NFP_NET_CFG_CTRL_GATHER    | NFP_NET_CFG_CTRL_LSO |           \
     NFP_NET_CFG_CTRL_IRQMOD    | NFP_NET_CFG_CTRL_BPF |           \
     NFP_NET_CFG_CTRL_LIVE_ADDR | NFP_NET_CFG_CTRL_VXLAN |         \
     NFP_NET_CFG_CTRL_NVGRE)

#endif

#define NFD_CFG_PF_LEGAL_UPD \
    (NFP_NET_CFG_UPDATE_GEN     | NFP_NET_CFG_UPDATE_RING |        \
     NFP_NET_CFG_UPDATE_RSS     | NFP_NET_CFG_UPDATE_MSIX |        \
     NFP_NET_CFG_UPDATE_RESET   | NFP_NET_CFG_UPDATE_IRQMOD |      \
     NFP_NET_CFG_UPDATE_VXLAN   | NFP_NET_CFG_UPDATE_BPF |         \
     NFP_NET_CFG_UPDATE_MACADDR | NFP_NET_CFG_UPDATE_VF)

/* Set Core NIC ABI version and supported VF configuration capabilities. */
#define NFD_VF_CFG_ABI_VER      2
#define NFD_VF_CFG_CAP                                       \
    (NFD_VF_CFG_MB_CAP_MAC | NFD_VF_CFG_MB_CAP_VLAN |        \
     NFD_VF_CFG_MB_CAP_SPOOF | NFD_VF_CFG_MB_CAP_LINK_STATE |\
     NFD_VF_CFG_MB_CAP_TRUST)

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
 * MU in the system. BLM_NBI8_BLQ1_Q_SIZE is the max number of MUs in the
 * system * MU descr size (4B). So NFD_IN_WQ_SZ = (BLM_NBI8_BLQ1_Q_SIZE/4)*16
 */
#define NFD_IN_WQ_SZ           ((BLM_NBI8_BLQ1_Q_SIZE/4) * 16)


/* Optional defines */
#define NFD_IN_ADD_SEQN
#define NFD_IN_NUM_WQS          1

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
#define NFD_IN_NUM_SEQRS        2
#else
#define NFD_IN_NUM_SEQRS        8
#endif
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

#define NFD_BPF_CAPABLE         1
#define NFD_BPF_START_OFF       3072
#define NFD_BPF_MAX_LEN         2560
#define NFD_BPF_DONE_OFF        1
#define NFD_BPF_CAPS            NFP_NET_BPF_CAP_RELO
#define NFD_BPF_ABI             2
#define NFD_BPF_STACK_SZ        512

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
#define NFD_NET_APP_ID              (4)
#else
    #if NS_FLAVOR_TYPE == NS_FLAVOR_BPF
        #define NFD_NET_APP_ID      (2)
    #else
        #define NFD_NET_APP_ID      (1)
    #endif
#endif

/* enable cmsg */
#define NFD_USE_CTRL

/* # of PFs + # VFs + # CTRLs */
#define NVNICS (NFD_MAX_PFS + NFD_MAX_VFS + NFD_MAX_CTRL)

#define NFD_USE_TLV_PF
#define NFD_USE_TLV_VF
#define NFD_CFG_TLV_BLOCK_SZ           3072
#define NFD_CFG_TLV_BLOCK_OFF          0x2200

#define NFD_OUT_USE_RX_BATCH_TGT

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
#define NFD_USE_MULTI_HOST
#endif

#define NFD_IN_WQ_SHARED               emem0

#endif /* !_NFD_USER_CFG_H_ */
