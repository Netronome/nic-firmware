/**
 * Copyright (C) 2015 Netronome Systems, Inc.  All rights reserved.
 *
 * @file catamaran_defs.h
 *
 * @brief Header file defining Catamaran data structures
 *
 * @note This file is auto-generated; do not modify.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#ifndef __CATAMARAN_DEFS_H__
#define __CATAMARAN_DEFS_H__


/* Catamaran Firmware Info */
#define CATAMARAN_REV_INFO_ADDR 0xff


/* General Configuration Data Info */
#define CATAMARAN_CFG_TABLE_ADDR_WIDTH                6
#define CATAMARAN_CFG_TABLE_BASE0                     0x160
#define CATAMARAN_CFG_TABLE_BASE1                     0x180
#define CATAMARAN_CFG_TABLE_SIZE                                              \
    (1 << CATAMARAN_CFG_TABLE_ADDR_WIDTH)

#define CATAMARAN_CFG_LOC_ADDR(_entry)                ((_entry) / 16)
#define CATAMARAN_CFG_DATA_ENTRY_8_OFF(_entry)        (((_entry) & 0xf) ^ 0xf)
#define CATAMARAN_CFG_DATA_ENTRY_16_LOWER_OFF(_entry) (((_entry) & 0xf) ^ 0xe)
#define CATAMARAN_CFG_DATA_ENTRY_16_UPPER_OFF(_entry) (((_entry) & 0xf) ^ 0xf)

#define CATAMARAN_CFG_GEN_ERROR_OFF                   0x0
#define CATAMARAN_CFG_GEN_ERROR_SZ                    2
#define CATAMARAN_CFG_GEN_ERROR_BP_SHF                8
#define CATAMARAN_CFG_GEN_ERROR_BP_FLAG_SHF           3
#define CATAMARAN_CFG_GEN_ERROR_SEQ_SHF               0
#define CATAMARAN_CFG_GEN_ERROR_SEQ_FLAG_SHF          4
#define CATAMARAN_CFG_GEN_ERROR_TNFP_SHF              6
#define CATAMARAN_CFG_GEN_ERROR_TNFP_FLAG_SHF         5

#define CATAMARAN_CFG_LIF_LKUP_HASH_OFF               0x2
#define CATAMARAN_CFG_LIF_LKUP_HASH_SZ                1

#define CATAMARAN_CFG_MAC_MATCH_HASH_OFF              0x3
#define CATAMARAN_CFG_MAC_MATCH_HASH_SZ               1

#define CATAMARAN_CFG_DEF_VLAN_OFF                    0x4
#define CATAMARAN_CFG_DEF_VLAN_SZ                     2

#define CATAMARAN_CFG_LB_INIT_ACCUM_OFF               0x6
#define CATAMARAN_CFG_LB_INIT_ACCUM_SZ                2

#define CATAMARAN_CFG_LB_HEAD_ETH_ARP_OFF             0x22
#define CATAMARAN_CFG_LB_HEAD_ETH_ARP_SZ              2
#define CATAMARAN_CFG_LB_HEAD_ETH_FCOE_OFF            0x26
#define CATAMARAN_CFG_LB_HEAD_ETH_FCOE_SZ             2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_ESP_OFF        0x12
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_ESP_SZ         2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_FRAG_OFF       0x1a
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_FRAG_SZ        2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_GRE_OFF        0x1c
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_GRE_SZ         2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_OTH_OFF        0x10
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_OTH_SZ         2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_SCTP_OFF       0x18
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_SCTP_SZ        2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_TCP_OFF        0x16
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_TCP_SZ         2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_UDP_OFF        0x14
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV4_UDP_SZ         2
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV6_OFF            0x1e
#define CATAMARAN_CFG_LB_HEAD_ETH_IPV6_SZ             2
#define CATAMARAN_CFG_LB_HEAD_ETH_MPLS_OFF            0x24
#define CATAMARAN_CFG_LB_HEAD_ETH_MPLS_SZ             2
#define CATAMARAN_CFG_LB_HEAD_ETH_OTH_OFF             0x20
#define CATAMARAN_CFG_LB_HEAD_ETH_OTH_SZ              2
#define CATAMARAN_CFG_LB_HEAD_ETH_SHORT_OFF           0x28
#define CATAMARAN_CFG_LB_HEAD_ETH_SHORT_SZ            2

