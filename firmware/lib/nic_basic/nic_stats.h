/*
 * Copyright 2015 Netronome, Inc.
 *
 * @file          lib/nic/_c/nic_stats.c
 * @brief         Implementation for additional stats
 */

#ifndef _LIBNIC_NIC_STATS_H_
#define _LIBNIC_NIC_STATS_H_

#include "ext_stats.h"

#if defined(__NFP_LANG_MICROC)
typedef char ext_stats_key_t[32];

__asm {
    .alloc_mem __ext_stats imem+0 global ((NS_PLATFORM_NUM_PORTS + 1) * EXT_STATS_SIZE) 256
    .alloc_mem _ext_stats_phy_data emem global (NS_PLATFORM_NUM_PORTS * EXT_STATS_SIZE) 256
    .alloc_mem _ext_stats_phy_blk_sz emem global 8 8
}

#elif defined(__NFP_LANG_ASM)

.alloc_mem __ext_stats imem+0 global ((NS_PLATFORM_NUM_PORTS + 1) * EXT_STATS_SIZE) 256
.alloc_mem _ext_stats_phy_data emem global (NS_PLATFORM_NUM_PORTS * EXT_STATS_SIZE) 256
.alloc_mem _ext_stats_phy_blk_sz emem global 8 8
.init _ext_stats_phy_blk_sz EXT_STATS_SIZE
#endif

#endif
