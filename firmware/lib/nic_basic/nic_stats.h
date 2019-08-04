/*
 * Copyright 2015-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          lib/nic/_c/nic_stats.c
 * @brief         Implementation for additional stats
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _LIBNIC_NIC_STATS_H_
#define _LIBNIC_NIC_STATS_H_

#include "nfd_user_cfg.h"
#include <nfd_ctrl.h>

#include "nic_stats_gen.h"

#if defined(__NFP_LANG_MICROC)
typedef char ext_stats_key_t[32];

__asm {
    .alloc_mem _nic_stats_queue imem+0 global (512 * NIC_STATS_QUEUE_SIZE) 256
    .alloc_mem _nic_stats_vnic emem global (NVNICS * NIC_STATS_VNIC_SIZE) 256
}

#elif defined(__NFP_LANG_ASM)

.alloc_mem _nic_stats_queue imem+0 global (512 * NIC_STATS_QUEUE_SIZE) 256
.alloc_mem _nic_stats_vnic emem global (NVNICS * NIC_STATS_VNIC_SIZE) 256
#endif

#endif