#define CATAMARAN_CFG_LB_COMPLETE_OPCODE              1
#define CATAMARAN_CFG_LB_COMPLETE_OP_BP_FLAG          0x8
#define CATAMARAN_CFG_LB_COMPLETE_OP_SEQ_FLAG         0x10
#define CATAMARAN_CFG_LB_COMPLETE_OP_TNFP_FLAG        0x20
#define CATAMARAN_CFG_LB_ERROR_OPCODE                 0
#define CATAMARAN_CFG_LB_ETH_OPCODE                   4
#define CATAMARAN_CFG_LB_ETH_OP_DA_FLAG               0x1
#define CATAMARAN_CFG_LB_ETH_OP_SA_FLAG               0x2
#define CATAMARAN_CFG_LB_ETH_OP_ETYP_FLAG             0x4
#define CATAMARAN_CFG_LB_IPV4_OPCODE                  2
#define CATAMARAN_CFG_LB_IPV4_OP_DA_FLAG              0x1
#define CATAMARAN_CFG_LB_IPV4_OP_SA_FLAG              0x2
#define CATAMARAN_CFG_LB_IPV4_OP_PROTO_FLAG           0x4
#define CATAMARAN_CFG_LB_IPV6_OPCODE                  6
#define CATAMARAN_CFG_LB_IPV6_OP_DA_FLAG              0x1
#define CATAMARAN_CFG_LB_IPV6_OP_SA_FLAG              0x2
#define CATAMARAN_CFG_LB_IPV6_OP_NEXTHDR_FLAG         0x4
#define CATAMARAN_CFG_LB_SCTP_OPCODE                  7
#define CATAMARAN_CFG_LB_SCTP_OP_DP_FLAG              0x1
#define CATAMARAN_CFG_LB_SCTP_OP_SP_FLAG              0x2
#define CATAMARAN_CFG_LB_TCP_OPCODE                   7
#define CATAMARAN_CFG_LB_TCP_OP_DP_FLAG               0x1
#define CATAMARAN_CFG_LB_TCP_OP_SP_FLAG               0x2
#define CATAMARAN_CFG_LB_UDP_OPCODE                   7
#define CATAMARAN_CFG_LB_UDP_OP_DP_FLAG               0x1
#define CATAMARAN_CFG_LB_UDP_OP_SP_FLAG               0x2

#define CATAMARAN_CFG_BPSET0_THRESH_0_OFF             0x30
#define CATAMARAN_CFG_BPSET0_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET0_THRESH_1_OFF             0x40
#define CATAMARAN_CFG_BPSET0_THRESH_1_SZ              2
#define CATAMARAN_CFG_BPSET1_THRESH_0_OFF             0x32
#define CATAMARAN_CFG_BPSET1_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET1_THRESH_1_OFF             0x42
#define CATAMARAN_CFG_BPSET1_THRESH_1_SZ              2
#define CATAMARAN_CFG_BPSET2_THRESH_0_OFF             0x34
#define CATAMARAN_CFG_BPSET2_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET2_THRESH_1_OFF             0x44
#define CATAMARAN_CFG_BPSET2_THRESH_1_SZ              2
#define CATAMARAN_CFG_BPSET3_THRESH_0_OFF             0x36
#define CATAMARAN_CFG_BPSET3_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET3_THRESH_1_OFF             0x46
#define CATAMARAN_CFG_BPSET3_THRESH_1_SZ              2
#define CATAMARAN_CFG_BPSET4_THRESH_0_OFF             0x38
#define CATAMARAN_CFG_BPSET4_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET4_THRESH_1_OFF             0x48
#define CATAMARAN_CFG_BPSET4_THRESH_1_SZ              2
#define CATAMARAN_CFG_BPSET5_THRESH_0_OFF             0x3a
#define CATAMARAN_CFG_BPSET5_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET5_THRESH_1_OFF             0x4a
#define CATAMARAN_CFG_BPSET5_THRESH_1_SZ              2
#define CATAMARAN_CFG_BPSET6_THRESH_0_OFF             0x3c
#define CATAMARAN_CFG_BPSET6_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET6_THRESH_1_OFF             0x4c
#define CATAMARAN_CFG_BPSET6_THRESH_1_SZ              2
#define CATAMARAN_CFG_BPSET7_THRESH_0_OFF             0x3e
#define CATAMARAN_CFG_BPSET7_THRESH_0_SZ              2
#define CATAMARAN_CFG_BPSET7_THRESH_1_OFF             0x4e
#define CATAMARAN_CFG_BPSET7_THRESH_1_SZ              2


