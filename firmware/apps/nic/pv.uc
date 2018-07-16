/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   pv.uc
 * @brief  Packet state and metadata management. Also provides packet read access abstraction.
 */

#ifndef _PACKET_VECTOR_UC
#define _PACKET_VECTOR_UC

#include <bitfields.uc>
#include <gro.uc>
#include <nfd_in.uc>
#include <nfd_out.uc>
#include <ov.uc>
#include <passert.uc>
#include <stdmac.uc>
#include <net/eth.h>
#include <net/ip.h>
#include <net/tcp.h>
#include <net/vxlan.h>
#include <nic_basic/nic_stats.h>
#include <nfp_net_ctrl.h>

#include "pkt_buf.uc"

#include "protocols.h"
#include "app_config_instr.h"

#define BF_MASK(w, m, l) ((1 << (m + 1 - l)) - 1)

#define NBI_IN_META_SIZE_LW 6

#define BF_AB(a, w, m, l) a[w], (l/8)    // Returns aggregate[word], byte. "byte" is the byte(0-3) wherein the MSB - LSB falls

/**
 * Packet vector internal representation
 *
 * Important!!!
 * ------------
 * Field locations have been deliberately chosen for efficient mapping to and
 * from various descriptor formats and should not be moved. Code within this
 * module actively exploits this specific layout for more efficient decoding
 * and encoding of packet state. Do not change the layout or the values of
 * intentional constants without exhaustively assessing the impact on all the
 * code within this module.
 *
 * Optimization assumptions
 * ------------------------
 *  - No shared code store - SCS == 0
 *
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-----------+-------------------+---+---------------------------+
 *    0  |     0     |   Packet Number   |BLS|       Packet Length       |
 *       +-+---+-----+-------------------+---+---------------------------+
 *    1  |S|CBS|           MU Buffer Address [39:11]                     |
 *       +-+---+-----+-------------------+-----+-------------------------+
 *    2  |A|    0    |   Packet Number   |  0  |         Offset          |
 *       +-+---------+-------------------+-----+---------+---------------+
 *    3  |        Sequence Number        |  0  | Seq Ctx |   Protocol    |
 *       +-------------------------------+---+-+---------+---+-+-+-+-+-+-+
 *    4  |         TX Host Flags         | 0 |Seek (64B algn)|-|Q|M|B|C|c|
 *       +-------------------------------+---+---------------+-+-+-+-+-+-+
 *    5  |       8B Header Offsets (stacked outermost to innermost)      |
 *       +-----------------+-------------+---------------+---------------+
 *    6  |  Ingress Queue  | Meta Length |   Reserved    | Queue Offset  |
 *       +-----------------+-------------+---------------+---------------+
 *    7  |                    Metadata Type Fields                       |
 *       +---------------------------------------------------------------+
 *    8  |             Original Packet Length (if from host)             |
 *       +---------------+-----------+-+-+-------+-----------------------+
 *    9  |    Next VF    | Reserved  |B|P|   0   |        VLAN ID        |
 *       +-----+-+-+-+-+-+-+-+---+---+-+-+-------+-----------------------+
 *   10  |P_STS|M|E|A|F|D|R|H|L3I|MPD|VLD|           Checksum            |
 *       +-----+-+-+-+-+-+-+-+---+---+---+-------------------------------+
 *
 * 0     - Intentionally zero for efficient extraction and manipulation
 * S     - Split packet
 * A     - 1 if CTM buffer is allocated (ie. packet number and CTM address valid)
 * CBS   - CTM Buffer Size
 * BLS   - Buffer List
 * Q     - Queue offset selected (overrides RSS)
 * V     - One or more VLANs present
 * M     - dest MAC is multicast
 * B     - dest MAC is broadcast
 * C     - Enable MAC offload of L3 checksum
 * c     - Enable MAC offload of L4 checksum
 *
 * Protocol - Parsed Packet Type (see defines below)
 *
 * TX host flags:
 *       +-------------------------------+
 *    4  |-|-|-|-|-|-|-|B|-|4|$|t|T|u|U|-|
 *       +--------------------------------
 *
 * -   - Flag currently unsupported by firmware (see nfp-drv-kmods)
 * B   - BPF offload executed
 * 4   - IPv4 header was parsed
 * $   - IPv4 checksum is valid
 * t   - TCP header was parsed
 * T   - TCP checksum is valid
 * u   - UDP header was parsed
 * U   - UDP checksum is valid
 *
 * Ingress Queue:
 *
 *       +-+---+-----------+
 * PCIE: |0|ISL|   Queue   |
 *       +-+---+-----------+
 *
 *       +-+---------------+
 * NBI:  |1|     Port      |
 *       +-+---------------+
 */

#define PV_SIZE_LW                      16

#define PV_LENGTH_wrd                   0
#define PV_NUMBER_bf                    PV_LENGTH_wrd, 25, 16
#define PV_BLS_bf                       PV_LENGTH_wrd, 15, 14
#define PV_LENGTH_bf                    PV_LENGTH_wrd, 13, 0

#define PV_MU_ADDR_wrd                  1
#define PV_SPLIT_bf                     PV_MU_ADDR_wrd, 31, 31
#define PV_CBS_bf                       PV_MU_ADDR_wrd, 30, 29
#define PV_MU_ADDR_bf                   PV_MU_ADDR_wrd, 28, 0

#define PV_CTM_ADDR_wrd                 2
#define PV_CTM_ADDR_bf                  PV_CTM_ADDR_wrd, 31, 0
#define PV_CTM_ALLOCATED_bf             PV_CTM_ADDR_wrd, 31, 31
#define PV_OFFSET_bf                    PV_CTM_ADDR_wrd, 12, 0

#define PV_SEQ_wrd                      3
#define PV_SEQ_NO_bf                    PV_SEQ_wrd, 31, 16
#define PV_SEQ_CTX_bf                   PV_SEQ_wrd, 12, 8
#define PV_PROTO_bf                     PV_SEQ_wrd, 7, 0

#define PV_FLAGS_wrd                    4
#define PV_TX_FLAGS_bf                  PV_FLAGS_wrd, 31, 16
#define PV_TX_HOST_RX_BPF_bf            PV_FLAGS_wrd, 24, 24
#define PV_TX_HOST_L3_bf                PV_FLAGS_wrd, 22, 21
#define PV_TX_HOST_IP4_bf               PV_FLAGS_wrd, 22, 22
#define PV_TX_HOST_CSUM_IP4_OK_bf       PV_FLAGS_wrd, 21, 21
#define PV_TX_HOST_L4_bf                PV_FLAGS_wrd, 20, 17
#define PV_TX_HOST_TCP_bf               PV_FLAGS_wrd, 20, 20
#define PV_TX_HOST_CSUM_TCP_OK_bf       PV_FLAGS_wrd, 19, 19
#define PV_TX_HOST_UDP_bf               PV_FLAGS_wrd, 18, 18
#define PV_TX_HOST_CSUM_UDP_OK_bf       PV_FLAGS_wrd, 17, 17
#define PV_SEEK_BASE_bf                 PV_FLAGS_wrd, 13, 6
#define PV_QUEUE_SELECTED_bf            PV_FLAGS_wrd, 4, 4
#define PV_MAC_DST_TYPE_bf              PV_FLAGS_wrd, 3, 2
#define PV_MAC_DST_MC_bf                PV_FLAGS_wrd, 3, 3
#define PV_MAC_DST_BC_bf                PV_FLAGS_wrd, 2, 2
#define PV_CSUM_OFFLOAD_bf              PV_FLAGS_wrd, 1, 0
#define PV_CSUM_OFFLOAD_L3_bf           PV_FLAGS_wrd, 1, 1
#define PV_CSUM_OFFLOAD_L4_bf           PV_FLAGS_wrd, 0, 0

#define PV_HEADER_STACK_wrd             5
#define PV_HEADER_STACK_bf              PV_HEADER_STACK_wrd, 31, 0
#define PV_HEADER_OFFSET_OUTER_IP_bf    PV_HEADER_STACK_wrd, 31, 24
#define PV_HEADER_OFFSET_OUTER_L4_bf    PV_HEADER_STACK_wrd, 23, 16
#define PV_HEADER_OFFSET_INNER_IP_bf    PV_HEADER_STACK_wrd, 15, 8
#define PV_HEADER_OFFSET_INNER_L4_bf    PV_HEADER_STACK_wrd, 7, 0

#define PV_QUEUE_wrd                    6
#define PV_QUEUE_IN_bf                  PV_QUEUE_wrd, 31, 23
#define PV_QUEUE_IN_TYPE_bf             PV_QUEUE_wrd, 31, 31
#define PV_QUEUE_IN_NBI_NR_bf           PV_QUEUE_wrd, 30, 30
#define PV_QUEUE_IN_NBI_PORT_bf         PV_QUEUE_wrd, 29, 23
#define PV_QUEUE_IN_PCI_ISL_bf          PV_QUEUE_wrd, 30, 29
#define PV_QUEUE_IN_PCI_Q_bf            PV_QUEUE_wrd, 28, 23
#define PV_META_LENGTH_bf               PV_QUEUE_wrd, 22, 16
#define PV_QUEUE_OFFSET_bf              PV_QUEUE_wrd, 7, 0

#define PV_META_TYPES_wrd               7
#define PV_META_TYPES_bf                PV_META_TYPES_wrd, 31, 0

#define PV_ORIG_LENGTH_wrd              8
#define PV_ORIG_LENGTH_bf               PV_ORIG_LENGTH_wrd, 13, 0

#define PV_VLAN_wrd                     9
#define PV_BROADCAST_NEXT_VF_bf         PV_VLAN_wrd, 31, 24
#define PV_BROADCAST_ACTIVE_bf          PV_VLAN_wrd, 17, 17
#define PV_BROADCAST_PROMISC_bf         PV_VLAN_wrd, 16, 16
#define PV_VLAN_ID_bf                   PV_VLAN_wrd, 11, 0

#define PV_CSUM_wrd                     10
#define PV_CSUM_bf                      PV_CSUM_wrd, 15, 0
#define PV_VLD_bf                       PV_CSUM_wrd, 17, 16
#define PV_MPD_bf                       PV_CSUM_wrd, 19, 18

#define PROTO_IPV6_TCP                          0x00
#define PROTO_IPV6_UDP                          0x01
#define PROTO_IPV4_TCP                          0x02
#define PROTO_IPV4_UDP                          0x03
#define PROTO_IPV6_UNKNOWN                      0x04
#define PROTO_IPV6_FRAGMENT                     0x05
#define PROTO_IPV4_UNKNOWN                      0x06
#define PROTO_IPV4_FRAGMENT                     0x07
#define PROTO_IPV6_UDP_VXLAN_IPV6_TCP           0x20
#define PROTO_IPV6_UDP_VXLAN_IPV6_UDP           0x21
#define PROTO_IPV6_UDP_VXLAN_IPV4_TCP           0x22
#define PROTO_IPV6_UDP_VXLAN_IPV4_UDP           0x23
#define PROTO_IPV6_UDP_VXLAN_IPV6_UNKNOWN       0x24
#define PROTO_IPV6_UDP_VXLAN_IPV6_FRAGMENT      0x25
#define PROTO_IPV6_UDP_VXLAN_IPV4_UNKNOWN       0x26
#define PROTO_IPV6_UDP_VXLAN_IPV4_FRAGMENT      0x27
#define PROTO_MPLS_IPV6_TCP                     0x40
#define PROTO_MPLS_IPV6_UDP                     0x41
#define PROTO_MPLS_IPV4_TCP                     0x42
#define PROTO_MPLS_IPV4_UDP                     0x43
#define PROTO_MPLS_IPV6_UNKNOWN                 0x44
#define PROTO_MPLS_IPV6_FRAGMENT                0x45
#define PROTO_MPLS_IPV4_UNKNOWN                 0x46
#define PROTO_MPLS_IPV4_FRAGMENT                0x47
#define PROTO_IPV4_UDP_VXLAN_IPV6_TCP           0x60
#define PROTO_IPV4_UDP_VXLAN_IPV6_UDP           0x61
#define PROTO_IPV4_UDP_VXLAN_IPV4_TCP           0x62
#define PROTO_IPV4_UDP_VXLAN_IPV4_UDP           0x63
#define PROTO_IPV4_UDP_VXLAN_IPV6_UNKNOWN       0x64
#define PROTO_IPV4_UDP_VXLAN_IPV6_FRAGMENT      0x65
#define PROTO_IPV4_UDP_VXLAN_IPV4_UNKNOWN       0x66
#define PROTO_IPV4_UDP_VXLAN_IPV4_FRAGMENT      0x67
#define PROTO_IPV6_GRE_IPV6_TCP                 0x80
#define PROTO_IPV6_GRE_IPV6_UDP                 0x81
#define PROTO_IPV6_GRE_IPV4_TCP                 0x82
#define PROTO_IPV6_GRE_IPV4_UDP                 0x83
#define PROTO_IPV6_GRE_IPV6_UNKNOWN             0x84
#define PROTO_IPV6_GRE_IPV6_FRAGMENT            0x85
#define PROTO_IPV6_GRE_IPV4_UNKNOWN             0x86
#define PROTO_IPV6_GRE_IPV4_FRAGMENT            0x87
#define PROTO_IPV6_UDP_GENEVE_IPV6_TCP          0xA0
#define PROTO_IPV6_UDP_GENEVE_IPV6_UDP          0xA1
#define PROTO_IPV6_UDP_GENEVE_IPV4_TCP          0xA2
#define PROTO_IPV6_UDP_GENEVE_IPV4_UDP          0xA3
#define PROTO_IPV6_UDP_GENEVE_IPV6_UNKNOWN      0xA4
#define PROTO_IPV6_UDP_GENEVE_IPV6_FRAGMENT     0xA5
#define PROTO_IPV6_UDP_GENEVE_IPV4_UNKNOWN      0xA6
#define PROTO_IPV6_UDP_GENEVE_IPV4_FRAGMENT     0xA7
#define PROTO_IPV4_GRE_IPV6_TCP                 0xC0
#define PROTO_IPV4_GRE_IPV6_UDP                 0xC1
#define PROTO_IPV4_GRE_IPV4_TCP                 0xC2
#define PROTO_IPV4_GRE_IPV4_UDP                 0xC3
#define PROTO_IPV4_GRE_IPV6_UNKNOWN             0xC4
#define PROTO_IPV4_GRE_IPV6_FRAGMENT            0xC5
#define PROTO_IPV4_GRE_IPV4_UNKNOWN             0xC6
#define PROTO_IPV4_GRE_IPV4_FRAGMENT            0xC7
#define PROTO_IPV4_UDP_GENEVE_IPV6_TCP          0xE0
#define PROTO_IPV4_UDP_GENEVE_IPV6_UDP          0xE1
#define PROTO_IPV4_UDP_GENEVE_IPV4_TCP          0xE2
#define PROTO_IPV4_UDP_GENEVE_IPV4_UDP          0xE3
#define PROTO_IPV4_UDP_GENEVE_IPV6_UNKNOWN      0xE4
#define PROTO_IPV4_UDP_GENEVE_IPV6_FRAGMENT     0xE5
#define PROTO_IPV4_UDP_GENEVE_IPV4_UNKNOWN      0xE6
#define PROTO_IPV4_UDP_GENEVE_IPV4_FRAGMENT     0xE7

