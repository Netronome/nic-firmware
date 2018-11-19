/*
 * Copyright (C) 2015-2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_config_instr.h
 * @brief         Header file for App Config ME instruction table
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _APP_CONFIG_INSTR_H_
#define _APP_CONFIG_INSTR_H_

#include <kernel/nfp_net_ctrl.h>
#include <vnic/shared/nfd.h>

#define NUM_PCIE_Q          64      // number of queues configured per PCIe
#define NUM_PCIE_Q_PER_PORT NFD_MAX_PF_QUEUES // nr queues cfg per port
#define NIC_MAX_INSTR       16      // max number of instructions in table

#define NIC_CFG_INSTR_TBL_ADDR 0x00
#define NIC_CFG_INSTR_TBL_SIZE 32768

#define RSS_TBL_SIZE_LW     (NFP_NET_CFG_RSS_ITBL_SZ / 4)
#define NIC_RSS_TBL_SIZE    (NFP_NET_CFG_RSS_ITBL_SZ * NS_PLATFORM_NUM_PORTS * NFD_MAX_ISL)
#define NIC_RSS_TBL_ADDR    NIC_CFG_INSTR_TBL_SIZE

#define VLAN_TO_VNICS_MAP_TBL_SIZE ((1<<12) * 8)

/* For host ports,
 *   use 0 to NIC_HOST_MAX_ENTRIES-1
 * For wire ports,
 *   use NIC_HOST_MAX_ENTRIES .. NIC_WIRE_MAX_ENTRIES+NIC_HOST_MAX_ENTRIES*/
#if defined(__NFP_LANG_ASM)

    .alloc_mem NIC_CFG_INSTR_TBL cls+NIC_CFG_INSTR_TBL_ADDR \
                island NIC_CFG_INSTR_TBL_SIZE addr40

    .alloc_mem NIC_RSS_TBL cls+NIC_RSS_TBL_ADDR \
                island NIC_RSS_TBL_SIZE addr40

    .alloc_mem _vf_vlan_cache ctm island VLAN_TO_VNICS_MAP_TBL_SIZE 65536

    /* PCIe Queue RX BUF SZ table*/
    .alloc_mem _fl_buf_sz_cache imem global (64*4*4) 256

#elif defined(__NFP_LANG_MICROC)

    __asm
    {
        .alloc_mem NIC_CFG_INSTR_TBL cls + NIC_CFG_INSTR_TBL_ADDR \
            island NIC_CFG_INSTR_TBL_SIZE addr40
    }

    __asm
    {
        .alloc_mem NIC_RSS_TBL cls + NIC_RSS_TBL_ADDR \
            island NIC_RSS_TBL_SIZE addr40
    }

    __asm
    {
        .alloc_mem _vf_vlan_cache ctm island VLAN_TO_VNICS_MAP_TBL_SIZE 65536
    }

    /* PCIe Queue RX BUF SZ table*/
    __asm
    {
        .alloc_mem _fl_buf_sz_cache imem global (64*4*4) 256
    }

#endif
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
#if defined(__NFP_LANG_ASM)
    #define    INSTR_DROP              0
    #define    INSTR_RX_WIRE           1
    #define    INSTR_DST_MAC_MATCH     2
    #define    INSTR_CHECKSUM          3
    #define    INSTR_RSS               4
    #define    INSTR_TX_HOST           5
    #define    INSTR_RX_HOST           6
    #define    INSTR_TX_WIRE           7
    #define    INSTR_CMSG              8
    #define    INSTR_EBPF              9
    #define    INSTR_POP_VLAN          10
    #define    INSTR_PUSH_VLAN         11
    #define    INSTR_SRC_MAC_MATCH     12
    #define    INSTR_VEB_LOOKUP        13
    #define    INSTR_POP_PKT           14
    #define    INSTR_PUSH_PKT          15
    #define    INSTR_TX_VLAN           16
    #define    INSTR_L2_SWITCH_WIRE    17
    #define    INSTR_L2_SWITCH_HOST    18