/* Header-Parse Protocol Look-Up Info */
#define CATAMARAN_HP_ENTRIES_PER_LOC             2
#define CATAMARAN_HP_HASH_ETH                    0x2f
#define CATAMARAN_HP_HASH_GRE                    0x2f
#define CATAMARAN_HP_HASH_IP                     0x4
#define CATAMARAN_HP_HASH_PPPOE                  0x2e
#define CATAMARAN_HP_HASH_TCP                    0x6
#define CATAMARAN_HP_HASH_UDP                    0x11
#define CATAMARAN_HP_TABLE_ADDR_WIDTH            8
#define CATAMARAN_HP_TABLE_BASE0                 0x200
#define CATAMARAN_HP_TABLE_BASE1                 0x300
#define CATAMARAN_HP_TABLE_SIZE                                               \
    (1 << CATAMARAN_HP_TABLE_ADDR_WIDTH)
#define CATAMARAN_HP_NUM_ENTRIES                                              \
    (CATAMARAN_HP_ENTRIES_PER_LOC << CATAMARAN_HP_TABLE_ADDR_WIDTH)
#define CATAMARAN_HP_PARENT_FIELD_SZ             8
#define CATAMARAN_HP_PROTO_FIELD_SZ              16
#define CATAMARAN_HP_NUM_PROTOS                                               \
    (1 << CATAMARAN_HP_PROTO_FIELD_SZ)
#define CATAMARAN_HP_MAX_PROTO_NUM               (CATAMARAN_HP_NUM_PROTOS - 1)
#define CATAMARAN_HP_MIN_PROTO_NUM               0
#define CATAMARAN_HP_HASH_KEY(_parent, _proto)   (_proto)
#define CATAMARAN_HP_KEY(_parent, _proto)                                     \
    (((_parent) << CATAMARAN_HP_PROTO_FIELD_SZ)                               \
     | CATAMARAN_HP_HASH_KEY(_parent, _proto))
#define CATAMARAN_HP_KEY_MASK                                                 \
    ((1 << (CATAMARAN_HP_PARENT_FIELD_SZ + CATAMARAN_HP_PROTO_FIELD_SZ)) - 1)
#define CATAMARAN_HP_DATA_FIELD_SZ               16
#define CATAMARAN_HP_DATA_MASK                                                \
    ((1 << (CATAMARAN_HP_DATA_FIELD_SZ)) - 1)
#define CATAMARAN_HP_OPCODE_FIELD_SZ             8
#define CATAMARAN_HP_OPCODE_MASK                                              \
    ((1 << CATAMARAN_HP_OPCODE_FIELD_SZ) - 1)
#define CATAMARAN_HP_NOP_OPCODE                  0
#define CATAMARAN_HP_OP_FIELD_SZ                 8
#define CATAMARAN_HP_OP_RSRC_SHF                 CATAMARAN_HP_OPCODE_FIELD_SZ
#define CATAMARAN_HP_OP_RSRC_SZ                  2
#define CATAMARAN_HP_OP_RSRC_MASK                                             \
    ((1 << CATAMARAN_HP_OP_RSRC_SZ) - 1)
#define CATAMARAN_HP_OP_RSRC_NOP                 0
#define CATAMARAN_HP_OP_RSRC_ASSIGN1             1
#define CATAMARAN_HP_OP_RSRC_ASSIGN2             2
#define CATAMARAN_HP_OP_RSRC_ASSIGN3             3
#define CATAMARAN_HP_OP_OFF_SHF                                               \
    (CATAMARAN_HP_OP_RSRC_SHF + CATAMARAN_HP_OP_RSRC_SZ)
