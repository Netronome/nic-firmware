#ifndef _ACTIONS_UC
#define _ACTIONS_UC

#include <kernel/nfp_net_ctrl.h>

#include "app_config_instr.h"
#include "protocols.h"

#include "pv.uc"
#include "pkt_io.uc"
#include "ebpf.uc"

.reg volatile read $__actions[NIC_MAX_INSTR]
.addr $__actions[0] 32
.xfer_order $__actions
.reg volatile __actions_t_idx

#macro __actions_read(out_data, in_mask, in_shf)
    #if (streq('in_mask', '--'))
        #if (streq('in_shf', '--'))
            alu[out_data, --, B, *$index++]
        #else
            alu[out_data, --, B, *$index++, in_shf]
        #endif
    #else
        #if (streq('in_shf', '--'))
            alu[out_data, in_mask, AND, *$index++]
        #else
            alu[out_data, in_mask, AND, *$index++, in_shf]
        #endif
    #endif
    alu[__actions_t_idx, __actions_t_idx, +, 4]
#endm


#macro __actions_restore_t_idx()
    local_csr_wr[T_INDEX, __actions_t_idx]
    nop
    nop
    nop
#endm


#macro __actions_next()
    br_bclr[*$index, INSTR_PIPELINE_BIT, next#]
#endm


#macro __actions_statistics(in_pkt_vec)
.begin
    .reg stats_base
    .reg tmp
    .reg hi

    __actions_read(stats_base, 0xff, --)
    pv_stats_select(in_pkt_vec, stats_base)
    br[check_mac#]

broadcast#:
    pv_stats_select(in_pkt_vec, PV_STATS_BC)
    br[done#]

multicast#:
    alu[hi, --, B, *$index++, <<16]
    alu[tmp, --, B, 1, <<16]
    alu[--, hi, +, tmp]  // byte_align_be[] not necessary for MAC (word aligned)
    alu[--, *$index, +carry, 0]
    __actions_restore_t_idx()
    bcs[broadcast#]

    pv_stats_select(in_pkt_vec, PV_STATS_MC)
    br[done#]

check_mac#:
    pv_seek(in_pkt_vec, 0, PV_SEEK_CTM_ONLY)

    br_bset[*$index, BF_L(MAC_MULTICAST_bf), multicast#]

    __actions_restore_t_idx()

done#:
.end
#endm


#macro __actions_check_mtu(in_pkt_vec, DROP_LABEL)
.begin
    .reg mask
    .reg mtu
    .reg pkt_len

    immed[mask, 0x3fff]
    __actions_read(mtu, mask, --)
    pv_check_mtu(in_pkt_vec, mtu, DROP_LABEL)
.end
#endm


#macro __actions_check_mac(in_pkt_vec, DROP_LABEL)
.begin
    .reg mac[2]
    .reg tmp

    __actions_read(mac[0], --, --)
    __actions_read(mac[1], --, --)

    pv_seek(in_pkt_vec, 0, PV_SEEK_CTM_ONLY)

    // permit multicast and broadcast addresses to pass
    br_bset[*$index, BF_L(MAC_MULTICAST_bf), pass#]

    alu[tmp, mac[0], XOR, *$index++]
    alu[--, --, B, tmp, <<16]
    bne[DROP_LABEL]

    alu[--, mac[1], XOR, *$index++]
    bne[DROP_LABEL]

pass#:
    __actions_restore_t_idx()
.end
#endm


#macro __actions_rss(in_pkt_vec)
.begin
    .reg hash
    .reg hash_type
    .reg ipv4_delta
    .reg ipv6_delta
    .reg rss_table_idx
    .reg key
    .reg l3_info
    .reg l3_offset
    .reg l4_offset
    .reg opcode
    .reg parse_status
    .reg pkt_type // 0 - IPV6_TCP, 1 - IPV6_UDP, 2 - IPV4_TCP, 3 - IPV4_UDP
    .reg queue
    .reg queue_shf
    .reg queue_off
    .reg udp_delta
    .reg write $metadata

    __actions_read(opcode, --, --)
    __actions_read(key, --, --)

    // skip RSS for unkown L3
    bitfield_extract__sz1(l3_info, BF_AML(in_pkt_vec, PV_PARSE_L3I_bf))
    beq[skip_rss#]

    // skip RSS for MPLS
    bitfield_extract__sz1(--, BF_AML(in_pkt_vec, PV_PARSE_MPD_bf))
    bne[skip_rss#]

    // skip RSS for 2 or more VLANs (Catamaran L4 offsets unreliable)
    br_bset[BF_A(in_pkt_vec, PV_PARSE_VLD_bf), BF_M(PV_PARSE_VLD_bf), skip_rss#]

    local_csr_wr[CRC_REMAINDER, key]

    // seek to L3 source address
    alu[l3_offset, (1 << 2), AND, BF_A(in_pkt_vec, PV_PARSE_VLD_bf), >>(BF_L(PV_PARSE_VLD_bf) - 2)] // 4 bytes for VLAN
    alu[l3_offset, l3_offset, +, (14 + 8 + 2)] // 14 bytes for Ethernet, 8 bytes of IP header, 2 bytes seek align
    alu[ipv4_delta, (1 << 2), AND, BF_A(in_pkt_vec, PV_PARSE_L3I_bf), >>(BF_M(PV_PARSE_L3I_bf) - 2)] // 4 bytes extra for IPv4
    alu[l3_offset, l3_offset, +, ipv4_delta]
    pv_seek(in_pkt_vec, l3_offset, (PV_SEEK_CTM_ONLY | PV_SEEK_PAD_INCLUDED))

    br_bset[BF_A(in_pkt_vec, PV_PARSE_L3I_bf), BF_M(PV_PARSE_L3I_bf), process_l4#], defer[3] // branch if IPv4, 2 words hashed
        crc_be[crc_32, --, *$index++]
        immed[hash_type, 1]
        crc_be[crc_32, --, *$index++]

    // IPv6
    alu[hash_type, hash_type, +, 1]
    crc_be[crc_32, --, *$index++]

    // hash 5 more words for IPv6
    #define_eval LOOP (0)
    #while (LOOP < 5)
        nop
        crc_be[crc_32, --, *$index++]
        #define_eval LOOP (LOOP + 1)
    #endloop
    #undef LOOP

process_l4#:
    bitfield_extract__sz1(parse_status, BF_AML(in_pkt_vec, PV_PARSE_STS_bf))

    // skip L4 if not configured (per packet type enable/disable: IPV4_UDP, IPV4_TCP, IPV6_UDP, IPV6_TCP)
    alu[pkt_type, l3_info, AND, 2]
    alu[pkt_type, pkt_type, OR, parse_status, >>2]
    alu[--, pkt_type, OR, 0]
    alu[--, opcode, AND, 1, <<indirect]
    beq[skip_l4#], defer[1]
        alu[rss_table_idx, 0x7f, AND, opcode, >>8]

    // skip L4 if offset unknown
    alu[l4_offset, 0xfe, AND, BF_A(in_pkt_vec, PV_PARSE_L4_OFFSET_bf), >>(BF_L(PV_PARSE_L4_OFFSET_bf) - 1)]
    beq[skip_l4#] // zero for unsupported protocols or unparsable IP extention headers

    // preemptive seek to avoid local_csr_wr[T_INDEX, ...] update latency in normal case
    pv_seek(in_pkt_vec, l4_offset, PV_SEEK_T_INDEX_ONLY)

        // skip L4 if unknown
        br=byte[parse_status, 0, 0, skip_l4#]

        // skip L4 if packet is fragmented
        br=byte[parse_status, 0, 7, skip_l4#]

        alu[udp_delta, (1 << 1), AND, parse_status, >>1]

    crc_be[crc_32, --, *$index++]

        alu[udp_delta, udp_delta, OR, parse_status, >>2]
        alu[hash_type, hash_type, +, 3]
        alu[hash_type, hash_type, +, udp_delta]

skip_l4#:
    pv_meta_push_type(in_pkt_vec, hash_type)
    br_bset[opcode, INSTR_RSS_V1_META_BIT, skip_meta_type#], defer[3]
        local_csr_rd[CRC_REMAINDER]
        immed[hash, 0]
        alu[$metadata, --, B, hash]

    pv_meta_push_type(in_pkt_vec, NFP_NET_META_HASH)

skip_meta_type#:
    pv_meta_prepend(in_pkt_vec, $metadata, 4]

    alu[queue_off, 0x1f, AND, hash, >>2]
    alu[rss_table_idx, rss_table_idx, +, queue_off]
    local_csr_wr[NN_GET, rss_table_idx]
        __actions_restore_t_idx()
        alu[queue_shf, 0x18, AND, hash, <<3]
        alu[--, queue_shf, OR, 0]
    alu[queue, 0xff, AND, *n$index, >>indirect]
    pv_set_egress_queue(in_pkt_vec, queue)

skip_rss#:
.end
#endm


#macro __actions_rxcsum(in_pkt_vec)
   __actions_read(--, --, --)
   pv_propagate_mac_csum_status(in_pkt_vec)
#endm


#macro __actions_checksum_complete(in_pkt_vec)
.begin
    .reg available_words
    .reg carries
    .reg checksum
    .reg data_len
    .reg idx
    .reg include_mask
    .reg iteration_bytes
    .reg iteration_words
    .reg last_bits
    .reg offset
    .reg pkt_len
    .reg remaining_words
    .reg shift
    .reg zero_padded
    .reg write $metadata

    .sig sig_read

    __actions_read(--, --, --)

    immed[checksum, 0]
    immed[carries, 0]

    pv_get_length(pkt_len, in_pkt_vec)

    alu[data_len, pkt_len, -, 14]
    bgt[start#], defer[3]
        alu[remaining_words, --, B, data_len, >>2]
        immed[iteration_words, 0]
        immed[offset, (14 + 2)]

    br[skip_checksum#]

#define_eval LOOP_UNROLL (0)
#while (LOOP_UNROLL < 32)
w/**/LOOP_UNROLL#:
    alu[checksum, checksum, +carry, *$index++]
    #define_eval LOOP_UNROLL (LOOP_UNROLL + 1)
#endloop
#undef LOOP_UNROLL

    alu[carries, carries, +carry, 0] // accumulate carries that would be lost to looping construct alu[]s

start#:
    pv_seek(idx, in_pkt_vec, offset, --, PV_SEEK_PAD_INCLUDED)

    alu[remaining_words, remaining_words, -, iteration_words]
    beq[last_bits#]

    alu[available_words, 32, -, idx]
    alu[--, available_words, -, remaining_words]
    bmi[consume_available#]

    alu[idx, 32, -, remaining_words]

consume_available#:
    jump[idx, w0#], targets[w0#,  w1#,  w2#,  w3#,  w4#,  w5#,  w6#,  w7#,
                            w8#,  w9#,  w10#, w11#, w12#, w13#, w14#, w15#,
                            w16#, w17#, w18#, w19#, w20#, w21#, w22#, w23#,
                            w24#, w25#, w26#, w27#, w28#, w29#, w30#, w31#], defer[3]
        alu[iteration_words, 32, -, idx]
        alu[iteration_bytes, --, B, iteration_words, <<2]
        alu[offset, offset, +, iteration_bytes]

last_bits#:
    pv_meta_push_type(in_pkt_vec, NFP_NET_META_CSUM)
    alu[last_bits, (3 << 3), AND, data_len, <<3]
    beq[finalize#]

    alu[shift, 32, -, last_bits]
    alu[include_mask, shift, ~B, 0]
    alu[include_mask, --, B, include_mask, <<indirect]
    alu[zero_padded, include_mask, AND, *$index]
    alu[checksum, checksum, +, zero_padded]

finalize#:
    alu[checksum, checksum, +carry, carries]
    alu[$metadata, checksum, +carry, 0] // adding carries might cause another carry

    pv_meta_prepend(in_pkt_vec, $metadata, 4)

    __actions_restore_t_idx()

skip_checksum#:
.end
#endm


#macro actions_load(in_pkt_vec)
.begin
    .reg addr
    .sig sig_actions

    pv_get_instr_addr(addr, in_pkt_vec, (NIC_MAX_INSTR * 4))
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    ov_clean()
    cls[read, $__actions[0], 0, addr, max_16], indirect_ref, defer[2], ctx_swap[sig_actions]
        .reg_addr __actions_t_idx 28 B
        alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
        nop

    local_csr_wr[T_INDEX, __actions_t_idx]
    nop
    nop
    nop
.end
#endm


#macro actions_execute(in_pkt_vec, EGRESS_LABEL, DROP_LABEL, ERROR_LABEL)
.begin
    .reg jump_idx
    .reg egress_q_base
    .reg egress_q_mask

next#:
    alu[jump_idx, --, B, *$index, >>INSTR_OPCODE_LSB]
    jump[jump_idx, ins_0#], targets[ins_0#, ins_1#, ins_2#, ins_3#, ins_4#, ins_5#, ins_6#, ins_7#, ins_8#, ins_9#, ins_10#], defer[1] ;actions_jump
        immed[egress_q_mask, BF_MASK(PV_QUEUE_OUT_bf)]

    ins_0#: br[DROP_LABEL]
    ins_1#: br[statistics#]
    ins_2#: br[mtu#]
    ins_3#: br[mac#]
    ins_4#: br[rss#]
    ins_5#: br[checksum_complete#]
    ins_6#: br[tx_host#]
    ins_7#: br[tx_wire#]
    ins_8#: br[cmsg#]
    ins_9#: br[ebpf#]
    ins_10#: br[rxcsum#]

statistics#:
    __actions_statistics(in_pkt_vec)
    __actions_next()

mtu#:
    __actions_check_mtu(in_pkt_vec, DROP_LABEL)
    __actions_next()

mac#:
    __actions_check_mac(in_pkt_vec, DROP_LABEL)
    __actions_next()

rss#:
    __actions_rss(in_pkt_vec)
    __actions_next()

checksum_complete#:
    __actions_checksum_complete(in_pkt_vec)
    __actions_next()

tx_host#:
    __actions_read(egress_q_base, egress_q_mask, --)
    pkt_io_tx_host(in_pkt_vec, egress_q_base, EGRESS_LABEL, DROP_LABEL)

tx_wire#:
    __actions_read(egress_q_base, egress_q_mask, --)
    pkt_io_tx_wire(in_pkt_vec, egress_q_base, EGRESS_LABEL, DROP_LABEL)

cmsg#:
    cmsg_desc_workq($__pkt_io_gro_meta, in_pkt_vec, EGRESS_LABEL)

ebpf#:
    __actions_read(--, --, --)
    ebpf_call(in_pkt_vec, DROP_LABEL, tx_wire_ebpf#)

rxcsum#:
    __actions_rxcsum(in_pkt_vec)
    br[next#] // last instruction in code will not pipeline

.end
#endm


.if (0)
    ebpf_reentry#:
    ebpf_reentry()
.endif


#endif