#elif defined(__NFP_LANG_MICROC)
enum instruction_ops {
    INSTR_DROP = 0,
    INSTR_RX_WIRE,
    INSTR_DST_MAC_MATCH,
    INSTR_CHECKSUM,
    INSTR_RSS,
    INSTR_TX_HOST,
    INSTR_RX_HOST,
    INSTR_TX_WIRE,
    INSTR_CMSG,
    INSTR_EBPF,
    INSTR_POP_VLAN,
    INSTR_PUSH_VLAN,
    INSTR_SRC_MAC_MATCH,
    INSTR_VEB_LOOKUP,
    INSTR_POP_PKT,
    INSTR_PUSH_PKT,
    INSTR_TX_VLAN,
    INSTR_L2_SWITCH_WIRE,
    INSTR_L2_SWITCH_HOST
};

/* this maping will eventually be replaced at build time with actual offsets
 *
 * - required to be in monotonically increasing order of relative action
 *   addresses as they appear in ME code store
 * - additional entry at end denotes length of the last action (as if another
 *   action follows)
 */

/* Instruction format of NIC_CFG_INSTR_TBL table.
 *
 *
 * INSTR_DROP:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |              0              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 *       P = Pipeline actions
 *
 * INSTR_RX_WIRE:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-----+-------------+-----+-+-+-+
 *    0  |              1              |P|  0  |VXLAN_NN_IDX |VXLAN|G|N|C|
 *       +-----------------------------+-+-----+-------------+-----+-+-+-+
 *
 *       VXLAN_NN_IDX = NN base of VXLAN port table
 *       VXLAN = Number of VXLAN ports
 *       G = Parse GENEVE
 *       N = Parse NVGRE
 *       C = Propagate MAC checksum
 *
 * INSTR_VEB_LOOKUP:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |              2              |P|            MAC HI             |
 *       +-----------------------------+-+-------------------------------+
 *    1  |                            MAC LO                             |
 *       +---------------------------------------------------------------+
 *
 * MAC: pass on match (skip lookup / shortcut to PF)
 * MAC = 0: pass on VEB miss (promiscuous mode)
 *
 * INSTR_DST_MAC_MATCH:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |              3              |P|            MAC HI             |
 *       +-----------------------------+-+-------------------------------+
 *    1  |                            MAC LO                             |
 *       +---------------------------------------------------------------+
 *
 * MAC: drop on mismatch
 *
 * INSTR_SRC_MAC_MATCH:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |              3              |P|            MAC LO             |
 *       +-----------------------------+-+-------------------------------+
 *    1  |                            MAC HI                             |
 *       +---------------------------------------------------------------+
 *
 * MAC: drop on mismatch
 *
 * INSTR_RSS:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-+-+-+-+---------+-+-+---------+
 *    0  |              4              |P|u|t|U|T| Tbl idx |1| MAX Queue |
 *       +---------------+-------------+-+-+-+-+-+---------+-+-+---------+
 *    1  |                            RSS Key                            |
 *       +---------------------------------------------------------------+
 *
 *       u - Enable IPV4_UDP
 *       t - Enable IPV4_TCP
 *       U - Enable IPV6_UDP
 *       T - Enable IPV6_TCP
 *       1 - RSSv1
 *
 * INSTR_CHECKSUM:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------+-+-------+-+-+-+-+
 *    0  |              5              |P|      0      |M|   0   |I|i|C|c|
 *       +-----------------------------+-+-------------+-+-------+-+-+-+-+
 *
 *       M - Update CHECKSUM_COMPLETE metadata
 *       I - Update inner L3 checksum in packet (if requested by host)
 *       i - Update inner L4 checksum in packet (if requested by host)
 *       C - Update outer L3 checksum in packet (if requested by host)
 *       c - Update outer L4 checksum in packet (if requested by host)
 *
 * INSTR_TX_HOST:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-+-+-----------+---+-----------+
 *    0  |              6              |P|C|M|  MIN RXB  |PCI|Base Queue |
 *       +-----------------------------+-+-+-+-----------+---+-----------+
 *
 * C - Continue action processing after TX (non-terminal)
 * M - continue only if packet MAC DST is Multicast/Broadcast
 *
 *
 * INSTR_TX_VLAN:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |              7              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_RX_HOST:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+---------------------------+-+-+
 *    0  |              8              |P|           MTU             |C|c|
 *       +-----------------------------+-+---------------------------+-+-+
 *
 * C - Enable outer L3 checksum processing
 * c - Enable outer L4 checksum processing
 *
 * INSTR_TX_WIRE:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-+-+-----+-+-------------------+
 *    0  |              9              |P|C|M|  0  |N|     TM Queue      |
 *       +-----------------------------+-+-+-+-----+-+-------------------+
 *
 * C - Continue (non-terminal action)
 * M - continue if Multicast
 * N - NBI
 *
 * INSTR_RX_CMSG:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |             10              |P|           Reserved            |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_EXEC_EBPF:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |             11              |P|            UC Addr            |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_POP_VLAN:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-+-------------+---------------+
 *    0  |             12              |P|                               |
 *       +-----------------------------+-+-+-------------+---------------+
 *
 * INSTR_PUSH_VLAN:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-+-------------+---------------+
 *    0  |             13              |P|           VLAN TAG            |
 *       +-----------------------------+-+-+-------------+---------------+
 *
 * INSTR_PUSH_PKT:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |             14              |P|                               |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_POP_PKT:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |             15              |P|                               |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_L2_SWITCH_WIRE:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |              17             |P|                               |
 *       +-----------------------------+-+-------------------------------+
 *
 * INSTR_L2_SWITCH_HOST:
 * Bit \  3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------------+-+-------------------------------+
 *    0  |              18             |P|                               |
 *       +-----------------------------+-+-------------------------------+
 */