#define CATAMARAN_HP_OP_OFF_SZ                   2
#define CATAMARAN_HP_OP_OFF_MASK                                              \
    ((1 << CATAMARAN_HP_OP_OFF_SZ) - 1)
#define CATAMARAN_HP_OP_OFF_NOP                  0x0
#define CATAMARAN_HP_OP_OFF_REMOVE               0x1
#define CATAMARAN_HP_OP_OFF_ADD                  0x2
#define CATAMARAN_HP_OP_OFF_OVERWRITE            0x3
#define CATAMARAN_HP_OP_MISC_FIELD_SHF                                        \
    (CATAMARAN_HP_OP_OFF_SHF + CATAMARAN_HP_OP_OFF_SZ)
#define CATAMARAN_HP_OP_MISC_FIELD_SZ                                         \
    (CATAMARAN_HP_DATA_FIELD_SZ - CATAMARAN_HP_OP_MISC_FIELD_SHF)
#define CATAMARAN_HP_OP_MISC_FIELD_MASK                                       \
    ((1 << CATAMARAN_HP_OP_MISC_FIELD_SZ) - 1)
#define CATAMARAN_HP_OP_POL_ID_SHF               CATAMARAN_HP_OP_MISC_FIELD_SHF
#define CATAMARAN_HP_OP_POL_ID_SZ                3
#define CATAMARAN_HP_OP_POL_ID_MASK                                           \
    ((1 << CATAMARAN_HP_OP_POL_ID_SZ) - 1)
#define CATAMARAN_HP_OP_POL_ID_NOP               0
#define CATAMARAN_HP_OP_POL_ID_OP1               1
#define CATAMARAN_HP_OP_POL_ID_OP2               2
#define CATAMARAN_HP_OP_POL_ID_OP3               3
#define CATAMARAN_HP_OP_POL_ID_OP4               4
#define CATAMARAN_HP_OP_POL_ID_OP5               5
#define CATAMARAN_HP_OP_POL_ID_OP6               6
#define CATAMARAN_HP_OP_POL_ID_OP7               7
#define CATAMARAN_HP_DATA_ENTRY(_opcode, _rsrc, _off, _misc)                  \
    ((_opcode) | ((_rsrc) << CATAMARAN_HP_OP_RSRC_SHF)                        \
     | ((_off) << CATAMARAN_HP_OP_OFF_SHF)                                    \
     | ((_misc) << CATAMARAN_HP_OP_MISC_FIELD_SHF))
#define CATAMARAN_HP_OPCODE(_data)                                            \
    ((_data) & CATAMARAN_HP_OPCODE_MASK)
#define CATAMARAN_HP_OP_RSRC(_data)                                           \
    (((_data) >> CATAMARAN_HP_OP_RSRC_SHF)                                    \
     & CATAMARAN_HP_OP_RSRC_MASK)
#define CATAMARAN_HP_OP_OFF(_data)                                            \
    (((_data) >> CATAMARAN_HP_OP_OFF_SHF)                                     \
     & CATAMARAN_HP_OP_OFF_MASK)
#define CATAMARAN_HP_OP_POL_ID(_data)                                         \
    (((_data) >> CATAMARAN_HP_OP_POL_ID_SHF)                                  \
     & CATAMARAN_HP_OP_POL_ID_MASK)

#define CATAMARAN_HP_VXLAN_DEF_PORT              4789
#define CATAMARAN_HP_VXLAN_OPCODE                0xaf
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF_SHF       CATAMARAN_HP_OP_MISC_FIELD_SHF
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF_SZ        2
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF_MASK                                   \
    ((1 << CATAMARAN_HP_VXLAN_OP_I_L2_OFF_SZ) - 1)
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF_NOP       0x0
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF_REMOVE    0x1
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF_ADD       0x2
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF_OVERWRITE 0x3
#define CATAMARAN_HP_VXLAN_OP_I_L2_OFF(_data)                                 \
    (((_data) >> CATAMARAN_HP_VXLAN_OP_I_L2_OFF_SHF)                          \
     & CATAMARAN_HP_VXLAN_OP_I_L2_OFF_MASK)


