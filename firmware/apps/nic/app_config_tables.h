/*
 * Copyright (C) 2015 Netronome, Inc. All rights reserved.
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
 * @file          apps/nic/nic.h
 * @brief         Header file for NIC local functions/declarations
 */

#ifndef _APP_CONFIG_TABLES_H_
#define _APP_CONFIG_TABLES_H_

#include <nfp.h>
#include <stdint.h>

#include <net/eth.h>
#include <net/gre.h>
#include <net/ip.h>
#include <net/tcp.h>
#include <net/udp.h>
#include <net/vxlan.h>
#include <net/hdr_ext.h>

#include <nfp_chipres.h>
#include <nfp/mem_atomic.h>
#include <nfp/mem_ring.h>

#define WORKER_ISL0 32
#define WORKER_ISL1 33
#define WORKER_ISL2 34
#define WORKER_ISL3 35
#define WORKER_ISL4 36

enum {

    INSTR_MTU = 1,
    INSTR_MAC,
    INSTR_EXTRACT_KEY_WITH_RSS,
    INSTR_RSS_CRC32_HASH_WITH_KEY,
    INSTR_SEL_RSS_QID_WITH_MASK,
    INSTR_TX_HOST,
    INSTR_TX_WIRE,
    INSTR_TX_DROP
};


/* if NBI 1 has any ports then two NIB islands */
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 0
#define NUM_NBI 2
#else
#define NUM_NBI 1
#endif

#define NUM_NBI_CHANNELS    64      // channels per NBI
#define NUM_PCIE            1       // number of PCIe islands
#define NUM_PCIE_Q          64      // number of queues configured per PCIe
#define NUM_PCIE_Q_PER_PORT NFD_MAX_PF_QUEUES // nr queues configured per port
#define NIC_MAX_INSTR       32      // 128 bytes, 4B per instruction

#define NIC_HOST_MAX_ENTRIES  (NUM_PCIE*NUM_PCIE_Q)
#define NIC_NBI_ENTRY_START   NIC_HOST_MAX_ENTRIES
#define NIC_WIRE_MAX_ENTRIES  (NUM_NBI*NUM_NBI_CHANNELS)


#define NIC_CFG_INSTR_TBL_ADDR (0x00)
#define NIC_CFG_INSTR_TBL_SIZE (((NIC_HOST_MAX_ENTRIES+NIC_WIRE_MAX_ENTRIES) \
                                * NIC_MAX_INSTR)<<2)

/* start of RSS table in NN registers */
#define NN_RSS_TABLE    0


/* For host ports, use 0 to MAX_VFS
 * For wire ports, use MIN_PFS .. MAX_PFS */
__asm
{
    .alloc_mem NIC_CFG_INSTR_TBL cls + NIC_CFG_INSTR_TBL_ADDR \
                island NIC_CFG_INSTR_TBL_SIZE addr40
    .init NIC_CFG_INSTR_TBL 0 0
}



/**
 * Handle port config from PCIe. Configure the config instruction tables for wire
 * and host.
 *
 * @vnic_port   VNIC port
 * @control     First word of the BAR data
 * @update      Second word of the BAR data
 */
void app_config_port(unsigned int vnic_port, unsigned int control,
                        unsigned int update);


/**
 * Handle port down from PCIe. Configure the config instruction tables for wire
 * and host.
 *
 * @vnic_port    VNIC port
 */
void app_config_port_down(unsigned int vnic_port);

#endif /* _APP_CONFIG_TABLES_H_ */