/* Instruction format of NIC_CFG_INSTR_TBL table. Some 32-bit words will
 * be parameter only i.e. MAC which is 48 bits. */
union instruction_format {
    struct {
        uint32_t op : 15;
        uint32_t pipeline: 1;
        uint32_t args: 16;
    };
    uint32_t value;
};

typedef union {
    struct {
        uint32_t op : 15;
        uint32_t pipeline : 1;
        uint32_t cfg_proto : 4;
        uint32_t tbl_idx : 5;
        uint32_t v1_meta : 1;
        uint32_t max_queue : 6;
        uint32_t key;
    };
    uint32_t __raw[2];
} instr_rss_t;

typedef union {
    struct {
	    uint32_t op: 15;
	    uint32_t pipeline: 1;
	    uint32_t reserved: 3;
	    uint32_t vxlan_nn_idx: 7;
	    uint32_t parse_vxlans: 3;
	    uint32_t parse_geneve: 1;
	    uint32_t parse_nvgre: 1;
	    uint32_t host_encap_prop_csum: 1;
    };
    uint32_t __raw[1];
} instr_rx_wire_t;

typedef union {
    struct {
	    uint32_t op: 15;
	    uint32_t pipeline: 1;
	    uint32_t mtu: 14;
	    uint32_t csum_outer_l3: 1;
	    uint32_t csum_outer_l4: 1;
    };
    uint32_t __raw[1];
} instr_rx_host_t;

typedef union {
    struct {
        uint32_t op: 15;
        uint32_t pipeline: 1;
        uint32_t cont: 1;
        uint32_t multicast: 1;
        uint32_t min_rxb: 6;
        uint32_t pcie: 2;
        uint32_t queue: 6;
    };
    uint32_t __raw[1];
} instr_tx_host_t;

typedef union {
    struct {
        uint32_t op: 15;
        uint32_t pipeline: 1;
        uint32_t reserved: 16;
    };
    uint32_t __raw[2];
} instr_tx_vlan_t;