#define PROTO_TCP                          (0x0 << 0)
#define PROTO_UDP                          (0x1 << 0)
#define PROTO_IPV6                         (0x0 << 1)
#define PROTO_IPV4                         (0x1 << 1)
#define PROTO_MPLS                         (0x1 << 6)
#define PROTO_L4_UNKNOWN                   (0x1 << 2)
#define PROTO_FRAG                         (0x5 << 0)
#define PROTO_GRE                          (0x4 << 5)
#define PROTO_GENEVE                       (0x5 << 5)
#define TUNNEL_SHF                         5
#define PROTO_UNKNOWN                      0xFF

#ifndef PV_GRO_NFD_START
    #define PV_GRO_NFD_START            4
#endif

#if (defined(NFD_PCIE1_EMEM) || defined(NFD_PCIE2_EMEM) || defined(NFD_PCIE3_EMEM))
    #define PV_MULTI_PCI
#endif


#macro pv_init(io_vec, PACKET_ID)
#if (strstr('io_vec', '*l$index') == 1)
    .alloc_mem _PKT_IO_PKT_VEC_/**/PACKET_ID lmem me (4 * (1 << log2((PV_SIZE_LW * 4), 1))) (4 * (1 << log2((PV_SIZE_LW * 4), 1)))
.begin
    .reg addr
    .reg offset

    immed[addr, _PKT_IO_PKT_VEC_/**/PACKET_ID]
#if (log2((PV_SIZE_LW * 4), 1) <= 8)
    alu[addr, addr, OR, t_idx_ctx, >>(8 - log2((PV_SIZE_LW * 4), 1))]
#else
    alu[addr, addr, OR, t_idx_ctx, <<(log2((PV_SIZE_LW * 4), 1) - 8)]
#endif
    #define_eval _PV_INIT_LM_HANDLE strright('io_vec', 1)
    local_csr_wr[ACTIVE_LM_ADDR_/**/_PV_INIT_LM_HANDLE, addr]
    #undef _PV_INIT_LM_HANDLE
    nop
    nop
    nop
.end
#endif
#endm


#macro pv_set_tx_flag(io_vec, flag)
    alu[BF_A(io_vec, PV_TX_FLAGS_bf), BF_A(io_vec, PV_TX_FLAGS_bf), OR, 1, <<flag]
#endm

#macro pv_set_queue_offset__sz1(io_vec, in_queue)
    ld_field[BF_A(io_vec, PV_QUEUE_OFFSET_bf), 0001, in_queue] ; PV_QUEUE_OFFSET_bf
#endm


#macro pv_get_nbi_egress_channel_mapped_to_ingress(out_chan, in_vec)
    // TODO: configure Catamaran / TM such that egress and ingress channel numbers coincide
    bitfield_extract__sz1(out_chan, BF_AML(in_vec, PV_QUEUE_IN_NBI_PORT_bf))
    #define_eval __PV_EGRESS_CHANNEL_SPACING NS_PLATFORM_NBI_TM_QID_LO(1)
    #define __PV_EGRESS_CHANNEL_SHIFT 0
    #if (__PV_EGRESS_CHANNEL_SPACING != 0)
        #define_eval __PV_EGRESS_CHANNEL_SHIFT log2(__PV_EGRESS_CHANNEL_SPACING)
    #endif
    alu[out_chan, --, B, out_chan, <<__PV_EGRESS_CHANNEL_SHIFT] // will only work for base queue
    #undef __PV_EGRESS_CHANNEL_SPACING
    #undef __PV_EGRESS_CHANNEL_SHIFT
#endm


#macro pv_set_ingress_queue__sz1(out_pkt_vec, in_addr, IN_SIZE)
    passert(IN_SIZE, "POWER_OF_2")
    alu[BF_A(out_pkt_vec, PV_QUEUE_IN_bf), --, B, in_addr, <<(BF_L(PV_QUEUE_IN_bf) - log2(IN_SIZE))]
#endm


