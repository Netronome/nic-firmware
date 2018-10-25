/* Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef TEST_DEFINES_H
#define TEST_DEFINES_H


#define NS_PLATFORM_TYPE        1
#define NS_PLATFORM_NUM_PORTS   1
#define BLM_CUSTOM_CONFIG
#define GRO_NUM_BLOCKS          1
#define NFD_MAX_VFS             62
#define NFD_MAX_PF_QUEUES       2
#define NFD_MAX_PFS             NS_PLATFORM_NUM_PORTS
#define NFD_USE_CTRL
#include <vnic/shared/nfd_ctrl.h> //required for NFD_MAX_CTRL
#define TEST_MAC                0xAA00CCDDEE00ull
#define APP_WORKER_ISLAND_LIST  0x204
#define APP_MES_LIST            0x204
#define NVNICS                  (NFD_MAX_PFS + NFD_MAX_VFS + NFD_MAX_CTRL)

#endif
