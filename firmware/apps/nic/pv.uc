#ifndef _PACKET_VECTOR_UC
#define _PACKET_VECTOR_UC

#include <bitfields.uc>
#include <gro.uc>
#include <nfd_in.uc>
#include <nfd_out.uc>

#include "pkt_buf.uc"

#define BF_MASK(w, m, l) ((1 << (m + 1 - l)) - 1)

#define NBI_IN_META_SIZE_LW 6

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
 *       +-+-----------------------------+-----+---------+-+-------------+
 *    3  |        Sequence Number        |  0  | Seq Ctx |0| Meta Length |
 *       +-------------------------------+-----+---------+-+---------+-+-+
 *    4  |         TX Host Flags         | T_INDEX Seek  |Q|   Res   |3|4|
 *       +-----+-------------+---+---+---+---------------+-+---------+-+-+
 *    5  |P_STS|  Reserved   |L3I|MPD|VLD|           Checksum            |
 *       +-----+-------------+---+---+---+-------------------------------+
 *
 * 0/1   - Intentional constants for efficient extraction and manipulation
 * S     - Split packet
 * A     - 1 if CTM buffer is allocated (ie. packet number and CTM address valid)
 * CBS   - CTM Buffer Size 
 * BLS   - Buffer List
 * Q     - work Queue source (0 = NFD, 1 = NBI)
 * 3     - Enable offload of L3 checksum
 * 4     - Enable offload of L2 checksum
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

#define PV_SIZE_LW                      6

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
#define PV_HOST_META_LENGTH_bf          PV_SEQ_wrd, 6, 0

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
#define PV_WORK_QUEUE_bf                PV_FLAGS_wrd, 7, 7
#define PV_CSUM_OFFLOAD_bf              PV_FLAGS_wrd, 1, 0 
#define PV_CSUM_OFFLOAD_L3_bf           PV_FLAGS_wrd, 1, 1
#define PV_CSUM_OFFLOAD_L4_bf           PV_FLAGS_wrd, 0, 0