typedef union {
    struct {
        uint32_t op: 15;
        uint32_t pipeline: 1;
        uint32_t cont: 1;
        uint32_t multicast: 1;
        uint32_t reserved: 3;
        //uint32_t nbi: 1;
        uint32_t tm_queue: 11;
    };
    uint32_t __raw[1];
} instr_tx_wire_t;

typedef union {
    struct {
        uint32_t op: 15;
        uint32_t pipeline: 1;
        uint32_t reserved: 7;
        uint32_t complete_meta : 1;
        uint32_t zero: 4;
        uint32_t inner_l3 : 1;
        uint32_t inner_l4 : 1;
        uint32_t outer_l3 : 1;
	uint32_t outer_l4 : 1;
    };
    uint32_t __raw[1];
} instr_checksum_t;
#endif

#define INSTR_PIPELINE_BIT 16
#define INSTR_OPCODE_LSB   17

#define INSTR_RSS_CFG_PROTO_bf  0, 15, 12
#define INSTR_RSS_TABLE_IDX_bf  0, 11, 7
#define INSTR_RSS_V1_META_bf    0, 6, 6
#define INSTR_RSS_MAX_QUEUE_bf  0, 5, 0
#define INSTR_RSS_KEY_bf        1, 31, 0

#define INSTR_RX_HOST_MTU_bf     0, 15, 2

#define INSTR_RX_VXLAN_NN_IDX_bf 0, 12, 6
#define INSTR_RX_PARSE_VXLANS_bf 0, 5, 3
#define INSTR_RX_PARSE_GENEVE_bf 0, 2, 2
#define INSTR_RX_PARSE_NVGRE_bf  0, 1, 1
#define INSTR_RX_HOST_ENCAP_bf   0, 0, 0
#define INSTR_RX_WIRE_CSUM_bf    0, 0, 0

#define INSTR_TX_CONTINUE_bf     0, 15, 15
#define INSTR_TX_MULTICAST_bf    0, 14, 14

#define INSTR_TX_HOST_MIN_RXB_bf 0, 13, 8

#define INSTR_TX_WIRE_NBI_bf     0, 10, 10
#define INSTR_TX_WIRE_TMQ_bf     0, 9, 0

#define INSTR_CSUM_META_bf       0, 8, 8
#define INSTR_CSUM_IL3_bf        0, 3, 3
#define INSTR_CSUM_IL4_bf        0, 2, 2
#define INSTR_CSUM_OL3_bf        0, 1, 1
#define INSTR_CSUM_OL4_bf        0, 0, 0

#define INSTR_DEL_OFFSET_bf      0, 14, 8
#define INSTR_DEL_LENGTH_bf      0, 7, 0

#if defined(__NFP_LANG_ASM)

    #define __LOOP 0
    #define __OFFSET 0

    #while (__LOOP <= (NUM_PCIE_Q_PER_PORT * NS_PLATFORM_NUM_PORTS))
        .init NIC_CFG_INSTR_TBL+__OFFSET  ((INSTR_RX_HOST << INSTR_OPCODE_LSB) | 16383) INSTR_DROP
        #define_eval __OFFSET (__OFFSET + (4 * NIC_MAX_INSTR))
        #define_eval __LOOP (__LOOP + 1)
    #endloop

    #define_eval __LOOP 0
    #define_eval __OFFSET ((1 << 8) * (NIC_MAX_INSTR * 4))

    #while (__LOOP < NS_PLATFORM_NUM_PORTS)
        .init NIC_CFG_INSTR_TBL+__OFFSET  ((INSTR_RX_WIRE << INSTR_OPCODE_LSB) | 16383) INSTR_DROP
        #define_eval __OFFSET (__OFFSET + (4 * NIC_MAX_INSTR))
        #define_eval __LOOP (__LOOP + 1)
	#endloop

    #undef __LOOP
    #undef __OFFSET


#endif

#endif /* _APP_CONFIG_INSTR_H_ */
