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


#define NUM_PCIE_Q          64      // number of queues configured per PCIe
#define NUM_PCIE_Q_PER_PORT NFD_MAX_PF_QUEUES // nr queues cfg per port
#define NIC_MAX_INSTR       16      // max number of instructions in table

#define NIC_CFG_INSTR_TBL_ADDR 0x00
#define NIC_CFG_INSTR_TBL_SIZE 32768

#define RSS_TBL_SIZE_LW     64

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
    INSTR_RX_WIRE,
    INSTR_MAC,
    INSTR_RSS,
    INSTR_CHECKSUM_COMPLETE,
    INSTR_TX_HOST,
    INSTR_RX_HOST,
    INSTR_TX_WIRE,
    INSTR_CMSG,
    INSTR_EBPF,
};

/* Instruction format of NIC_CFG_INSTR_TBL table.
 *
 *
 * INSTR_DROP:
 *       +-----------------------------+-+-------------------------------+
 *    0  |              0              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 *       P = Pipeline actions
 *
 * INSTR_RX_WIRE:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+---+---------------------------+
 *    0  |              1              |P| 0 |           MTU             |
 *       +-----------------------------+-+-+-+---+-+-+-------------------+
 *    1  |  VXLAN1 (N=1) / NN_IDX (N>1)  |E|VXLAN|N|G|         R         |
 *       +-------------------------------+-+-----+-+-+-------------------+
 *
 *       G = Parse GENEVE
 *       N = Parse NVGRE
 *       VXLAN = Parse VXLAN for N ports
 *
 * INSTR_MAC_CLASSIFY:
 *       +-----------------------------+-+-------------------------------+
 *    0  |              2              |P|            MAC HI             |
 *       +-----------------------------+-+-------------------------------+
 *    1  |                            MAC LO                             |
 *       +---------------------------------------------------------------+
 *
 * Passing MAC = 0xffffff enabled promiscuous mode
 *
 * INSTR_RSS:
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-+-----------+-+-+-+-+---------+
 *    0  |              3              |P|1| MAX Queue |u|t|U|T| C Shift |
 *       +---------------+-------------+-+-+-----+-----+-+-+-+-+---------+
 *    1  |  Queue Mask   |  Row Mask   | Col Msk | Table Addr  | R Shift |
 *       +---------------+-------------+---------+-------------+---------+
 *    2  |                            RSS Key                            |
 *       +---------------------------------------------------------------+
 *
 *       u - Enable IPV4_UDP
 *       t - Enable IPV4_TCP
 *       U - Enable IPV6_UDP
 *       T - Enable IPV6_TCP
 *       1 - RSSv1
 *
 * INSTR_CHECKSUM_COMPLETE:
 *       +-----------------------------+-+-------------------------------+
 *    0  |              4              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_TX_HOST:
 *       +-----------------------------+-+---------------+---+-----------+
 *    0  |              5              |P|       0       |PCI|Base Queue |
 *       +-----------------------------+-+---------------+---------------+
 *
 * INSTR_RX_HOST:
 *       +-----------------------------+-+---------------+---------------+
 *    0  |              6              |P| 0 |           MTU             |
 *       +-------------------------------+---+---------------------------+
 *
 * INSTR_TX_WIRE:
 *       +-----------------------------+-+---------+-+-------------------+
 *    0  |              7              |P|    0    |N|     TM Queue      |
 *       +-----------------------------+-+---------+-+-------------------+
 *
 * INSTR_RX_CMSG:
 *       +-----------------------------+-+-------------------------------+
 *    0  |              8              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_VF
 *       +-----------------------------+-+-------------------------------+
 *    0  |              9              |P|              MTU              |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_STRIP_VLAN:
 *       +-----------------------------+-+-------------------------------+
 *    0  |             10              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_LKUP_VLAN:
 *       +-----------------------------+-+-------------------------------+
 *    0  |             11              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_EXEC_EBPF:
 *       +-----------------------------+-+-------------------------------+
 *    0  |             12              |P|            UC Addr            |
 *       +-----------------------------+-+-------------------------------+
 */

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

typedef union {
    struct {
        uint32_t instr : 15;
        uint32_t pipeline : 1;
        uint32_t v1_meta : 1;
        uint32_t max_queue : 6;
        uint32_t cfg_proto : 4;
        uint32_t col_shf : 5;
        uint32_t queue_mask : 8;
        uint32_t row_mask : 7;
        uint32_t col_mask : 5;
        uint32_t table_addr : 7;
        uint32_t row_shf : 5;
	uint32_t key;
    };
    uint32_t __raw[3];
} instr_rss_t;
#endif

#define INSTR_PIPELINE_BIT 16
#define INSTR_OPCODE_LSB   17

#define INSTR_RSS_V1_META_bf    0, 15, 15
#define INSTR_RSS_MAX_QUEUE_bf  0, 14, 9
#define INSTR_RSS_CFG_PROTO_bf  0, 8, 5
#define INSTR_RSS_COL_SHIFT_bf  0, 4, 0
#define INSTR_RSS_QUEUE_MASK_bf 1, 31, 24
#define INSTR_RSS_ROW_MASK_bf   1, 23, 17
#define INSTR_RSS_COL_MASK_bf   1, 16, 12
#define INSTR_RSS_TABLE_ADDR_bf 1, 11, 5
#define INSTR_RSS_ROW_SHIFT_bf  1, 4, 0
#define INSTR_RSS_KEY_bf        2, 31, 0


#endif /* _APP_CONFIG_INSTR_H_ */
