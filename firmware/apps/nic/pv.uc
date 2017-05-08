#ifndef _PACKET_VECTOR_UC
#define _PACKET_VECTOR_UC

#include <bitfields.uc>
#include <gro.uc>
#include <nfd_in.uc>
#include <nfd_out.uc>
#include <ov.uc>
#include <passert.uc>
#include <stdmac.uc>
#include <net/tcp.h>
#include <nic_basic/nic_stats.h>
#include <kernel/nfp_net_ctrl.h>

#include "pkt_buf.uc"

#include "protocols.h"

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
 *
 *  - Only 1 NBI used - NBI_COUNT == 1
 *  - Only 1 PCI used = SS == 0
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
 *       +-+---------+-------------------+-----+---------+-+-------------+
 *    3  |        Sequence Number        |  0  | Seq Ctx |0| Meta Length |
 *       +-------------------------------+---+-+---------+-+-+-------+-+-+
 *    4  |         TX Host Flags         | 0 |Seek (64B algn)|  Rsv  |C|c|
 *       +-----+-------------+---+---+---+---+---------------+-------+-+-+
 *    5  |P_STS|L4Offset (2B)|L3I|MPD|VLD|           Checksum            |
 *       +-----+---------+---+---+---+---+-----------+-------------------+
 *    6  | Ingress Queue |  Stats Addr   |     0     |   Egress Queue    |
 *       +---------------+---------------+-----------+-------------------+
 *    7  |                    Metadata Type Fields                       |
 *       +---------------------------------------------------------------+
 *
 * 0/1   - Intentional constants for efficient extraction and manipulation
 * S     - Split packet
 * A     - 1 if CTM buffer is allocated (ie. packet number and CTM address valid)
 * CBS   - CTM Buffer Size
 * BLS   - Buffer List
 * Q     - work Queue source (0 = NFD, 1 = NBI)
 * C     - Enable MAC offload of L3 checksum
 * c     - Enable MAC offload of L4 checksum
 * P_STS - Parse Status
 *         (0 = no data,
 *          1 = ESP,
 *          2 = TCP CSUM OK,
 *          3 = TCP CSUM FAIL,
 *          4 = UDP CSUM OK,
 *          5 = UDP CSUM FAIL,
 *          6 = AH,
 *          7 = FRAG)
 * L3I   - MAC L3 Information (0 = unkown, 1 = IPv6, 2 = IPv4 CSUM FAIL, 3 = IPv4 OK)
 * MPD   - MPLS Tag Depth (3 = unknown)
 * VLD   - VLAN Tag Depth (3 = unknown)
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
 */

#define PV_SIZE_LW                      8

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
#define PV_META_LENGTH_bf               PV_SEQ_wrd, 6, 0

#define PV_FLAGS_wrd                    4
#define PV_TX_FLAGS_bf                  PV_FLAGS_wrd, 31, 16
#define PV_TX_HOST_RX_BPF               PV_FLAGS_wrd, 24, 24
#define PV_TX_HOST_L3_bf                PV_FLAGS_wrd, 22, 21
#define PV_TX_HOST_IP4_bf               PV_FLAGS_wrd, 22, 22
#define PV_TX_HOST_CSUM_IP4_OK_bf       PV_FLAGS_wrd, 21, 21
#define PV_TX_HOST_L4_bf                PV_FLAGS_wrd, 20, 17
#define PV_TX_HOST_TCP_bf               PV_FLAGS_wrd, 20, 20
#define PV_TX_HOST_CSUM_TCP_OK_bf       PV_FLAGS_wrd, 19, 19
#define PV_TX_HOST_UDP_bf               PV_FLAGS_wrd, 18, 18
#define PV_TX_HOST_CSUM_UDP_OK_bf       PV_FLAGS_wrd, 17, 17
#define PV_SEEK_BASE_bf                 PV_FLAGS_wrd, 13, 6
#define PV_CSUM_OFFLOAD_bf              PV_FLAGS_wrd, 1, 0
#define PV_CSUM_OFFLOAD_L3_bf           PV_FLAGS_wrd, 1, 1
#define PV_CSUM_OFFLOAD_L4_bf           PV_FLAGS_wrd, 0, 0

#define PV_PARSE_wrd                    5
#define PV_PARSE_STS_bf                 PV_PARSE_wrd, 31, 29
#define PV_PARSE_L4_OFFSET_bf           PV_PARSE_wrd, 28, 22
#define PV_PARSE_L3I_bf                 PV_PARSE_wrd, 21, 20
#define PV_PARSE_MPD_bf                 PV_PARSE_wrd, 19, 18
#define PV_PARSE_VLD_bf                 PV_PARSE_wrd, 17, 16
#define PV_CSUM_bf                      PV_PARSE_wrd, 15, 0

#define PV_QUEUE_wrd                    6
#define PV_QUEUE_IN_bf                  PV_QUEUE_wrd, 31, 24
#define PV_QUEUE_IN_NBI_bf              PV_QUEUE_wrd, 31, 31
#define PV_STAT_bf                      PV_QUEUE_wrd, 23, 16
#define PV_QUEUE_OUT_bf                 PV_QUEUE_wrd, 9, 0

#define PV_META_TYPES_wrd               7
#define PV_META_TYPES_bf                PV_META_TYPES_wrd, 31, 0