#define CATAMARAN_LB_ENTRIES_PER_LOC   16
#define CATAMARAN_LB_TABLE_ADDR_WIDTH  4
#define CATAMARAN_LB_TABLE_BASE0       0x1e0
#define CATAMARAN_LB_TABLE_BASE1       0x1f0
#define CATAMARAN_LB_TABLE_SIZE                                               \
    (1 << CATAMARAN_LB_TABLE_ADDR_WIDTH)
#define CATAMARAN_LB_NUM_ENTRIES                                              \
    (CATAMARAN_LB_ENTRIES_PER_LOC << CATAMARAN_LB_TABLE_ADDR_WIDTH)

#define CATAMARAN_LB_BP_VAL_SHIFT      3
#define CATAMARAN_LB_SEQ_VAL_SHIFT     0
#define CATAMARAN_LB_TNFP_VAL_SHIFT    6

#define CATAMARAN_LB_BP_PREIDX(_entry) (_entry)
#define CATAMARAN_LB_SEQ_PREIDX(_entry, _num_bps)                             \
    (CATAMARAN_LB_BP_PREIDX(_entry) / (_num_bps))
#define CATAMARAN_LB_TNFP_PREIDX(_entry, _num_bps, _num_seqs)                 \
    (CATAMARAN_LB_SEQ_PREIDX(_entry, _num_bps) / (_num_seqs))
#define CATAMARAN_LB_XTRA_PREIDX(_entry, _num_bps, _num_seqs, _num_tnfps)     \
    (CATAMARAN_LB_TNFP_PREIDX(_entry, _num_bps, _num_seqs) / (_num_tnfps))

#define CATAMARAN_LB_BP_IDX(_entry, _num_bps, _num_seqs, _num_tnfps)          \
    ((CATAMARAN_LB_BP_PREIDX(_entry)                                          \
      + CATAMARAN_LB_SEQ_PREIDX(_entry, _num_bps)) % (_num_bps))
#define CATAMARAN_LB_SEQ_IDX(_entry, _num_bps, _num_seqs, _num_tnfps)         \
    ((CATAMARAN_LB_SEQ_PREIDX(_entry, _num_bps)                               \
      + CATAMARAN_LB_TNFP_PREIDX(_entry, _num_bps, _num_seqs)) % (_num_seqs))
#define CATAMARAN_LB_TNFP_IDX(_entry, _num_bps, _num_seqs, _num_tnfps)        \
    ((CATAMARAN_LB_TNFP_PREIDX(_entry, _num_bps, _num_seqs)                   \
      + CATAMARAN_LB_XTRA_PREIDX(_entry, _num_bps, _num_seqs, _num_tnfps))    \
     % (_num_tnfps))


/* Channel-To-Port Look-Up Info */
#define CATAMARAN_CHAN_ENTRIES_PER_LOC   8
#define CATAMARAN_CHAN_TABLE_ADDR_WIDTH  4
#define CATAMARAN_CHAN_TABLE_BASE0       0x1a0
#define CATAMARAN_CHAN_TABLE_BASE1       0x1b0
#define CATAMARAN_CHAN_TABLE_SIZE                                             \
    (1 << CATAMARAN_CHAN_TABLE_ADDR_WIDTH)
#define CATAMARAN_CHAN_NUM_ENTRIES                                            \
    (CATAMARAN_CHAN_ENTRIES_PER_LOC << CATAMARAN_CHAN_TABLE_ADDR_WIDTH)

#define CATAMARAN_CHAN_LOC_ADDR(_chan)                                        \
    ((_chan) / CATAMARAN_CHAN_ENTRIES_PER_LOC)
#define CATAMARAN_CHAN_MODE_OFF(_chan)                                        \
    ((((_chan) * (16 / CATAMARAN_CHAN_ENTRIES_PER_LOC)) & 0xf) ^ 0xe)
