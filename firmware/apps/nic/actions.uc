#ifndef _ACTIONS_UC
#define _ACTIONS_UC

#include "app_config_instr.h"
#include "protocols.h"

#include "pv.uc"
#include "pkt_io.uc"


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
    alu[act_t_idx, act_t_idx, +, 4]
#endm


#macro __actions_restore_t_idx()
    local_csr_wr[T_INDEX, act_t_idx]
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
    alu[hi, --, B, *$index++]
    alu[tmp, --, B, 1, <<16]
    alu[--, *$index++, +, tmp]  // byte_align_be[] not necessary for MAC (word aligned)
    alu[--, hi, +carry, 0]
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

    __actions_read(mac[1], --, <<16)
    __actions_read(mac[0], --, --)

    pv_seek(in_pkt_vec, 0, PV_SEEK_CTM_ONLY)

    // permit multicast and broadcast addresses to pass
    br_bset[*$index, BF_L(MAC_MULTICAST_bf), pass#]

    alu[--, mac[0], XOR, *$index++] // byte_align_be[] not necessary for MAC (word aligned)
    bne[DROP_LABEL]

    alu[tmp, mac[1], XOR, *$index++]
    alu[--, --, B, tmp, >>16]
    bne[DROP_LABEL]

pass#:
    __actions_restore_t_idx()
.end
#endm


#macro __actions_rss(in_pkt_vec)
.begin
    .reg data
    .reg hash
    .reg ipv4_delta
    .reg idx
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

    __actions_read(opcode, --, --)
    __actions_read(key, --, --)

     // skip RSS for unkown L3
    bitfield_extract__sz1(l3_info, BF_AML(in_pkt_vec, PV_PARSE_L3I_bf))
    beq[skip_rss#]

    // skip RSS for MPLS
    bitfield_extract__sz1(--, BF_AML(in_pkt_vec, PV_PARSE_MPD_bf))
    bne[skip_rss#]

    // skip RSS for 2 or more VLANs
    br_bset[BF_A(in_pkt_vec, PV_PARSE_VLD_bf), BF_M(PV_PARSE_VLD_bf), skip_rss#]

    local_csr_wr[CRC_REMAINDER, key]

    // seek to L3 source address
    alu[l3_offset, (1 << 2), AND, BF_A(in_pkt_vec, PV_PARSE_VLD_bf), >>(BF_L(PV_PARSE_VLD_bf) - 2)] // 4 bytes for VLAN
    alu[l3_offset, l3_offset, +, (14 + 8)] // 14 bytes for Ethernet, 8 bytes of IP header
    alu[ipv4_delta, (1 << 2), AND, BF_A(in_pkt_vec, PV_PARSE_L3I_bf), >>(BF_M(PV_PARSE_L3I_bf) - 2)] // 4 bytes extra for IPv4
    alu[l3_offset, l3_offset, +, ipv4_delta]
    pv_seek(in_pkt_vec, l3_offset, PV_SEEK_CTM_ONLY)

    byte_align_be[--, *$index++]
    byte_align_be[data, *$index++]
    br_bset[BF_A(in_pkt_vec, PV_PARSE_L3I_bf), BF_M(PV_PARSE_L3I_bf), process_l4#], defer[3] // branch if IPv4, 2 words hashed
        crc_be[crc_32, --, data]
        byte_align_be[data, *$index++]
        crc_be[crc_32, --, data]

    // hash 6 more words for IPv6
    #define_eval LOOP (0)
    #while (LOOP < 6)
        byte_align_be[data, *$index++]
        crc_be[crc_32, --, data]
        #define_eval LOOP (LOOP + 1)
    #endloop
    #undef LOOP

process_l4#:
    // skip L4 if offset unknown
    alu[l4_offset, 0xfe, AND, BF_A(in_pkt_vec, PV_PARSE_L4_OFFSET_bf), >>(BF_L(PV_PARSE_L4_OFFSET_bf) - 1)]
    beq[skip_l4#] // zero for unsupported protocols or unparsable IP extention headers

    // skip L4 if unknown
    bitfield_extract__sz1(parse_status, BF_AML(in_pkt_vec, PV_PARSE_STS_bf))
    beq[skip_l4#]

    // skip L4 if packet is fragmented
    br=byte[parse_status, 0, 7, skip_l4#]

    // skip L4 if not configured
    alu[pkt_type, l3_info, AND, 2]
    alu[pkt_type, pkt_type, OR, parse_status, >>2]
    alu[--, pkt_type, OR, 0]
    alu[--, opcode, AND, 1, <<indirect]
    beq[skip_l4#]

    pv_seek(in_pkt_vec, l4_offset, 4, PV_SEEK_CTM_ONLY)
    byte_align_be[--, *$index++]
    byte_align_be[data, *$index++]
    crc_be[crc_32, --, data]
        nop
        nop
        nop
        nop

skip_l4#:
        alu[idx, 0x7f, AND, opcode, >>8]
    local_csr_rd[CRC_REMAINDER]
    immed[hash, 0]
    alu[queue_off, 0x1f, AND, hash, >>2]
    alu[idx, idx, +, queue_off]
    local_csr_wr[NN_GET, idx]
        __actions_restore_t_idx()
        alu[queue_shf, 0x18, AND, hash, <<3]
        alu[--, queue_shf, OR, 0]
    alu[queue, 0xff, AND, *n$index, >>indirect]
    pv_set_egress_queue(in_pkt_vec, queue)

skip_rss#:
.end
#endm


#macro __actions_checksum_complete(in_pkt_vec)
.begin
    .reg carries
    .reg checksum
    .reg folded
    .reg iteration_bytes
    .reg iteration_words
    .reg jump_idx
    .reg last_bits
    .reg mask
    .reg next_offset
    .reg padded
    .reg pkt_length
    .reg pkt_words
    .reg shift
   
    __actions_read(--, --, --)

    immed[carries, 0] 
    immed[checksum, 0]
    immed[next_offset, 0]
    pv_get_length(pkt_length, in_pkt_vec)
    alu[pkt_words, --, B, pkt_length, >>2]

loop#:
    pv_seek(jump_idx, in_pkt_vec, next_offset, --, PV_SEEK_ANY) 
    
    alu[iteration_words, 32, -, jump_idx]
    alu[--, pkt_words, -, iteration_words]
    bgt[consume_entire_cache#]

    alu[jump_idx, 32, -, pkt_words]
    jump[jump_idx, w0#], targets[w0#,  w1#,  w2#,  w3#,  w4#,  w5#,  w6#,   w7#, \
                                 w8#,  w9#,  w10#, w11#, w12#, w13#, w14#, w15#, \
                                 w16#, w17#, w18#, w19#, w20#, w21#, w22#, w23#, \
                                 w24#, w25#, w26#, w27#, w28#, w29#, w30#, w31#], defer[3]
       alu[iteration_words, --, B, pkt_words]
       alu[iteration_bytes, --, B, iteration_words, <<2]
       alu[next_offset, next_offset, +, iteration_bytes]

consume_entire_cache#:
    immed[iteration_words, 32]
    alu[next_offset, next_offset, +, 128]

#define_eval LOOP_UNROLL (0)
#while (LOOP_UNROLL < 32)
w/**/LOOP_UNROLL#:
    alu[checksum, checksum, +carry, *$index++]
    #define_eval LOOP_UNROLL (LOOP_UNROLL + 1)
#endloop
#undef LOOP_UNROLL

    alu[carries, carries, +carry, 0] // accumulate carries that would be lost to looping construct alu[]s

    alu[pkt_words, pkt_words, -, iteration_words]
    bgt[loop#]
 
    alu[last_bits, (3 << 3), AND, pkt_length, <<3]
    beq[fold#]

    pv_seek(jump_idx, in_pkt_vec, next_offset, 4, PV_SEEK_ANY)
    alu[shift, 32, -, last_bits]
    alu[mask, shift, ~B, 0]
    alu[mask, --, B, mask, <<indirect]
    alu[padded, mask, AND, *$index++]
   
    alu[checksum, checksum, +, padded]
    alu[carries, carries, +carry, 0]

fold#:
    alu[checksum, checksum, +, carries]
    alu[checksum, checksum, +carry, 0] // adding carries might cause another carry
    alu[checksum, --, ~B, checksum]

    __actions_restore_t_idx()
.end
#endm


#macro actions_execute(in_pkt_vec, EGRESS_LABEL, DROP_LABEL, ERROR_LABEL)
.begin
    .reg act_t_idx
    .reg addr
    .reg jump_idx

    .reg volatile read $actions[NIC_MAX_INSTR]
    .xfer_order $actions
    .sig sig_actions

    pv_get_instr_addr(addr, in_pkt_vec, (NIC_MAX_INSTR * 4))
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    ov_clean()
    cls[read, $actions[0], 0, addr, max_16], indirect_ref, defer[2], ctx_swap[sig_actions]
        alu[act_t_idx, t_idx_ctx, OR, &$actions[0], <<2]
        nop

    local_csr_wr[T_INDEX, act_t_idx]
    nop
    nop
    nop

next#:
    alu[jump_idx, --, B, *$index, >>INSTR_OPCODE_LSB]
    jump[jump_idx, ins_0#], targets[ins_0#, ins_1#, ins_2#, ins_3#, ins_4#, ins_5#, ins_6#, ins_7#] ;actions_jump

        ins_0#: br[DROP_LABEL]
        ins_1#: br[statistics#]
        ins_2#: br[mtu#]
        ins_3#: br[mac#]
        ins_4#: br[rss#]
        ins_5#: br[checksum_complete#]
        ins_6#: br[tx_host#]
        ins_7#: br[tx_wire#]

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
    pkt_io_tx_host(in_pkt_vec, EGRESS_LABEL, DROP_LABEL)

tx_wire#:
    pkt_io_tx_wire(in_pkt_vec, EGRESS_LABEL, DROP_LABEL)

.end
#endm

#endif

