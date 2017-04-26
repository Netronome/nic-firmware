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
    pv_seek(in_pkt_vec, 0, 6)

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

    pv_seek(in_pkt_vec, 0, 6)

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
    pv_seek(in_pkt_vec, l3_offset, 32)

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

    pv_seek(in_pkt_vec, l4_offset, 4)
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

#define ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE_LW    32
#define ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE    (ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE_LW << 2)
#define ACTION_CHECKSUM_COMPLETE_CHUNK_MASK    ((ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE_LW << 2)-1)

/** __actions_checksum_block()
 * Calculate the accumulative checksum value over a chunk of packet data
 *
 * @io_sum    32-bit value containing the running checksum value for the current packet
 * @offset_start    32-bit offset of the first byte to process (ignored if this is not the first block)32-bit offset of the last byte to process
 * @offset_end    32-bit offset of the last byte to process
 * @in_pkt_vec    packet vector
 */
#macro __actions_checksum_block(io_sum, offset_start, offset_end, in_pkt_vec)
.begin
    .reg chunk_start
    .reg process_len
    .reg temp_offset
    .reg bytes_mask
    .reg masked_word
    .reg bytes_remaining
    .reg word_count
    .reg j_offset

    // Determine which chunk of packet data to load
    alu[chunk_start, offset_end, AND~, ACTION_CHECKSUM_COMPLETE_CHUNK_MASK]

    pv_seek(in_pkt_vec, chunk_start, ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE)
    alu[process_len, offset_end, -, chunk_start]
    alu[process_len, process_len, +, 1]

    // If this is the first chunk, start processing at offset_start, and reduce length accordingly
    .if (chunk_start == 0)
        // T_INDEX += offset_start
        local_csr_rd[T_INDEX]
        immed[temp_offset, 0]
        alu[temp_offset, temp_offset, +, offset_start]
        local_csr_wr[T_INDEX, temp_offset] ; Usage latency = 3 cycles
        alu[process_len, process_len, -, offset_start]

        // TODO:  there must be better more clever ways to do the following masking using byte index etc
        alu[bytes_remaining, offset_start, AND, 0x3]
        alu[bytes_remaining, 4, -, bytes_remaining]
        alu[process_len, process_len, -, bytes_remaining]
        alu[bytes_remaining, 0x18, AND, offset_start, <<3]
        immed[bytes_mask,0x8000,<<16]
        alu[--, bytes_remaining, OR, bytes_mask] ;//a_op of this instr = shift amount, result bit 31 of this instr = sign extend
        asr[bytes_mask, 0, >>indirect]; //shift >> shift amount & sign extend prev result which is 0x8000 0000
        alu[masked_word, *$index++,AND~,bytes_mask]
        alu[io_sum, io_sum, +, masked_word] // no +carry here yet, for it is the first one
    .endif

    #define_eval __LOOP 1
    #define_eval __BASE (ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE_LW-1)
    #define_eval __TARGETS 'step_0#'
    #while (__LOOP < ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE_LW)
        #define_eval __TARGETS '__TARGETS,step_/**/__LOOP#'
        #define_eval __LOOP (__LOOP + 1)
    #endloop

    // Use a jump table to drop into the right amount of remaining words to process - requires jump tables to work!
    alu[bytes_remaining, 0x18, AND, process_len, <<3]
    alu[word_count, --, B, process_len, >>2]
    alu[j_offset, (ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE_LW-1), -, word_count]

    jump[j_offset, step_/**/__BASE#], targets[__TARGETS], defer[3]
        immed[bytes_mask,0x8000,<<16]
        alu[--, bytes_remaining, OR, bytes_mask] ;//a_op of this instr = shift amount, result bit 31 of this instr = sign extend
        asr[bytes_mask, 0, >>indirect]; //shift >> shift amount & sign extend prev result which is 0x8000 0000

    #define_eval __LOOP ACTION_CHECKSUM_COMPLETE_CHUNK_SIZE_LW-1
    #while (__LOOP > 0)
        step_/**/__LOOP#:
            #define_eval __IDX ( __LOOP)
            alu[io_sum, io_sum, +carry, *$index++]
            #define_eval __LOOP (__LOOP - 1)
    #endloop

step_0#:
    alu[io_sum, io_sum, +carry, 0]
    alu[masked_word, *$index++,AND,bytes_mask]
    alu[io_sum, io_sum, +carry, masked_word]
    alu[io_sum, io_sum, +carry, 0]

    #undef __LOOP
    #undef __TARGETS

    // update offset end
    alu[offset_end, chunk_start, -, 1]

.end
#endm // __actions_checksum_block()


#define ACTION_CHECKSUM_COMPLETE_L2_SIZE 14

#macro __actions_checksum_complete(in_pkt_vec)
.begin
    .reg ipv4_delta
    .reg target_start
    .reg target_end
    .reg target_len
    .reg vlan_count
    .reg mpls_count
    .reg calculated_checksum
    .reg shift_down

    __actions_read(--, --, --)

    // skip checksum complete for unkown L3 or bad IPv4 checksum
    br_bclr[BF_AL(in_pkt_vec, PV_PARSE_L3I_bf), skip_checksum_complete#]

    // Determine L3 start offset
    bitfield_extract__sz1(vlan_count, BF_AML(in_pkt_vec, PV_PARSE_VLD_bf))
    alu[target_start, --, B, vlan_count, <<2]
    bitfield_extract__sz1(mpls_count, BF_AML(in_pkt_vec, PV_PARSE_MPD_bf))
    alu[mpls_count, --, B, mpls_count, <<2]
    alu[target_start, target_start, +, mpls_count]
    alu[target_start, target_start, +, (ACTION_CHECKSUM_COMPLETE_L2_SIZE - 4)]
    alu[ipv4_delta, (1 << 2), AND, BF_A(in_pkt_vec, PV_PARSE_L3I_bf), >>(BF_M(PV_PARSE_L3I_bf) - 2)] // What is this about? I see no difference in IPv4 offsets for various L3I's
    alu[target_start, target_start, +, ipv4_delta]

    // TODO: investigate feasibility to use MAC data as shortcut to deduce checksum_complete when TCP/UDP CSUM OK (P_STS) & IPv4 OK (L3I)

    // Determine L3+payload length
    pv_get_length(target_len, in_pkt_vec)
    alu[target_end, target_len, -, 1]

    immed[calculated_checksum, 0]
    .while (target_end > 0)
        __actions_checksum_block(calculated_checksum, target_start,target_end,in_pkt_vec)
    .endw

    // fold into 16 bits
    alu[shift_down, --, B, calculated_checksum, >>16]
    alu[calculated_checksum, shift_down, +16, calculated_checksum]
    alu[shift_down, --, B, calculated_checksum, >>16]
    alu[calculated_checksum, shift_down, +16, calculated_checksum]

    // 1's compliment
    alu[calculated_checksum, --, ~B, calculated_checksum]
    alu[calculated_checksum, 0, +16, calculated_checksum]

    // TODO: OK, so now what? What should we do with this value?

skip_checksum_complete#:
.end
#endm

#macro __actions_nop(count)
    #define_eval LOOP (count)
    #while (LOOP > 0)
        __actions_read(--, --, --)
        #define_eval LOOP (LOOP - 1)
    #endloop
    #undef LOOP
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
//    __actions_checksum_complete(in_pkt_vec)
    __actions_read(--, --, --)
    pv_propagate_mac_csum_status(in_pkt_vec) // checksum unecessary for now
    __actions_next()

tx_host#:
    pkt_io_tx_host(in_pkt_vec, EGRESS_LABEL, DROP_LABEL)

tx_wire#:
    pkt_io_tx_wire(in_pkt_vec, EGRESS_LABEL, DROP_LABEL)

.end
#endm

#endif