#define CATAMARAN_CHAN_PORT_OFF(_chan)                                        \
    ((((_chan) * (16 / CATAMARAN_CHAN_ENTRIES_PER_LOC)) & 0xf) ^ 0xf)

#define CATAMARAN_CHAN_NUM_CHANS         128
#define CATAMARAN_CHAN_MAX_CHAN_NUM      (CATAMARAN_CHAN_NUM_CHANS - 1)
#define CATAMARAN_CHAN_MIN_CHAN_NUM      0
#define CATAMARAN_CHAN_NUM_PORTS         256
#define CATAMARAN_CHAN_MAX_PORT_NUM      (CATAMARAN_CHAN_NUM_PORTS - 1)
#define CATAMARAN_CHAN_MIN_PORT_NUM      0
#define CATAMARAN_CHAN_MODE_UNCONFIGURED 0
#define CATAMARAN_CHAN_MODE_PORT_TO_LIF  1
#define CATAMARAN_CHAN_MODE_VLAN_TO_LIF  2
#define CATAMARAN_CHAN_MODE_MAC_DA_MATCH 3
#define CATAMARAN_CHAN_MIN_MODE_NUM      CATAMARAN_CHAN_MODE_UNCONFIGURED
#define CATAMARAN_CHAN_MAX_MODE_NUM      CATAMARAN_CHAN_MODE_MAC_DA_MATCH


/* Port-To-LIF+Mode Look-Up Info */
#define CATAMARAN_PORT_ENTRIES_PER_LOC  8
#define CATAMARAN_PORT_TABLE_ADDR_WIDTH 4
#define CATAMARAN_PORT_TABLE_BASE0      0x1c0
#define CATAMARAN_PORT_TABLE_BASE1      0x1d0
#define CATAMARAN_PORT_TABLE_SIZE                                             \
    (1 << CATAMARAN_PORT_TABLE_ADDR_WIDTH)
#define CATAMARAN_PORT_NUM_ENTRIES                                            \
    (CATAMARAN_PORT_ENTRIES_PER_LOC << CATAMARAN_PORT_TABLE_ADDR_WIDTH)
#define CATAMARAN_PORT_NUM_PORTS        128
#define CATAMARAN_PORT_MAX_PORT_NUM     (CATAMARAN_PORT_NUM_PORTS - 1)
#define CATAMARAN_PORT_MIN_PORT_NUM     0

#define CATAMARAN_PORT_LOC_ADDR(_port)                                        \
    ((_port) / CATAMARAN_PORT_ENTRIES_PER_LOC)
#define CATAMARAN_PORT_DATA_ENTRY_LOWER_OFF(_port)                            \
    ((((_port) * (16 / CATAMARAN_PORT_ENTRIES_PER_LOC)) & 0xf) ^ 0xf)
#define CATAMARAN_PORT_DATA_ENTRY_UPPER_OFF(_port)                            \
    ((((_port) * (16 / CATAMARAN_PORT_ENTRIES_PER_LOC)) & 0xf) ^ 0xe)

#define CATAMARAN_PORT_LIF_FIELD_SZ     10
#define CATAMARAN_PORT_NUM_LIFS         (1 << CATAMARAN_PORT_LIF_FIELD_SZ)
#define CATAMARAN_PORT_MAX_LIF_NUM      (CATAMARAN_PORT_NUM_LIFS - 1)
#define CATAMARAN_PORT_MIN_LIF_NUM      0
#define CATAMARAN_PORT_LIF_LOWER_SZ     8
#define CATAMARAN_PORT_LIF_LOWER_MASK                                         \
    ((1 << CATAMARAN_PORT_LIF_LOWER_SZ) - 1)
#define CATAMARAN_PORT_LIF_UPPER_MASK                                         \
    ((1 << (CATAMARAN_PORT_LIF_FIELD_SZ - CATAMARAN_PORT_LIF_LOWER_SZ)) - 1)
