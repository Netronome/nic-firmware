/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   pv.uc
 * @brief  Packet state and metadata management. Also provides packet read access abstraction.
 *
 * SPDX-License-Identifier: BSD-2-Clause
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

#define PV_MAX_CLONES 2
passert(PV_MAX_CLONES, "EQ", 2)

#define NULL_VLAN 0xfff

.alloc_mem __pv_reserved_pkt_mem ctm+0 island (64*2048) reserved
.alloc_mem __pv_pkt_sequencer imem global 4 256

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
 * Word  +-----------------------------------+---------------------------+
 *       |                                                               | 0 <- ACTIVE_LM_ADDR_2 (init)
 *       |                       Prepend Metadata                        |
 *  0-7  |                                                               |
 *       |                                   +---------------------------+
 *       |                                   | Original Pkt Length (PCI) |
 *       +-----------+-------------------+---+---------------------------+
 *    8  |  CTM ISL  |   Packet Number   |BLS|       Packet Length       | 0 <- ACTIVE_LM_ADDR_1 (fixed)
 *       +-+---+-----+-------------------+---+---------------------------+
 *    9  |S|CBS|           MU Buffer Address [39:11]                     | 1
 *       +-+---+-----+-------------------+-----+-------------------------+
 *    10 |A|    0    |   Packet Number   |  0  |         Offset          | 2
 *       +-+---------+-------------------+-----+---------+---------------+
 *    11 |        Sequence Number        | --- | Seq Ctx |   Protocol    | 3
 *       +-------------------------------+-+-+-+---------+---+-+-+-+-+-+-+
 *    12 |         TX Host Flags         |M|B|Seek (64B algn)|-|Q|I|i|C|c| 4
 *       +-------------------------------+-+-+---------------+-+-+-+-+-+-+
 *    13 |       8B Header Offsets (stacked outermost to innermost)      | 5
 *       +-----------------+-----+-----------------------+---------------+
 *    14 |  Ingress Queue  | LMP |        VLAN ID        | Queue Offset  | 6
 *       +-----------------+-----+-----------------------+---------------+
 *    15 |                      Metadata Type Fields                     | 7
 *       +---------------------------------------------------------------+
 *
 * 0     - Intentionally zero for efficient extraction and manipulation
 * S     - Split packet
 * A     - 1 if CTM buffer is allocated (ie. packet number and CTM address valid)
 * CBS   - CTM Buffer Size
 * BLS   - Buffer List
 * P     - Packet pending (multicast)
 * Q     - Queue offset selected (overrides RSS)
 * V     - One or more VLANs present
 * M     - dest MAC is multicast
 * B     - dest MAC is broadcast
 * I     - Enable offload of inner L3 checksum
 * i     - Enable offload of inner L4 checksum
 * C     - Enable offload of outer L3 checksum
 * c     - Enable offload of outer L4 checksum
 * LMP   - LM Metadata Pointer
 *
 * Protocol - Parsed Packet Type (see defines below)
 *
 * TX host flags:
 *       +-------------------------------+
 *    4  |R|4|$|t|T|u|U|B|-|4|$|t|T|u|U|V|
 *       +--------------------------------
 *          <- inner ->     <- outer ->
 *
 * -   - Flag currently unsupported by firmware (see nfp-drv-kmods)
   R   - RSSv1 metadata
 * B   - BPF offload executed
 * 4   - IPv4 header was parsed
 * $   - IPv4 checksum is valid
 * t   - TCP header was parsed
 * T   - TCP checksum is valid
 * u   - UDP header was parsed
 * U   - UDP checksum is valid
 * V   - VLAN parsed and stripped
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
#define PV_CTM_ISL_bf                   PV_LENGTH_wrd, 31, 26
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
#define PV_PROTO_IPV4_bf                PV_SEQ_wrd, 1, 1
#define PV_PROTO_UDP_bf                 PV_SEQ_wrd, 0, 0

#define PV_FLAGS_wrd                    4
#define PV_TX_FLAGS_bf                  PV_FLAGS_wrd, 31, 16
#define PV_TX_HOST_RX_RSS_bf            PV_FLAGS_wrd, 31, 31
#define PV_TX_HOST_I_IP4_bf             PV_FLAGS_wrd, 30, 30
#define PV_TX_HOST_I_CSUM_IP4_OK_bf     PV_FLAGS_wrd, 29, 20
#define PV_TX_HOST_I_TCP_bf             PV_FLAGS_wrd, 28, 28
#define PV_TX_HOST_I_CSUM_TCP_OK_bf     PV_FLAGS_wrd, 27, 27
#define PV_TX_HOST_I_UDP_bf             PV_FLAGS_wrd, 26, 26
#define PV_TX_HOST_I_CSUM_UDP_OK_bf     PV_FLAGS_wrd, 25, 25
#define PV_TX_HOST_RX_BPF_bf            PV_FLAGS_wrd, 24, 24
#define PV_TX_HOST_L3_bf                PV_FLAGS_wrd, 22, 21
#define PV_TX_HOST_IP4_bf               PV_FLAGS_wrd, 22, 22
#define PV_TX_HOST_CSUM_IP4_OK_bf       PV_FLAGS_wrd, 21, 21
#define PV_TX_HOST_L4_bf                PV_FLAGS_wrd, 20, 17
#define PV_TX_HOST_TCP_bf               PV_FLAGS_wrd, 20, 20
#define PV_TX_HOST_CSUM_TCP_OK_bf       PV_FLAGS_wrd, 19, 19
#define PV_TX_HOST_UDP_bf               PV_FLAGS_wrd, 18, 18
#define PV_TX_HOST_CSUM_UDP_OK_bf       PV_FLAGS_wrd, 17, 17
#define PV_MAC_DST_TYPE_bf              PV_FLAGS_wrd, 15, 14
#define PV_MAC_DST_MC_bf                PV_FLAGS_wrd, 15, 15
#define PV_MAC_DST_BC_bf                PV_FLAGS_wrd, 14, 14
#define PV_SEEK_BASE_bf                 PV_FLAGS_wrd, 13, 6
#define PV_QUEUE_SELECTED_bf            PV_FLAGS_wrd, 4, 4
#define PV_CSUM_OFFLOAD_bf              PV_FLAGS_wrd, 3, 0
#define PV_CSUM_OFFLOAD_IL3_bf          PV_FLAGS_wrd, 3, 3
#define PV_CSUM_OFFLOAD_IL4_bf          PV_FLAGS_wrd, 2, 2
#define PV_CSUM_OFFLOAD_OL3_bf          PV_FLAGS_wrd, 1, 1
#define PV_CSUM_OFFLOAD_OL4_bf          PV_FLAGS_wrd, 0, 0

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
#define PV_META_LM_PTR_bf               PV_QUEUE_wrd, 22, 20
#define PV_VLAN_ID_bf                   PV_QUEUE_wrd, 19, 8
#define PV_QUEUE_OFFSET_bf              PV_QUEUE_wrd, 7, 0

#define PV_META_TYPES_wrd               7
#define PV_META_TYPES_bf                PV_META_TYPES_wrd, 31, 0

#define PV_META_BASE_wrd                8
#define PV_META_BASE_bf                 PV_META_BASE_wrd, 31, 0

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
#define PROTO_ENCAP_SHF                    5
#define PROTO_UNKNOWN                      0xFF

#ifndef PV_GRO_NFD_START
    #define PV_GRO_NFD_START            8
#endif

#if (defined(NFD_PCIE1_EMEM) || defined(NFD_PCIE2_EMEM) || defined(NFD_PCIE3_EMEM))
    #define PV_MULTI_PCI
#endif


.alloc_mem _PKT_IO_PKT_VEC lmem+0 me (4 * (1 << log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1))) (4 * (1 << log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1)))

#macro pv_reset(in_pv_addr, in_act_addr, in_t_idx, IN_SIZE)
.begin
    .reg addr

    local_csr_wr[ACTIVE_LM_ADDR_1, in_pv_addr]
    local_csr_wr[T_INDEX, in_t_idx]
    alu[addr, in_pv_addr, -, (PV_META_BASE_wrd * 4)]
    local_csr_wr[ACTIVE_LM_ADDR_2, addr]
    alu[BF_A(*l$index1, PV_QUEUE_IN_bf), --, B, in_act_addr, <<(BF_L(PV_QUEUE_IN_bf) - log2(IN_SIZE))]
.end
#endm


#macro pv_save_meta_lm_ptr(out_vec)
.begin
    .reg base
    .reg addr
    .reg meta_len

    local_csr_rd[ACTIVE_LM_ADDR_2]
    immed[addr, 0]
    alu[addr, BF_MASK(PV_META_LM_PTR_bf), AND, addr, >>2]
    bitfield_insert__sz2(BF_AML(out_vec, PV_META_LM_PTR_bf), addr)
.end
#endm


#macro pv_restore_meta_lm_ptr(in_vec)
.begin
    .reg addr

    alu[addr, (BF_MASK(PV_META_LM_PTR_bf) << 2), AND, BF_A(in_vec, PV_META_LM_PTR_bf), >>(BF_L(PV_META_LM_PTR_bf) - 2)]
    alu[addr, addr, OR, t_idx_ctx, >>(8 - log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1))]
    local_csr_wr[ACTIVE_LM_ADDR_2, addr]
.end
#endm


#macro pv_push(io_vec, ERROR_LABEL)
.begin
    .reg addr
    .reg pkt_num

    br_bclr[BF_AL(io_vec, PV_CTM_ALLOCATED_bf), ERROR_LABEL]

    alu[addr, (PV_SIZE_LW * 4 + PV_META_BASE_wrd * 4), OR, t_idx_ctx, >>(8 - log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1))]
    local_csr_wr[ACTIVE_LM_ADDR_0, addr]

    pv_save_meta_lm_ptr(io_vec)
    bitfield_extract(pkt_num, BF_AML(io_vec, PV_NUMBER_bf))

    #define LOOP 0
    #while (LOOP < (PV_SIZE_LW - PV_META_BASE_wrd - 1))
        alu[*l$index0++, --, B, io_vec++]
        #define_eval LOOP (LOOP + 1)
    #endloop
    #undef LOOP

    local_csr_wr[ACTIVE_LM_ADDR_1, addr]

        alu[*l$index0, --, B, 0] ; PV_META_TYPES_bf
        alu[addr, addr, -, (PV_META_BASE_wrd * 4)]
        local_csr_wr[ACTIVE_LM_ADDR_2, addr]

    pkt_buf_copy_ctm_to_mu_head(pkt_num, BF_A(io_vec, PV_MU_ADDR_bf), BF_A(io_vec, PV_OFFSET_bf))
    bits_clr__sz1(BF_AL(io_vec, PV_CTM_ALLOCATED_bf), BF_MASK(PV_CTM_ALLOCATED_bf)) ; PV_CTM_ALLOCATED_bf
    bits_clr__sz1(BF_AL(io_vec, PV_META_LM_PTR_bf), BF_MASK(PV_META_LM_PTR_bf)) ; PV_META_LM_PTR_bf