#define_eval PV_NOT_PARSED              ((3 << BF_L(PV_PARSE_MPD_bf)) | (3 << BF_L(PV_PARSE_VLD_bf)))


#macro pv_propagate_mac_csum_status(io_vec)
.begin
    .reg shift
    .reg l3_csum_tbl
    .reg l4_csum_tbl
    .reg l3_flags
    .reg l4_flags

    immed[l4_csum_tbl, 0x238c, <<8]
    alu[shift, (7 << 2), AND, BF_A(io_vec, PV_PARSE_STS_bf), >>(BF_L(PV_PARSE_STS_bf) - 2)] ; PV_PARSE_STS_bf
    alu[l3_csum_tbl, shift, B, 0xe0]
    alu[l4_flags, 0xf, AND, l4_csum_tbl, >>indirect]
    alu[shift, (3 << 1), AND, BF_A(io_vec, PV_PARSE_L3I_bf), >>(BF_L(PV_PARSE_L3I_bf) - 1)]
    alu[--,  shift, OR, 0]
    alu[l3_flags, 0x3, AND, l3_csum_tbl, >>indirect]
    alu[BF_A(io_vec, PV_TX_HOST_L4_bf), BF_A(io_vec, PV_TX_HOST_L4_bf), OR, l4_flags, <<BF_L(PV_TX_HOST_L4_bf)]
    alu[BF_A(io_vec, PV_TX_HOST_L3_bf), BF_A(io_vec, PV_TX_HOST_L3_bf), OR, l3_flags, <<BF_L(PV_TX_HOST_L3_bf)]
.end
#endm


#macro pv_set_egress_queue(io_vec, in_queue)
    #ifdef PARANOIA
        alu[BF_A(io_vec, PV_QUEUE_OUT_bf), --, B, BF_A(io_vec, PV_QUEUE_OUT_bf), >>(BF_M(PV_QUEUE_OUT_bf) + 1)]
        alu[BF_A(io_vec, PV_QUEUE_OUT_bf), in_queue, OR, BF_A(io_vec, PV_QUEUE_OUT_bf), <<(BF_M(PV_QUEUE_OUT_bf) + 1)]
    #else
        alu[BF_A(io_vec, PV_QUEUE_OUT_bf), BF_A(io_vec, PV_QUEUE_OUT_bf), OR, in_queue]
    #endif
#endm


#macro pv_get_ingress_queue(out_queue, in_vec)
    bitfield_extract__sz1(out_queue, BF_AML(in_vec, PV_QUEUE_IN_bf))
#endm


#macro pv_get_instr_addr(out_addr, in_vec, IN_LIST_SIZE)
    passert(NIC_CFG_INSTR_TBL_ADDR, "EQ", 0)
    passert(IN_LIST_SIZE, "POWER_OF_2")
    alu[out_addr, (IN_LIST_SIZE - 1), ~AND, BF_A(in_vec, PV_QUEUE_IN_bf), >>(BF_L(PV_QUEUE_IN_bf) - log2(IN_LIST_SIZE))]
#endm