#define CATAMARAN_PORT_MODE_FIELD_SZ    4
#define CATAMARAN_PORT_NUM_MODES        (1 << CATAMARAN_PORT_MODE_FIELD_SZ)
#define CATAMARAN_PORT_MAX_MODE_NUM     (CATAMARAN_PORT_NUM_MODES - 1)
#define CATAMARAN_PORT_MIN_MODE_NUM     0
#define CATAMARAN_PORT_MODE_MASK        (CATAMARAN_PORT_NUM_MODES - 1)
#define CATAMARAN_PORT_MODE_SHF         4
#define CATAMARAN_PORT_DATA_ENTRY_LOWER(_lif, _mode)                          \
    ((_lif) & CATAMARAN_PORT_LIF_LOWER_MASK)
#define CATAMARAN_PORT_DATA_ENTRY_UPPER(_lif, _mode)                          \
    ((((_mode) & CATAMARAN_PORT_MODE_MASK) << CATAMARAN_PORT_MODE_SHF)        \
     | (((_lif) >> CATAMARAN_PORT_LIF_LOWER_SZ)                               \
        & CATAMARAN_PORT_LIF_UPPER_MASK))
#define CATAMARAN_PORT_LIF(_data_lo, _data_hi)                                \
    ((_data_lo) | (((_data_hi) & CATAMARAN_PORT_LIF_UPPER_MASK)               \
                   << CATAMARAN_PORT_LIF_LOWER_SZ))
#define CATAMARAN_PORT_MODE(_data_lo, _data_hi)                               \
    (((_data_hi) >> CATAMARAN_PORT_MODE_SHF) & CATAMARAN_PORT_MODE_MASK)


/* LIF+VLAN Look-Up Info */
#define CATAMARAN_VLAN_ENTRIES_PER_LOC    2
#define CATAMARAN_VLAN_HASH_SEED          0xbb
#define CATAMARAN_VLAN_TABLE_ADDR_WIDTH   10
#define CATAMARAN_VLAN_TABLE_BASE0        0x0
#define CATAMARAN_VLAN_TABLE_BASE1        0x400
#define CATAMARAN_VLAN_TABLE_SIZE                                             \
    (1 << CATAMARAN_VLAN_TABLE_ADDR_WIDTH)
#define CATAMARAN_VLAN_NUM_ENTRIES                                            \
    (CATAMARAN_VLAN_ENTRIES_PER_LOC << CATAMARAN_VLAN_TABLE_ADDR_WIDTH)
#define CATAMARAN_VLAN_DEF_UNTAGGED_VLAN  0xfff
#define CATAMARAN_VLAN_DEF_UNTAGGED_CNOTS 0
#define CATAMARAN_VLAN_PORT_FIELD_SZ      8
#define CATAMARAN_VLAN_NUM_PORTS                                              \
    (1 << CATAMARAN_VLAN_PORT_FIELD_SZ)
#define CATAMARAN_VLAN_MAX_PORT_NUM       (CATAMARAN_VLAN_NUM_PORTS - 1)
#define CATAMARAN_VLAN_MIN_PORT_NUM       0
#define CATAMARAN_VLAN_CNOTS_FLAG_SHF     13
#define CATAMARAN_VLAN_VALID_FLAG_SHF     15
#define CATAMARAN_VLAN_VALID_FLAG_MASK    (1 << CATAMARAN_VLAN_VALID_FLAG_SHF)
#define CATAMARAN_VLAN_VLAN_FIELD_SZ      12
#define CATAMARAN_VLAN_NUM_VLANS                                              \
    (1 << CATAMARAN_VLAN_VLAN_FIELD_SZ)
#define CATAMARAN_VLAN_MAX_VLAN_NUM       (CATAMARAN_VLAN_NUM_VLANS - 1)
#define CATAMARAN_VLAN_MIN_VLAN_NUM       0
#define CATAMARAN_VLAN_HASH_KEY0(_port, _vlan, _cnots)                        \
    (_port)
#define CATAMARAN_VLAN_HASH_KEY1(_port, _vlan, _cnots)                        \
    (CATAMARAN_VLAN_VALID_FLAG_MASK                                           \
     | ((_cnots) << CATAMARAN_VLAN_CNOTS_FLAG_SHF) | (_vlan))