#define PV_PARSE_wrd                    5
#define PV_PARSE_STS_bf                 PV_PARSE_wrd, 31, 29
#define PV_PARSE_RESV_bf                PV_PARSE_wrd, 28, 22
#define PV_PARSE_L3I_bf                 PV_PARSE_wrd, 21, 20
#define PV_PARSE_MPD_bf                 PV_PARSE_wrd, 19, 18
#define PV_PARSE_VLD_bf                 PV_PARSE_wrd, 17, 16
#define PV_CSUM_bf                      PV_PARSE_wrd, 15, 0

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
#macro pv_get_gro_wire_desc(out_desc, in_vec, queue, pms_offset)
.begin
    .reg addr_lo
    .reg ctm_buf_sz
    .reg prev_alu 
    
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
#macro pv_get_gro_host_desc(out_desc, in_vec, in_queue)
.begin
    .reg buf_list
    .reg ctm_buf_sz
    .reg ctm_only
    .reg desc
    .reg offset
    .reg pkt_len
    .reg pkt_num

    #if (NBI_COUNT != 1 || SS != 0)
        #error "Only targets PCIe = 0 and NFD_OUT_NBI_wrd assumes nbi = 0"
    #endif

    // Word 0
    alu[desc, BF_A(in_vec, PV_NUMBER_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] ; PV_NUMBER_bf, PV_BLS_bf
    alu[pkt_len, 0, +16, desc]
    alu[desc, desc, -, pkt_len]
    alu[desc, desc, OR, GRO_DTYPE_NFD]
    alu[offset, 0x7f, AND, BF_A(in_vec, PV_OFFSET_bf), >>1] ; PV_OFFSET_bf
    alu[desc, desc, OR, offset, <<GRO_META_W0_META_START_BIT]
    alu[ctm_only, 1, AND~, BF_A(in_vec, PV_SPLIT_bf), >>BF_L(PV_SPLIT_bf)] ; PV_SPLIT_bf
    alu[desc, desc, OR, ctm_only, <<NFD_OUT_CTM_ONLY_shf]
    alu[desc, desc, OR, __ISLAND, <<NFD_OUT_CTM_ISL_shf]
    bitfield_extract__sz1(ctm_buf_sz, BF_AML(in_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[out_desc[NFD_OUT_SPLIT_wrd], desc, OR, ctm_buf_sz, <<NFD_OUT_SPLIT_shf]

    // Word 1
    alu[desc, BF_A(in_vec, PV_MU_ADDR_bf), AND~, ((BF_MASK(PV_SPLIT_bf) << BF_WIDTH(PV_CBS_bf)) | BF_MASK(PV_CBS_bf)), <<BF_L(PV_CBS_bf)]
    bitfield_extract__sz1(buf_list, BF_AML(in_vec, PV_BLS_bf)) ; PV_BLS_bf
    alu[out_desc[NFD_OUT_BLS_wrd], desc, OR, buf_list, <<NFD_OUT_BLS_shf]

    // Word 2 
    alu[desc, pkt_len, OR, BF_A(in_vec, PV_HOST_META_LENGTH_bf), <<NFD_OUT_METALEN_shf]
    #ifndef GRO_EVEN_NFD_OFFSETS_ONLY
       alu[desc, desc, OR, BF_A(in_vec, PV_OFFSET_bf), <<31]
    #endif
    alu[out_desc[NFD_OUT_QID_wrd], desc, OR, in_queue, <<NFD_OUT_QID_shf]
   
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
 *    4  |     Port      |    HP-Off1    |    HP-Off0    |     Misc      |
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
#define CAT_L4_TYPE_bf                  CAT_PROTO_wrd, 15, 12 // (L3_TYPE & 0x3) => 2 = UDP, 3 = TCP
#define CAT_L3_TYPE_bf                  CAT_PROTO_wrd, 11, 8 // (L3_TYPE & 0xd) => 4 = IPv4, 5 = IPv6

#define CAT_PORT_wrd                    4
#define CAT_PORT_bf                     CAT_PORT_wrd, 31, 24
#define CAT_L4_OFF_bf                   CAT_PORT_wrd, 15, 8

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

#macro __pv_rx_nbi(io_vec, in_nbi_desc, FAIL_LABEL)
.begin
    .reg cbs
    .reg shift

    alu[BF_A(io_vec, PV_LENGTH_bf), BF_A(in_nbi_desc, CAT_CTM_NUM_bf), AND~, BF_MASK(CAT_CTM_NUM_bf), <<BF_L(CAT_CTM_NUM_bf)] 
    alu[BF_A(io_vec, PV_LENGTH_bf), BF_A(io_vec, PV_LENGTH_bf), -, MAC_PREPEND_BYTES]
  
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
    alu[cbs, BF_A(io_vec, PV_LENGTH_bf), AND~, BF_MASK(PV_BLS_bf), <<BF_L(PV_BLS_bf)] // must mask out BLS before add
    alu[cbs, (PKT_NBI_OFFSET + MAC_PREPEND_BYTES - 1), +16, cbs] ; PV_LENGTH_bf
    alu[--, --, B, cbs, >>10] 
    bne[max_cbs#], defer[3]
        alu[BF_A(io_vec, PV_MU_ADDR_bf), BF_A(in_nbi_desc, CAT_MUPTR_bf), AND~, 0x3, <<BF_L(PV_CBS_bf)]
        alu[shift, (3 << 1), AND, cbs, >>(8 - 1)]
        alu[cbs, shift, B, 3]
    alu[cbs, cbs, AND, ((2 << 6) | (2 << 4) | (1 << 2) | (0 << 0)), >>indirect]
max_cbs#:
    alu[BF_A(io_vec, PV_MU_ADDR_bf), BF_A(io_vec, PV_MU_ADDR_bf), OR, cbs, <<BF_L(PV_CBS_bf)]

    // map NBI sequencers to 0, 1, 2, 3
    alu[BF_A(io_vec, PV_SEQ_NO_bf), BF_A(in_nbi_desc, CAT_SEQ_NO_bf), AND~, 0xff] ; PV_SEQ_NO_bf
    alu[BF_A(io_vec, PV_SEQ_CTX_bf), BF_A(io_vec, PV_SEQ_CTX_bf), AND~, 0xfc, <<8] ; PV_SEQ_CTX_bf

    alu[BF_A(io_vec, PV_CTM_ADDR_bf), --, B, BF_A(io_vec, PV_NUMBER_bf), >>BF_L(PV_NUMBER_bf)] ; PV_CTM_ADDR_bf
    alu[BF_A(io_vec, PV_CTM_ADDR_bf), (PKT_NBI_OFFSET + MAC_PREPEND_BYTES), OR, BF_A(io_vec, PV_CTM_ADDR_bf), <<BF_L(PV_NUMBER_bf)]
    alu[BF_A(io_vec, PV_CTM_ADDR_bf), BF_A(io_vec, PV_CTM_ADDR_bf), OR, 1, <<BF_L(PV_CTM_ALLOCATED_bf)]

    immed[BF_A(io_vec, PV_WORK_QUEUE_bf), (1 << BF_L(PV_WORK_QUEUE_bf))]

    alu[BF_A(io_vec, PV_PARSE_STS_bf), BF_A(in_nbi_desc, MAC_PARSE_STS_bf), AND~, BF_MASK(PV_PARSE_RESV_bf), <<BF_L(PV_PARSE_RESV_bf)]

    // error checks after metadata is populated (will need for drop)
    #ifdef PARANOIA // should never happen, Catamaran is buggy if it does
       br_bset[BF_AL(in_nbi_desc, CAT_VALID_bf), valid#] ; CAT_VALID_bf
           local_csr_wr[MAILBOX_0, 0xfe] // fatal error, can't safely drop without valid sequencer info
           ctx_arb[bpt]
       valid#:
    #endif
    alu[--, BF_MASK(CAT_ERRORS_bf), AND, BF_A(in_nbi_desc, CAT_ERRORS_bf), >>BF_L(CAT_ERRORS_bf)] ; CAT_ERRORS_bf
    bne[FAIL_LABEL]

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
#macro __pv_rx_nfd(io_vec, out_pkt_len, in_pkt_num, in_nfd_desc, FAIL_LABEL)
.begin
    .reg meta_len
    .reg pkt_num
    .reg seq_ctx
    .reg seq_no
    .reg split
    .reg udp_csum
    
    bitfield_extract__sz1(out_pkt_len, BF_AML(in_nfd_desc, NFD_IN_DATALEN_fld)) ; NFD_IN_DATALEN_fld
    bitfield_extract__sz1(meta_len, BF_AML(in_nfd_desc, NFD_IN_OFFSET_fld)) ; NFD_IN_OFFSET_fld
    alu[out_pkt_len, out_pkt_len, -, meta_len]

    alu[BF_A(io_vec, PV_NUMBER_bf), out_pkt_len, OR, in_pkt_num, <<BF_L(PV_NUMBER_bf)]
    #if (NFD_IN_BLM_JUMBO_BLS == NFD_IN_BLM_REG_BLS)
        alu[BF_A(io_vec, PV_BLS_bf), BF_A(io_vec, PV_BLS_bf), OR, NFD_IN_BLM_REG_BLS, <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    #else
        .reg bls
        br_bset[BF_AL(in_nfd_desc, NFD_IN_JUMBO_fld), jumbo#], defer[1]
            immed[bls, NFD_IN_BLM_JUMBO_BLS]
        immed[bls, NFD_IN_BLM_REG_BLS]
    jumbo#:
        alu[BF_A(io_vec, PV_BLS_bf), BF_A(io_vec, PV_BLS_bf), OR, bls, <<BF_L(PV_BLS_bf)] ; PV_BLS_bf
    #endif

    // Assume CBS = 0
    alu[BF_A(io_vec, PV_MU_ADDR_bf), BF_A(in_nfd_desc, NFD_IN_BUFADDR_fld), AND~, 0x7, <<(BF_M(PV_MU_ADDR_bf) + 1)] 
    alu[split, (256 - NFD_IN_DATA_OFFSET + 1), -, out_pkt_len] 
    alu[split, split, +carry, out_pkt_len]
    alu[BF_A(io_vec, PV_SPLIT_bf), BF_A(io_vec, PV_SPLIT_bf), OR, split, <<BF_L(PV_SPLIT_bf)] ; PV_SPLIT_bf

    alu[BF_A(io_vec, PV_CTM_ADDR_bf), NFD_IN_DATA_OFFSET, OR, in_pkt_num, <<BF_L(PV_NUMBER_bf)]
    alu[BF_A(io_vec, PV_CTM_ADDR_bf), BF_A(io_vec, PV_CTM_ADDR_bf), OR, 1, <<BF_L(PV_CTM_ALLOCATED_bf)]

    // map NFD queues to sequencers 4, 5, 6, 7
    alu[BF_A(io_vec, PV_SEQ_NO_bf), BF_A(in_nfd_desc, NFD_IN_SEQN_fld), AND~, 0xfe] ; PV_SEQ_NO_bf
    alu[BF_A(io_vec, PV_SEQ_CTX_bf), BF_A(io_vec, PV_SEQ_CTX_bf), +, 4] ; PV_SEQ_CTX_bf
    alu[BF_A(io_vec, PV_SEQ_CTX_bf), --, B, BF_A(io_vec, PV_SEQ_CTX_bf), <<BF_L(PV_SEQ_CTX_bf)] ; PV_SEQ_CTX_bf
    alu[BF_A(io_vec, PV_HOST_META_LENGTH_bf), BF_A(io_vec, PV_HOST_META_LENGTH_bf), OR, meta_len] ; PV_HOST_META_LENGTH_bf

    alu[BF_A(io_vec, PV_CSUM_OFFLOAD_bf), BF_MASK(PV_CSUM_OFFLOAD_bf), AND, \
        BF_A(in_nfd_desc, NFD_IN_FLAGS_TX_TCP_CSUM_fld), >>BF_L(NFD_IN_FLAGS_TX_TCP_CSUM_fld)] // WORK_QUEUE = 0
    bitfield_extract__sz1(udp_csum, BF_AML(in_nfd_desc, NFD_IN_FLAGS_TX_UDP_CSUM_fld)) ; NFD_IN_FLAGS_TX_UDP_CSUM_fld
    alu[BF_A(io_vec, PV_CSUM_OFFLOAD_bf), BF_A(io_vec, PV_CSUM_OFFLOAD_bf), OR, udp_csum] ; PV_CSUM_OFFLOAD_bf
   
    immed[BF_A(io_vec, PV_PARSE_STS_bf), (PV_NOT_PARSED >> 16), <<16] ; PV_PARSE_STS_bf

    // error checks last to ensure consistent metadata and buffer allocation state in drop path
    br_bset[BF_AL(in_nfd_desc, NFD_IN_INVALID_fld), FAIL_LABEL]

    pkt_buf_copy_mu_head_to_ctm(in_pkt_num, BF_A(io_vec, PV_MU_ADDR_bf), NFD_IN_DATA_OFFSET, 1)

    // TODO: LSO fixups
    br_bset[BF_AL(in_nfd_desc, NFD_IN_FLAGS_TX_LSO_fld), FAIL_LABEL]
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

    alu[--, --, B, BF_A(in_pkt_vec, PV_MU_ADDR_bf), <<(31-BF_M(PV_MU_ADDR_bf))]
    beq[skip_mu_buffer#]
    pkt_buf_free_mu_buffer(bls, mu_addr)
skip_mu_buffer#:

    br_bclr[BF_AL(in_pkt_vec, PV_CTM_ALLOCATED_bf), skip_ctm_buffer#]
    alu[pkt_num, --, B, BF_A(in_pkt_vec, PV_NUMBER_bf), >>BF_L(PV_NUMBER_bf)] ; PV_NUMBER_bf
    pkt_buf_free_ctm_buffer(pkt_num)
skip_ctm_buffer#:

.end
#endm


.sig volatile __pv_sig_nbi
.reg volatile read $__pv_nbi_desc[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $__pv_nbi_desc
#macro __pv_dispatch_nbi()
.begin
    .reg addr
    immed[addr, (PKT_NBI_OFFSET / 4)]
    mem[packet_add_thread, $__pv_nbi_desc[0], addr, 0, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], sig_done[__pv_sig_nbi]
.end
#endm


.reg volatile __pv_nfd_pkt_no
.sig volatile __pv_sig_nfd
.sig volatile __pv_sig_nfd_retry_dispatch
.set_sig __pv_sig_nfd_retry_dispatch
.reg volatile read $__pv_nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $__pv_nfd_desc

#macro __pv_nfd_dispatch_no_packet()
.begin
    .reg future
    .reg big
    local_csr_wr[ACTIVE_FUTURE_COUNT_SIGNAL, &__pv_sig_nfd_retry_dispatch]
    local_csr_rd[TIMESTAMP_LOW]
    immed[future, 0]
    alu[future, future, +, 8] // 128 cycles
    local_csr_wr[ACTIVE_CTX_FUTURE_COUNT, future]
    alu[__pv_nfd_pkt_no, --, B, 1, <<31]
 .end
#endm


#macro __pv_dispatch_nfd()
.begin
    pkt_buf_alloc_ctm(__pv_nfd_pkt_no, PKT_BUF_ALLOC_CTM_SZ_256B, skip_dispatch#, __pv_nfd_dispatch_no_packet) 
    nfd_in_recv($__pv_nfd_desc, 0, 0, 0, __pv_sig_nfd, SIG_DONE)
skip_dispatch#:
.end
#endm


#macro pv_init(out_vec) 
.begin
    alu[BF_A(out_vec, PV_WORK_QUEUE_bf), --, B, 0]
    __pv_dispatch_nbi()
.end
#endm


#macro pv_listen(out_vec, out_ingress_queue, FAIL_LABEL)
.begin
    .reg pkt_len

    br_bclr[BF_AL(out_vec, PV_WORK_QUEUE_bf), nfd_dispatch#]
    
    // previously processed packet was from NBI
    __pv_dispatch_nbi()  
    
listen_with_nfd_priority#:
    br_signal[__pv_sig_nfd_retry_dispatch, nfd_dispatch#]
    br_signal[__pv_sig_nfd, rx_nfd#]
    br_signal[__pv_sig_nbi, rx_nbi#]
    ctx_arb[__pv_sig_nbi, __pv_sig_nfd, __pv_sig_nfd_retry_dispatch], any, br[listen_with_nfd_priority#]

nfd_dispatch#:
    // previously processed packet was from NFD
    __pv_dispatch_nfd()

listen_with_nbi_priority#:
    br_signal[__pv_sig_nfd_retry_dispatch, nfd_dispatch#]
    br_signal[__pv_sig_nbi, rx_nbi#]
    br_signal[__pv_sig_nfd, rx_nfd#]
    ctx_arb[__pv_sig_nbi, __pv_sig_nfd, __pv_sig_nfd_retry_dispatch], any, br[listen_with_nbi_priority#]

rx_nbi#:
    __pv_rx_nbi(out_vec, $__pv_nbi_desc, FAIL_LABEL)
    br[end#], defer[2]
        bitfield_extract__sz1(out_ingress_queue, BF_AML($__pv_nbi_desc, CAT_PORT_bf)) ; CAT_PORT_bf
        alu[out_ingress_queue, out_ingress_queue, OR, 1, <<6] // NBI = 0

rx_nfd#:
    __pv_rx_nfd(out_vec, pkt_len, __pv_nfd_pkt_no, $__pv_nfd_desc, FAIL_LABEL)
    alu[out_ingress_queue, 0xff, AND, BF_A($__pv_nfd_desc, NFD_IN_QID_fld)] ; NFD_QID_fld
    nfd_stats_update_received(0, out_ingress_queue, pkt_len)
 
end#:
.end
#endm


#endif