.end
#endm


#macro pv_pop(io_vec, ERROR_LABEL)
.begin
    .reg bls
    .reg addr
    .reg write $x[4]
    .xfer_order $x

    br_bset[BF_AL(io_vec, PV_CTM_ALLOCATED_bf), ERROR_LABEL]

    alu[addr, (PV_META_BASE_wrd * 4), OR, t_idx_ctx, >>(8 - log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1))]
    local_csr_wr[ACTIVE_LM_ADDR_1, addr]

        bitfield_extract__sz1(bls, BF_AML(io_vec, PV_BLS_bf)) // still old value
        nop
        nop

    pv_restore_meta_lm_ptr(io_vec)

        bits_clr__sz1(BF_AL(io_vec, PV_BLS_bf), BF_MASK(PV_BLS_bf))
        bits_set__sz1(BF_AL(io_vec, PV_BLS_bf), bls)
        nop
.end
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


#macro pv_get_length(out_length, in_vec)
    alu[out_length, 0, +16, BF_A(in_vec, PV_LENGTH_bf)] ; PV_LENGTH_bf
    alu[out_length, out_length, AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
#endm


#macro pv_meta_push_type__sz1(io_vec, in_type)
    alu[BF_A(io_vec, PV_META_TYPES_bf), in_type, OR, BF_A(io_vec, PV_META_TYPES_bf), <<4]
#endm


#macro pv_meta_prepend(io_vec, in_metadata)
    alu[*l$index2++, --, B, in_metadata]
#endm


#macro pv_meta_get_len(out_meta_len)
.begin
    .reg lm_ptr

    local_csr_rd[ACTIVE_LM_ADDR_2]
    immed[lm_ptr, 0]
    alu[out_meta_len, (BF_MASK(PV_META_LM_PTR_bf) << 2), AND, lm_ptr]
    alu[out_meta_len, out_meta_len, +, 4]
.end
#endm


#macro pv_meta_write(out_meta_len, in_vec, in_pkt_addr_hi, in_pkt_addr_lo)
.begin
    .reg lm_ptr
    .reg idx
    .reg meta_base
    .reg ref_cnt
    .reg write $meta[9]
    .xfer_order $meta
    .sig sig_meta

    aggregate_directive(.set_wr, $meta, 9)

    alu[$meta[0], --, B, BF_A(in_vec, PV_META_TYPES_bf)]
    beq[no_meta#]

    local_csr_rd[ACTIVE_LM_ADDR_2]
    immed[lm_ptr, 0]
    alu[ref_cnt, BF_MASK(PV_META_LM_PTR_bf), AND, lm_ptr, >>2]
    alu[out_meta_len, --, B, ref_cnt, <<2]
    alu[lm_ptr, lm_ptr, -, out_meta_len]

    alu[idx, 8, -, ref_cnt]
    jump[idx, t8#], targets[t8#, t7#, t6#, t5#, t4#, t3#, t2#, t1#], defer[3]
        local_csr_wr[ACTIVE_LM_ADDR_2, lm_ptr]
        alu[out_meta_len, out_meta_len, +, 4]
        alu[meta_base, in_pkt_addr_lo, -, out_meta_len]

no_meta#:
    br[end#], defer[1]
        immed[out_meta_len, 0]

#define LOOP 8
#while (LOOP > 1)
t/**/LOOP#:
    alu[$meta[LOOP], --, B, *l$index2++]
#define_eval LOOP (LOOP - 1)
#endloop
#undef LOOP
t1#:

    ov_single(OV_LENGTH, ref_cnt) // don't subtract 1, ref_cnt includes $meta[0]
    #pragma warning(disable:5009)
    mem[write32, $meta[0], in_pkt_addr_hi, <<8, meta_base, max_9], indirect_ref, ctx_swap[sig_meta], defer[2]
        alu[$meta[1], --, B, *l$index2++]
    #pragma warning(default:5009)
        nop

end#:
.end
#endm


#macro pv_meta_write(out_meta_len, in_vec)
.begin
    .reg addr_hi
    .reg addr_lo

    pv_get_base_addr(addr_hi, addr_lo, in_vec)
    pv_meta_write(out_meta_len, in_vec, addr_hi, addr_lo)
.end
#endm


#macro pv_multicast_init(io_vec, in_bls, CONTINUE_LABEL)
.begin
    .reg mu_addr
    .reg ctm_isl
    .reg pkt_num
    .reg read $dummy
    .reg write $buf_meta[4]
    .xfer_order $buf_meta
    .sig sig_meta
    .sig sig_sync

    alu[mu_addr, --, B, BF_A(io_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))] ; PV_MU_ADDR_bf
    alu[$buf_meta[0], --, B, 1] // initial buffer reference count
    alu[$buf_meta[1], 0x80, OR, BF_A(io_vec, PV_CTM_ISL_bf), >>BF_L(PV_CTM_ISL_bf)] ; PV_CTM_ISL_bf
    alu[pkt_num, --, B, BF_A(io_vec, PV_NUMBER_bf), <<(31 - BF_M(PV_NUMBER_bf))] ; PV_NUMBER_bf
    alu[$buf_meta[2], --, B, pkt_num, >>(31 - BF_M(PV_NUMBER_bf) + BF_L(PV_NUMBER_bf))] ; PV_NUMBER_bf
#pragma warning(disable:5009)
#pragma warning(disable:4700)
    mem[atomic_write, $buf_meta[0], mu_addr, <<8, 0, 4], sig_done[sig_meta]
    mem[atomic_read, $dummy, mu_addr, <<8, 0, 1], sig_done[sig_sync]
    ctx_arb[sig_meta, sig_sync], defer[2], br[CONTINUE_LABEL]
#pragma warning(default:4700)
        alu[$buf_meta[3], NFD_OUT_BLM_POOL_START, +, in_bls]
        bits_set__sz1(BF_AL(io_vec, PV_BLS_bf), 3)
#pragma warning(default:5009)

.end
#endm


#macro pv_multicast_resend(io_vec)
.begin
    .reg mu_addr
    .reg read $dummy
    .sig sig_sync

    alu[mu_addr, --, B, BF_A(io_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))] ; PV_MU_ADDR_bf
    ov_single(OV_IMMED8, 1)
    mem[test_add_imm, $dummy, mu_addr, <<8, 0, 1], indirect_ref, ctx_swap[sig_sync]
.end
#endm


#macro pv_stats_tx_host(io_vec, in_pci_isl, in_pci_q, in_continue, IN_TERM_LABEL, IN_CONT_LABEL)
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

#pragma warning(disable:5009)
#pragma warning(disable:4700)

    passert(NIC_STATS_QUEUE_RX_IDX, "EQ", 0)
    passert(log2(NIC_STATS_QUEUE_SIZE / 8), "GT", log2(BF_MASK(PV_MAC_DST_TYPE_bf) + 1))
    #ifdef PV_MULTI_PCI
        alu[type_idx, BF_MASK(PV_MAC_DST_TYPE_bf), AND, BF_A(io_vec, PV_MAC_DST_TYPE_bf), >>BF_L(PV_MAC_DST_TYPE_bf)] ; PV_MAC_DST_TYPE_bf
    #endif

    br_bclr[BF_AL(io_vec, PV_QUEUE_IN_TYPE_bf), from_host#], defer[3]
        immed[addr, (_nic_stats_queue >> 24), <<(24-8)]
        alu[length, BF_A(io_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
        ld_field[length, 1100, 2, <<16] // 32 bit unpacked addressing

    // update egress queue's RX stats

from_nbi#:
#if (! streq('in_continue', '--'))
    br_bset[in_continue, BF_L(INSTR_TX_CONTINUE_bf), continue_from_nbi#]
#endif
    mem[stats_log, $idx_rx, addr, <<8, length, 1], sig_done[sig_rx]
    ctx_arb[sig_rx], br[IN_TERM_LABEL], defer[2]
    #ifdef PV_MULTI_PCI
        alu[queue_idx, in_pci_q, OR, in_pci_isl, <<6]
        alu[$idx_rx, type_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #else
        alu[type_idx, BF_MASK(PV_MAC_DST_TYPE_bf), AND, BF_A(io_vec, PV_MAC_DST_TYPE_bf), >>BF_L(PV_MAC_DST_TYPE_bf)] ; PV_MAC_DST_TYPE_bf
        alu[$idx_rx, type_idx, OR, in_pci_q, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #endif

#if (! streq('in_continue', '--'))
continue_from_nbi#:
    mem[stats_log, $idx_rx, addr, <<8, length, 1], sig_done[sig_rx]
    ctx_arb[sig_rx], br[IN_CONT_LABEL], defer[2]
#endif

from_host#:
    #ifdef PV_MULTI_PCI
        alu[queue_idx, in_pci_q, OR, in_pci_isl, <<6]
        alu[$idx_rx, type_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #else
        alu[type_idx, BF_MASK(PV_MAC_DST_TYPE_bf), AND, BF_A(io_vec, PV_MAC_DST_TYPE_bf), >>BF_L(PV_MAC_DST_TYPE_bf)] ; PV_MAC_DST_TYPE_bf
        alu[$idx_rx, type_idx, OR, in_pci_q, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #endif

    mem[stats_log, $idx_rx, addr, <<8, length, 1], sig_done[sig_rx]

    // update ingress queue's TX stats

    alu[stat_idx, NIC_STATS_QUEUE_TX_IDX, +, type_idx]
#if (! streq('in_continue', '--'))
    br_bset[in_continue, BF_L(INSTR_TX_CONTINUE_bf), continue_from_host#], defer[3]
#endif
        alu[--, io_vec--, OR, 0]
        alu[length, --, B, io_vec++]
        ld_field[length, 1100, 2, <<16] // 32 bit unpacked addressing

    mem[stats_log, $idx_tx, addr, <<8, length, 1], sig_done[sig_tx]
    ctx_arb[sig_rx, sig_tx], br[IN_TERM_LABEL], defer[2]
        alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
        passert(log2(NIC_STATS_QUEUE_SIZE / 8), "GT", log2(NIC_STATS_QUEUE_TX_IDX))
        alu[$idx_tx, stat_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]

#if (! streq('in_continue', '--'))
continue_from_host#:
    mem[stats_log, $idx_tx, addr, <<8, length, 1], sig_done[sig_tx]
    ctx_arb[sig_rx, sig_tx], br[IN_CONT_LABEL], defer[2]
        alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
        alu[$idx_tx, stat_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
#endif

#pragma warning(default:4700)
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

    alu[type_idx, BF_MASK(PV_MAC_DST_TYPE_bf), AND, BF_A(io_vec, PV_MAC_DST_TYPE_bf), >>BF_L(PV_MAC_DST_TYPE_bf)] ; PV_MAC_DST_TYPE_bf
    alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
    immed[addr, (_nic_stats_queue >> 24), <<(24-8)]
    alu[--, io_vec--, OR, 0]
    alu[length, --, B, io_vec++]
    ld_field[length, 1100, 2, <<16] // 32 bit unpacked addressing

    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    mem[stats_log, $idx, addr, <<8, length, 1], sig_done[sig_stat]
    #pragma warning(default:4700)
    ctx_arb[sig_stat], br[IN_LABEL], defer[2]
        alu[stat_idx, NIC_STATS_QUEUE_TX_IDX, +, type_idx]
        alu[$idx, stat_idx, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
    #pragma warning(default:5009)
.end
#endm


#macro pv_stats_tx_wire(io_vec)
    pv_stats_tx_wire(io_vec, end#)
end#:
#endm

#macro pv_stats_update(io_vec, IN_STAT, IN_QUEUE, IN_LABEL)
.begin
    .reg addr
    .reg length
    .reg queue_idx
    .reg sig_stat
    .reg write $idx
    .sig sig_stat

    immed[addr, (_nic_stats_queue >> 24), <<(24-8)]

    alu[length, BF_A(io_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf

    // bit[31-18] reserved, bit[17-16] - stats addr pack, 2=32 bit unpacked addr
    ld_field[length, 1100, 2, <<16] 

    #pragma warning(push)
    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    #if (is_ct_const(NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX))
        #if (log2(NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX, 1) < log2(NIC_STATS_QUEUE_SIZE / 8))
            #if (streq('IN_LABEL', '--'))
                mem[stats_log, $idx, addr, <<8, length, 1], ctx_swap[sig_stat], defer[2]
            #else
                mem[stats_log, $idx, addr, <<8, length, 1], sig_done[sig_stat]
                ctx_arb[sig_stat], br[IN_LABEL], defer[2]
            #endif
            #if (streq('IN_QUEUE', '--'))
                alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
            #else
                alu[queue_idx, --, B, IN_QUEUE]
            #endif
            alu[$idx, NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX, OR, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
        #else
            #if (streq('IN_QUEUE', '--'))
                alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
            #endif
            #if (streq('IN_LABEL', '--'))
                mem[stats_log, $idx, addr, <<8, length, 1], ctx_swap[sig_stat], defer[2]
            #else
                mem[stats_log, $idx, addr, <<8, length, 1], sig_done[sig_stat]
                ctx_arb[sig_stat], br[IN_LABEL], defer[2]
            #endif
            #if (streq('IN_QUEUE', '--'))
                alu[queue_idx, --, B, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
            #else
                alu[queue_idx, --, B, IN_QUEUE, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
            #endif
            alu[$idx, queue_idx, +, NIC_STATS_QUEUE_/**/IN_STAT/**/_IDX]
        #endif
    #else
        #if (streq('IN_QUEUE', '--'))
            alu[queue_idx, --, B, BF_A(io_vec, PV_QUEUE_IN_bf), >>BF_L(PV_QUEUE_IN_bf)] ; PV_QUEUE_IN_bf
        #endif
        #if (streq('IN_LABEL', '--'))
            mem[stats_log, $idx, addr, <<8, length, 1], ctx_swap[sig_stat], defer[2]
        #else
            mem[stats_log, $idx, addr, <<8, length, 1], sig_done[sig_stat]
            ctx_arb[sig_stat], br[IN_LABEL], defer[2]
        #endif
        #if (streq('IN_QUEUE', '--'))
            alu[queue_idx, --, B, queue_idx, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
        #else
            alu[queue_idx, --, B, IN_QUEUE, <<(log2(NIC_STATS_QUEUE_SIZE / 8))]
        #endif
        alu[$idx, queue_idx, +, IN_STAT]
    #endif
    #pragma warning(pop)
.end
#endm


#macro pv_stats_update(io_vec, IN_STAT, IN_LABEL)
    pv_stats_update(io_vec, IN_STAT, --, IN_LABEL)
#endm


#macro pv_stats_update(io_vec, IN_STAT)
    pv_stats_update(io_vec, IN_STAT, --, --)
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


#macro pv_get_gro_mu_free_desc(out_desc, in_vec)
.begin
    .reg addr_hi
    .reg bls
    .reg mu_addr
    .reg ring

    immed[out_desc[GRO_META_TYPE_wrd], (GRO_DTYPE_DROP_MU_BUF << GRO_META_TYPE_shf)]
    immed[out_desc[1], 0]

    bitfield_extract__sz1(bls, BF_AML(in_vec, PV_BLS_bf)) ; PV_BLS_bf
    alu[ring, NFD_OUT_BLM_POOL_START, +, bls]

    #define_eval _PV_GRO_FREE_POOL strleft(NFD_OUT_BLM_POOL_START, strlen(NFD_OUT_BLM_POOL_START)-2)
    #if (_PV_GRO_FREE_POOL/**/_LOCALITY == MU_LOCALITY_DIRECT_ACCESS)
        alu[out_desc[GRO_META_DROP_RINGNUM_wrd], ring, OR,
            ((_PV_GRO_FREE_POOL/**/_LOCALITY << 6) | (_PV_GRO_FREE_POOL/**/_ISLAND & 0x3f)), <<24]
    #else
        alu[out_desc[GRO_META_DROP_RINGNUM_wrd], ring, OR,
            ((_PV_GRO_FREE_POOL/**/_LOCALITY << 6) | (1 << 5) | ((_PV_GRO_FREE_POOL/**/_ISLAND & 0x3) << 3)), <<24]
    #endif
    bitfield_extract__sz1(out_desc[GRO_META_DROP_BUFH_wrd], BF_AML(in_vec, PV_MU_ADDR_bf)) ; PV_MU_ADDR_bf
.end
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
#macro pv_get_gro_wire_desc(out_desc, in_vec, in_nbi, in_tm_q, in_pms_offset)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg ctm_buf_sz
    .reg desc
    .reg prev_alu

    .reg ctm_buf_s
    .reg queue

    #if (SCS != 0)
        #error "SCS will break __MEID used below."
    #endif

    ld_field_w_clr[addr_hi, 1000, BF_A(in_vec, PV_CTM_ISL_bf), >>2] ; PV_CTM_ISL_bf
    #if (NBI_COUNT > 2)
        #error "Implementation relies on single bit in_nbi."
    #elif (NBI_COUNT > 1)
        passert((GRO_DEST_IFACE_BASE & 1), "EQ", 0)
        #error change GRO_DTYPE_IFACE for multicast
        alu[out_desc[GRO_META_TYPE_wrd], (GRO_DTYPE_IFACE | (GRO_DEST_IFACE_BASE << GRO_META_DEST_shf)), OR, in_nbi, <<GRO_META_DEST_shf]
        alu[addr_hi, addr_hi, OR, in_nbi, <<30]
    #else
        immed[out_desc[GRO_META_TYPE_wrd], (GRO_DTYPE_IFACE | (GRO_DEST_IFACE_BASE << GRO_META_DEST_shf))]
    #endif
    alu[out_desc[GRO_META_NBI_ADDRHI_wrd], addr_hi, OR, ((__MEID & 1) + 2), <<20] ; __MEID

    alu[addr_lo, BF_A(in_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    alu[addr_lo, addr_lo, AND~, BF_MASK(PV_CTM_ISL_bf), <<BF_L(PV_CTM_ISL_bf)] ; PV_CTM_ISL_bf
    alu[out_desc[GRO_META_NBI_ADDRLO_wrd], addr_lo, +16, BF_A(in_vec, PV_CTM_ADDR_bf)] ; PV_CTM_ADDR_bf

    #if (is_ct_const(pms_offset))
        immed[prev_alu, ((((in_pms_offset >> 3) - 1) << 8) | 0xcb)]
    #else
        alu[prev_alu, in_pms_offset, -, (1 << 3)]
        alu[prev_alu, 0xcb, OR, prev_alu, <<(8-3)]
    #endif
    alu[prev_alu, prev_alu, OR, in_tm_q, <<16]
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[out_desc[GRO_META_NBI_PALU_wrd], prev_alu, OR, ctm_buf_sz, <<28]

.end
#endm


#macro pv_setup_packet_ready(out_addr_hi, out_addr_lo, in_vec, in_nbi, in_tm_q, in_pms_offset)
.begin
    .reg ctm_buf_sz
    .reg prev_alu

    #if (SCS != 0)
        #error "SCS will break __MEID used below."
    #endif

    ld_field_w_clr[out_addr_hi, 1000, BF_A(in_vec, PV_CTM_ISL_bf), >>2] ; PV_CTM_ISL_bf
    #if (NBI_COUNT > 2)
        #error "Implementation relies on single bit in_nbi."
    #elif (NBI_COUNT > 1)
        alu[out_addr_hi, out_addr_hi, OR, in_nbi, <<30]
    #endif
    alu[out_addr_hi, out_addr_hi, OR, ((__MEID & 1) + 2), <<20] ; __MEID

    alu[out_addr_lo, BF_A(in_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    alu[out_addr_lo, out_addr_lo, AND~, BF_MASK(PV_CTM_ISL_bf), <<BF_L(PV_CTM_ISL_bf)] ; PV_CTM_ISL_bf
    alu[out_addr_lo, out_addr_lo, +16, BF_A(in_vec, PV_CTM_ADDR_bf)] ; PV_CTM_ADDR_bf

    local_csr_wr[CMD_INDIRECT_REF_0, 0]
    #if (is_ct_const(pms_offset))
        immed[prev_alu, ((((in_pms_offset >> 3) - 1) << 8) | 0xcb)]
    #else
        alu[prev_alu, in_pms_offset, -, (1 << 3)]
        alu[prev_alu, 0xcb, OR, prev_alu, <<(8-3)]
    #endif
    alu[prev_alu, prev_alu, OR, in_tm_q, <<16]
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[--, prev_alu, OR, ctm_buf_sz, <<28]
.end
#endm


#macro pv_get_required_host_buf_sz(out_buf_sz, in_vec, in_meta_len)
    alu[out_buf_sz, BF_A(in_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_LENGTH_bf, PV_BLS_bf
    alu[out_buf_sz, in_meta_len, +16, out_buf_sz]
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
#macro pv_get_gro_host_desc(out_desc, in_vec, in_buf_sz, in_meta_len, in_pci_isl, in_pci_q)
.begin
    .reg buf_list
    .reg ctm_buf_sz
    .reg ctm_only
    .reg desc
    .reg offset

    #ifdef SPLIT_EMU_RINGS
        // NFD supports SPLIT_EMU_RINGS (separate EMU rings for each NBI)
        // by providing the "N" bit extending the BLS field.  In practice
        // If SPLIT_EMU_RINGS is _not_ used, then N is simply zero for all
        // NBIs.
        #error "SPLIT_EMU_RINGS configuration not supported."
    #endif

    // Word 0
    br_bclr[BF_AL(in_vec, PV_CTM_ALLOCATED_bf), skip_ctm#], defer[3] ; PV_CTM_ALLOCATED_bf
        alu[offset, BF_A(in_vec, PV_OFFSET_bf), -, in_meta_len] ; PV_OFFSET_bf
        alu[desc, 0x7f, AND, offset, >>1]
        alu[desc, GRO_DTYPE_NFD, OR, desc, <<GRO_META_W0_META_START_BIT]
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[desc, desc, OR, ctm_buf_sz, <<NFD_OUT_SPLIT_shf]
    ld_field[desc, 1100, BF_A(in_vec, PV_NUMBER_bf)] ; PV_CTM_ISL_bf, PV_NUMBER_bf
    alu[ctm_only, 1, AND~, BF_A(in_vec, PV_SPLIT_bf), >>BF_L(PV_SPLIT_bf)]
    alu[desc, desc, OR, ctm_only, <<NFD_OUT_CTM_ONLY_shf]
skip_ctm#:
    alu[out_desc[NFD_OUT_OFFSET_wrd], desc, OR, in_pci_isl, <<GRO_META_DEST_shf]

    // Word 1
    alu[desc, BF_A(in_vec, PV_MU_ADDR_bf), AND~, ((BF_MASK(PV_SPLIT_bf) << BF_WIDTH(PV_CBS_bf)) | BF_MASK(PV_CBS_bf)), <<BF_L(PV_CBS_bf)]
    bitfield_extract__sz1(buf_list, BF_AML(in_vec, PV_BLS_bf)) ; PV_BLS_bf
    alu[out_desc[NFD_OUT_BLS_wrd], desc, OR, buf_list, <<NFD_OUT_BLS_shf]

    // Word 2
    alu[desc, in_buf_sz, OR, in_meta_len, <<NFD_OUT_METALEN_shf]
    #ifndef GRO_EVEN_NFD_OFFSETS_ONLY
       alu[desc, desc, OR, offset, <<31]
    #endif
    alu[out_desc[NFD_OUT_QID_wrd], desc, OR, in_pci_q, <<NFD_OUT_QID_shf]

    // Word 3
    alu[out_desc[NFD_OUT_FLAGS_wrd], --, B, BF_A(in_vec, PV_TX_FLAGS_bf), >>BF_L(PV_TX_FLAGS_bf)] ; PV_TX_FLAGS_bf
.end
#endm

/**
 * Descriptor for direct delivery via NFD
 *
 * Note, this macro assumes metadata has already been prepended!
 *
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-----------+-+-----------------+---+-+-----------+-------------+
 *    0  |  CTM ISL  |C|  Packet Number  |CBS|0|         offset          |
 *       +-+---+-----+-+-----------------+---+-+-----------+-------------+
 *    1  |N|BLS|           MU Buffer Address [39:11]                     |
 *       +-+---+---------+---------------+-------------------------------+
 *    2  |1| Meta Length |  RX Queue     |           Data Length         |
 *       +-+-------------+---------------+-------------------------------+
 *    3  |             VLAN              |             Flags             |
 *       +-------------------------------+-------------------------------+
 */
#macro pv_get_nfd_host_desc(out_desc, in_vec, in_meta_len)
.begin
    .reg buf_list
    .reg ctm_buf_sz
    .reg ctm_only
    .reg desc
    .reg mu_addr
    .reg offset

    #ifdef SPLIT_EMU_RINGS
        // NFD supports SPLIT_EMU_RINGS (separate EMU rings for each NBI)
        // by providing the "N" bit extending the BLS field.  In practice
        // If SPLIT_EMU_RINGS is _not_ used, then N is simply zero for all
        // NBIs.
        #error "SPLIT_EMU_RINGS configuration not supported."
    #endif

    // Word 0
    alu[desc, 1, AND, BF_A(in_vec, PV_CTM_ALLOCATED_bf), >>BF_L(PV_CTM_ALLOCATED_bf)] ; PV_CTM_ALLOCATED_bf
    beq[skip_ctm#], defer[3]
        // Word 1
        alu[mu_addr, BF_A(in_vec, PV_MU_ADDR_bf), AND~, ((BF_MASK(PV_SPLIT_bf) << BF_WIDTH(PV_CBS_bf)) | BF_MASK(PV_CBS_bf)), <<BF_L(PV_CBS_bf)]
        bitfield_extract__sz1(buf_list, BF_AML(in_vec, PV_BLS_bf)) ; PV_BLS_bf
        alu[out_desc[NFD_OUT_BLS_wrd], mu_addr, OR, buf_list, <<NFD_OUT_BLS_shf]
    ld_field_w_clr[desc, 1100, BF_A(in_vec, PV_NUMBER_bf)] ; PV_CTM_ISL_bf, PV_NUMBER_bf
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[desc, desc, OR, ctm_buf_sz, <<NFD_OUT_SPLIT_shf]
    alu[ctm_only, 1, AND~, BF_A(in_vec, PV_SPLIT_bf), >>BF_L(PV_SPLIT_bf)]
    alu[desc, desc, OR, ctm_only, <<NFD_OUT_CTM_ONLY_shf]
skip_ctm#:
    alu[offset, BF_A(in_vec, PV_OFFSET_bf), -, in_meta_len]
    alu[out_desc[NFD_OUT_OFFSET_wrd], desc, +16, offset]

    // Word 3
    alu[out_desc[NFD_OUT_FLAGS_wrd], --, B, BF_A(in_vec, PV_TX_FLAGS_bf), >>BF_L(PV_TX_FLAGS_bf)] ; PV_TX_FLAGS_bf
.end
#endm

#macro pv_update_nfd_desc_queue(out_desc, in_vec, in_buf_sz, in_meta_len, in_pci_q)
.begin
    .reg desc

    // Word 2
    alu[desc, in_buf_sz, OR, in_meta_len, <<NFD_OUT_METALEN_shf]
    alu[desc, desc, OR, 1, <<31]
    alu[out_desc[NFD_OUT_QID_wrd], desc, OR, in_pci_q, <<NFD_OUT_QID_shf]
.end
#endm

#macro pv_get_nfd_host_desc(out_desc, in_vec, in_buf_sz, in_meta_len, in_pci_q)
    pv_get_nfd_host_desc(out_desc, in_vec, in_meta_len)
    pv_update_nfd_desc_queue(out_desc, in_vec, in_buf_sz, in_meta_len, in_pci_q)
#endm


#macro pv_get_ctm_base(out_addr, in_vec)
    // mask out packet offset
    alu[out_addr, 0xff, ~AND, BF_A(in_vec, PV_CTM_ADDR_bf), >>8] ; PV_CTM_ADDR_bf
#endm


#macro pv_get_base_addr(out_hi, out_lo, in_vec)
.begin
    .reg no_ctm
    .reg addr_msk

    alu[no_ctm, 1, AND~, BF_A(in_vec, PV_CTM_ADDR_bf), >>BF_L(PV_CTM_ALLOCATED_bf)]
    alu[addr_msk, 0, -, no_ctm]
    alu[out_lo, BF_A(in_vec, PV_CTM_ADDR_bf), AND~, addr_msk, <<BF_L(PV_NUMBER_bf)]
    alu[out_hi, addr_msk, AND, BF_A(in_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]
.end
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
    alu[$nbi_meta[0], --, B, BF_A(in_vec, PV_NUMBER_bf)] ; PV_NUMBER_bf
    alu[$nbi_meta[1], BF_A(in_vec, PV_MU_ADDR_bf), AND~, BF_MASK(PV_CBS_bf), <<BF_L(PV_CBS_bf)] ; PV_MU_ADDR_bf
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


#macro pv_get_seq_no(out_seq_no, in_vec)
    bitfield_extract__sz1(out_seq_no, BF_AML(in_vec, PV_SEQ_NO_bf)) ; PV_SEQ_NO_bf
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
 *       +-----+-+-+-+-+-+-+-+---+---+---+-------------------------------+
 *    7  |P_STS|M|E|A|F|D|R|H|L3 |MPL|VLN|           Checksum            |
 *       +-----+-+-+-+-+-+-+-+---+---+---+-------------------------------+
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

#macro pv_init_nbi(out_vec, in_nbi_desc, in_rx_args)
.begin
    .reg addr
    .reg cbs
    .reg dst_mac_bc
    .reg ip_ver
    .reg l3_csum_tbl
    .reg l3_flags
    .reg l3_offset
    .reg l3_type
    .reg l4_csum_tbl
    .reg l4_flags
    .reg l4_tcp
    .reg l4_type
    .reg l4_offset
    .reg mac_dst_type
    .reg parse_args
    .reg seq_ctx
    .reg shift
    .reg tunnel
    .reg vlan_len
    .reg vlan_id
    .reg read $seq
    .sig sig_seq

    #ifdef PARANOIA
        br_bclr[BF_AL(in_nbi_desc, CAT_VALID_bf), fail#] ; CAT_VALID_bf
    #endif

    alu[BF_A(out_vec, PV_LENGTH_bf), BF_A(in_nbi_desc, CAT_PKT_LEN_bf), -, MAC_PREPEND_BYTES]

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
    alu[cbs, (PKT_NBI_OFFSET - 1), +16, BF_A(in_nbi_desc, CAT_PKT_LEN_bf)] ; CAT_PKT_LEN_bf
    alu[--, 0xf, AND, cbs, >>10]
    bne[max_cbs#], defer[3]
        alu[BF_A(out_vec, PV_MU_ADDR_bf), BF_A(in_nbi_desc, CAT_MUPTR_bf), AND~, BF_MASK(PV_CBS_bf), <<BF_L(PV_CBS_bf)]
        alu[shift, (BF_MASK(PV_CBS_bf) << 1), AND, cbs, >>(8 - 1)]
        alu[cbs, shift, B, 3]
    alu[cbs, cbs, AND, ((2 << 6) | (2 << 4) | (1 << 2) | (0 << 0)), >>indirect]
max_cbs#:
    alu[BF_A(out_vec, PV_MU_ADDR_bf), BF_A(out_vec, PV_MU_ADDR_bf), OR, cbs, <<BF_L(PV_CBS_bf)]

    immed[BF_A(out_vec, PV_TX_FLAGS_bf), 0]

    br_bset[in_rx_args, BF_L(INSTR_RX_WIRE_CSUM_bf), propagate_csum#], defer[3]
        alu[BF_A(out_vec, PV_CTM_ADDR_bf), BF_A(out_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_CTM_ISL_bf), <<BF_L(PV_CTM_ISL_bf)]
        alu[BF_A(out_vec, PV_CTM_ADDR_bf), BF_A(out_vec, PV_CTM_ADDR_bf), OR, 1, <<BF_L(PV_CTM_ALLOCATED_bf)]
        ld_field[BF_A(out_vec, PV_CTM_ADDR_bf), 0011, (PKT_NBI_OFFSET + MAC_PREPEND_BYTES)]

map_seq#:
    bitfield_extract__sz1(seq_ctx, BF_AML(in_nbi_desc, CAT_SEQ_CTX_bf))
    beq[alloc_seq#] // if null sequencer, allocate new sequence number
    alu[seq_ctx, seq_ctx, +, 1] // balance over GRO blocks, seq_ctx = 2/3/4/5
    alu[BF_A(out_vec, PV_SEQ_NO_bf), BF_A(in_nbi_desc, CAT_SEQ_NO_bf), OR, 0xff] ; PV_SEQ_NO_bf, PV_PROTO_bf (unkown)

seek#:
    pv_seek(out_vec, 0, PV_SEEK_INIT, read_pkt#)

#ifdef PARANOIA
fail#:
    fatal_error("INVALID CATAMARAN METADATA") // fatal error, can't safely drop without valid sequencer info
#endif

propagate_csum#:
    immed[l4_csum_tbl, 0x238c, <<8]
    alu[shift, (7 << 2), AND, BF_A(in_nbi_desc, MAC_PARSE_STS_bf), >>(BF_L(MAC_PARSE_STS_bf) - 2)] ; MAC_PARSE_STS_bf
    alu[l3_csum_tbl, shift, B, 0xe0]
    alu[l4_flags, 0xf, AND, l4_csum_tbl, >>indirect]
    alu[shift, (3 << 1), AND, BF_A(in_nbi_desc, MAC_PARSE_L3_bf), >>(BF_L(MAC_PARSE_L3_bf) - 1)] ; MAC_PARSE_L3_bf
    alu[BF_A(out_vec, PV_TX_HOST_L4_bf), shift, B, l4_flags, <<BF_L(PV_TX_HOST_L4_bf)] ; PV_TX_HOST_L4_bf
    alu[l3_flags, 0x3, AND, l3_csum_tbl, >>indirect]
    br[map_seq#], defer[1]
        alu[BF_A(out_vec, PV_TX_HOST_L3_bf), BF_A(out_vec, PV_TX_HOST_L3_bf), OR, l3_flags, <<BF_L(PV_TX_HOST_L3_bf)] ; PV_TX_HOST_L3_bf

alloc_seq#:
    move(addr, (__pv_pkt_sequencer >> 8))
    ov_single(OV_IMMED8, 1)
    mem[test_add_imm, $seq, addr, <<8, 0, 1], indirect_ref, ctx_swap[sig_seq]
    br[seek#], defer[1]
        alu[BF_A(out_vec, PV_SEQ_NO_bf), 0xff, OR, $seq, <<16]

hdr_parse#:
    alu[parse_args, in_rx_args, AND~, 1, <<BF_L(INSTR_RX_HOST_ENCAP_bf)]
    pv_hdr_parse(out_vec, parse_args, end#)

ipv4_frag#:
    br[finalize_l3#], defer[1]
        ld_field[BF_A(out_vec, PV_PROTO_bf), 0001, PROTO_IPV4_FRAGMENT]

read_pkt#:
    __pv_get_mac_dst_type(mac_dst_type, out_vec) // advances *$index by 2 words
    alu[vlan_len, (3 << 2), AND, BF_A(in_nbi_desc, MAC_PARSE_VLAN_bf), >>(BF_L(MAC_PARSE_VLAN_bf) - 2)]
    beq[skip_vlan#], defer[3]
        alu[BF_A(out_vec, PV_MAC_DST_TYPE_bf), BF_A(out_vec, PV_MAC_DST_TYPE_bf), OR, mac_dst_type, <<BF_L(PV_MAC_DST_TYPE_bf)] ; PV_MAC_DST_TYPE_bf
        alu[BF_A(out_vec, PV_META_TYPES_bf), *$index++, B, 0] ; PV_META_TYPES_bf
        immed[vlan_id, NULL_VLAN]

    alu[--, *$index++, OR, 0]
    alu[vlan_id, --, B, *$index--, >>16]

skip_vlan#:
    bitfield_extract__sz1(l3_type, BF_AML(in_nbi_desc, CAT_L3_CLASS_bf)) ; CAT_L3_CLASS_bf
    br!=byte[l3_type, 0, 4, hdr_parse#], defer[2] // if packet is not IPv4 perform parse
        bits_set__sz1(BF_AL(out_vec, PV_VLAN_ID_bf), vlan_id) ; PV_VLAN_ID_bf
        passert(BF_L(PV_SEQ_CTX_bf), "EQ", 8)
        ld_field[BF_A(out_vec, PV_SEQ_CTX_bf), 0010, seq_ctx, <<BF_L(PV_SEQ_CTX_bf)]

    // packet is IPv4, classify fragments
    br_bset[BF_AL(in_nbi_desc, CAT_V4_FRAG_bf), ipv4_frag#], defer[3]
        bitfield_extract__sz1(l3_offset, BF_AML(in_nbi_desc, CAT_L3_OFFSET_bf)) ; CAT_L3_OFFSET_bf
        alu[l3_offset, l3_offset, -, MAC_PREPEND_BYTES]
        alu[BF_A(out_vec, PV_HEADER_STACK_bf), --, B, l3_offset, <<BF_L(PV_HEADER_OFFSET_INNER_IP_bf)]

    // packet is IPv4, deep parse if NVGRE is configured
    br_bset[in_rx_args, BF_L(INSTR_RX_PARSE_NVGRE_bf), hdr_parse#]

    // packet is IPv4, deep parse if not TCP or UDP
    alu[l4_type, 0xe, AND, BF_A(in_nbi_desc, CAT_L4_CLASS_bf), >>BF_L(CAT_L4_CLASS_bf)] ; CAT_L4_CLASS_bf
    br!=byte[l4_type, 0, 2, hdr_parse#]

    // deep parse if UDP tunnels are possible and configured
    alu[tunnel, in_rx_args, AND, ((BF_MASK(INSTR_RX_PARSE_VXLANS_bf) << BF_L(INSTR_RX_PARSE_VXLANS_bf)) | (1 << BF_L(INSTR_RX_PARSE_GENEVE_bf)))]
    alu[tunnel, 0, -, tunnel]
    alu[tunnel, tunnel, AND~, BF_A(in_nbi_desc, CAT_L4_CLASS_bf)]
    br_bset[tunnel, BF_L(CAT_L4_CLASS_bf), hdr_parse#] ; CAT_L4_CLASS_bf

    // set PV_PROTO_bf to IPv4 according to L4 protocol
    alu[BF_A(out_vec, PV_PROTO_bf), BF_A(out_vec, PV_PROTO_bf), AND~, 0xfc] ; PV_PROTO_bf
    alu[l4_tcp, 1, AND, BF_A(in_nbi_desc, CAT_L4_CLASS_bf), >>BF_L(CAT_L4_CLASS_bf)] ; CAT_L4_CLASS_bf
    alu[BF_A(out_vec, PV_PROTO_bf), BF_A(out_vec, PV_PROTO_bf), AND~, l4_tcp] ; PV_PROTO_bf

    // store header offsets
    bitfield_extract__sz1(l4_offset, BF_AML(in_nbi_desc, CAT_L4_OFFSET_bf)) ; CAT_L4_OFFSET_bf
    alu[l4_offset, l4_offset, -, MAC_PREPEND_BYTES]
    alu[BF_A(out_vec, PV_HEADER_STACK_bf), BF_A(out_vec, PV_HEADER_STACK_bf), OR, l4_offset, <<BF_L(PV_HEADER_OFFSET_INNER_L4_bf)]
    alu[BF_A(out_vec, PV_HEADER_STACK_bf), BF_A(out_vec, PV_HEADER_STACK_bf), OR, l4_offset, <<BF_L(PV_HEADER_OFFSET_OUTER_L4_bf)]

finalize_l3#:
    alu[BF_A(out_vec, PV_HEADER_STACK_bf), BF_A(out_vec, PV_HEADER_STACK_bf), OR, l3_offset, <<BF_L(PV_HEADER_OFFSET_OUTER_IP_bf)]

end#:
.end
#endm


#macro __pv_lso_fixup(io_vec, in_nfd_desc, DONE_LABEL, ERROR_LABEL)
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

    .reg write $udp_len
    .sig sig_write_udp_len

    .reg addr_hi
    .reg addr_lo
    .reg encap
    .reg ip_id
    .reg ip_len
    .reg l3_addr
    .reg l3_offset
    .reg l4_addr
    .reg l4_offset
    .reg lso_seq
    .reg mss
    .reg shift
    .reg sig_mask
    .reg tcp_seq_add
    .reg tcp_flags_mask
    .reg tmp
    .reg udp_len

    bitfield_extract__sz1(l3_offset, BF_AML(io_vec, PV_HEADER_OFFSET_OUTER_IP_bf))
    beq[lso_error#]

    bitfield_extract__sz1(l4_offset, BF_AML(io_vec, PV_HEADER_OFFSET_OUTER_L4_bf))
    beq[lso_error#]

    br_bset[BF_AL(io_vec, PV_PROTO_UDP_bf), lso_error#]

    alu[addr_hi, --, B, BF_A(io_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]

    bitfield_extract(mss, BF_AML(in_nfd_desc, NFD_IN_LSO_MSS_fld))

    bitfield_extract__sz1(lso_seq, BF_AML(in_nfd_desc, NFD_IN_LSO_SEQ_CNT_fld))
    alu[lso_seq, lso_seq, -, 1]

    br_bset[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_ENCAP_fld), udp_encap#], defer[3]
lso_begin#:
        immed[sig_mask, 0]
        alu[l3_addr, l3_offset, +16, BF_A(io_vec, PV_OFFSET_bf)]
        alu[l4_addr, l4_offset, +16, BF_A(io_vec, PV_OFFSET_bf)]

    mem[read32, $tcp_hdr[0], addr_hi, <<8, l4_addr, 4], ctx_swap[sig_read_tcp], defer[2]
        alu[sig_mask, sig_mask, OR, mask(sig_write_tcp_seq), <<(&sig_write_tcp_seq)]
        alu[sig_mask, sig_mask, OR, mask(sig_write_tcp_flags), <<(&sig_write_tcp_flags)]

    /* TCP_SEQ_bf += (mss * (lso_seq - 1)) */
    multiply32(tcp_seq_add, mss, lso_seq, OP_SIZE_8X24) // multiplier is 8 bits, multiplicand is 24 bits (8x24)
    alu[$tcp_seq, BF_A($tcp_hdr, TCP_SEQ_bf), +, tcp_seq_add]

    alu[addr_lo, l4_addr, +, TCP_SEQ_OFFS]
    mem[write32, $tcp_seq, addr_hi, <<8, addr_lo, 1], sig_done[sig_write_tcp_seq]

    /*   .if (BIT(in_nfd_lso_wrd, BF_L(NFD_IN_LSO_END_fld)))
     *       tcp_flags_mask = 0xffff
     *   .else
     *       tcp_flags_mask = ~(NET_TCP_FLAG_FIN | NET_TCP_FLAG_RST | NET_TCP_FLAG_PSH)
     *   .endif
     *   TCP_FLAGS_bf = TCP_FLAGS_bf & tcp_flags_mask
     *
     *   TCP stores data offset and flags and in the same 16 bit word (preserve upper bits)
     */
    alu[shift, 8, AND, BF_A(in_nfd_desc, NFD_IN_LSO_END_fld), >>(BF_L(NFD_IN_LSO_END_fld) - 3)] // 8 if last packet, else 0
    alu[tcp_flags_mask, shift, B, (NET_TCP_FLAG_FIN | NET_TCP_FLAG_RST | NET_TCP_FLAG_PSH)]
    alu[tcp_flags_mask, --, B, tcp_flags_mask, >>indirect]
    alu[$tcp_flags, BF_A($tcp_hdr, TCP_FLAGS_bf), AND~, tcp_flags_mask, <<16]
    alu[addr_lo, l4_addr, +, TCP_FLAGS_OFFS]
    mem[write8, $tcp_flags, addr_hi, <<8, addr_lo, 2], sig_done[sig_write_tcp_flags]

    br_bclr[BF_AL(io_vec, PV_PROTO_IPV4_bf), ipv6#], defer[3]
        /* IP length = pkt_len - l3_off */
        alu[ip_len, BF_A(io_vec, PV_LENGTH_bf), -, l3_offset]
        alu[ip_len, ip_len, AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)]
        alu[ip_len, --, B, ip_len, <<16]

ipv4#:
    alu[addr_lo, l3_addr, +, IPV4_LEN_OFFS]
    mem[read32, $ip, addr_hi, <<8, addr_lo, 1], ctx_swap[sig_read_ip]

    alu[ip_id, $ip, +, lso_seq]
    alu[$ip, ip_len, +16, ip_id]

    mem[write32, $ip, addr_hi, <<8, addr_lo, 1], sig_done[sig_write_ip]
    alu[encap, l4_offset, XOR, BF_A(io_vec, PV_HEADER_STACK_bf)]
    br!=byte[encap, 0, 0, repeat_from_ipv4#]
    ctx_arb[--], defer[2], br[DONE_LABEL]
        .io_completed sig_write_ip, sig_write_udp_len, sig_write_tcp_seq, sig_write_tcp_flags
        alu[sig_mask, sig_mask, OR, mask(sig_write_ip), <<(&sig_write_ip)]
        local_csr_wr[ACTIVE_CTX_WAKEUP_EVENTS, sig_mask]

ctx_arb_lso_error#:
    ctx_arb[--], defer[2], br[lso_error#]
        .io_completed sig_write_ip, sig_write_udp_len, sig_write_tcp_seq, sig_write_tcp_flags
        alu[sig_mask, sig_mask, OR, mask(sig_write_ip), <<(&sig_write_ip)]
        local_csr_wr[ACTIVE_CTX_WAKEUP_EVENTS, sig_mask]

lso_error#:
    pv_stats_update(io_vec, TX_ERROR_LSO, ERROR_LABEL)

repeat_from_ipv4#:
    // force outer L3 CSUM offload
    alu[BF_A(io_vec, PV_CSUM_OFFLOAD_bf), BF_A(io_vec, PV_CSUM_OFFLOAD_bf), OR, 1, <<BF_L(PV_CSUM_OFFLOAD_OL3_bf)]

repeat#:
    bitfield_extract(l3_offset, BF_AML(io_vec, PV_HEADER_OFFSET_INNER_IP_bf))
    beq[ctx_arb_lso_error#]

    bitfield_extract(l4_offset, BF_AML(io_vec, PV_HEADER_OFFSET_INNER_L4_bf))
    beq[ctx_arb_lso_error#]

    ctx_arb[--], defer[2], br[lso_begin#]
        .io_completed sig_write_ip, sig_write_udp_len, sig_write_tcp_seq, sig_write_tcp_flags
        alu[sig_mask, sig_mask, OR, mask(sig_write_ip), <<(&sig_write_ip)]
        local_csr_wr[ACTIVE_CTX_WAKEUP_EVENTS, sig_mask]

udp_encap#:
    alu[udp_len, BF_A(io_vec, PV_LENGTH_bf), -, l4_offset]
    alu[udp_len, udp_len, AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)]
    alu[$udp_len, --, B, udp_len, <<16]

    alu[addr_lo, l4_addr, +, UDP_LEN_OFFS]
    mem[write8, $udp_len, addr_hi, <<8, addr_lo, 2], sig_done[sig_write_udp_len]
    alu[sig_mask, sig_mask, OR, mask(sig_write_udp_len), <<(&sig_write_udp_len)]
    br_bset[BF_A(io_vec, PV_PROTO_IPV4_bf), (BF_L(PV_PROTO_IPV4_bf) + PROTO_ENCAP_SHF), ipv4#], defer[3]
        alu[ip_len, BF_A(io_vec, PV_LENGTH_bf), -, l3_offset]
        alu[ip_len, ip_len, AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)]
        alu[ip_len, --, B, ip_len, <<16]

ipv6#:
    alu[tmp, --, B, 40, <<16]
    alu[$ip, ip_len, -, tmp]
    alu[addr_lo, l3_addr, +, IPV6_PAYLOAD_OFFS]
    mem[write8, $ip, addr_hi, <<8, addr_lo, 2], sig_done[sig_write_ip]
    alu[encap, l4_offset, XOR, BF_A(io_vec, PV_HEADER_STACK_bf)]
    br!=byte[encap, 0, 0, repeat#]
    ctx_arb[--], defer[2], br[DONE_LABEL]
        .io_completed sig_write_ip, sig_write_udp_len, sig_write_tcp_seq, sig_write_tcp_flags
        alu[sig_mask, sig_mask, OR, mask(sig_write_ip), <<(&sig_write_ip)]
        local_csr_wr[ACTIVE_CTX_WAKEUP_EVENTS, sig_mask]

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
 *    2  |TX_CSUM|IPV4_CS|TCP_CS |UDP_CS |TX_VLAN|TX_LSO |ENCAP  |OIP4_CS|
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
 *       25  VXLAN   -> PCIE_DESC_TX_ENCAP
 *       24  GRE     -> PCIE_DESC_TX_O_IP4_CSUM
 *
 *      S -> sp0 (spare)
 *    itf -> PCIe interface
 */

#define NFD_IN_LSO_L3_OFFS_fld      3, 7, 0
#define NFD_IN_LSO_L4_OFFS_fld      3, 15, 8


#macro pv_init_nfd(out_vec, in_pkt_num, in_nfd_desc, in_rx_args, DROP_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg csum_offload
    .reg csum_ol3
    .reg csum_udp
    .reg encap
    .reg hdr_parse
    .reg mac_dst_type
    .reg meta_len
    .reg mtu
    .reg pcie
    .reg pkt_num
    .reg pkt_len
    .reg seq_ctx
    .reg seq_no
    .reg shift
    .reg split
    .reg vlan_id

    bitfield_extract__sz1(pkt_len, BF_AML(in_nfd_desc, NFD_IN_DATALEN_fld)) ; NFD_IN_DATALEN_fld
    bitfield_extract__sz1(meta_len, BF_AML(in_nfd_desc, NFD_IN_OFFSET_fld)) ; NFD_IN_OFFSET_fld
    alu[*l$index2[7], pkt_len, -, meta_len]

    alu[BF_A(out_vec, PV_NUMBER_bf), *l$index2[7], OR, in_pkt_num, <<BF_L(PV_NUMBER_bf)] ; PV_NUMBER_bf
    bits_set__sz1(BF_AL(out_vec, PV_CTM_ISL_bf), __ISLAND)
    #if (NFD_IN_BLM_JUMBO_BLS == NFD_IN_BLM_REG_BLS)
        bits_set__sz1(BF_AL(out_vec, PV_BLS_bf), NFD_IN_BLM_REG_BLS) ; PV_BLS_bf
    #else
        .reg bls
        br_bset[BF_AL(in_nfd_desc, NFD_IN_JUMBO_fld), jumbo#], defer[1]
            immed[bls, NFD_IN_BLM_JUMBO_BLS]
        immed[bls, NFD_IN_BLM_REG_BLS]
    jumbo#:
        bits_set__sz1(BF_AL(out_vec, PV_BLS_bf), bls) ; PV_BLS_bf
    #endif

    // Assume CBS = 0
    alu[BF_A(out_vec, PV_MU_ADDR_bf), BF_A(in_nfd_desc, NFD_IN_BUFADDR_fld), AND~, 0x7, <<(BF_M(PV_MU_ADDR_bf) + 1)]
    alu[split, (256 - NFD_IN_DATA_OFFSET), -, pkt_len]
    alu[split, --, B, split, >>31]
    alu[BF_A(out_vec, PV_SPLIT_bf), BF_A(out_vec, PV_SPLIT_bf), OR, split, <<BF_L(PV_SPLIT_bf)] ; PV_SPLIT_bf

    alu[BF_A(out_vec, PV_CTM_ADDR_bf), NFD_IN_DATA_OFFSET, OR, in_pkt_num, <<BF_L(PV_NUMBER_bf)]

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

    // error checks near end to ensure consistent metadata (fields written below excluded)
    // note that pv_free() does not depend on state of 'A' bit
    br_bset[BF_AL(in_nfd_desc, NFD_IN_INVALID_fld), error_pci#]

    alu[mtu, --, B, in_rx_args, >>BF_L(INSTR_RX_HOST_MTU_bf)]
    __pv_mtu_check(out_vec, mtu, (4 * 2), error_mtu#)

    alu[csum_offload, 0x3, AND, BF_A(in_nfd_desc, NFD_IN_FLAGS_TX_TCP_CSUM_fld), >>BF_L(NFD_IN_FLAGS_TX_TCP_CSUM_fld)]
    bitfield_extract__sz1(csum_udp, BF_AML(in_nfd_desc, NFD_IN_FLAGS_TX_UDP_CSUM_fld)) ; NFD_IN_FLAGS_TX_UDP_CSUM_fld
    alu[csum_offload, csum_offload, OR, csum_udp]
    alu[shift, (1 << 1), AND, BF_A(in_nfd_desc, NFD_IN_FLAGS_TX_ENCAP_fld), >>(BF_L(NFD_IN_FLAGS_TX_ENCAP_fld) - 1)]
    alu[csum_ol3, shift, AND, BF_A(in_nfd_desc, NFD_IN_FLAGS_TX_O_IPV4_CSUM_fld), >>(BF_L(NFD_IN_FLAGS_TX_O_IPV4_CSUM_fld) - 1)]
    alu[BF_A(out_vec, PV_CSUM_OFFLOAD_bf), csum_ol3, OR, csum_offload, <<indirect]

    immed[vlan_id, NULL_VLAN]
    bits_set__sz1(BF_AL(out_vec, PV_VLAN_ID_bf), vlan_id]

    pv_seek(out_vec, 0, PV_SEEK_INIT, preparse#)

error_pci#:
    pv_stats_update(out_vec, TX_ERROR_PCI, DROP_LABEL)

error_mtu#:
    pv_stats_update(out_vec, TX_ERROR_MTU, DROP_LABEL)

lso_fixup#:
    __pv_lso_fixup(out_vec, in_nfd_desc, init_ctm#, DROP_LABEL)

preparse#:
    __pv_get_mac_dst_type(mac_dst_type, out_vec) // advances *$index by 2 words
    br_bset[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_LSO_fld), hdr_parse#]
    alu[hdr_parse, (3 << BF_L(PV_CSUM_OFFLOAD_IL4_bf)), OR, in_rx_args]
    alu[--, hdr_parse, AND, BF_A(out_vec, PV_CSUM_OFFLOAD_bf)]
    beq[init_ctm#], defer[3]
hdr_parse#:
        alu[BF_A(out_vec, PV_MAC_DST_TYPE_bf), BF_A(out_vec, PV_MAC_DST_TYPE_bf), OR, mac_dst_type, <<BF_L(PV_MAC_DST_TYPE_bf)]
        alu[BF_A(out_vec, PV_META_TYPES_bf), *$index++, B, 0]
        alu[BF_A(out_vec, PV_HEADER_STACK_bf), --, B, 0]

    bitfield_extract__sz1(encap, BF_AML(in_nfd_desc, NFD_IN_FLAGS_TX_ENCAP_fld))
    pv_hdr_parse(out_vec, encap)

    br_bset[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_LSO_fld), lso_fixup#]

init_ctm#:
    pkt_buf_copy_mu_head_to_ctm(in_pkt_num, BF_A(out_vec, PV_MU_ADDR_bf), NFD_IN_DATA_OFFSET, 1)
    alu[BF_A(out_vec, PV_CTM_ADDR_bf), BF_A(out_vec, PV_CTM_ADDR_bf), OR, 1, <<BF_L(PV_CTM_ALLOCATED_bf)]

.end
#endm


#macro pv_free(out_desc, in_pkt_vec)
.begin
    .reg bls
    .reg mu_addr
    .reg addr_hi
    .reg addr_lo
    .reg addr_msk
    .reg pkt_num
    .reg no_ctm
    .reg $tmp
    .sig sig_read

    pv_get_base_addr(addr_hi, addr_lo, in_pkt_vec)

    // ensure packet I/O is complete before free
    mem[read32, $tmp, addr_hi, <<8, addr_lo, 1], ctx_swap[sig_read], defer[2]
        bitfield_extract(pkt_num, BF_AML(in_pkt_vec, PV_NUMBER_bf)) ; PV_NUMBER_bf

    bitfield_extract__sz1(mu_addr, BF_AML(in_pkt_vec, PV_MU_ADDR_bf)) ; PV_MU_ADDR_bf
    beq[skip_mu_buffer#], defer[1]
        bitfield_extract__sz1(bls, BF_AML(in_pkt_vec, PV_BLS_bf)) ; PV_BLS_bf
    pkt_buf_free_mu_buffer(bls, mu_addr)
skip_mu_buffer#:

    br=byte[bls, 0, 3, skip_ctm_buffer#]
    pkt_buf_free_ctm_buffer(--, pkt_num)
    immed[out_desc[GRO_META_TYPE_wrd], (GRO_DTYPE_DROP_SEQ << GRO_META_TYPE_shf)]

skip_ctm_buffer#:
.end
#endm


.reg __pv_seek_offset
.reg __pv_seek_rtn
#macro pv_seek_subroutine(io_vec)
.subroutine
.begin
    .reg aligned_offset
    .reg buffer_offset
    .reg cbs
    .reg ctm_bytes
    .reg ctm_words
    .reg data_ref
    .reg mu_addr
    .reg mu_words
    .reg read_offset
    .reg split_offset
    .reg straddle_data
    .reg reflect_addr
    .reg tibi
    .reg tmp
    .reg write $reflect
    .sig sig_reflect
    .sig sig_ctm
    .sig sig_mu

    br_bclr[BF_AL(io_vec, PV_CTM_ALLOCATED_bf), read_mu#], defer[2]
        alu[aligned_offset, __pv_seek_offset, AND~, 0x3f]
        alu[read_offset, aligned_offset, -, 2]

    br_bset[BF_AL(io_vec, PV_SPLIT_bf), split#]

    ov_single(OV_LENGTH, 32, OVF_SUBTRACT_ONE)
    mem[read32, $__pv_pkt_data[0], BF_A(io_vec, PV_CTM_ADDR_bf), read_offset, max_32], indirect_ref, defer[2], ctx_swap[sig_ctm]
        alu[tibi, __pv_seek_offset, AND, 0x3f]
        alu[tibi, tibi, OR, t_idx_ctx]

finalize#:
    rtn[__pv_seek_rtn], defer[3]
        local_csr_wr[T_INDEX_BYTE_INDEX, tibi] // reload T_INDEX after ctx_swap[]
        alu[BF_A(pkt_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), AND~, BF_MASK(PV_SEEK_BASE_bf), <<BF_L(PV_SEEK_BASE_bf)]
        alu[BF_A(pkt_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), OR, aligned_offset]

split#:
    // determine the split offset based on CTM buffer size
    bitfield_extract__sz1(cbs, BF_AML(io_vec, PV_CBS_bf))
    alu[split_offset, cbs, B, 1, <<8]
    alu[split_offset, --, B, split_offset, <<indirect]

    alu[buffer_offset, read_offset, +16, BF_A(io_vec, PV_OFFSET_bf)]
    alu[ctm_bytes, split_offset, -, buffer_offset]
    ble[read_mu#]

    alu[--, 128, -, ctm_bytes]
    bgt[read_straddled#]

    ov_single(OV_LENGTH, 32, OVF_SUBTRACT_ONE)
    mem[read32, $__pv_pkt_data[0], BF_A(io_vec, PV_CTM_ADDR_bf), read_offset, max_32], indirect_ref, sig_done[sig_ctm]
    ctx_arb[sig_ctm], br[finalize#], defer[2]
        alu[tibi, __pv_seek_offset, AND, 0x3f]
        alu[tibi, tibi, OR, t_idx_ctx]

read_mu#:
    alu[mu_addr, --, B, BF_A(io_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]
    alu[read_offset, read_offset, +16, BF_A(io_vec, PV_OFFSET_bf)]
    ov_single(OV_LENGTH, 32, OVF_SUBTRACT_ONE)
    mem[read32, $__pv_pkt_data[0], mu_addr, <<8, read_offset, max_32], indirect_ref, sig_done[sig_mu]
    ctx_arb[sig_mu], br[finalize#], defer[2]
        alu[tibi, __pv_seek_offset, AND, 0x3f]
        alu[tibi, tibi, OR, t_idx_ctx]

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
        ld_field_w_clr[straddle_data, 1100, *$index]
        #if (SCS != 0)
            #error calculation of reflect_addr depends on __MEID
        #endif
        immed[reflect_addr, ((&$reflect << 2) | ((__MEID & 0xf) << 10))]

    local_csr_wr[T_INDEX, data_ref]
    alu[reflect_addr, reflect_addr, OR, __ISLAND, <<24]
    ov_single(OV_DATA_REF, data_ref)
    ct[reflect_read_sig_init, $__pv_pkt_data[0], t_idx_ctx, reflect_addr, 1], indirect_ref, ctx_swap[sig_reflect], defer[2]
        alu[tmp, 0, +16, *$index]
        alu[$reflect, tmp, OR, straddle_data]

    br[finalize#], defer[2]
        alu[tibi, __pv_seek_offset, AND, 0x3f]
        alu[tibi, tibi, OR, t_idx_ctx]
.end
.endsub
#endm


#define PV_SEEK_DEFAULT      (0)
#define PV_SEEK_T_INDEX_ONLY (1 << 1)
#define PV_SEEK_PAD_INCLUDED (1 << 2)
#define PV_SEEK_INIT         (1 << 3)

.reg volatile read $__pv_pkt_data[32]
.addr $__pv_pkt_data[0] 0
.xfer_order $__pv_pkt_data
#macro pv_seek(out_cache_idx, io_vec, in_offset, in_flags, EXIT_LABEL)
.begin
    .reg outside
    .reg tibi // T_INDEX_BYTE_INDEX

#if ((in_flags) & PV_SEEK_INIT)
    br[PV_SEEK_SUBROUTINE#], defer[2]
        #if (isnum((in_offset)))
            #if ((in_flags) & PV_SEEK_PAD_INCLUDED)
                immed[__pv_seek_offset, (in_offset)]
            #else
                immed[__pv_seek_offset, ((in_offset) + 2)]
            #endif
        #else
            #if ((in_flags) & PV_SEEK_PAD_INCLUDED)
                alu[__pv_seek_offset, --, B, in_offset]
            #else
                alu[__pv_seek_offset, in_offset, +, 2]
            #endif
        #endif
        #if (! streq('EXIT_LABEL', '--'))
            load_addr[__pv_seek_rtn, EXIT_LABEL]
        #else
            load_addr[__pv_seek_rtn, end#]
        #endif
#else // PV_SEEK_INIT == 0
    #if ((in_flags) & PV_SEEK_T_INDEX_ONLY)
        #define _PV_SEEK_OFFSET_MASK 0x7f
    #else
        #define _PV_SEEK_OFFSET_MASK 0x3f
    #endif

    #if (isnum((in_offset)))
       #if (((in_flags) & PV_SEEK_T_INDEX_ONLY) == 0)
            #define_eval _PV_SEEK_OFFSET (in_offset)
            #if (((in_flags) & PV_SEEK_PAD_INCLUDED) == 0)
                #define_eval _PV_SEEK_OFFSET (_PV_SEEK_OFFSET + 2)
            #endif
            alu[tibi, t_idx_ctx, OR, (_PV_SEEK_OFFSET & _PV_SEEK_OFFSET_MASK)]
            local_csr_wr[T_INDEX_BYTE_INDEX, tibi]
            #if (_PV_SEEK_OFFSET < 256)
                alu[outside, BF_A(io_vec, PV_SEEK_BASE_bf), XOR, _PV_SEEK_OFFSET]
            #else
                immed[__pv_seek_offset, _PV_SEEK_OFFSET]
                alu[outside, BF_A(io_vec, PV_SEEK_BASE_bf), XOR, __pv_seek_offset]
                #define _PV_SEEK_OFFSET __pv_seek_offset
            #endif
        #endif
    #else
        #if (((in_flags) & PV_SEEK_PAD_INCLUDED) == 0)
            alu[__pv_seek_offset, in_offset, +, 2]
            alu[tibi, __pv_seek_offset, AND, _PV_SEEK_OFFSET_MASK]
            #define _PV_SEEK_OFFSET __pv_seek_offset
        #else
            alu[tibi, in_offset, AND, _PV_SEEK_OFFSET_MASK]
            #define_eval _PV_SEEK_OFFSET in_offset
        #endif
        alu[tibi, tibi, OR, t_idx_ctx]
        local_csr_wr[T_INDEX_BYTE_INDEX, tibi]
        #if (((in_flags) & PV_SEEK_T_INDEX_ONLY) == 0)
            alu[outside, BF_A(io_vec, PV_SEEK_BASE_bf), XOR, _PV_SEEK_OFFSET]
        #endif
    #endif

    #if (((in_flags) & PV_SEEK_T_INDEX_ONLY) == 0)
        alu[--, BF_MASK(PV_SEEK_BASE_bf), AND, outside, >>BF_L(PV_SEEK_BASE_bf)]
        #if (! streq('EXIT_LABEL', '--'))
            #if (! streq('out_cache_idx', '--'))
                beq[EXIT_LABEL], defer[1]
                    alu[out_cache_idx, 0x1f, AND, tibi, >>2]
            #else
                beq[EXIT_LABEL]
            #endif
            #if (isnum(_PV_SEEK_OFFSET))
                br[PV_SEEK_SUBROUTINE#], defer[2]
                    immed[__pv_seek_offset, _PV_SEEK_OFFSET]
            #elif (! streq('_PV_SEEK_OFFSET', '__pv_seek_offset'))
                br[PV_SEEK_SUBROUTINE#], defer[2]
                    alu[__pv_seek_offset, --, B, _PV_SEEK_OFFSET]
            #else
                br[PV_SEEK_SUBROUTINE#], defer[1]
            #endif
            load_addr[__pv_seek_rtn, EXIT_LABEL]
        #else
            #if (isnum(_PV_SEEK_OFFSET))
                #if (! streq('out_cache_idx', '--'))
                    bne[PV_SEEK_SUBROUTINE#], defer[3]
                        alu[out_cache_idx, 0x1f, AND, tibi, >>2]
                #else
                    bne[PV_SEEK_SUBROUTINE#], defer[2]
                #endif
                immed[__pv_seek_offset, _PV_SEEK_OFFSET]
            #elif (! streq('_PV_SEEK_OFFSET', '__pv_seek_offset'))
                #if (! streq('out_cache_idx', '--'))
                    bne[PV_SEEK_SUBROUTINE#], defer[3]
                       alu[out_cache_idx, 0x1f, AND, tibi, >>2]
                #else
                    bne[PV_SEEK_SUBROUTINE#], defer[2]
                #endif
                alu[__pv_seek_offset, --, B, _PV_SEEK_OFFSET]
            #elif (! streq('out_cache_idx', '--'))
                bne[PV_SEEK_SUBROUTINE#], defer[2]
                    alu[out_cache_idx, 0x1f, AND, tibi, >>2]
            #else
                bne[PV_SEEK_SUBROUTINE#], defer[1]
            #endif
            load_addr[__pv_seek_rtn, end#]
        #endif
    #else // PV_SEEK_T_INDEX_ONLY
        #if (! streq('EXIT_LABEL', '--'))
            #if (! streq('out_cache_idx', '--'))
                br[EXIT_LABEL], defer[1]
                    alu[out_cache_idx, 0x1f, AND, tibi, >>2]
            #else
                br[EXIT_LABEL]
            #endif
        #else
            #if (! streq('out_cache_idx', '--'))
                alu[out_cache_idx, 0x1f, AND, tibi, >>2]
            #else
                nop
            #endif
            nop
            nop
        #endif
    #endif
    #undef _PV_SEEK_OFFSET
    #undef _PV_SEEK_OFFSET_MASK
#endif
end#:
.end
#endm


#macro pv_seek(io_vec, in_offset)
    pv_seek(--, io_vec, in_offset, 0, --)
#endm


#macro pv_seek(io_vec, in_offset, in_flags)
    pv_seek(--, io_vec, in_offset, in_flags, --)
#endm


#macro pv_seek(io_vec, in_offset, in_flags, EXIT_LABEL)
    pv_seek(--, io_vec, in_offset, in_flags, EXIT_LABEL)
#endm


#macro pv_invalidate_cache(in_pkt_vec)
    alu[BF_A(in_pkt_vec, PV_SEEK_BASE_bf), BF_A(in_pkt_vec, PV_SEEK_BASE_bf), OR, 0xff, <<BF_L(PV_SEEK_BASE_bf)]
#endm


.reg __pv_hdr_parse_args
.reg __pv_hdr_parse_rtn
#macro pv_hdr_parse_subroutine(pkt_vec)
.subroutine
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
    pv_seek(pkt_vec, pkt_offset)

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

    br_bset[__pv_hdr_parse_args, BF_L(INSTR_RX_HOST_ENCAP_bf), skip_vxlan#], defer[1]
        // don't need byte_align_be[] after seek because check_tunnel# is only done for outer header
        alu[udp_dst_port, 0, +16, *$index++]

    bitfield_extract__sz1[vxlan_idx, __pv_hdr_parse_args, BF_ML(INSTR_RX_VXLAN_NN_IDX_bf)) ; INSTR_RX_VXLAN_NN_IDX_bf
    local_csr_wr[NN_GET, vxlan_idx]
    bitfield_extract__sz1(n_vxlan, __pv_hdr_parse_args, BF_ML(INSTR_RX_PARSE_VXLANS_bf)) ; INSTR_RX_PARSE_VXLANS_bf

check_nn_vxlan#:
    alu[n_vxlan, n_vxlan, -, 1]
    bmi[check_geneve_tun#]

    alu[--, udp_dst_port, -, *n$index++]
    bne[check_nn_vxlan#]

skip_vxlan#:
    alu[pkt_offset, pkt_offset, +, (UDP_HDR_SIZE + VXLAN_SIZE + ETHERNET_SIZE)]

seek_inner#:
    alu[tmp, 0xff, AND, BF_A(pkt_vec, PV_PROTO_bf)]
    ld_field[BF_A(pkt_vec, PV_PROTO_bf), 0001, tmp, <<PROTO_ENCAP_SHF]
    alu[BF_A(pkt_vec, PV_HEADER_STACK_bf), --, B, BF_A(pkt_vec, PV_HEADER_STACK_bf), <<16]

seek_eth_type#:
    pv_seek(pkt_vec, pkt_offset, PV_SEEK_PAD_INCLUDED, check_eth_type#)

check_geneve_tun#:
    br_bclr[__pv_hdr_parse_args, BF_L(INSTR_RX_PARSE_GENEVE_bf), done#]
    immed[proto_test, NET_GENEVE_PORT]
    alu[--, udp_dst_port, -, proto_test]
    bne[done#]

    alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, (PROTO_GENEVE >> PROTO_ENCAP_SHF)]

    alu[--, --, B, *$index++] // skip over UDP Length:Checksum
    alu[hdr_len, (0x3f << 2), AND, *$index++, >>(24 - 2)] // Opt Len

    br[seek_inner#], defer[2]
        alu[pkt_offset, pkt_offset, +, hdr_len]
        alu[pkt_offset, pkt_offset, +, (UDP_HDR_SIZE + GENEVE_SIZE + ETHERNET_SIZE)]

check_ipv4_gre#:
    br!=byte[next_hdr, 0, NET_IP_PROTO_GRE, unknown_l4#]

gre#:
    br!=byte[BF_A(pkt_vec, PV_HEADER_STACK_bf), 3, 0, done#]
    br_bclr[__pv_hdr_parse_args, BF_L(INSTR_RX_PARSE_NVGRE_bf), unknown_l4#]
    pv_seek(pkt_vec, pkt_offset, PV_SEEK_T_INDEX_ONLY)
    alu[BF_A(pkt_vec, PV_PROTO_bf), BF_A(pkt_vec, PV_PROTO_bf), OR, (PROTO_GRE >> PROTO_ENCAP_SHF)]
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
    rtn[__pv_hdr_parse_rtn]
.end
.endsub
#endm


#macro pv_hdr_parse(pkt_vec, port_tun_args, RETURN_LABEL)
    br[PV_HDR_PARSE_SUBROUTINE#], defer[2]
        load_addr[__pv_hdr_parse_rtn, RETURN_LABEL]
        alu[__pv_hdr_parse_args, --, B, port_tun_args]
#endm


#macro pv_hdr_parse(pkt_vec, port_tun_args)
    pv_hdr_parse(pkt_vec, port_tun_args, end#)
end#:
#endm

#endif