#define CATAMARAN_VLAN_KEY(_port, _vlan, _cnots)                              \
    ((CATAMARAN_VLAN_HASH_KEY0(_port, _vlan, _cnots) << 16)                   \
     | CATAMARAN_VLAN_HASH_KEY1(_port, _vlan, _cnots))
#define CATAMARAN_VLAN_KEY_MASK                                               \
    ((1 << (CATAMARAN_VLAN_PORT_FIELD_SZ + 16)) - 1)

#define CATAMARAN_VLAN_DATA_FIELD_SZ      16
#define CATAMARAN_VLAN_DATA_MASK                                              \
    ((1 << CATAMARAN_VLAN_DATA_FIELD_SZ) - 1)
#define CATAMARAN_VLAN_LIF_FIELD_SZ       CATAMARAN_PORT_LIF_FIELD_SZ
#define CATAMARAN_VLAN_NUM_LIFS                                               \
    (1 << CATAMARAN_VLAN_LIF_FIELD_SZ)
#define CATAMARAN_VLAN_MAX_LIF_NUM        (CATAMARAN_VLAN_NUM_LIFS - 1)
#define CATAMARAN_VLAN_MIN_LIF_NUM        CATAMARAN_PORT_MIN_LIF_NUM
#define CATAMARAN_VLAN_LIF_MASK           (CATAMARAN_VLAN_NUM_LIFS - 1)
#define CATAMARAN_VLAN_MODE_FIELD_SZ      CATAMARAN_PORT_MODE_FIELD_SZ
#define CATAMARAN_VLAN_NUM_MODES          (1 << CATAMARAN_VLAN_MODE_FIELD_SZ)
#define CATAMARAN_VLAN_MAX_MODE_NUM       (CATAMARAN_VLAN_NUM_MODES - 1)
#define CATAMARAN_VLAN_MIN_MODE_NUM       CATAMARAN_PORT_MIN_MODE_NUM
#define CATAMARAN_VLAN_MODE_MASK          (CATAMARAN_VLAN_NUM_MODES - 1)
#define CATAMARAN_VLAN_MODE_SHF                                               \
    (CATAMARAN_VLAN_DATA_FIELD_SZ - CATAMARAN_VLAN_MODE_FIELD_SZ)
#define CATAMARAN_VLAN_DATA_ENTRY(_lif, _mode)                                \
    (((_mode) << CATAMARAN_VLAN_MODE_SHF) | (_lif))
#define CATAMARAN_VLAN_LIF(_data)         ((_data) & CATAMARAN_VLAN_LIF_MASK)
#define CATAMARAN_VLAN_MODE(_data)                                            \
    (((_data) >> CATAMARAN_VLAN_MODE_SHF) & CATAMARAN_VLAN_MODE_MASK)


/* MAC DA Match Info */
#define CATAMARAN_MAC_ENTRIES_PER_LOC   2
#define CATAMARAN_MAC_HASH_SEED         0xcc
#define CATAMARAN_MAC_TABLE_ADDR_WIDTH  10
#define CATAMARAN_MAC_TABLE_BASE0       0x800
#define CATAMARAN_MAC_TABLE_BASE1       0xc00
#define CATAMARAN_MAC_TABLE_SIZE                                              \
    (1 << CATAMARAN_MAC_TABLE_ADDR_WIDTH)
#define CATAMARAN_MAC_NUM_ENTRIES                                             \
    (CATAMARAN_MAC_ENTRIES_PER_LOC << CATAMARAN_MAC_TABLE_ADDR_WIDTH)
#define CATAMARAN_MAC_HASH_KEY(_mac_da) (_mac_da)
#define CATAMARAN_MAC_KEY(_mac_da)      CATAMARAN_MAC_HASH_KEY(_mac_da)
#define CATAMARAN_MAC_KEY_MASK          ((1 << 48) - 1)
#define CATAMARAN_MAC_MATCH_ID_SZ       16
#define CATAMARAN_MAC_DATA_MASK                                               \
    ((1 << CATAMARAN_MAC_MATCH_ID_SZ) - 1)


#endif /* ndef __CATAMARAN_DEFS_H__ */