#macro pv_get_length(out_length, in_vec)
    alu[out_length, 0, +16, BF_A(in_vec, PV_LENGTH_bf)] ; PV_LENGTH_bf
    alu[out_length, out_length, AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
#endm


#macro pv_meta_push_type(io_vec, in_type)
    alu[BF_A(io_vec, PV_META_TYPES_bf), in_type, OR, BF_A(io_vec, PV_META_TYPES_bf), <<4]
#endm

#macro pv_meta_prepend(io_vec, in_metadata, in_length)
.begin
    .reg addr
    .reg meta_len
    .sig sig_meta

    alu[BF_A(io_vec, PV_META_LENGTH_bf), BF_A(io_vec, PV_META_LENGTH_bf), +, in_length]
    bitfield_extract__sz1(meta_len, BF_AML(io_vec, PV_META_LENGTH_bf))
    alu[addr, BF_A(io_vec, PV_CTM_ADDR_bf), -, meta_len]
    mem[write32, in_metadata, addr, 0, (in_length >> 2)], ctx_swap[sig_meta]
.end
#endm


#define PV_STATS_DISCARD 0
#define PV_STATS_ERROR   1
#define PV_STATS_UC      2
#define PV_STATS_MC      3
#define PV_STATS_BC      4
#define PV_STATS_TX      8
#macro pv_stats_select(io_vec, in_stats)
    alu[BF_A(io_vec, PV_STAT_bf), BF_A(io_vec, PV_STAT_bf), AND~, 0x7, <<BF_L(PV_STAT_bf)] ; PV_STAT_bf
    alu[BF_A(io_vec, PV_STAT_bf), BF_A(io_vec, PV_STAT_bf), OR, in_stats, <<BF_L(PV_STAT_bf)] ; PV_STAT_bf
#endm


#macro pv_stats_add_tx_octets(io_vec)
.begin
    .reg addr
    .reg isl
    .reg octets

    immed[isl, (_nic_stats_extra >> 24), <<16]
    alu[addr, 0xff, AND, BF_A(io_vec, PV_STAT_bf), >>BF_L(PV_STAT_bf)]
    alu[addr, --, B, addr, <<3]
    alu[octets, BF_A(io_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)]
    ov_start((OV_IMMED16 | OV_LENGTH))
    ov_set(OV_LENGTH, ((1 << 2) | (1 << 3)))
    ov_set_use(OV_IMMED16, octets) // ov_set_use() will shift IMMED16 left 16 bits, no need to mask
    ov_clean()
    mem[add64_imm, --, isl, <<8, addr, 1], indirect_ref
.end
#endm


#macro pv_stats_incr_error(io_vec)
.begin
    .reg addr
    .reg isl

    immed[isl, (_nic_stats_extra >> 24), <<16]
    alu[addr, 0xf8, AND, BF_A(io_vec, PV_STAT_bf), >>BF_L(PV_STAT_bf)]
    alu[addr, (PV_STATS_ERROR << 3), OR, addr, <<3]
    mem[incr64, --, isl, <<8, addr, 1]
.end
#endm


#macro pv_stats_incr_discard(io_vec)
.begin
    .reg addr
    .reg isl

    immed[isl, (_nic_stats_extra >> 24), <<16]
    alu[addr, 0xf8, AND, BF_A(io_vec, PV_STAT_bf), >>BF_L(PV_STAT_bf)]
    alu[addr, --, B, addr, <<3]
    mem[incr64, --, isl, <<8, addr, 1]
.end
#endm


#macro pv_check_mtu(in_vec, in_mtu, FAIL_LABEL)
.begin
    .reg max_vlan
    .reg len

    alu[len, BF_A(in_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)]
    alu[len, len, -, in_mtu]

    alu[max_vlan, (3 << 2), AND, BF_A(in_vec, PV_PARSE_VLD_bf), >>(BF_L(PV_PARSE_VLD_bf) - 2)]
    alu[len, len, -, max_vlan]

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
#macro pv_get_gro_wire_desc(out_desc, in_vec, base_queue, pms_offset)
.begin
    .reg addr_lo
    .reg ctm_buf_sz
    .reg prev_alu
    .reg queue

    #if (NBI_COUNT != 1 || SCS != 0)
        #error "RO_META_TYPE_wrd and GRO_META_NBI_ADDRHI_wrd assume nbi = 0. The latter depends on __MEID too."
    #endif

    immed[out_desc[GRO_META_TYPE_wrd], (GRO_DTYPE_IFACE | (GRO_DEST_IFACE_BASE << GRO_META_DEST_shf))] // nbi = 0
    immed[out_desc[GRO_META_NBI_ADDRHI_wrd], ((__ISLAND << 8) | (((__MEID & 1) + 2) << 4)), <<16] // nbi = 0, __MEID

    alu[addr_lo, BF_A(in_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    alu[out_desc[GRO_META_NBI_ADDRLO_wrd], addr_lo, +16, in_vec[PV_CTM_ADDR_wrd]]

    #if (is_ct_const(pms_offset))
        immed[prev_alu, ((((pms_offset >> 3) - 1) << 8) | 0xcb)]
    #else
        alu[prev_alu, --, B, pms_offset, >>3]
        alu[prev_alu, prev_alu, -, 1]
        alu[prev_alu, 0xcb, OR, prev_alu, <<8]
    #endif
    alu[queue, base_queue, +, BF_A(in_vec, PV_QUEUE_OUT_bf)]
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
#macro pv_get_gro_host_desc(out_desc, in_vec, base_queue)
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
    .reg queue
    .reg write $meta_types
    .sig sig_meta

    #if (NBI_COUNT != 1 || SS != 0)
        #error "Only targets PCIe = 0 and NFD_OUT_NBI_wrd assumes nbi = 0"
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
    alu[desc, BF_A(in_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_NUMBER_bf, PV_BLS_bf
    alu[pkt_len, 0, +16, desc]
    alu[desc, desc, -, pkt_len]
    alu[data_len, pkt_len, +, meta_len]
    alu[desc, desc, OR, GRO_DTYPE_NFD]
    alu[offset, 0, +16, BF_A(in_vec, PV_OFFSET_bf)] ; PV_OFFSET_bf
    alu[offset, offset, -, meta_len]
    alu[offset, --, B, offset, >>1]
    alu[desc, desc, OR, offset, <<GRO_META_W0_META_START_BIT]
    alu[ctm_only, 1, AND~, BF_A(in_vec, PV_SPLIT_bf), >>BF_L(PV_SPLIT_bf)] ; PV_SPLIT_bf
    alu[desc, desc, OR, ctm_only, <<NFD_OUT_CTM_ONLY_shf]
    alu[desc, desc, OR, __ISLAND, <<NFD_OUT_CTM_ISL_shf]
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[out_desc[NFD_OUT_SPLIT_wrd], desc, OR, ctm_buf_sz, <<NFD_OUT_SPLIT_shf]

    // Word 2
    alu[desc, data_len, OR, meta_len, <<NFD_OUT_METALEN_shf]
    #ifndef GRO_EVEN_NFD_OFFSETS_ONLY
       alu[desc, desc, OR, BF_A(in_vec, PV_OFFSET_bf), <<31] // meta_len is always even, this is safe
    #endif
    alu[queue, base_queue, +, BF_A(in_vec, PV_QUEUE_OUT_bf)]
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


#macro pv_get_mac_prepend(out_prepend, in_vec)
    alu[out_prepend, --, B, BF_A(in_vec, PV_CSUM_OFFLOAD_bf), <<30]
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
#macro pv_get_nbi_meta(out_nbi_meta, in_vec)
    alu[out_nbi_meta[0], BF_A(in_vec, PV_NUMBER_bf), OR, __ISLAND, <<26] ; PV_NUMBER_bf
    alu[out_nbi_meta[1], BF_A(in_vec, PV_MU_ADDR_bf), AND~, 0x3, <<29] ; PV_MU_ADDR_bf
#endm


#macro pv_get_seq_ctx(out_seq_ctx, in_vec)
    bitfield_extract__sz1(out_seq_ctx, BF_AML(in_vec, PV_SEQ_CTX_bf)) ; PV_SEQ_CTX_bf
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
 *    7  |P_STS|M|E|A|F|D|R|H|L3 |MPL|VLN|           Checksum            |
 *       +-----+-+-+-+-+-+-+-+-------------------------------------------+
 *      S -> 1 if packet is split between CTM and MU data
 *      BLS -> Buffer List
 *
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
#define CAT_L4_TYPE_bf                  CAT_PROTO_wrd, 15, 12 // 2 = UDP, 3 = TCP
#define CAT_L3_TYPE_bf                  CAT_PROTO_wrd, 11, 8 // (L3_TYPE & 0xd) => 4 = IPv4, 5 = IPv6

#define CAT_PORT_wrd                    4
#define CAT_PORT_bf                     CAT_PORT_wrd, 31, 24
#define CAT_L4_OFFSET_bf                CAT_PORT_wrd, 15, 8
#define CAT_FRAG_bf                     CAT_PORT_wrd, 7, 7

#define CAT_FLAGS_wrd                   5
#define CAT_ERRORS_bf                   CAT_FLAGS_wrd, 31, 30
#define CAT_PKT_ERROR_bf                CAT_FLAGS_wrd, 31, 31
#define CAT_IFACE_ERROR_bf              CAT_FLAGS_wrd, 30, 30
#define CAT_PKT_WARN_bf                 CAT_FLAGS_wrd, 29, 29 // IPv4 CSUM err, local src, multicast src, class E, TTL=0, IPv6 HL=0/1
#define CAT_SPECIAL_bf                  CAT_FLAGS_wrd, 28, 28 // IPv6 hop-by-hop, MPLS OAM
#define CAT_VLANS_bf                    CAT_FLAGS_wrd, 27, 26

#define MAC_TIMESTAMP_wrd               6
#define MAC_TIMESTAMP_bf                MAC_TIMESTAMP_wrd, 31, 0

#define MAC_PARSE_wrd                   7
#define MAC_PARSE_STS_bf                MAC_PARSE_wrd, 31, 29
#define MAC_PARSE_V6_OPT_bf             MAC_PARSE_wrd, 28, 22
#define MAC_PARSE_L3_bf                 MAC_PARSE_wrd, 21, 20
#define MAC_PARSE_MPLS_bf               MAC_PARSE_wrd, 19, 18
#define MAC_PARSE_VLAN_bf               MAC_PARSE_wrd, 17, 16
#define MAC_CSUM_bf                     MAC_PARSE_wrd, 15, 0

#macro pv_init_nbi(out_vec, in_nbi_desc, DROP_LABEL, FAIL_LABEL)
.begin
    .reg cbs
    .reg l4_type
    .reg l4_offset
    .reg shift

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

    // map NBI sequencers to 0, 1, 2, 3
    alu[BF_A(out_vec, PV_SEQ_NO_bf), BF_A(in_nbi_desc, CAT_SEQ_NO_bf), AND~, 0xff] ; PV_SEQ_NO_bf
    alu[BF_A(out_vec, PV_SEQ_CTX_bf), BF_A(out_vec, PV_SEQ_CTX_bf), AND~, 0xfc, <<8] ; PV_SEQ_CTX_bf

    alu[BF_A(out_vec, PV_SEEK_BASE_bf), --, B, 0xff, <<BF_L(PV_SEEK_BASE_bf)]

    alu[BF_A(out_vec, PV_PARSE_STS_bf), BF_A(in_nbi_desc, MAC_PARSE_STS_bf), AND~, BF_MASK(PV_PARSE_L4_OFFSET_bf), <<BF_L(PV_PARSE_L4_OFFSET_bf)]

    alu[l4_type, 0xe, AND, BF_A(in_nbi_desc, CAT_L4_TYPE_bf), >>BF_L(CAT_L4_TYPE_bf)]
    br=byte[l4_type, 0, 2, store_l4_offset#], defer[3] // use L4 offset if Catamaran has parsed TCP or UDP (Catamaran offset is valid)
        alu[BF_A(out_vec, PV_CTM_ADDR_bf), --, B, BF_A(out_vec, PV_NUMBER_bf), >>BF_L(PV_NUMBER_bf)] ; PV_CTM_ADDR_bf
        alu[BF_A(out_vec, PV_CTM_ADDR_bf), (PKT_NBI_OFFSET + MAC_PREPEND_BYTES), OR, BF_A(out_vec, PV_CTM_ADDR_bf), <<BF_L(PV_NUMBER_bf)]
        alu[BF_A(out_vec, PV_CTM_ADDR_bf), BF_A(out_vec, PV_CTM_ADDR_bf), OR, 1, <<BF_L(PV_CTM_ALLOCATED_bf)]

    /* Catamaran doesn't know that it sometimes has the correct offset for certain IPv6 extention headers
     * Thus, do not rely on CAT_L4_TYPE if the packet is not recognized as TCP/UDP and check the exceptions
     * individually. Fortunately, the branch above should be taken for the bulk of interesting packets, so
     * enumerating the exceptions is not unduely expensive.
     */

    // Catamaran does not have L4 offset if there are MPLS tags
    bitfield_extract__sz1(--, BF_AML(out_vec, PV_PARSE_MPD_bf))
    bne[skip_l4_offset#]

    // Catamaran does not reliably have L4 offset for nested VLAN tags
    br_bset[BF_A(out_vec, PV_PARSE_VLD_bf), BF_M(PV_PARSE_VLD_bf), skip_l4_offset#]

    // No L4 offset if L3 is unkown
    bitfield_extract__sz1(--, BF_AML(out_vec, PV_PARSE_L3I_bf))
    beq[skip_l4_offset#]

    // permit IPv6 hop-by-hop, routing and destination extention headers (Catamaran provides valid L4 offsets for these)
    alu[--, 0x78, AND, BF_A(in_nbi_desc, MAC_PARSE_V6_OPT_bf), >>BF_L(MAC_PARSE_V6_OPT_bf)] ; MAC_PARSE_V6_OPT_bf
    bne[skip_l4_offset#]

store_l4_offset#:
    alu[l4_offset, 0x7f, AND, BF_A(in_nbi_desc, CAT_L4_OFFSET_bf), >>(BF_L(CAT_L4_OFFSET_bf) + 1)]
    alu[l4_offset, l4_offset, -, (MAC_PREPEND_BYTES / 2)] // L4 offset is already divided by 2 above
    alu[BF_A(out_vec, PV_PARSE_L4_OFFSET_bf), BF_A(out_vec, PV_PARSE_L4_OFFSET_bf), OR, l4_offset, <<BF_L(PV_PARSE_L4_OFFSET_bf)]

skip_l4_offset#:
    alu[BF_A(out_vec, PV_QUEUE_IN_bf), BF_A(in_nbi_desc, CAT_PORT_bf), AND, BF_MASK(PV_QUEUE_IN_bf), <<BF_L(PV_QUEUE_IN_bf)]
    alu[BF_A(out_vec, PV_QUEUE_IN_bf), BF_A(out_vec, PV_QUEUE_IN_bf), OR, 1, <<BF_L(PV_QUEUE_IN_NBI_bf)] // NBI = 0

    // error checks after metadata is populated (will need for drop)
    #ifdef PARANOIA // should never happen, Catamaran is buggy if it does
       br_bset[BF_AL(in_nbi_desc, CAT_VALID_bf), valid#] ; CAT_VALID_bf
           fatal_error("INVALID CATAMARAN METADATA") // fatal error, can't safely drop without valid sequencer info
       valid#:
    #endif

    immed[BF_A(out_vec, PV_META_TYPES_bf), 0]

    alu[--, BF_MASK(CAT_SEQ_CTX_bf), AND, BF_A(in_nbi_desc, CAT_SEQ_CTX_bf), >>BF_L(CAT_SEQ_CTX_bf)] ; CAT_SEQ_CTX_bf
    beq[FAIL_LABEL] // drop without releasing sequence number for sequencer zero (errored packets are expected here)

    alu[--, BF_MASK(CAT_ERRORS_bf), AND, BF_A(in_nbi_desc, CAT_ERRORS_bf), >>BF_L(CAT_ERRORS_bf)] ; CAT_ERRORS_bf
    bne[DROP_LABEL] // catch any other errors we miss (these appear to have valid sequence numbers)

.end
#endm

#macro __pv_lso_fixup(io_vec, in_nfd_desc)
.begin
    .sig l3_sig

    .reg read $l4_hdr[4] //Whether TCP or UDP we only need the first 4 LW's
    .xfer_order $l4_hdr
    .sig l4_sig1_rd, l4_sig1_wr, l4_sig2_wr

    .reg write $l3_hdr_flush
    .reg write $l4_hdr_flush1, $l4_hdr_flush2

    .reg pkt_len
    .reg l3_off, l4_off
    .reg mss, tmp
    .reg lso_seq
    .reg tcp_seq_add
    .reg tcp_flags_mask, tcp_flags_wrd

//Always assume TCP header is present
tcp#:
    bitfield_extract__sz1(lso_seq, BF_AML(in_nfd_desc, NFD_IN_LSO_SEQ_CNT_fld))
    bitfield_extract__sz1(l4_off, BF_AML(in_nfd_desc, NFD_IN_LSO2_L4_OFFS_fld)) ; NFD_IN_LSO2_L4_OFFS_fld

    mem[read32, $l4_hdr[0], BF_A(io_vec, PV_CTM_ADDR_bf), l4_off, 4], ctx_swap[l4_sig1_rd], defer[2]
        alu_shf[mss, --, b, BF_A(in_nfd_desc, NFD_IN_LSO_MSS_fld), <<(31 - BF_M(NFD_IN_LSO_MSS_fld))]; NFD_IN_LSO_MSS_fld
        alu_shf[mss, --, b, mss, >>(31 - BF_M(NFD_IN_LSO_MSS_fld))]; NFD_IN_LSO_MSS_fld

   /* Setup TCP sequence number
       TCP_SEQ_bf += (mss * (lso_seq - 1))*/
    alu[lso_seq, lso_seq, -, 1]
    multiply32(tcp_seq_add, mss, lso_seq, OP_SIZE_8X24)// Multiplier is 8 bits, multiplicand is 24 bits (8x24)

    alu[$l4_hdr_flush1, $l4_hdr[BF_W(TCP_SEQ_bf)], +, tcp_seq_add]

    alu[l4_off, l4_off, +, TCP_SEQ_OFFS]

    mem[write32, $l4_hdr_flush1, BF_A(io_vec, PV_CTM_ADDR_bf), l4_off, 1], sig_done[l4_sig1_wr]

    /* Setup TCP flags
        .if (BIT(in_nfd_lso_wrd, BF_L(NFD_IN_LSO_END_fld)))
            tcp_flags_mask = 0xffffffff
        .else
            tcp_flags_mask = ~(NET_TCP_FLAG_FIN | NET_TCP_FLAG_RST | NET_TCP_FLAG_PSH)
        .endif
        TCP_FLAGS_bf = TCP_FLAGS_bf & tcp_flags_mask
     */
    /* TCP stores data offset and flags and in the same 16 bit word
       Flags are bits 8 to 0. Set to all F's to preserve upper bits */

    br_bset[BF_AL(in_nfd_desc, NFD_IN_LSO_END_fld),tcp_flags_fix_done#], defer[1]
        alu[tcp_flags_mask, --, ~b, 0]

    alu[tcp_flags_mask, tcp_flags_mask, and~, (NET_TCP_FLAG_FIN | NET_TCP_FLAG_RST | NET_TCP_FLAG_PSH), <<16]
tcp_flags_fix_done#:

    alu[$l4_hdr_flush2, BF_A($l4_hdr, TCP_FLAGS_bf), and, tcp_flags_mask]

    alu[l4_off, l4_off, +, (TCP_FLAGS_OFFS - TCP_SEQ_OFFS)]

    mem[write8, $l4_hdr_flush2, BF_A(io_vec, PV_CTM_ADDR_bf), l4_off, 2], sig_done[l4_sig2_wr]

    //Make sure L4 CSUM is calculated
    alu[BF_A(io_vec, PV_CSUM_OFFLOAD_L4_bf), BF_A(io_vec, PV_CSUM_OFFLOAD_L4_bf), OR, 1, <<BF_L(PV_CSUM_OFFLOAD_L4_bf)]

    bitfield_extract__sz1(l3_off, BF_AML(in_nfd_desc, NFD_IN_LSO2_L3_OFFS_fld)) ; NFD_IN_LSO2_L3_OFFS_fld

    alu[pkt_len, --, b, BF_A(io_vec, PV_LENGTH_bf), <<(31 - BF_M(PV_LENGTH_bf))] ; PV_LENGTH_bf

    br_bclr[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_IPV4_CSUM_fld), ipv6#], defer[3]
        /* Setup IPv4/IPv6 length field
        length = pkt_len - l3_off */
        alu[pkt_len, --, b, pkt_len, >>(31 - BF_M(PV_LENGTH_bf))] ; PV_LENGTH_bf
        alu[tmp, pkt_len, -, l3_off]
        alu[$l3_hdr_flush, --, b, tmp, <<16]

ipv4#:
    // Make sure IPv4 header CSUM is calculated
    alu[BF_A(io_vec, PV_CSUM_OFFLOAD_L3_bf), BF_A(io_vec, PV_CSUM_OFFLOAD_L3_bf), OR, 1, <<BF_L(PV_CSUM_OFFLOAD_L3_bf)]

    br[l3_wr#], defer [1]
        alu[l3_off, l3_off, +, IPV4_LEN_OFFS]

ipv6#:
    alu[l3_off, l3_off, +, IPV6_PAYLOAD_OFFS]

l3_wr#:
    //Issue L3 header write
    mem[write8, $l3_hdr_flush, BF_A(io_vec, PV_CTM_ADDR_bf), l3_off, 2], sig_done[l3_sig]
    ctx_arb[l3_sig, l4_sig1_wr, l4_sig2_wr]

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

#macro pv_init_nfd(out_vec, in_pkt_num, in_nfd_desc, FAIL_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg meta_len
    .reg pkt_num
    .reg pkt_len
    .reg seq_ctx
    .reg seq_no
    .reg split
    .reg udp_csum

    bitfield_extract__sz1(pkt_len, BF_AML(in_nfd_desc, NFD_IN_DATALEN_fld)) ; NFD_IN_DATALEN_fld
    bitfield_extract__sz1(meta_len, BF_AML(in_nfd_desc, NFD_IN_OFFSET_fld)) ; NFD_IN_OFFSET_fld
    alu[pkt_len, pkt_len, -, meta_len]

    alu[BF_A(out_vec, PV_NUMBER_bf), pkt_len, OR, in_pkt_num, <<BF_L(PV_NUMBER_bf)]
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

    // map NFD queues to sequencers 4, 5
    alu[BF_A(out_vec, PV_SEQ_NO_bf), BF_A(in_nfd_desc, NFD_IN_SEQN_fld), AND~, 0xfe] ; PV_SEQ_NO_bf
    alu[BF_A(out_vec, PV_SEQ_CTX_bf), BF_A(out_vec, PV_SEQ_CTX_bf), +, 4] ; PV_SEQ_CTX_bf
    alu[BF_A(out_vec, PV_SEQ_CTX_bf), --, B, BF_A(out_vec, PV_SEQ_CTX_bf), <<BF_L(PV_SEQ_CTX_bf)] ; PV_SEQ_CTX_bf
    alu[BF_A(out_vec, PV_META_LENGTH_bf), BF_A(out_vec, PV_META_LENGTH_bf), OR, meta_len] ; PV_META_LENGTH_bf

    alu[BF_A(out_vec, PV_CSUM_OFFLOAD_bf), BF_MASK(PV_CSUM_OFFLOAD_bf), AND, \
        BF_A(in_nfd_desc, NFD_IN_FLAGS_TX_TCP_CSUM_fld), >>BF_L(NFD_IN_FLAGS_TX_TCP_CSUM_fld)]
    bitfield_extract__sz1(udp_csum, BF_AML(in_nfd_desc, NFD_IN_FLAGS_TX_UDP_CSUM_fld)) ; NFD_IN_FLAGS_TX_UDP_CSUM_fld
    alu[BF_A(out_vec, PV_CSUM_OFFLOAD_bf), BF_A(out_vec, PV_CSUM_OFFLOAD_bf), OR, udp_csum] ; PV_CSUM_OFFLOAD_bf

    // error checks near end to ensure consistent metadata (fields written below excluded) and buffer allocation
    // state (contents of CTM also excluded) in drop path
    br_bset[BF_AL(in_nfd_desc, NFD_IN_INVALID_fld), FAIL_LABEL]

    pkt_buf_copy_mu_head_to_ctm(in_pkt_num, BF_A(out_vec, PV_MU_ADDR_bf), NFD_IN_DATA_OFFSET, 1)

    br_bclr[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_LSO_fld), skip_lso#], defer[3]
        alu[BF_A(out_vec, PV_SEEK_BASE_bf), BF_A(out_vec, PV_SEEK_BASE_bf), OR, 0xff, <<BF_L(PV_SEEK_BASE_bf)] ; PV_SEEK_BASE_bf
        immed[BF_A(out_vec, PV_PARSE_STS_bf), (PV_NOT_PARSED >> 16), <<16] ; PV_PARSE_STS_bf
        alu[BF_A(out_vec, PV_QUEUE_IN_bf), --, B, BF_A(in_nfd_desc, NFD_IN_QID_fld), <<BF_L(PV_QUEUE_IN_bf)]

    __pv_lso_fixup(out_vec, in_nfd_desc)
skip_lso#:

    immed[BF_A(out_vec, PV_META_TYPES_bf), 0]

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
        bitfield_extract__sz1(mu_addr, BF_AML(in_pkt_vec, PV_MU_ADDR_bf)) ; PV_MU_ADDR_bf

    alu[--, --, B, BF_A(in_pkt_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]
    beq[skip_mu_buffer#]
    pkt_buf_free_mu_buffer(bls, mu_addr)
skip_mu_buffer#:

    br_bclr[BF_AL(in_pkt_vec, PV_CTM_ALLOCATED_bf), skip_ctm_buffer#]
    alu[pkt_num, --, B, BF_A(in_pkt_vec, PV_NUMBER_bf), >>BF_L(PV_NUMBER_bf)] ; PV_NUMBER_bf
    pkt_buf_free_ctm_buffer(pkt_num)
skip_ctm_buffer#:

.end
#endm


#macro pv_acquire_nfd_credit(in_pkt_vec, in_queue_base, FAIL_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo

    .reg read $nfd_credits
    .sig sig_nfd_credit

    alu[addr_hi, --, B, (NFD_PCIE_ISL_BASE | __NFD_DIRECT_ACCESS), <<24] // PCIe = 0
    alu[addr_lo, BF_A(in_pkt_vec, PV_QUEUE_OUT_bf), AND, 0x3f]
    alu[addr_lo, addr_lo, +, in_queue_base]
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

.reg volatile read $__pv_pkt_data[32]
.addr $__pv_pkt_data[0] 0
.xfer_order $__pv_pkt_data
#macro pv_seek(out_cache_idx, io_vec, in_offset, in_length, in_flags)
.begin
    .reg tibi

#if (((in_flags) & PV_SEEK_T_INDEX_ONLY) != 0)
    alu[tibi, t_idx_ctx, +8, in_offset]
    local_csr_wr[T_INDEX_BYTE_INDEX, tibi]
    nop
    nop
    nop
#else
    .reg outside
    .reg pkt_off_aligned
    .sig sig_ctm

    alu[tibi, t_idx_ctx, +8, in_offset]
    br[check#], defer[2]
        local_csr_wr[T_INDEX_BYTE_INDEX, tibi]
        alu[outside, BF_A(io_vec, PV_SEEK_BASE_bf), XOR, in_offset]

#if (((in_flags) & PV_SEEK_CTM_ONLY) == 0)
    .reg buf_offset
    .reg cbs
    .reg data_ref
    .reg mu_addr
    .reg offset_wrd
    .reg shift
    .reg sig_mask
    .reg split_wrd
    .reg read_size
    .reg words_read
    .sig sig_mu

split#:
    // determine the split offset based on CTM buffer size
    bitfield_extract__sz1(cbs, BF_AML(io_vec, PV_CBS_bf))
    alu[shift, cbs, +, (8 - 2)] // will do calculations on word offsets
    alu[words_read, shift, B, 0] // also init number of words read
    alu[split_wrd, --, B, 1, <<indirect]

    alu[buf_offset, pkt_off_aligned, +16, BF_A(io_vec, PV_OFFSET_bf)]
    alu[offset_wrd, --, B, buf_offset, >>2]
    alu[read_size, split_wrd, -, offset_wrd]
    ble[read_mu#], defer[1]
        immed[sig_mask, 0]

    alu[--, 32, -, read_size]
    bgt[read_ctm#] // branch only taken if read straddles CTM and MU

    immed[read_size, 32]

read_ctm#:
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, read_size, OVF_SUBTRACT_ONE)
    ov_clean()
    mem[read32, $__pv_pkt_data[0], BF_A(io_vec, PV_CTM_ADDR_bf), <<8, pkt_off_aligned, max_32], indirect_ref, sig_done[sig_ctm]

    br!=byte[read_size, 0, 32, straddle#] // branch only taken if read straddles CTM and MU

    ctx_arb[sig_ctm]
    local_csr_wr[T_INDEX_BYTE_INDEX, tibi] // reload T_INDEX after ctx_swap[]
    br[end#], defer[2]
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), AND~, BF_MASK(PV_SEEK_BASE_bf), <<BF_L(PV_SEEK_BASE_bf)]
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), OR, pkt_off_aligned]

straddle#:
    alu[sig_mask, sig_mask, OR, mask(sig_ctm), <<&sig_ctm]
    alu[words_read, words_read, +, read_size]

read_mu#:
    alu[read_size, (32 - 1), -, words_read] // subtract one for OV_LENGTH
    alu[data_ref, t_idx_ctx, +, words_read]

    alu[mu_addr, --, B, BF_A(io_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]

    ov_start((OV_LENGTH | OV_DATA_REF))
    ov_set(OV_DATA_REF, data_ref)
    ov_set_use(OV_LENGTH, read_size)
    ov_clean()
    mem[read32, $__pv_pkt_data[0], mu_addr, <<8, buf_offset, max_32], indirect_ref, sig_done[sig_mu]

    ctx_arb[--], defer[2]
    .io_completed sig_ctm, sig_mu
        alu[sig_mask, sig_mask, OR, mask(sig_mu), <<&sig_mu]
        local_csr_wr[ACTIVE_CTX_WAKEUP_EVENTS, sig_mask]

    local_csr_wr[T_INDEX_BYTE_INDEX, tibi] // reload T_INDEX after ctx_swap[]
    br[end#], defer[2]
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), AND~, BF_MASK(PV_SEEK_BASE_bf), <<BF_L(PV_SEEK_BASE_bf)]
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), OR, pkt_off_aligned]

#endif // ((in_flags) & PV_SEEK_CTM_ONLY) == 0

read#:
    // if a length request is received, check if it can be satisfied by cached data
    #if (! streq('in_length', '--'))
        .reg balance
        immed[balance, 256]
        alu[balance, balance, -, tibi]
        alu[--, balance, -, in_length]
        bpl[end#]
    #endif

    #if (isnum(in_offset))
        immed[pkt_off_aligned, (in_offset & 0xffc0)]
    #else
        alu[pkt_off_aligned, in_offset, AND~, 0x3f]
    #endif

    #if (((in_flags) & PV_SEEK_CTM_ONLY) == 0)
        br_bset[BF_AL(io_vec, PV_SPLIT_bf), split#]
    #endif

    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 32, OVF_SUBTRACT_ONE)
    ov_clean()
    mem[read32, $__pv_pkt_data[0], BF_A(io_vec, PV_CTM_ADDR_bf), pkt_off_aligned, max_32], indirect_ref, ctx_swap[sig_ctm]

    local_csr_wr[T_INDEX_BYTE_INDEX, tibi] // reload T_INDEX after ctx_swap[]
    br[end#], defer[2]
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), AND~, BF_MASK(PV_SEEK_BASE_bf), <<BF_L(PV_SEEK_BASE_bf)]
        alu[BF_A(io_vec, PV_SEEK_BASE_bf), BF_A(io_vec, PV_SEEK_BASE_bf), OR, pkt_off_aligned]

check#:
    #if (! streq('out_cache_idx', '--'))
        alu[out_cache_idx, 0x1f, AND, tibi, >>2]
    #endif
    alu[outside, BF_MASK(PV_SEEK_BASE_bf), AND, outside, >>BF_L(PV_SEEK_BASE_bf)]
    bne[read#]

end#:
#endif // ((in_flags) & PV_SEEK_T_INDEX_ONLY) == 0
.end
#endm


#macro pv_seek(io_vec, in_offset)
    pv_seek(--, io_vec, in_offset, --, 0)
#endm


#macro pv_seek(io_vec, in_offset, in_flags)
    pv_seek(--, io_vec, in_offset, --, in_flags)
#endm


#macro pv_seek(io_vec, in_offset, in_length, in_flags)
    pv_seek(--, io_vec, in_offset, in_length, in_flags)
#endm

#endif
