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
 * @file          apps/nic/app_config_instr.h
 * @brief         Header file for App Config ME instruction table
 */

#ifndef _APP_CONFIG_INSTR_H_
#define _APP_CONFIG_INSTR_H_


/* if NBI 1 has any ports then two NIB islands */
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 0
#define NUM_NBI 2
#else
#define NUM_NBI 1
#endif

#define NUM_NBI_CHANNELS    64      // channels per NBI
#define NUM_PCIE            2       // number of PCIe islands
#define NUM_PCIE_Q          64      // number of queues configured per PCIe
#define NUM_PCIE_Q_PER_PORT NFD_MAX_PF_QUEUES // nr queues cfg per port
#define NIC_MAX_INSTR       16      // max number of instructions in table

#define NIC_HOST_MAX_ENTRIES  (NUM_PCIE*NUM_PCIE_Q)
#define NIC_NBI_ENTRY_START   NIC_HOST_MAX_ENTRIES
#define NIC_WIRE_MAX_ENTRIES  (NUM_NBI*NUM_NBI_CHANNELS)


#define NIC_CFG_INSTR_TBL_ADDR 0x00
#define NIC_CFG_INSTR_TBL_SIZE (((NIC_HOST_MAX_ENTRIES+NIC_WIRE_MAX_ENTRIES) \
                                * NIC_MAX_INSTR)<<2)

/* For host ports,
 *   use 0 to NIC_HOST_MAX_ENTRIES-1
 * For wire ports,
 *   use NIC_HOST_MAX_ENTRIES .. NIC_WIRE_MAX_ENTRIES+NIC_HOST_MAX_ENTRIES*/
#if defined(__NFP_LANG_ASM)

    .alloc_mem NIC_CFG_INSTR_TBL cls+NIC_CFG_INSTR_TBL_ADDR \
                island NIC_CFG_INSTR_TBL_SIZE addr40
    .init NIC_CFG_INSTR_TBL 0 0

#elif defined(__NFP_LANG_MICROC)

    __asm
    {
        .alloc_mem NIC_CFG_INSTR_TBL cls + NIC_CFG_INSTR_TBL_ADDR \
                    island NIC_CFG_INSTR_TBL_SIZE addr40
        .init NIC_CFG_INSTR_TBL 0 0
    }


/* Instructions in the worker (actions.uc) should follow the exact same order
 * as in enum used by app config below.
 * The pipeline bit in the instruction_format is set when previous and
 * current instruction follows each other. This eliminates a branch/jmp by the
 * worker.
 *      i0#: br[drop#]
 *      i1#: br[mtu#]
 *      i2#: br[mac#]
 *      i3#: br[rss#]
 *      i4#: br[checksum_complete#]
 *      i5#: br[tx_host#]
 *      i6#: br[tx_wire#]
 */
enum instruction_type {
    INSTR_TX_DROP = 0,
    INSTR_MTU,
    INSTR_MAC,
    INSTR_RSS,
    INSTR_CHECKSUM_COMPLETE,
    INSTR_TX_HOST,
    INSTR_TX_WIRE
};


/* Instruction format of NIC_CFG_INSTR_TBL table. Some 32-bit words will
 * be parameter only i.e. MAC which is 48 bits. */
union instruction_format {
    struct {
        uint32_t instr : 15;
        uint32_t pipeline: 1;
        uint32_t param: 16;
    };
    uint32_t value;
};
#endif

#define INSTR_PIPELINE_BIT 16
#define INSTR_OPCODE_LSB   17


#endif /* _APP_CONFIG_INSTR_H_ */