#macro pv_get_length(out_length, in_vec)
    alu[out_length, 0, +16, BF_A(in_vec, PV_LENGTH_bf)] ; PV_LENGTH_bf
    alu[out_length, out_length, AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
#endm


#macro pv_meta_push_type__sz1(io_vec, in_type)
    alu[BF_A(io_vec, PV_META_TYPES_bf), in_type, OR, BF_A(io_vec, PV_META_TYPES_bf), <<4]
#endm


#macro pv_meta_prepend(io_vec, in_metadata, in_length)
.begin
    .reg addr
    .reg meta_len
    .sig sig_meta

    bitfield_extract__sz1(meta_len, BF_AML(io_vec, PV_META_LENGTH_bf)) ; PV_META_LENGTH_bf
    alu[meta_len, meta_len, +, in_length]
    alu[addr, BF_A(io_vec, PV_CTM_ADDR_bf), -, meta_len] ; PV_CTM_ADDR_bf
    mem[write32, in_metadata, addr, 0, (in_length >> 2)], ctx_swap[sig_meta], defer[2]
        bitfield_insert__sz2(BF_AML(io_vec, PV_META_LENGTH_bf), meta_len) ; PV_META_LENGTH_bf
.end
#endm


#macro pv_stats_tx_host(io_vec, in_queue_base, IN_LABEL)
.begin
    .reg addr
    .reg length
    .reg queue_idx
    .reg stat_idx
    .reg type_idx
    .reg write $idx_rx
    .reg write $idx_tx
    .sig sig_rx
    .sig sig_tx

    passert(NIC_STATS_QUEUE_RX_IDX, "EQ", 0)
    passert(log2(NIC_STATS_QUEUE_SIZE / 8), "GT", log2(BF_MASK(PV_MAC_DST_TYPE_bf) + 1))
    alu[type_idx, BF_MASK(PV_MAC_DST_TYPE_bf), AND, BF_A(io_vec, PV_MAC_DST_TYPE_bf), >>BF_L(PV_MAC_DST_TYPE_bf)] ; PV_MAC_DST_TYPE_bf

    br_bset[BF_AL(io_vec, PV_QUEUE_IN_TYPE_bf), nbi#], defer[3]
        immed[addr, (_nic_stats_queue >> 24), <<(24-8)]
        alu[length, BF_A(io_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
        ld_field[length, 1100, 2, <<16] // 32 bit unpacked addressing

    // update egress queue's RX stats
    alu[queue_idx, in_queue_base, +8, BF_A(io_vec, PV_QUEUE_OFFSET_bf)] ; PV_QUEUE_OFFSET_bf
    alu[$idx_rx, type_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    mem[stats_log, $idx_rx, addr, <<8, length, 2], sig_done[sig_rx]

    // update ingress queue's TX stats
    alu[length, 0, +16, BF_A(io_vec, PV_ORIG_LENGTH_bf)]
    ld_field[length, 1100, 2, <<16] // 32 bit unpacked addressing512
    alu[stat_idx, NIC_STATS_QUEUE_TX_IDX, +, type_idx]
    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    mem[stats_log, $idx_tx, addr, <<8, length, 2], sig_done[sig_tx]
    #pragma warning(default:4700)
    ctx_arb[sig_rx, sig_tx], br[IN_LABEL], defer[2]
        alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
        passert(log2(NIC_STATS_QUEUE_SIZE / 8), "GT", log2(NIC_STATS_QUEUE_TX_IDX))
        alu[$idx_tx, stat_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #pragma warning(default:5009)

nbi#:
    // update egress queue's RX stats
    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    mem[stats_log, $idx_rx, addr, <<8, length, 2], sig_done[sig_rx]
    #pragma warning(default:4700)
    ctx_arb[sig_rx], br[IN_LABEL], defer[2]
        alu[queue_idx, in_queue_base, +8, BF_A(io_vec, PV_QUEUE_OFFSET_bf)] ; PV_QUEUE_OFFSET_bf
        alu[$idx_rx, type_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #pragma warning(default:5009)
.end
#endm


#macro pv_stats_tx_wire(io_vec, IN_LABEL)
.begin
    .reg addr
    .reg length
    .reg queue_idx
    .reg stat_idx
    .reg type_idx
    .reg write $idx
    .sig sig_stat

    passert(log2(NIC_STATS_QUEUE_SIZE / 8), "GT", log2(NIC_STATS_QUEUE_TX_IDX))

    br_bset[BF_AL(io_vec, PV_QUEUE_IN_TYPE_bf), IN_LABEL] // no update if packet source is NBI

    immed[addr, (_nic_stats_queue >> 24), <<(24-8)]
    alu[addr, addr, OR, 2, <<(16-8)] // 32 bit unpacked addressing

    alu[length, 0, +16, BF_A(io_vec, PV_ORIG_LENGTH_bf)]

    alu[type_idx, BF_MASK(PV_MAC_DST_TYPE_bf), AND, BF_A(io_vec, PV_MAC_DST_TYPE_bf), >>BF_L(PV_MAC_DST_TYPE_bf)] ; PV_MAC_DST_TYPE_bf
    alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf

    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    mem[stats_log, $idx, addr, <<8, length, 2], sig_done[sig_stat]
    #pragma warning(default:4700)
    ctx_arb[sig_stat], br[IN_LABEL], defer[2]
        alu[stat_idx, NIC_STATS_QUEUE_TX_IDX, +, type_idx]
        alu[$idx, stat_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #pragma warning(default:5009)
.end
#endm


#macro pv_stats_update(io_vec, IN_STAT, IN_LABEL)
.begin
    .reg addr
    .reg length
    .reg queue_idx
    .reg sig_stat
    .reg write $idx
    .sig sig_stat

    immed[addr, (_nic_stats_queue >> 24), <<(24-8)]
    alu[addr, addr, OR, 2, <<(16-8)] // 32 bit unpacked addressing

    alu[length, BF_A(io_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf

    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    #if (is_ct_const(NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX))
        #if (log2(NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX, 1) < log2(NIC_STATS_QUEUE_SIZE / 8))
            #if (streq('IN_LABEL', '--'))
                mem[stats_log, $idx, addr, <<8, length, 2], ctx_swap[sig_stat], defer[2]
            #else
                mem[stats_log, $idx, addr, <<8, length, 2], sig_done[sig_stat]
                ctx_arb[sig_stat], br[IN_LABEL], defer[2]
            #endif
            alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
            alu[$idx, NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
        #else
            alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
            #if (streq('IN_LABEL', '--'))
                mem[stats_log, $idx, addr, <<8, length, 2], ctx_swap[sig_stat], defer[2]
            #else
                mem[stats_log, $idx, addr, <<8, length, 2], sig_done[sig_stat]
                ctx_arb[sig_stat], br[IN_LABEL], defer[2]
            #endif
            alu[queue_idx, --, B, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
            alu[$idx, queue_idx, +, NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX]
        #endif
    #else
        alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
        #if (streq('IN_LABEL', '--'))
            mem[stats_log, $idx, addr, <<8, length, 2], ctx_swap[sig_stat], defer[2]
        #else
            mem[stats_log, $idx, addr, <<8, length, 2], sig_done[sig_stat]
            ctx_arb[sig_stat], br[IN_LABEL], defer[2]
        #endif
        alu[queue_idx, --, B, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
        alu[$idx, queue_idx, +, IN_STAT]
    #endif
    #pragma warning(default:4700)
    #pragma warning(default:5009)
.end
#endm


#macro __pv_mtu_check(in_vec, in_mtu, in_vlan_len, FAIL_LABEL)
.begin
    .reg max_vlan
    .reg len

    alu[len, BF_A(in_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)]
    alu[len, len, -, in_mtu]

    alu[len, len, -, in_vlan_len]

    br_bclr[len, BF_L(PV_BLS_bf), FAIL_LABEL]
.end
#endm


#macro pv_get_gro_drop_desc(out_desc, in_vec)
    immed[out_desc[GRO_META_TYPE_wrd], (GRO_DTYPE_DROP_SEQ << GRO_META_TYPE_shf)]
    immed[out_desc[1], 0]
    immed[out_desc[2], 0]
    immed[out_desc[3], 0]
#endm


/**
 * GRO descriptor for delivery via NBI
 *
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-------------------------------------------------+-------+-----+
 *    0  |                    Reserved                     |  NBI  |  1  |
 *       +---+-----------+-------+-------------------------+-------+-----+
 *    1  |NBI|  CTM ISL  |  DM   |                  0                    | (addr_hi)
 *       +---+-------+---+-------+-------+---+---------------------------+
 *    2  |     0     |   Packet Number   | 0 | Packet Len (incl. offset) | (addr_lo)
 *       +---+---+---+-------------------+---+-+---------+---------------+
 *    3  | 0 |CBS| 0 |     TX Queue      |  0  | PMS Off |     0xCB      | (prev_alu)
 *       +---+---+-----------------------------+---------+---------------+
 *
 * Words 1 through 3 correspond to the arguments to the packet complete
 * command that will ultimately be used by GRO to send the packet.
 */
#macro pv_get_gro_wire_desc(out_desc, in_vec, in_queue_base, pms_offset)
.begin
    .reg addr_lo
    .reg ctm_buf_sz
    .reg desc
    .reg nbi
    .reg prev_alu
    .reg queue

    #if (NBI_COUNT != 1 || SCS != 0)
        #error "RO_META_TYPE_wrd and GRO_META_NBI_ADDRHI_wrd assume nbi = 0. The latter depends on __MEID too."
    #endif

    alu[nbi, 0x80, AND, in_queue_base, >>10]
    alu[out_desc[GRO_META_TYPE_wrd], (GRO_DTYPE_IFACE | (GRO_DEST_IFACE_BASE << GRO_META_DEST_shf)), OR, nbi, <<GRO_META_DEST_shf]
    immed[desc, ((__ISLAND << 8) | (((__MEID & 1) + 2) << 4)), <<16] // __MEID
    alu[out_desc[GRO_META_NBI_ADDRHI_wrd], desc, OR, nbi, <<30]

    alu[addr_lo, BF_A(in_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    alu[out_desc[GRO_META_NBI_ADDRLO_wrd], addr_lo, +16, in_vec[PV_CTM_ADDR_wrd]]

    #if (is_ct_const(pms_offset))
        immed[prev_alu, ((((pms_offset >> 3) - 1) << 8) | 0xcb)]
    #else
        alu[prev_alu, --, B, pms_offset, >>3]
        alu[prev_alu, prev_alu, -, 1]
        alu[prev_alu, 0xcb, OR, prev_alu, <<8]
    #endif
    alu[queue, in_queue_base, AND~, 0x3f, <<10]
    alu[queue, queue, +8, BF_A(in_vec, PV_QUEUE_OFFSET_bf)]
    alu[prev_alu, prev_alu, OR, queue, <<16]
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[out_desc[GRO_META_NBI_PALU_wrd], prev_alu, OR, ctm_buf_sz, <<28]
.end
#endm

/**
 * GRO descriptor for delivery via NFD
 *
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-----------+-+-----------------+---+-------------+-------+-----+
 *    0  |  CTM ISL  |C|  Packet Number  |CBS| offset >> 1 | PCIe  |  2  |
 *       +-+---+-----+-+-----------------+---+-------------+-------+-----+
 *    1  |N|BLS|           MU Buffer Address [39:11]                     |
 *       +-+---+---------+---------------+-------------------------------+
 *    2  |O| Meta Length |  RX Queue     |           Data Length         |
 *       +-+-------------+---------------+-------------------------------+
 *    3  |             VLAN              |             Flags             |
 *       +-------------------------------+-------------------------------+
 */
#macro pv_get_gro_host_desc(out_desc, in_vec, in_queue_base)
.begin
    .reg addr
    .reg buf_list
    .reg ctm_buf_sz
    .reg ctm_only
    .reg desc
    .reg meta_len
    .reg offset
    .reg pkt_len
    .reg data_len
    .reg pkt_num
    .reg tmp
    .reg queue
    .reg write $meta_types
    .sig sig_meta

    #ifdef SPLIT_EMU_RINGS
        // NFD supports SPLIT_EMU_RINGS (separate EMU rings for each NBI)
        // by providing the "N" bit extending the BLS field.  In practice
        // If SPLIT_EMU_RINGS is _not_ used, then N is simply zero for all
        // NBIs.
        #error "SPLIT_EMU_RINGS configuration not supported."
    #endif

    bitfield_extract__sz1(meta_len, BF_AML(in_vec, PV_META_LENGTH_bf))
    beq[skip_meta#], defer[3]
        // Word 1
        alu[desc, BF_A(in_vec, PV_MU_ADDR_bf), AND~, ((BF_MASK(PV_SPLIT_bf) << BF_WIDTH(PV_CBS_bf)) | BF_MASK(PV_CBS_bf)), <<BF_L(PV_CBS_bf)]
        bitfield_extract__sz1(buf_list, BF_AML(in_vec, PV_BLS_bf)) ; PV_BLS_bf
        alu[out_desc[NFD_OUT_BLS_wrd], desc, OR, buf_list, <<NFD_OUT_BLS_shf]

        alu[meta_len, meta_len, +, 4]
        alu[addr, BF_A(in_vec, PV_CTM_ADDR_bf), -, meta_len]
        alu[$meta_types, --, B, BF_A(in_vec, PV_META_TYPES_bf)]
        mem[write32, $meta_types, addr, 0, 1], ctx_swap[sig_meta], defer[2]
skip_meta#:

    // Word 0
    alu[tmp, BF_A(in_vec, PV_OFFSET_bf), -, meta_len] ; PV_OFFSET_bf
    ld_field_w_clr[offset, 0011, tmp, >>1]
    alu[desc, GRO_DTYPE_NFD, OR, offset, <<GRO_META_W0_META_START_BIT]
    ld_field[desc, 1100, BF_A(in_vec, PV_NUMBER_bf)] ; PV_NUMBER_bf
    #ifdef PV_MULTI_PCI
        alu[tmp, 3, AND, in_queue_base, >>6]
        alu[desc, desc, OR, tmp, <<GRO_META_DEST_shf]
    #endif
    alu[ctm_only, 1, AND~, BF_A(in_vec, PV_SPLIT_bf), >>BF_L(PV_SPLIT_bf)] ; PV_SPLIT_bf
    alu[desc, desc, OR, ctm_only, <<NFD_OUT_CTM_ONLY_shf]
    alu[desc, desc, OR, __ISLAND, <<NFD_OUT_CTM_ISL_shf]
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[out_desc[NFD_OUT_SPLIT_wrd], desc, OR, ctm_buf_sz, <<NFD_OUT_SPLIT_shf]

    // Word 2
    alu[data_len, BF_A(in_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_LENGTH_bf, PV_BLS_bf
    alu[data_len, meta_len, +16, data_len]
    alu[desc, data_len, OR, meta_len, <<NFD_OUT_METALEN_shf]
    #ifndef GRO_EVEN_NFD_OFFSETS_ONLY
       alu[desc, desc, OR, BF_A(in_vec, PV_OFFSET_bf), <<31] // meta_len is always even, this is safe
    #endif
    #ifdef PV_MULTI_PCI
        alu[queue, in_queue_base, AND, 0x3f]
        alu[queue, queue, +8, BF_A(in_vec, PV_QUEUE_OFFSET_bf)]
    #else
        alu[queue, in_queue_base, +8, BF_A(in_vec, PV_QUEUE_OFFSET_bf)]
    #endif
    alu[out_desc[NFD_OUT_QID_wrd], desc, OR, queue, <<NFD_OUT_QID_shf]

    // Word 3
    alu[out_desc[NFD_OUT_FLAGS_wrd], --, B, BF_A(in_vec, PV_TX_FLAGS_bf), >>BF_L(PV_TX_FLAGS_bf)] ; PV_TX_FLAGS_bf
.end

#endm


#macro pv_get_ctm_base(out_addr, in_vec)
    // mask out packet offset
    alu[out_addr, 0xff, ~AND, BF_A(in_vec, PV_CTM_ADDR_bf), >>8] ; PV_CTM_ADDR_bf
#endm


#macro pv_get_mu_base(out_addr, in_vec)
    alu[out_addr, --, B, BF_A(in_vec, PV_MU_ADDR_bf), <<3] ; PV_MU_ADDR_bf
#endm


/**
 * Packet NBI metadata format:
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-----------+-------------------+---+---------------------------+
 *    0  |CTM Number |  Packet Number    |BLS|     Packet Length         |
 *       +-+---+-----+-------------------+---+---------------------------+
 *    1  |S|Rsv|           MU Buffer Address [39:11]                     |
 *       +-+---+---------------------------------------------------------+
 */
.reg volatile write $_pv_prepend_short[3]
.reg volatile write $_pv_prepend_long[5]
.xfer_order $_pv_prepend_short $_pv_prepend_long
.addr $_pv_prepend_short[0] 48
move($_pv_prepend_short[1], 0x04142434)
move($_pv_prepend_long[1], 0x04142434)
move($_pv_prepend_long[2], 0x44546474)
move($_pv_prepend_long[3], 0)
#macro pv_write_nbi_meta(out_pms_offset, in_vec, FAIL_LABEL)
.begin
    .reg ctm_addr
    .reg delta
    .reg max_pms_addr
    .reg offsets
    .reg script
    .reg shift
    .reg table

    .reg write $nbi_meta[2]
    .xfer_order $nbi_meta
    .sig sig_wr_nbi_meta

    .reg read $tmp
    .sig sig_rd_prepend
    .sig sig_wr_prepend

    // write NBI metadata to base of packet buffer (offset zero)
    pv_get_ctm_base(ctm_addr, in_vec)
    alu[$nbi_meta[0], BF_A(in_vec, PV_NUMBER_bf), OR, __ISLAND, <<26] ; PV_NUMBER_bf
    alu[$nbi_meta[1], BF_A(in_vec, PV_MU_ADDR_bf), AND~, 0x3, <<29] ; PV_MU_ADDR_bf
    mem[write32, $nbi_meta[0], ctm_addr, <<8, 0, 2], sig_done[sig_wr_nbi_meta]

    /* Lookup legal packet modifier script offset in 32-bit table
     * Packet Offset | PMS Offset | Delete Delta (max_pms_addr - pms_offset)
     * --------------+------------+-----------------------------------------
     * [0;43]        | 120        | (illegal)
     * [44;75]       | 32         | [0;31]
     * [76;107]      | 56         | [8;39]
     * [108;139]     | 96         | [0;31]
     * [140;248]     | 120        | [8;116]
     * (table stored as the >>4 shifted inverse to fit non-zeroes into an immed[] instruction)
     */
    immed[table, ((~((120 << 28) | (120 << 24) | (120 << 20) | (120 << 16) | \
                  (96 << 12) | (56 << 8) | (32 << 4) | 120) >> 4) & 0xffff)]
    alu[max_pms_addr, BF_A(in_vec, PV_OFFSET_bf), -, 12] // room for 8 byte PMS + 4 byte MAC prepend
    alu[shift, 0x1c, AND, max_pms_addr, >>3]
    alu[table, shift, B, table, <<4] // undo shift
    alu[out_pms_offset, 0x78, AND~, table, >>indirect] // invert result

    alu[delta, max_pms_addr, -, pms_offset] // interpret delta as bottom 16 bits
    br_bset[delta, 15, illegal_offset#] // delta (16 bits) is negative for offsets < 44

    alu[offsets, delta, +, (128 + 64 + 15)] // note (128 + 64 + 15) == (255 - 48)
    br!=byte[offsets, 1, 0, more_offsets#] // max delete script is 48

    alu[script, 0x3, AND, offsets, >>4] // offset_len = ((delta + 15) / 16) % 4
    alu[script, (1 << 6), OR, script, <<24] // rdata_loc = 1

less_offsets#:
    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    mem[write32, $_pv_prepend_short[0], ctm_addr, <<8, out_pms_offset, 3], sig_done[sig_wr_prepend]
    #pragma warning(default:4700)
    mem[read32, $tmp, ctm_addr, <<8, out_pms_offset, 1], sig_done[sig_rd_prepend]
    ctx_arb[sig_wr_nbi_meta, sig_wr_prepend, sig_rd_prepend], br[end#], defer[2]
        alu[$_pv_prepend_short[0], script, OR, delta, <<16] // opcode index
        alu[$_pv_prepend_short[2], --, B, BF_A(in_vec, PV_CSUM_OFFLOAD_bf), <<30] // mac prepend
    #pragma warning(default:5009)

more_offsets#:
    alu[delta, delta, -, 8]
    alu[offsets, delta, +, (128 + 15)] // note (128 + 15) == (255 - 112)
    br!=byte[offsets, 1, 0, illegal_offset#] // max delete script is 112

    alu[script, 0x7, AND, offsets, >>4] // offset_len = ((delta + 15) / 16)
    br=byte[script, 0, 3, less_offsets#], defer[1]
        alu[script, (1 << 6), OR, script, <<24] // rdata_loc = 1

    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    mem[write32, $_pv_prepend_long[0], ctm_addr, <<8, pms_offset, 5], sig_done[sig_wr_prepend]
    #pragma warning(default:4700)
    mem[read32, $tmp, ctm_addr, <<8, pms_offset, 1], sig_done[sig_rd_prepend]
    ctx_arb[sig_wr_nbi_meta, sig_wr_prepend, sig_rd_prepend], br[end#], defer[2]
        alu[$_pv_prepend_long[0], script, OR, delta, <<16]
        alu[$_pv_prepend_long[4], --, B, BF_A(in_vec, PV_CSUM_OFFLOAD_bf), <<30] // mac prepend
    #pragma warning(default:5009)

illegal_offset#:
    ctx_arb[sig_wr_nbi_meta], br[FAIL_LABEL]

end#:
.end
#endm


#macro pv_get_seq_ctx(out_seq_ctx, in_vec)
    bitfield_extract__sz1(out_seq_ctx, BF_AML(in_vec, PV_SEQ_CTX_bf)) ; PV_SEQ_CTX_bf
#endm

#macro __pv_get_mac_dst_type(out_type, io_vec)
.begin
    .reg tmp
    passert(BF_L(PV_MAC_DST_MC_bf), "EQ", (BF_M(PV_MAC_DST_BC_bf) + 1))
    alu[out_type, (1 << 1), AND, *$index, >>(BF_L(MAC_MULTICAST_bf) - 1)] // bit 1 is set if multicast
    alu[tmp, 1, +16, *$index++]
    alu[tmp, --, B, tmp, >>16]
    alu[--, *$index++, +, tmp] // carry is set if broadcast
    alu[out_type, out_type, +carry, 0] // bit 0 is set if broadcast
.end
#endm


#macro pv_get_seq_no(out_seq_no, in_vec)
    bitfield_extract__sz1(out_seq_no, BF_AML(in_vec, PV_SEQ_NO_bf)) ; PV_SEQ_NO_bf
#endm

/**
 * Packet Metadata and MAC Prepend with Catamaran Pico Engine load (see Catamaran IDD):
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-----------+-------------------+---+---------------------------+
 *    0  | CTM Number| Packet Number     |BLS|     Packet Length         |
 *       +-+---+-----+-------------------+---+---------------------------+
 *    1  |S|Rsv|                   MU Pointer                            |
 *       +-+---+-------------------------+---+-----+-----+-+-----+-+-----+
 *    2  |      Sequence Number          |NFP|  R  | Seq |P|MType|V| BP  |
 *       +-------------------------+-+---+---+---+-+-----+-+-----+-+-----+
 *    3  |        Reserved         |E|TLD|  OL4  |  OL3  |   OL2   |  R  |
 *       +---------------+---------+-+---+---+---+-------+---------+-----+
 *    4  |     Port      |    HP-Off1    |    HP-Off0    |F|   Misc      |
 *       +-+-+-+-+-+-+-+-+---------------+---------------+---------------+
 *    5  |P|I|P|S|Tag|I|T|     O-Off     |       LIF+Mode / Match        |
 *       |E|E|W|p|Cnt|T|S|               |                               |
 *       +-+-+-+-+-+-+-+-+---------------+-------------------------------+
 *    6  |                           Timestamp                           |
 *       +-----+-+-+-+-+-+-+-+-------------------------------------------+
 *    7  |P_STS|M|E|A|F|D|R|H|L3 |MPL|VLN|           Checksum            | (not currently maintained)
 *       +-----+-+-+-+-+-+-+-+-------------------------------------------+
 *      S -> 1 if packet is split between CTM and MU data
 *      BLS -> Buffer List
 *
 * P_STS - Parse Status
 *         (0 = no data,
 *          1 = ESP,
 *          2 = TCP CSUM OK,
 *          3 = TCP CSUM FAIL,
 *          4 = UDP CSUM OK,
 *          5 = UDP CSUM FAIL,
 *          6 = AH,
 *          7 = FRAG)
 *
 * L3    - MAC L3 Information (0 = unkown, 1 = IPv6, 2 = IPv4 CSUM FAIL, 3 = IPv4 OK)
 * MPL   - MPLS Tag Depth (3 = 3 or more)
 * VLN   - VLAN Tag Depth (3 = 3 or more)
 */

#define CAT_PKT_NUM_wrd                 0
#define CAT_CTM_NUM_bf                  CAT_PKT_NUM_wrd, 31, 26
#define CAT_PKT_NUM_bf                  CAT_PKT_NUM_wrd, 25, 16
#define CAT_BLS_bf                      CAT_PKT_NUM_wrd, 15, 14
#define CAT_PKT_LEN_bf                  CAT_PKT_NUM_wrd, 13, 0

#define CAT_MUPTR_wrd                   1
#define CAT_SPLIT_bf                    CAT_MUPTR_wrd, 31, 31
#define CAT_MUPTR_bf                    CAT_MUPTR_wrd, 28, 0

#define CAT_SEQ_wrd                     2
#define CAT_SEQ_NO_bf                   CAT_SEQ_wrd, 31, 16
#define CAT_SEQ_CTX_bf                  CAT_SEQ_wrd, 10, 8
#define CAT_PROTO_ERROR_bf              CAT_SEQ_wrd, 7, 7 // packet error will also be set
#define CAT_MTYPE_bf                    CAT_SEQ_wrd, 6, 4 // metadata type - 0 for NBI 0, 1 for NBI 1, 2-7 undefined
#define CAT_VALID_bf                    CAT_SEQ_wrd, 3, 3

#define CAT_PROTO_wrd                   3
#define CAT_ETERM_bf                    CAT_PROTO_wrd, 18, 18 // early termination
#define CAT_L4_CLASS_bf                 CAT_PROTO_wrd, 15, 12 // 2 = UDP, 3 = TCP
#define CAT_L4_TYPE_bf                  CAT_PROTO_wrd, 13, 12
#define CAT_L3_CLASS_bf                 CAT_PROTO_wrd, 11, 8 // (L3_TYPE & 0xd) => 4 = IPv4, 5 = IPv6
#define CAT_L3_TYPE_bf                  CAT_PROTO_wrd, 11, 10
#define CAT_L3_IP_VER_bf                CAT_PROTO_wrd, 8, 8

#define CAT_L3_TYPE_UNKNOWN             0
#define CAT_L3_TYPE_IP                  1
#define CAT_L3_TYPE_MPLS                2

#define CAT_PORT_wrd                    4
#define CAT_PORT_bf                     CAT_PORT_wrd, 31, 24
#define CAT_L4_OFFSET_bf                CAT_PORT_wrd, 15, 8
#define CAT_V4_FRAG_bf                  CAT_PORT_wrd, 7, 7

#define CAT_FLAGS_wrd                   5
#define CAT_ERRORS_bf                   CAT_FLAGS_wrd, 31, 30
#define CAT_PKT_ERROR_bf                CAT_FLAGS_wrd, 31, 31
#define CAT_IFACE_ERROR_bf              CAT_FLAGS_wrd, 30, 30
#define CAT_PKT_WARN_bf                 CAT_FLAGS_wrd, 29, 29 // IPv4 CSUM err, local src, multicast src, class E, TTL=0, IPv6 HL=0/1
#define CAT_SPECIAL_bf                  CAT_FLAGS_wrd, 28, 28 // IPv6 hop-by-hop, MPLS OAM
#define CAT_VLANS_bf                    CAT_FLAGS_wrd, 27, 26
#define CAT_L3_OFFSET_bf                CAT_FLAGS_wrd, 23, 16

#define MAC_TIMESTAMP_wrd               6
#define MAC_TIMESTAMP_bf                MAC_TIMESTAMP_wrd, 31, 0

#define MAC_PARSE_wrd                   7
#define MAC_PARSE_STS_bf                MAC_PARSE_wrd, 31, 29
#define MAC_PARSE_V6_OPT_bf             MAC_PARSE_wrd, 28, 22
#define MAC_PARSE_V6_FRAG_bf            MAC_PARSE_wrd, 25, 25
#define MAC_PARSE_L3_bf                 MAC_PARSE_wrd, 21, 20
#define MAC_PARSE_MPLS_bf               MAC_PARSE_wrd, 19, 18
#define MAC_PARSE_VLAN_bf               MAC_PARSE_wrd, 17, 16
#define MAC_CSUM_bf                     MAC_PARSE_wrd, 15, 0

#macro pv_init_nbi(out_vec, in_nbi_desc, in_mtu, in_tunnel_args, DROP_MTU_LABEL, DROP_PROTO_LABEL, ERROR_PARSE_LABEL)
.begin
    .reg cbs
    .reg dst_mac_bc
    .reg not_frag
    .reg ip_ver
    .reg l3_csum_tbl
    .reg l3_flags
    .reg l3_offset
    .reg l3_type
    .reg l4_csum_tbl
    .reg l4_flags
    .reg l4_type
    .reg l4_offset
    .reg mac_dst_type
    .reg shift
    .reg tunnel
    .reg vlan_len
    .reg vlan_id

    alu[BF_A(out_vec, PV_LENGTH_bf), BF_A(in_nbi_desc, CAT_CTM_NUM_bf), AND~, BF_MASK(CAT_CTM_NUM_bf), <<BF_L(CAT_CTM_NUM_bf)]
    alu[BF_A(out_vec, PV_LENGTH_bf), BF_A(out_vec, PV_LENGTH_bf), -, MAC_PREPEND_BYTES]

    /* Using packet status (for CTM buffer size) to set up PV_MU_ADDR_wrd would require 7
     * cycles (vs the 8 or 9 required to derive CBS from the packet length):
     *
     * bitfield_extract(pkt_num, BF_AML(in_nbi_desc, CAT_PKT_NUM_bf)) // 2 cycles
     * mem[packet_read_packet_status, $status[0], 0, <<8, pkt_num, 1], ctx_swap[sig_status]
     * .if_unlikely(BIT($status[0], 31)) // one cycle in fast path
     *     // back off and retry
     * .endif
     * alu[cbs, 3, AND, $status[0], >>16]
     * alu[BF_A(io_vec, PV_MU_ADDR_bf), BF_A(in_nbi_desc, CAT_MUPTR_bf), AND~, 0x3, <<BF_L(PV_CBS_bf)]
     * alu[BF_A(io_vec, PV_MU_ADDR_bf), BF_A(io_vec, PV_MU_ADDR_bf), OR, cbs, <<BF_L(PV_CBS_bf)]
     *
     * It seems prudent to spend the additional 2 cycles (sadly for smaller packets) to
     * spare the per packet CTM accesses. This decision should be revisited if the need
     * for the absolute address (also part of packet status) ever arises for NBI packets.
     */
    alu[cbs, BF_A(out_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] // must mask out BLS before add
    alu[cbs, (PKT_NBI_OFFSET + MAC_PREPEND_BYTES - 1), +16, cbs] ; PV_LENGTH_bf
    alu[--, --, B, cbs, >>10]
    bne[max_cbs#], defer[3]
        alu[BF_A(out_vec, PV_MU_ADDR_bf), BF_A(in_nbi_desc, CAT_MUPTR_bf), AND~, 0x3, <<BF_L(PV_CBS_bf)]
        alu[shift, (3 << 1), AND, cbs, >>(8 - 1)]
        alu[cbs, shift, B, 3]
    alu[cbs, cbs, AND, ((2 << 6) | (2 << 4) | (1 << 2) | (0 << 0)), >>indirect]
max_cbs#:
    alu[BF_A(out_vec, PV_MU_ADDR_bf), BF_A(out_vec, PV_MU_ADDR_bf), OR, cbs, <<BF_L(PV_CBS_bf)]

    // set TX host flags
    immed[l4_csum_tbl, 0x238c, <<8]
    alu[shift, (7 << 2), AND, BF_A(in_nbi_desc, MAC_PARSE_STS_bf), >>(BF_L(MAC_PARSE_STS_bf) - 2)] ; MAC_PARSE_STS_bf
    alu[l3_csum_tbl, shift, B, 0xe0]
    alu[l4_flags, 0xf, AND, l4_csum_tbl, >>indirect]
    alu[shift, (3 << 1), AND, BF_A(in_nbi_desc, MAC_PARSE_L3_bf), >>(BF_L(MAC_PARSE_L3_bf) - 1)] ; MAC_PARSE_L3_bf
    alu[BF_A(out_vec, PV_TX_HOST_L4_bf), shift, B, l4_flags, <<BF_L(PV_TX_HOST_L4_bf)] ; PV_TX_HOST_L4_bf
    alu[l3_flags, 0x3, AND, l3_csum_tbl, >>indirect]
    alu[BF_A(out_vec, PV_TX_HOST_L3_bf), BF_A(out_vec, PV_TX_HOST_L3_bf), OR, l3_flags, <<BF_L(PV_TX_HOST_L3_bf)] ; PV_TX_HOST_L3_bf

    alu[BF_A(out_vec, PV_CTM_ADDR_bf), BF_A(out_vec, PV_NUMBER_bf), OR, 1, <<BF_L(PV_CTM_ALLOCATED_bf)]
    ld_field[BF_A(out_vec, PV_CTM_ADDR_bf), 0011, (PKT_NBI_OFFSET + MAC_PREPEND_BYTES)]

    pv_seek(out_vec, 0, (PV_SEEK_INIT | PV_SEEK_CTM_ONLY), skip_hdr_parse#)

hdr_parse#:
    pv_hdr_parse(out_vec, in_tunnel_args, finalize#)

skip_hdr_parse#:
    __pv_get_mac_dst_type(mac_dst_type, out_vec) // advances *$index by 2 words
    alu[out_vec[PV_FLAGS_wrd], *$index++, B, 0]
    alu[vlan_len, (3 << 2), AND, BF_A(in_nbi_desc, MAC_PARSE_VLAN_bf), >>(BF_L(MAC_PARSE_VLAN_bf) - 2)]
    beq[skip_vlan#], defer[3]
        bits_set__sz1(BF_AL(out_vec, PV_MAC_DST_TYPE_bf), mac_dst_type)
        alu[vlan_id, *$index++, B, 1, <<12]
        alu[BF_A(out_vec, PV_VLAN_ID_bf), vlan_id, -, 1] ; PV_VLAN_ID_bf

    alu[vlan_id, --, B, *$index, >>16]
    alu[BF_A(out_vec, PV_VLAN_ID_bf), BF_A(out_vec, PV_VLAN_ID_bf), AND, vlan_id]

skip_vlan#:
    bitfield_extract__sz1(l3_type, BF_AML(in_nbi_desc, CAT_L3_CLASS_bf)) ; CAT_L3_CLASS_bf
    br!=byte[l3_type, 0, 4, hdr_parse#], defer[3] // if packet is not IPv4 perform parse
        alu[BF_A(out_vec, PV_META_TYPES_bf), *$index--, B, 0]
        // map NBI sequencers to 0, 1, 2, 3
        alu[BF_A(out_vec, PV_SEQ_NO_bf), BF_A(in_nbi_desc, CAT_SEQ_NO_bf), OR, 0xff] ; PV_SEQ_NO_bf
        alu[BF_A(out_vec, PV_SEQ_CTX_bf), BF_A(out_vec, PV_SEQ_CTX_bf), AND~, 0xfc, <<8] ; PV_SEQ_CTX_bf

    // handle fragments
    alu[not_frag, 1, AND~, BF_A(in_nbi_desc, CAT_V4_FRAG_bf), >>BF_L(CAT_V4_FRAG_bf)] ; CAT_V4_FRAG_bf
    alu[not_frag, not_frag, AND~, BF_A(in_nbi_desc, MAC_PARSE_V6_FRAG_bf), >>BF_L(MAC_PARSE_V6_FRAG_bf)] ; MAC_PARSE_V6_FRAG_bf
    beq[store_l3_off#]
    alu[l4_type, 0xe, AND, BF_A(in_nbi_desc, CAT_L4_CLASS_bf), >>BF_L(CAT_L4_CLASS_bf)] ; CAT_L4_CLASS_bf
    br!=byte[l4_type, 0, 2, hdr_parse#] // if packet is not TCP/UDP perform parse

    br_bset[in_tunnel_args, BF_L(INSTR_RX_PARSE_NVGRE_bf), hdr_parse#]

    // check for possibility of UDP tunnels
    alu[tunnel, in_tunnel_args, AND, ((BF_MASK(INSTR_RX_PARSE_VXLANS_bf) << BF_L(INSTR_RX_PARSE_VXLANS_bf)) | (1 << BF_L(INSTR_RX_PARSE_GENEVE_bf)))]
    alu[--, 0, -, tunnel]
    alu[tunnel, tunnel, AND~, BF_A(in_nbi_desc, CAT_L4_CLASS_bf)]
    br_bset[tunnel, BF_L(CAT_L4_CLASS_bf), hdr_parse#]

    // store L3 offset
store_l3_off#:
    bitfield_extract__sz1(l3_offset, BF_AML(in_nbi_desc, CAT_L3_OFFSET_bf)) ; CAT_L3_OFFSET_bf
    alu[l3_offset, l3_offset, -, MAC_PREPEND_BYTES]
    alu[BF_A(out_vec, PV_HEADER_STACK_bf), --, B, l3_offset, <<8]
    alu[BF_A(out_vec, PV_HEADER_STACK_bf), BF_A(out_vec, PV_HEADER_STACK_bf), OR, l3_offset, <<24]

    alu[--, --, B, not_frag]
    beq[finalize#], defer[3] // skip L4 for fragments
        alu[BF_A(out_vec, PV_PROTO_bf), BF_A(out_vec, PV_PROTO_bf), AND~, not_frag]
        alu[ip_ver, 0x7c, OR, BF_A(in_nbi_desc, CAT_L3_IP_VER_bf), >>BF_L(CAT_L3_IP_VER_bf)] ; CAT_L3_IP_VER_bf
        alu[BF_A(out_vec, PV_PROTO_bf), BF_A(out_vec, PV_PROTO_bf), AND~, ip_ver, <<1] ; PV_PROTO_bf

    alu[l4_type, 1, AND~, BF_A(in_nbi_desc, MAC_PARSE_STS_bf), >>(BF_L(MAC_PARSE_STS_bf) + 1)]
    alu[BF_A(out_vec, PV_PROTO_bf), BF_A(out_vec, PV_PROTO_bf), OR, l4_type]
    alu[BF_A(out_vec, PV_PROTO_bf), BF_A(out_vec, PV_PROTO_bf), AND~, 1, <<2] // L4 is known

    // store L4 offset
    bitfield_extract__sz1(l4_offset, BF_AML(in_nbi_desc, CAT_L4_OFFSET_bf)) ; CAT_L4_OFFSET_bf
    alu[l4_offset, l4_offset, -, MAC_PREPEND_BYTES]
    alu[BF_A(out_vec, PV_HEADER_STACK_bf), BF_A(out_vec, PV_HEADER_STACK_bf), OR, l4_offset]
    alu[BF_A(out_vec, PV_HEADER_STACK_bf), BF_A(out_vec, PV_HEADER_STACK_bf), OR, l4_offset, <<16]

finalize#:
    // error checks after metadata is populated (will need for drop)
    #ifdef PARANOIA // should never happen, Catamaran is buggy if it does
       br_bset[BF_AL(in_nbi_desc, CAT_VALID_bf), valid#] ; CAT_VALID_bf
           fatal_error("INVALID CATAMARAN METADATA") // fatal error, can't safely drop without valid sequencer info
       valid#:
    #endif

    __pv_mtu_check(out_vec, in_mtu, vlan_len, DROP_MTU_LABEL)

    bitfield_extract__sz1(--, BF_AML(in_nbi_desc, CAT_SEQ_CTX_bf)) ; CAT_SEQ_CTX_bf
    beq[DROP_PROTO_LABEL] // drop without releasing sequence number for sequencer zero (errored packets are expected here)

    bitfield_extract__sz1(--, BF_AML(in_nbi_desc, CAT_ERRORS_bf)) ; CAT_ERRORS_bf
    bne[ERROR_PARSE_LABEL] // catch any other errors we miss (these appear to have valid sequence numbers)

.end
#endm


#macro __pv_lso_fixup(io_vec, in_nfd_desc)
.begin
    .reg $ip
    .sig sig_read_ip
    .sig sig_write_ip

    .reg read $tcp_hdr[4]
    .xfer_order $tcp_hdr
    .sig sig_read_tcp

    .reg write $tcp_seq
    .sig sig_write_tcp_seq
    .reg write $tcp_flags
    .sig sig_write_tcp_flags

    .reg ip_id
    .reg ip_len
    .reg l3_off
    .reg l4_off
    .reg lso_seq
    .reg mss
    .reg tcp_seq_add
    .reg tcp_flags_mask, tcp_flags_wrd
    .reg tmp

    bitfield_extract__sz1(l4_off, BF_AML(in_nfd_desc, NFD_IN_LSO2_L4_OFFS_fld)) ; NFD_IN_LSO2_L4_OFFS_fld
    mem[read32, $tcp_hdr[0], BF_A(io_vec, PV_CTM_ADDR_bf), l4_off, 4], ctx_swap[sig_read_tcp], defer[2]
        alu[mss, --, B, BF_A(in_nfd_desc, NFD_IN_LSO_MSS_fld), <<(31 - BF_M(NFD_IN_LSO_MSS_fld))]; NFD_IN_LSO_MSS_fld
        alu[mss, --, B, mss, >>(31 - BF_M(NFD_IN_LSO_MSS_fld))]; NFD_IN_LSO_MSS_fld

    bitfield_extract__sz1(lso_seq, BF_AML(in_nfd_desc, NFD_IN_LSO_SEQ_CNT_fld))
    alu[lso_seq, lso_seq, -, 1]

    /* TCP_SEQ_bf += (mss * (lso_seq - 1)) */
    multiply32(tcp_seq_add, mss, lso_seq, OP_SIZE_8X24) // multiplier is 8 bits, multiplicand is 24 bits (8x24)
    alu[$tcp_seq, BF_A($tcp_hdr, TCP_SEQ_bf), +, tcp_seq_add]

    alu[l4_off, l4_off, +, TCP_SEQ_OFFS]
    mem[write32, $tcp_seq, BF_A(io_vec, PV_CTM_ADDR_bf), l4_off, 1], sig_done[sig_write_tcp_seq]

    /*   .if (BIT(in_nfd_lso_wrd, BF_L(NFD_IN_LSO_END_fld)))
     *       tcp_flags_mask = 0xffffffff
     *   .else
     *       tcp_flags_mask = ~(NET_TCP_FLAG_FIN | NET_TCP_FLAG_RST | NET_TCP_FLAG_PSH)
     *   .endif
     *   TCP_FLAGS_bf = TCP_FLAGS_bf & tcp_flags_mask
     *
     *   TCP stores data offset and flags and in the same 16 bit word
     *   Flags are bits 8 to 0. Set to all F's to preserve upper bits
     */
    br_bset[BF_AL(in_nfd_desc, NFD_IN_LSO_END_fld), tcp_flags_fix_done#], defer[2]
        bitfield_extract__sz1(l3_off, BF_AML(in_nfd_desc, NFD_IN_LSO2_L3_OFFS_fld)) ; NFD_IN_LSO2_L3_OFFS_fld
        alu[tcp_flags_mask, --, ~B, 0]

    alu[tcp_flags_mask, tcp_flags_mask, AND~, (NET_TCP_FLAG_FIN | NET_TCP_FLAG_RST | NET_TCP_FLAG_PSH), <<16]

tcp_flags_fix_done#:
    alu[$tcp_flags, BF_A($tcp_hdr, TCP_FLAGS_bf), AND, tcp_flags_mask]
    alu[l4_off, l4_off, +, (TCP_FLAGS_OFFS - TCP_SEQ_OFFS)]
    mem[write8, $tcp_flags, BF_A(io_vec, PV_CTM_ADDR_bf), l4_off, 2], sig_done[sig_write_tcp_flags]

    br_bclr[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_IPV4_CSUM_fld), ipv6#], defer[3]
        /* IP length = pkt_len - l3_off */
        alu[ip_len, BF_A(io_vec, PV_LENGTH_bf), -, l3_off]
        alu[ip_len, ip_len, AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)]
        alu[ip_len, 0, B, ip_len, <<16]

ipv4#:
    alu[l3_off, l3_off, +, IPV4_LEN_OFFS]
    mem[read32, $ip, BF_A(io_vec, PV_CTM_ADDR_bf), l3_off, 1], ctx_swap[sig_read_ip]

    alu[ip_id, $ip, +, lso_seq]
    alu[$ip, ip_len, +16, ip_id]

    mem[write32, $ip, BF_A(io_vec, PV_CTM_ADDR_bf), l3_off, 1], sig_done[sig_write_ip]
    ctx_arb[sig_write_tcp_seq, sig_write_tcp_flags, sig_write_ip], br[end#]

ipv6#:
    alu[tmp, --, B, 40, <<16]
    alu[$ip, ip_len, -, tmp]
    alu[l3_off, l3_off, +, IPV6_PAYLOAD_OFFS]
    mem[write8, $ip, BF_A(io_vec, PV_CTM_ADDR_bf), l3_off, 2], sig_done[sig_write_ip]
    ctx_arb[sig_write_tcp_seq, sig_write_tcp_flags, sig_write_ip]

end#:
.end
#endm

/**
 * in_nfd_desc descriptor format (see nfd_in.uc)
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-+-------------+-------------------------------+---+-----------+
 *    0  |S|    offset   |         sequence number       |itf|   q_num   |
 *       +-+-+-+---------+-------------------------------+---+-----------+
 *    1  |I|J|S|                       buf_addr                          |
 *       +-+-+-+---------+---------------+-+-+---------------------------+
 *    2  |     flags     |   l4_offset   |L|S|           mss             |
 *       +---------------+---------------+-+-+---------------------------+
 *    3  |            data_len           |              vlan             |
 *       +-------------------------------+-------------------------------+
 *
 *       Flag bits (31-24) expanded:
 *          31       30      29      28      27      26      25     24
 *       +-------+-------+-------+-------+-------+-------+-------+-------+
 *    2  |TX_CSUM|IPV4_CS|TCP_CS |UDP_CS |TX_VLAN|TX_LSO |VXLAN  |GRE    |
 *       +-------+-------+-------+-------+-------+-------+-------+-------+
 *       This corresponds to nfp_net_pmd.h, TX descriptor format
 *       (lines 152-160).
 *
 *       31  TX_CSUM -> PCIE_DESC_TX_CSUM
 *       30  IPV4_CS -> PCIE_DESC_TX_IP4_CSUM
 *       29  TCP_CS  -> PCIE_DESC_TX_TCP_CSUM
 *       28  UDP_CS  -> PCIE_DESC_TX_UDP_CSUM
 *       27  TX_VLAN -> PCIE_DESC_TX_VLAN
 *       26  TX_LSO  -> PCIE_DESC_TX_LSO
 *       25  VXLAN   -> PCIE_DESC_TX_ENCAP_VXLAN
 *       24  GRE     -> PCIE_DESC_TX_ENCAP_GRE
 *
 *      S -> sp0 (spare)
 *    itf -> PCIe interface
 */

#define NFD_IN_LSO_L3_OFFS_fld      3, 7, 0
#define NFD_IN_LSO_L4_OFFS_fld      3, 15, 8


#macro pv_init_nfd(out_vec, in_pkt_num, in_nfd_desc, in_mtu, ERROR_MTU_LABEL, ERROR_PCI_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg mac_dst_type
    .reg meta_len
    .reg pcie
    .reg pkt_num
    .reg pkt_len
    .reg seq_ctx
    .reg seq_no
    .reg split
    .reg udp_csum

    bitfield_extract__sz1(pkt_len, BF_AML(in_nfd_desc, NFD_IN_DATALEN_fld)) ; NFD_IN_DATALEN_fld
    bitfield_extract__sz1(meta_len, BF_AML(in_nfd_desc, NFD_IN_OFFSET_fld)) ; NFD_IN_OFFSET_fld
    alu[pkt_len, pkt_len, -, meta_len]

    alu[BF_A(out_vec, PV_ORIG_LENGTH_bf), --, B, pkt_len] ; PV_ORIG_LENGTH_bf

    alu[BF_A(out_vec, PV_NUMBER_bf), pkt_len, OR, in_pkt_num, <<BF_L(PV_NUMBER_bf)]
    alu[BF_A(out_vec, PV_BLS_bf), BF_A(out_vec, PV_BLS_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    #if (NFD_IN_BLM_JUMBO_BLS == NFD_IN_BLM_REG_BLS)
        alu[BF_A(out_vec, PV_BLS_bf), BF_A(out_vec, PV_BLS_bf), OR, NFD_IN_BLM_REG_BLS, <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    #else
        .reg bls
        br_bset[BF_AL(in_nfd_desc, NFD_IN_JUMBO_fld), jumbo#], defer[1]
            immed[bls, NFD_IN_BLM_JUMBO_BLS]
        immed[bls, NFD_IN_BLM_REG_BLS]
    jumbo#:
        alu[BF_A(out_vec, PV_BLS_bf), BF_A(out_vec, PV_BLS_bf), OR, bls, <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    #endif

    // Assume CBS = 0
    alu[BF_A(out_vec, PV_MU_ADDR_bf), BF_A(in_nfd_desc, NFD_IN_BUFADDR_fld), AND~, 0x7, <<(BF_M(PV_MU_ADDR_bf) + 1)]
    alu[split, (256 - NFD_IN_DATA_OFFSET + 1), -, pkt_len]
    alu[split, split, +carry, pkt_len]
    alu[BF_A(out_vec, PV_SPLIT_bf), BF_A(out_vec, PV_SPLIT_bf), OR, split, <<BF_L(PV_SPLIT_bf)] ; PV_SPLIT_bf

    alu[BF_A(out_vec, PV_CTM_ADDR_bf), NFD_IN_DATA_OFFSET, OR, in_pkt_num, <<BF_L(PV_NUMBER_bf)]
    alu[BF_A(out_vec, PV_CTM_ADDR_bf), BF_A(out_vec, PV_CTM_ADDR_bf), OR, 1, <<BF_L(PV_CTM_ALLOCATED_bf)]

    // map NFD queues to sequencers starting at PV_GRO_NFD_START
    passert(BF_L(PV_SEQ_NO_bf), "EQ", BF_L(NFD_IN_SEQN_fld) + BF_L(PV_SEQ_CTX_bf))
    passert(BF_L(PV_SEQ_CTX_bf), "EQ", BF_L(NFD_IN_QID_fld) + BF_L(PV_SEQ_CTX_bf))
    passert(BF_W(PV_SEQ_NO_bf), "EQ", BF_W(PV_SEQ_CTX_bf))
    passert(BF_W(NFD_IN_SEQN_fld), "EQ", BF_W(NFD_IN_QID_fld))
    passert(BF_L(NFD_IN_QID_fld), "EQ", 0)
    passert(BF_L(PV_SEQ_NO_bf), "GT", BF_M(NFD_IN_QID_fld))
    passert(NFD_IN_NUM_SEQRS, "POWER_OF_2")
    alu[BF_A(out_vec, PV_SEQ_NO_bf), BF_A(in_nfd_desc, NFD_IN_QID_fld), AND~, (0x100 - NFD_IN_NUM_SEQRS)] ; PV_SEQ_NO_bf
    #ifdef PV_MULTI_PCI
        alu[pcie, 3, AND, BF_A(in_nfd_desc, NFD_IN_QID_fld), >>6]
        alu[BF_A(out_vec, PV_SEQ_CTX_bf), BF_A(out_vec, PV_SEQ_CTX_bf), OR, pcie, <<(log2(NFD_IN_NUM_SEQRS))]
    #endif
    alu[BF_A(out_vec, PV_SEQ_CTX_bf), BF_A(out_vec, PV_SEQ_CTX_bf), +, PV_GRO_NFD_START] ; PV_SEQ_CTX_bf
    alu[BF_A(out_vec, PV_SEQ_CTX_bf), 0xff, OR, BF_A(out_vec, PV_SEQ_CTX_bf), <<BF_L(PV_SEQ_CTX_bf)] ; PV_SEQ_CTX_bf

    alu[BF_A(out_vec, PV_CSUM_OFFLOAD_bf), BF_MASK(PV_CSUM_OFFLOAD_bf), AND, \
        BF_A(in_nfd_desc, NFD_IN_FLAGS_TX_TCP_CSUM_fld), >>BF_L(NFD_IN_FLAGS_TX_TCP_CSUM_fld)]
    bitfield_extract__sz1(udp_csum, BF_AML(in_nfd_desc, NFD_IN_FLAGS_TX_UDP_CSUM_fld)) ; NFD_IN_FLAGS_TX_UDP_CSUM_fld
    alu[BF_A(out_vec, PV_CSUM_OFFLOAD_bf), BF_A(out_vec, PV_CSUM_OFFLOAD_bf), OR, udp_csum] ; PV_CSUM_OFFLOAD_bf

    // error checks near end to ensure consistent metadata (fields written below excluded) and buffer allocation
    // state (contents of CTM also excluded) in drop path
    br_bset[BF_AL(in_nfd_desc, NFD_IN_INVALID_fld), ERROR_PCI_LABEL]

    __pv_mtu_check(out_vec, in_mtu, (4 * 3), ERROR_MTU_LABEL)

    pkt_buf_copy_mu_head_to_ctm(in_pkt_num, BF_A(out_vec, PV_MU_ADDR_bf), NFD_IN_DATA_OFFSET, 1)

    pv_seek(out_vec, 0, (PV_SEEK_INIT | PV_SEEK_CTM_ONLY))
    __pv_get_mac_dst_type(mac_dst_type, out_vec) // advances *$index by 2 words
    alu[BF_A(out_vec, PV_MAC_DST_TYPE_bf), BF_A(out_vec, PV_MAC_DST_TYPE_bf), OR, mac_dst_type, <<BF_L(PV_MAC_DST_TYPE_bf)]

    br_bclr[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_LSO_fld), skip_lso#], defer[3]
        immed[BF_A(out_vec, PV_HEADER_STACK_bf), 0]
        immed[BF_A(out_vec, PV_META_TYPES_bf), 0]
        bits_set__sz1(BF_AL(out_vec, PV_META_LENGTH_bf), meta_len) ; PV_META_LENGTH_bf

    __pv_lso_fixup(out_vec, in_nfd_desc)
skip_lso#:

.end
#endm


#macro pv_free_buffers(in_pkt_vec)
.begin
    .reg bls
    .reg mu_addr
    .reg pkt_num
    .reg $tmp
    .sig sig_read

    // ensure all CTM I/O is complete before free (assume code never writes to MU buffer)
    mem[read32, $tmp, BF_A(in_pkt_vec, PV_CTM_ADDR_bf), 0, 1], ctx_swap[sig_read], defer[2]
        bitfield_extract__sz1(bls, BF_AML(in_pkt_vec, PV_BLS_bf)) ; PV_BLS_bf
        alu[pkt_num, --, B, BF_A(in_pkt_vec, PV_NUMBER_bf), >>BF_L(PV_NUMBER_bf)] ; PV_NUMBER_bf

    bitfield_extract__sz1(mu_addr, BF_AML(in_pkt_vec, PV_MU_ADDR_bf)) ; PV_MU_ADDR_bf
    beq[skip_mu_buffer#]
    pkt_buf_free_mu_buffer(bls, mu_addr)
skip_mu_buffer#:

    br_bclr[BF_AL(in_pkt_vec, PV_CTM_ALLOCATED_bf), skip_ctm_buffer#]
    pkt_buf_free_ctm_buffer(--, pkt_num)
skip_ctm_buffer#:

.end
#endm


#macro pv_acquire_nfd_credit(in_pkt_vec, in_queue_base, FAIL_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo

    .reg read $nfd_credits
    .sig sig_nfd_credit

    alu[addr_hi, (NFD_PCIE_ISL_BASE | __NFD_DIRECT_ACCESS), OR, in_queue_base, >>6]
    alu[addr_hi, --, B, addr_hi, <<24]

    alu[addr_lo, in_queue_base, AND, 0x3f]
    alu[addr_lo, addr_lo, +8, BF_A(in_pkt_vec, PV_QUEUE_OFFSET_bf)]
    alu[addr_lo, --, B, addr_lo, <<(log2(NFD_OUT_ATOMICS_SZ))]

    ov_start(OV_IMMED8)
    ov_set_use(OV_IMMED8, 1)
    ov_clean()
    mem[test_subsat_imm, $nfd_credits, addr_hi, <<8, addr_lo, 1], indirect_ref, ctx_swap[sig_nfd_credit]

    alu[--, --, B, $nfd_credits]
    beq[FAIL_LABEL]

.end
#endm


#define PV_SEEK_ANY          (0)
#define PV_SEEK_CTM_ONLY     (1 << 0)
#define PV_SEEK_T_INDEX_ONLY (1 << 1)
#define PV_SEEK_PAD_INCLUDED (1 << 2)
#define PV_SEEK_REVERSE      (1 << 3)
#define PV_SEEK_INIT         (1 << 4)

.reg volatile read $__pv_pkt_data[32]
.addr $__pv_pkt_data[0] 0
.xfer_order $__pv_pkt_data
#macro pv_seek(out_cache_idx, io_vec, in_offset, in_length, in_flags, EXIT_LABEL)
.begin
    .reg tibi // T_INDEX_BYTE_INDEX
    .reg write $reflect

    #if ((in_flags & PV_SEEK_REVERSE) || (in_flags & PV_SEEK_T_INDEX_ONLY))
        #define _PV_SEEK_TEST_OFFSET_MASK 0x7f
        #define _PV_SEEK_READ_BASE_MASK 0x3f80
        #define _PV_SEEK_READ_OFFSET_MASK 0x7f
    #elif (! streq('in_length', '--'))
        #define _PV_SEEK_TEST_OFFSET_MASK 0x7f
        #define _PV_SEEK_READ_BASE_MASK 0x3fc0
        #define _PV_SEEK_READ_OFFSET_MASK 0x3f
    #else
        #define _PV_SEEK_TEST_OFFSET_MASK 0x3f
        #define _PV_SEEK_READ_BASE_MASK 0x3fc0
        #define _PV_SEEK_READ_OFFSET_MASK 0x3f
    #endif

    #if (isnum(in_offset))
        #define_eval _PV_SEEK_OFFSET in_offset
        #if (((in_flags & PV_SEEK_PAD_INCLUDED) == 0))
            #define_eval _PV_SEEK_OFFSET (_PV_SEEK_OFFSET + 2)
        #endif
        alu[tibi, t_idx_ctx, OR, (_PV_SEEK_OFFSET & _PV_SEEK_TEST_OFFSET_MASK)]
        #if (_PV_SEEK_OFFSET >= 256)
           .reg seek_offset
           immed[seek_offset, _PV_SEEK_OFFSET]
           #define_eval _PV_SEEK_OFFSET seek_offset
        #endif
    #else
        #define_eval _PV_SEEK_OFFSET in_offset
        #if (((in_flags & PV_SEEK_PAD_INCLUDED) == 0))
            .reg seek_offset
            alu[seek_offset, in_offset, +, 2]
            #define_eval _PV_SEEK_OFFSET seek_offset
        #endif
        alu[tibi, _PV_SEEK_OFFSET, AND, _PV_SEEK_TEST_OFFSET_MASK]
        alu[tibi, tibi, OR, t_idx_ctx]
    #endif

#if (((in_flags) & PV_SEEK_T_INDEX_ONLY) != 0)
    local_csr_wr[T_INDEX_BYTE_INDEX, tibi]
#if (! streq('EXIT_LABEL', '--'))
    br[EXIT_LABEL], defer[2]
#else
    nop
#endif
    #if (! streq('out_cache_idx', '--'))
        alu[out_cache_idx, 0x1f, AND, tibi, >>2]
    #else
        nop
    #endif
    nop
#else
    .reg outside
    .reg aligned_offset
    .reg read_offset
    .sig sig_ctm

    #if (! streq('out_cache_idx', '--'))
        alu[out_cache_idx, 0x1f, AND, tibi, >>2]
    #endif
#if ((in_flags & PV_SEEK_INIT) == 0)
#if (streq('EXIT_LABEL', '--'))
    br[check#], defer[2]
#endif
        local_csr_wr[T_INDEX_BYTE_INDEX, tibi]
        alu[outside, BF_A(io_vec, PV_SEEK_BASE_bf), XOR, _PV_SEEK_OFFSET]
#endif

#if ((in_flags & PV_SEEK_INIT) == 0 && !streq('EXIT_LABEL', '--'))
    #if (streq('in_length', '--'))
        #if (((in_flags & PV_SEEK_REVERSE) == 0))
            alu[--, BF_MASK(PV_SEEK_BASE_bf), AND, outside, >>BF_L(PV_SEEK_BASE_bf)]
        #else
            alu[--, (BF_MASK(PV_SEEK_BASE_bf) >> 1), AND, outside, >>(BF_L(PV_SEEK_BASE_bf) + 1)]
        #endif
        beq[EXIT_LABEL]
    #else
        .reg boundary
        alu[--, (BF_MASK(PV_SEEK_BASE_bf) >> 1), AND, outside, >>(BF_L(PV_SEEK_BASE_bf) + 1)]
        bne[read#]
        #if (((in_flags & PV_SEEK_REVERSE) == 0))
            alu[boundary, _PV_SEEK_OFFSET, +, in_length]
        #else
            alu[boundary, _PV_SEEK_OFFSET, -, in_length]
        #endif
        alu[outside, BF_A(io_vec, PV_SEEK_BASE_bf), XOR, boundary]
        alu[--, (BF_MASK(PV_SEEK_BASE_bf) >> 1), AND, outside, >>(BF_L(PV_SEEK_BASE_bf) + 1)]
        beq[EXIT_LABEL]
    #endif
#endif // ((in_flags & PV_SEEK_INIT) == 0 && !streq('EXIT_LABEL', '--'))

read#:
    #if (((in_flags) & PV_SEEK_CTM_ONLY) == 0)
        br_bset[BF_AL(io_vec, PV_SPLIT_bf), split#], defer[2]
    #endif
            #if (isnum(_PV_SEEK_OFFSET))
                immed[aligned_offset, (_PV_SEEK_OFFSET & _PV_SEEK_READ_BASE_MASK)]
            #else
                alu[aligned_offset, _PV_SEEK_OFFSET, AND~, _PV_SEEK_READ_OFFSET_MASK]
            #endif
            alu[read_offset, aligned_offset, -, 2]

read_ctm#:
    ov_single(OV_LENGTH, 32, OVF_SUBTRACT_ONE)
    mem[read32, $__pv_pkt_data[0], BF_A(io_vec, PV_CTM_ADDR_bf), read_offset, max_32], indirect_ref, defer[2], ctx_swap[sig_ctm]
        #if (isnum(_PV_SEEK_OFFSET))
            immed[tibi, (_PV_SEEK_OFFSET & _PV_SEEK_READ_OFFSET_MASK)]
        #else
            alu[tibi, _PV_SEEK_OFFSET, AND, _PV_SEEK_READ_OFFSET_MASK]
        #endif
        alu[tibi, tibi, OR, t_idx_ctx]

finalize#:
    local_csr_wr[T_INDEX_BYTE_INDEX, tibi] // reload T_INDEX after ctx_swap[]
#if (streq('EXIT_LABEL', '--'))
    br[end#], defer[2]
#else
    br[EXIT_LABEL], defer[2]
#endif
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), AND~, BF_MASK(PV_SEEK_BASE_bf), <<BF_L(PV_SEEK_BASE_bf)]
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), OR, aligned_offset]

    #if (((in_flags) & PV_SEEK_CTM_ONLY) == 0)
        .reg buffer_offset
        .reg cbs
        .reg ctm_bytes
        .reg ctm_words
        .reg data_ref
        .reg mask
        .reg mu_addr
        .reg mu_words
        .reg split_offset
        .reg straddle_data
        .reg reflect_addr
        .reg tmp
        .sig sig_mu
        .sig sig_reflect

    split#:
        // determine the split offset based on CTM buffer size
        bitfield_extract__sz1(cbs, BF_AML(io_vec, PV_CBS_bf))
        alu[split_offset, cbs, B, 1, <<8]
        alu[split_offset, --, B, split_offset, <<indirect]

        alu[buffer_offset, read_offset, +16, BF_A(io_vec, PV_OFFSET_bf)]
        alu[ctm_bytes, split_offset, -, buffer_offset]
        ble[read_mu#]

        alu[--, 128, -, ctm_bytes]
        ble[read_ctm#]

    read_straddled#:
        alu[ctm_words, --, B, ctm_bytes, >>2]
        ov_single(OV_LENGTH, ctm_words) // read one additional word
        mem[read32, $__pv_pkt_data[0], BF_A(io_vec, PV_CTM_ADDR_bf), read_offset, max_32], indirect_ref, ctx_swap[sig_ctm], defer[2]
            alu[read_offset, split_offset, -, 2]
            alu[data_ref, t_idx_ctx, +, ctm_bytes]

        local_csr_wr[T_INDEX, data_ref]
        alu[mu_addr, --, B, BF_A(io_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]
        alu[mu_words, (32 - 1), -, ctm_words] // subtract one for OV_LENGTH

        ov_start((OV_DATA_REF | OV_LENGTH))
        ov_set(OV_DATA_REF, data_ref)
        ov_set_use(OV_LENGTH, mu_words)
        ov_clean()
        mem[read32, $__pv_pkt_data[0], mu_addr, <<8, read_offset, max_32], indirect_ref, ctx_swap[sig_mu], defer[2]
            immed[mask, 0xffff]
            alu[straddle_data, *$index, AND~, mask]

        local_csr_wr[T_INDEX, data_ref]
        #if (SCS != 0)
            #error calculation of reflect_addr depends on __MEID
        #endif
        immed[reflect_addr, ((&$reflect << 2) | ((__MEID & 0xf) << 10))]
        alu[reflect_addr, reflect_addr, OR, __ISLAND, <<24]
        ov_single(OV_DATA_REF, data_ref)
        ct[reflect_read_sig_init, $__pv_pkt_data[0], t_idx_ctx, reflect_addr, 1], indirect_ref, ctx_swap[sig_reflect], defer[2]
            alu[tmp, *$index, AND, mask]
            alu[$reflect, tmp, OR, straddle_data]

        br[finalize#], defer[2]
            #if (isnum(_PV_SEEK_OFFSET))
                immed[tibi, (_PV_SEEK_OFFSET & _PV_SEEK_READ_OFFSET_MASK)]
            #else
                alu[tibi, _PV_SEEK_OFFSET, AND, _PV_SEEK_READ_OFFSET_MASK]
            #endif
            alu[tibi, tibi, OR, t_idx_ctx]

    read_mu#:
        alu[mu_addr, --, B, BF_A(io_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]
        alu[read_offset, read_offset, +16, BF_A(io_vec, PV_OFFSET_bf)]
        ov_single(OV_LENGTH, 32, OVF_SUBTRACT_ONE)
        mem[read32, $__pv_pkt_data[0], mu_addr, <<8, read_offset, max_32], indirect_ref, sig_done[sig_mu]
        ctx_arb[sig_mu], br[finalize#], defer[2]
            #if (isnum(_PV_SEEK_OFFSET))
                immed[tibi, (_PV_SEEK_OFFSET & _PV_SEEK_READ_OFFSET_MASK)]
            #else
                alu[tibi, _PV_SEEK_OFFSET, AND, _PV_SEEK_READ_OFFSET_MASK]
            #endif
            alu[tibi, tibi, OR, t_idx_ctx]

    #endif // ((in_flags) & PV_SEEK_CTM_ONLY) == 0

#if ((in_flags & PV_SEEK_INIT) == 0 && streq('EXIT_LABEL', '--'))
check#:
    #if (streq('in_length', '--'))
        #if (((in_flags & PV_SEEK_REVERSE) == 0))
            alu[--, BF_MASK(PV_SEEK_BASE_bf), AND, outside, >>BF_L(PV_SEEK_BASE_bf)]
        #else
            alu[--, (BF_MASK(PV_SEEK_BASE_bf) >> 1), AND, outside, >>(BF_L(PV_SEEK_BASE_bf) + 1)]
        #endif
        bne[read#]
    #else
        .reg boundary
        alu[--, (BF_MASK(PV_SEEK_BASE_bf) >> 1), AND, outside, >>(BF_L(PV_SEEK_BASE_bf) + 1)]
        bne[read#]
        #if (((in_flags & PV_SEEK_REVERSE) == 0))
            alu[boundary, _PV_SEEK_OFFSET, +, in_length]
        #else
            alu[boundary, _PV_SEEK_OFFSET, -, in_length]
        #endif
        alu[outside, BF_A(io_vec, PV_SEEK_BASE_bf), XOR, boundary]
        alu[--, (BF_MASK(PV_SEEK_BASE_bf) >> 1), AND, outside, >>(BF_L(PV_SEEK_BASE_bf) + 1)]
        bne[read#]
    #endif
#endif // ((in_flags & PV_SEEK_INIT) == 0 && streq('EXIT_LABEL', '--'))

end#:
#endif // ((in_flags) & PV_SEEK_T_INDEX_ONLY) == 0
#undef _PV_SEEK_OFFSET
#undef _PV_SEEK_TEST_OFFSET_MASK
#undef _PV_SEEK_READ_OFFSET_MASK
#undef _PV_SEEK_READ_BASE_MASK
.end
#endm


#macro pv_seek(io_vec, in_offset)
    pv_seek(--, io_vec, in_offset, --, 0, --)
#endm


#macro pv_seek(io_vec, in_offset, in_flags)
    pv_seek(--, io_vec, in_offset, --, in_flags, --)
#endm


#macro pv_seek(io_vec, in_offset, in_flags, EXIT_LABEL)
    pv_seek(--, io_vec, in_offset, --, in_flags, EXIT_LABEL)
#endm


#macro pv_seek(io_vec, in_offset, in_length, in_flags, EXIT_LABEL)
    pv_seek(--, io_vec, in_offset, in_length, in_flags, EXIT_LABEL)
#endm


#macro pv_invalidate_cache(in_pkt_vec)
    alu[BF_A(in_pkt_vec, PV_SEEK_BASE_bf), BF_A(in_pkt_vec, PV_SEEK_BASE_bf), OR, 0xff, <<BF_L(PV_SEEK_BASE_bf)]
#endm


#macro _pv_hdr_parse(pkt_vec, port_tun_args)
.begin
    .reg eth_type
    .reg proto_test
    .reg hdr_len
    .reg hdr_stack
    .reg label
    .reg l4_offset
    .reg mac_dst_type
    .reg next_hdr
    .reg n_vxlan
    .reg pkt_offset
    .reg udp_dst_port
    .reg vxlan_idx
    .reg tmp

    immed[pkt_offset, ETHERNET_SIZE]
    immed[BF_A(pkt_vec, PV_HEADER_STACK_bf), 0]
    ld_field[BF_A(pkt_vec, PV_PROTO_bf), 0001, 0]

check_eth_type#:
    byte_align_be[--, *$index++]
    byte_align_be[tmp, *$index++]
    alu[eth_type, --, B, tmp, >>16]

check_ipv6#:
    immed[proto_test, NET_ETH_TYPE_IPV6]
    alu[--, eth_type, -, proto_test]
    bne[check_ipv4#]

parse_ipv6#:
    ld_field[BF_A(pkt_vec, PV_HEADER_STACK_bf), 0010, pkt_offset, <<8] // IP Offset
    byte_align_be[--, *$index++]
    byte_align_be[next_hdr, *$index++]
    immed[hdr_len, IPV6_HDR_SIZE]

check_ipv6_next_hdr#:
    br=byte[next_hdr, 3, NET_IP_PROTO_UDP, parse_ipv6_udp#], defer[1]
        alu[pkt_offset, pkt_offset, +, hdr_len]

check_ipv6_tcp#:
    br!=byte[next_hdr, 3, NET_IP_PROTO_TCP, check_ipv6_other#]
    br[done_hdr_stack#], defer[2]
        ld_field[BF_A(pkt_vec, PV_HEADER_STACK_bf), 0001, pkt_offset] // L4 Offset
        alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

check_ipv6_other#:
    br=byte[next_hdr, 3, NET_IP_PROTO_FRAG, ipv6_frag#]

    br=byte[next_hdr, 3, NET_IP_PROTO_GRE, gre#]

    br=byte[next_hdr, 3, NET_IP_PROTO_HOPOPT, skip_ipv6_ext#]
    br=byte[next_hdr, 3, NET_IP_PROTO_DSTOPTS, skip_ipv6_ext#]
    br=byte[next_hdr, 3, NET_IP_PROTO_ROUTING, skip_ipv6_ext#]

    br[done_hdr_stack#], defer[2]
        alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_IPV6_UNKNOWN] // L4 Unknown
        alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

ipv6_frag#:
    br[done_hdr_stack#], defer[2]
        alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_IPV6_FRAGMENT] // IPv6 Frag
        alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

skip_ipv6_ext#:
    pv_seek(pkt_vec, pkt_offset, PV_SEEK_CTM_ONLY)

    byte_align_be[--, *$index++]
    byte_align_be[next_hdr, *$index++]
    alu[hdr_len, 0xff, AND, next_hdr, >>16]
    br[check_ipv6_next_hdr#], defer[2]
        /* hdr length = "Hdr Ext Len" * 8 + 8 */
        alu[hdr_len, --, B, hdr_len, <<3]
        alu[hdr_len, hdr_len, +, 8]

check_ipv4#:
    immed[proto_test, NET_ETH_TYPE_IPV4]
    alu[--, eth_type, -, proto_test]
    bne[check_vlan#]

parse_ipv4#:
    ld_field[BF_A(pkt_vec, PV_HEADER_STACK_bf), 0010, pkt_offset, <<8] // IP Offset

    // IHL*4 (tmp = 0x0800:4:IHL:xx)
    alu[l4_offset, (0xf << 2), AND, tmp, >>(8 - 2)]
    byte_align_be[--, *$index]
    byte_align_be[tmp, *$index++]

    //fragment test (frag pkt if more frags flag and frag offset is non-zero)
    alu[tmp, --, B, tmp, >>16]
    alu[tmp, tmp, AND~, 0x3, <<14]
    bne[ipv4_frag#], defer[1]
        alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_IPV4] // IPv4

    byte_align_be[next_hdr, *$index++]
    br=byte[next_hdr, 0, NET_IP_PROTO_UDP, parse_ipv4_udp#], defer[1]
        alu[pkt_offset, pkt_offset, +, l4_offset]

    br!=byte[next_hdr, 0, NET_IP_PROTO_TCP, check_ipv4_gre#]
    br[done_hdr_stack#], defer[2]
        ld_field[BF_A(pkt_vec, PV_HEADER_STACK_bf), 0001, pkt_offset] // L4 Offset
        alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

parse_ipv4_udp#:
    br!=byte[BF_A(pkt_vec, PV_HEADER_STACK_bf), 3, 0, end#], defer[2]
        ld_field[BF_A(pkt_vec, PV_HEADER_STACK_bf), 0001, pkt_offset] // L4 Offset
        alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_UDP] // UDP

check_tunnel#:
    pv_seek(pkt_vec, pkt_offset, PV_SEEK_T_INDEX_ONLY)

    // don't need byte_align_be[] after seek because check_tunnel# is only done for outer header
    alu[udp_dst_port, 0, +16, *$index++]

    bitfield_extract__sz1[vxlan_idx, port_tun_args, BF_ML(INSTR_RX_VXLAN_NN_IDX_bf)) ; INSTR_RX_VXLAN_NN_IDX_bf
    local_csr_wr[NN_GET, vxlan_idx]
    bitfield_extract__sz1(n_vxlan, port_tun_args, BF_ML(INSTR_RX_PARSE_VXLANS_bf)) ; INSTR_RX_PARSE_VXLANS_bf

check_nn_vxlan#:
    alu[n_vxlan, n_vxlan, -, 1]
    bmi[check_geneve_tun#]

    alu[--, udp_dst_port, -, *n$index++]
    bne[check_nn_vxlan#]
    alu[pkt_offset, pkt_offset, +, (UDP_HDR_SIZE + VXLAN_SIZE + ETHERNET_SIZE)]

seek_inner#:
    alu[tmp, 0xff, AND, BF_A(pkt_vec, PV_PROTO_bf)]
    ld_field[BF_A(pkt_vec, PV_PROTO_bf), 0001, tmp, <<TUNNEL_SHF]
    alu[BF_A(pkt_vec, PV_HEADER_STACK_bf), --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf), <<16]

seek_eth_type#:
    pv_seek(pkt_vec, pkt_offset, (PV_SEEK_CTM_ONLY | PV_SEEK_PAD_INCLUDED), check_eth_type#)

check_geneve_tun#:
    br_bclr[port_tun_args, BF_L(INSTR_RX_PARSE_GENEVE_bf), done#]
    immed[proto_test, NET_GENEVE_PORT]
    alu[--, udp_dst_port, -, proto_test]
    bne[done#]

    alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, (PROTO_GENEVE >> TUNNEL_SHF)]

    alu[--, --, B, *$index++] // skip over UDP Length:Checksum
    alu[hdr_len, (0x3f << 2), AND, *$index++, >>(24 - 2)] // Opt Len

    br[seek_inner#], defer[2]
        alu[pkt_offset, pkt_offset, +, hdr_len]
        alu[pkt_offset, pkt_offset, +, (UDP_HDR_SIZE + GENEVE_SIZE + ETHERNET_SIZE)]

check_ipv4_gre#:
    br!=byte[next_hdr, 0, NET_IP_PROTO_GRE, unknown_l4#]

gre#:
    br!=byte[BF_A(pkt_vec, PV_HEADER_STACK_bf), 3, 0, done#]
    br_bclr[port_tun_args, BF_L(INSTR_RX_PARSE_NVGRE_bf), unknown_l4#]
    pv_seek(pkt_vec, pkt_offset, PV_SEEK_T_INDEX_ONLY)
    alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, (PROTO_GRE >> TUNNEL_SHF)]
    // determine GRE header length - refer to RFC1701
    alu[tmp, (1 << 3), AND, *$index, >>(28 - 1)] // R implies C
    alu[tmp, tmp, OR, *$index, >>28]
    pop_count1[tmp]
    pop_count2[tmp]
    pop_count3[tmp, tmp]
    alu[tmp, --, B, tmp, <<2]
    br[seek_inner#], defer[2]
        alu[pkt_offset, pkt_offset, +, tmp]
        alu[pkt_offset, pkt_offset, +, (NVGRE_SIZE + ETHERNET_SIZE)]

unknown_l4#:
    br[done_hdr_stack#], defer[2]
        alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_L4_UNKNOWN] //L4 unknown
        alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

unknown_proto#:
    br[done_hdr_stack#], defer[2]
        ld_field[BF_A(pkt_vec, PV_PROTO_bf), 0001, PROTO_UNKNOWN]
        alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

ipv4_frag#:
    br[done_hdr_stack#], defer[2]
        alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_FRAG] // IPv4 Frag
        alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

check_vlan#:
    immed[proto_test, NET_ETH_TYPE_TPID]
    alu[--, eth_type, -, proto_test]
    beq[vlan_tag#]
    immed[proto_test, NET_ETH_TYPE_SVLAN]
    alu[--, eth_type, -, proto_test]
    bne[check_mpls#]

vlan_tag#:
    br[seek_eth_type#], defer[1]
        alu[pkt_offset, pkt_offset, +, (ETH_TYPE_SIZE + ETH_VLAN_SIZE)]

check_mpls#:
    immed[proto_test, NET_ETH_TYPE_MPLS]
    alu[--, eth_type, -, proto_test]
    bne[unknown_proto#]
    alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_MPLS] // MPLS

mpls_loop#:
    /* get low 16 bits of MPLS label into hi 16 bits of tmp */
    alu[label, --, B, tmp, <<16]
    byte_align_be[tmp, *$index++]

    /* check Bottom of Stack bit */
    br_bclr[tmp, 24, mpls_loop#], defer[1]
        alu[pkt_offset, pkt_offset, +, MPLS_LABEL_SIZE]

    /* check for IPv4 or IPv6 explicit null labels */
    alu[label, label, OR, tmp, >>16]
    alu[label, --, B, label, >>12]
    beq[parse_ipv4#]
    alu[--, label, -, 2]
    beq[parse_ipv6#]
    br[done#]

parse_ipv6_udp#:
    br=byte[BF_A(pkt_vec, PV_HEADER_STACK_bf), 3, 0, check_tunnel#], defer[2]
        ld_field[BF_A(pkt_vec, PV_HEADER_STACK_bf), 0001, pkt_offset] // L4 Offset
        alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, PROTO_UDP] // UDP

done#:
    alu[hdr_stack, --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf)]

done_hdr_stack#:
    br!=byte[BF_A(pkt_vec, PV_HEADER_STACK_bf), 3, 0, end#]
    alu[BF_A(pkt_vec, PV_HEADER_STACK_bf), BF_A(pkt_vec, PV_HEADER_STACK_bf), OR, hdr_stack, <<16]

end#:
.end
#endm


#macro pv_hdr_parse(pkt_vec, port_tun_args, RETURN_LABEL)
    br[PV_HDR_PARSE_SUBROUTINE#], defer[1]
        load_addr[rtn_addr_reg, RETURN_LABEL]
#endm


#macro pv_hdr_parse_subroutine(pkt_vec, port_tun_args)
.subroutine
    _pv_hdr_parse(pkt_vec, port_tun_args)
    rtn[rtn_addr_reg]
.endsub
#endm

#endif
