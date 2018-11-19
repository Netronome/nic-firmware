/*
 * Copyright (C) 2017-2020 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   action.uc
 * @brief  Action interpreter and core NIC data plane actions.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _ACTIONS_UC
#define _ACTIONS_UC

#include <kernel/nfp_net_ctrl.h>
#include <nic_basic/nic_stats.h>

#include "app_config_instr.h"
#include "protocols.h"

#include <passert.uc>

#include "pv.uc"
#include "pkt_io.uc"
#include "ebpf.uc"
#include "app_mac_lkup.h"
#include "mem_lkup.uc"


.alloc_mem __actions_sriov_keys lmem me 32 64

.reg global volatile g_mac_lkup_addr[2]

.reg volatile read $__actions[NIC_MAX_INSTR]
.addr $__actions[0] 32
.xfer_order $__actions
.reg volatile __actions_t_idx

mem_lkup_init_hash_tbl(_mac_lkup_tbl, imem0, MAC_LKUP_NUM_BUCKETS, MAC_LKUP_BUCKET_SZ)
mem_lkup_init_hash_addr(g_mac_lkup_addr, _mac_lkup_tbl, HASH_OP_CAMR48_64B, 0, MAC_LKUP_NUM_BUCKETS, MAC_LKUP_BUCKET_SZ)

#macro __actions_read(out_data, in_mask, in_shf)
    #if (streq('in_mask', '--'))
        #if (streq('in_shf', '--'))
            alu[out_data, --, B, *$index++]
        #else
            alu[out_data, --, B, *$index++, in_shf]
        #endif
    #else
        #if (streq('in_shf', '--'))
            #if (is_ct_const(in_mask) && in_mask == 0xffff)
                alu[out_data, 0, +16, *$index++]
            #else
                alu[out_data, in_mask, AND, *$index++]
            #endif
        #else
            alu[out_data, in_mask, AND, *$index++, in_shf]
        #endif
    #endif
    #ifdef __ACTIONS_T_IDX_DELTA
        #define_eval __ACTIONS_T_IDX_DELTA (__ACTIONS_T_IDX_DELTA + 4)
    #else
        .reg_addr __actions_t_idx 28 B
        alu[__actions_t_idx, __actions_t_idx, +, 4]
    #endif
#endm

#macro __actions_read(out_data, in_mask)
    __actions_read(out_data, in_mask, --)
#endm

#macro __actions_read(out_data)
    __actions_read(out_data, --, --)
#endm


#macro __actions_read()
    __actions_read(--, --, --)
#endm


#macro __actions_read_begin()
    #define __ACTIONS_T_IDX_DELTA 0
#endm


#macro __actions_read_end()
    .reg_addr __actions_t_idx 28 B
    alu[__actions_t_idx, __actions_t_idx, +, __ACTIONS_T_IDX_DELTA]
    #undef __ACTIONS_T_IDX_DELTA
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


#macro __actions_rx_wire(out_pkt_vec)
.begin
    .reg rx_args

    __actions_read(rx_args, 0xffff)
    pkt_io_rx_wire(out_pkt_vec, rx_args)
    __actions_restore_t_idx()
.end
#endm


#macro __actions_rx_host(out_pkt_vec, DROP_LABEL)
.begin
    .reg rx_args

    __actions_read(rx_args, 0xffff)
    pkt_io_rx_host(out_pkt_vec, rx_args, DROP_LABEL)
    __actions_restore_t_idx()
.end
#endm


/* VEB lookup key:
 * Word   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 *       +-----------------------+-------+-------------------------------+
 *    0  |       VLAN ID         |   0   |         MAC ADDR HI           |
 *       +-----------------------+-------+-------------------------------+
 *    1  |                           MAC ADDR LO                         |
 *       +---------+-------------------------------------------+---------+
 */

#macro __actions_veb_lookup(in_pkt_vec, DROP_LABEL)
.begin
    .reg ins_addr[2]
    .reg key_addr
    .reg mac_hi
    .reg mac_lo
    .reg port_mac[2]
    .reg tid
    .reg tmp
    .reg vlan_id

    .sig sig_read

    __actions_read_begin()
    __actions_read(port_mac[0], 0xffff)
    __actions_read(port_mac[1])
    __actions_read_end()

    br_bset[BF_AL(in_pkt_vec, PV_MAC_DST_MC_bf), end#]
    pv_seek(in_pkt_vec, 0, PV_SEEK_DEFAULT, mac_match_check#)

veb_error#:
    pv_stats_update(in_pkt_vec, RX_ERROR_VEB, DROP_LABEL)

veb_miss#:
    alu[--, port_mac[0], OR, port_mac[1]]
    beq[done#]
    pv_stats_update(in_pkt_vec, RX_DISCARD_ADDR, DROP_LABEL)

veb_lookup#:
    immed[key_addr, __actions_sriov_keys]
    alu[key_addr, key_addr, OR, t_idx_ctx, >>5]
    local_csr_wr[ACTIVE_LM_ADDR_0, key_addr]

    alu[tid, --, B, SRIOV_TID]
    bitfield_extract(vlan_id, BF_AML(in_pkt_vec, PV_VLAN_ID_bf))
    alu[vlan_id, --, B, vlan_id, <<20]

    alu[*l$index0++, vlan_id, +16, *$index++]
    alu[*l$index0, --, B, *$index]

    #define HASHMAP_RXFR_COUNT 4
    #define MAP_RDXR $__pv_pkt_data
    // hashmap_ops will overwrite the packet cache, we MUST invalidate
    pv_invalidate_cache(in_pkt_vec)
    hashmap_ops(tid,
                key_addr,
                --,
                HASHMAP_OP_LOOKUP,
                veb_error#, // invalid map - should never happen
                veb_miss#, // sriov miss
                HASHMAP_RTN_ADDR,
                --,
                --,
                ins_addr,
                swap)
    #undef MAP_RDXR
    #undef HASHMAP_RXFR_COUNT

veb_hit#:
    //Load a new set of instructions as pointed by the returned address.
    //Note that from this point on the original instructions list is overwritten and
    //we no longer process instructions from current list.
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    ov_clean()
    mem[read32, $__actions[0], ins_addr[0], <<8, ins_addr[1], max_16], indirect_ref, sig_done[sig_read]

    ctx_arb[sig_read], defer[2], br[done#]
        .reg_addr __actions_t_idx 28 B
        alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
        nop

mac_match_check#:
    alu[mac_hi, port_mac[0], XOR, *$index++]
    alu[mac_lo, port_mac[1], XOR, *$index--]
    alu[--, mac_lo, OR, mac_hi, <<16]
    bne[veb_lookup#]

done#:
    __actions_restore_t_idx()

end#:
.end
#endm


#macro __actions_dst_mac_match(in_pkt_vec, DROP_LABEL)
.begin
    .reg mac_hi
    .reg mac_lo
    .reg port_mac[2]

    /* match dst mac: hi 2 bytes first, low 4 bytes second */
    __actions_read_begin()
    __actions_read(port_mac[0], 0xffff)
    __actions_read(port_mac[1])
    __actions_read_end()

    br_bset[BF_AL(in_pkt_vec, PV_MAC_DST_MC_bf), end#]

    /* packet dst mac: hi 2 bytes first, 4 lo bytes second */
    pv_seek(in_pkt_vec, 0)

    alu[mac_hi, port_mac[0], XOR, *$index++]
    alu[mac_lo, port_mac[1], XOR, *$index++]

    __actions_restore_t_idx()

    alu[--, mac_lo, OR, mac_hi, <<16]
    bne[DROP_LABEL]

end#:
.end
#endm

#macro __actions_l2_switch_host(in_pkt_vec)
.begin

    .reg $mac_lkup[2]
    .xfer_order $mac_lkup
    .sig lkup_sig
    .reg tmp, act_addr
    .sig sig_actions

    __actions_read()

    br_bset[BF_AL(in_pkt_vec, PV_MAC_DST_MC_bf), end#]

    pv_seek(in_pkt_vec, 0)

    //Do with lookup MAC in packet header
    alu[$mac_lkup[1], 0, +16, *$index++]
    move($mac_lkup[0], *$index)

    //Lookup the MAC address
    mem[lookup, $mac_lkup[0], g_mac_lkup_addr[0], <<8, g_mac_lkup_addr[1], 1], sig_done[lkup_sig]
    ctx_arb[lkup_sig]

    //Mac not found, continue with original act list
    br_bclr[$mac_lkup[0], MAC_LKUP_IN_USE_bit, skip_act_list#]

    //Read rest of action list from a new address
    alu[act_addr, $mac_lkup[0], AND~, 1, <<MAC_LKUP_IN_USE_bit]
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    ov_clean()
    cls[read, $__actions[0], 0, act_addr, max_16], indirect_ref, defer[2], ctx_swap[sig_actions]
        .reg_addr __actions_t_idx 28 B
        alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
        nop

skip_act_list#:
    __actions_restore_t_idx()

end#:
.end
#endm


#macro __actions_l2_switch_wire(in_pkt_vec, DROP_LABEL)
.begin

    .reg $mac_lkup[2]
    .xfer_order $mac_lkup
    .sig lkup_sig
    .reg tmp, act_addr
    .sig sig_actions

    __actions_read()

    //Broadcast/Multicast: skip this step.
    br_bset[BF_AL(in_pkt_vec, PV_MAC_DST_MC_bf), end#]

    pv_seek(in_pkt_vec, 0)

    //Do with lookup MAC in packet header
    alu[$mac_lkup[1], 0, +16, *$index++]
    move($mac_lkup[0], *$index)

    //Lookup the MAC address
    mem[lookup, $mac_lkup[0], g_mac_lkup_addr[0], <<8, g_mac_lkup_addr[1], 1], sig_done[lkup_sig]
    ctx_arb[lkup_sig]

    //restore here in case of dropping
    __actions_restore_t_idx()

    //Mac not found,
    br_bclr[$mac_lkup[0], MAC_LKUP_IN_USE_bit, DROP_LABEL]

    //Read rest of action list from a new address
    alu[act_addr, $mac_lkup[0], AND~, 1, <<MAC_LKUP_IN_USE_bit]
    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    ov_clean()
    cls[read, $__actions[0], 0, act_addr, max_16], indirect_ref, defer[2], ctx_swap[sig_actions]
        .reg_addr __actions_t_idx 28 B
        alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
        nop

    __actions_restore_t_idx()

end#:
.end
#endm


#macro __actions_src_mac_match(in_pkt_vec, DROP_LABEL)
.begin
    .reg mac_hi
    .reg mac_lo
    .reg port_mac[2]

    /* match src mac: lo 2 bytes first, hi 4 bytes second */
    __actions_read_begin()
    __actions_read(port_mac[0], --, <<16)
    __actions_read(port_mac[1])
    __actions_read_end()

    /* packet src mac: hi 4 bytes first, 2 lo bytes second */
    pv_seek(in_pkt_vec, 8)

    alu[mac_hi, port_mac[1], XOR, *$index++]
    alu[mac_lo, port_mac[0], XOR, *$index++]

    __actions_restore_t_idx()

    alu[--, mac_hi, OR, mac_lo, >>16]
    bne[DROP_LABEL]

end#:
.end
#endm


#macro __actions_rss(in_pkt_vec)
.begin
    .reg args[2]
    .reg data
    .reg hash_type
    .reg l3_offset
    .reg l4_offset
    .reg l4_data
    .reg max_queue
    .reg process_l4
    .reg proto_delta
    .reg proto_shf
    .reg queue
    .reg rss_table_addr
    .reg rss_table_idx
    .reg write $metadata
    .reg read $rss_tbl_row
    .sig rss_tbl_sig

    __actions_read_begin()
    __actions_read(args[0])
    __actions_read(args[1])
    __actions_read_end()

    br_bset[BF_AL(in_pkt_vec, PV_QUEUE_SELECTED_bf), queue_selected#]

begin#:
    bitfield_extract__sz1(l3_offset, BF_AML(in_pkt_vec, PV_HEADER_OFFSET_INNER_IP_bf)) ; PV_HEADER_OFFSET_INNER_IP_bf
    beq[end#] // unknown L3

    /* Read and cache L4 data first because seeking might context swap. The
     * additional branch later to skip L4 when not required is cheaper than
     * waiting for CRC instruction latencies to save and restore CRC state.
     * The l4_offset is used as discriminator for processing L4. It is zero
     * in the packet vector if L4 is unrecognized and we set it to zero here
     * by masking out the bits if L4 is not configured for the packet. Note,
     * L4 will also be skipped for fragments since PV_PROTO is 7, effectively
     * disabling L4 by shifting the 4 configuration bits out of the register.
     */
    .set l4_data
    bitfield_extract(process_l4, BF_AML(args, INSTR_RSS_CFG_PROTO_bf)) ; INSTR_RSS_CFG_PROTO_bf
    alu[hash_type, BF_A(in_pkt_vec, PV_PROTO_bf), B, 1] ; PV_PROTO_bf
    alu[process_l4, 1, AND~, process_l4, >>indirect] // 1 if L4 is disabled for proto
    alu[process_l4, process_l4, -, 1] // generate mask of 0xffffffff if L4 is enabled
    passert(BF_L(PV_HEADER_OFFSET_INNER_L4_bf), "EQ", 0)
    /* extract non-zero l4_offset if and only if L4 is valid and it is enabled */
    alu[l4_offset, BF_A(in_pkt_vec, PV_HEADER_OFFSET_INNER_L4_bf), AND, process_l4, >>(31 - BF_M(PV_HEADER_OFFSET_INNER_L4_bf))] ; PV_HEADER_OFFSET_INNER_L4_bf
    beq[process_l3#], defer[3]
        alu[l3_offset, l3_offset, +, (8 + 2)] // 8 bytes of IP header, 2 bytes seek align
        alu[proto_delta, (1 << 2), AND, BF_A(in_pkt_vec, PV_PROTO_bf), <<1] // 4 bytes extra for IPv4
        alu[l3_offset, l3_offset, +, proto_delta]

    pv_seek(in_pkt_vec, l4_offset)

    byte_align_be[--, *$index++]
    byte_align_be[l4_data, *$index++]

process_l3#:
    pv_seek(in_pkt_vec, l3_offset, PV_SEEK_PAD_INCLUDED)

    local_csr_wr[CRC_REMAINDER, BF_A(args, INSTR_RSS_KEY_bf)]
    byte_align_be[--, *$index++]
    byte_align_be[data, *$index++]
    br_bset[BF_A(in_pkt_vec, PV_PROTO_bf), 1, process_l4#], defer[3] // branch if IPv4, 2 words hashed
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

    alu[hash_type, hash_type, +, 1]

process_l4#:
    br=byte[l4_offset, 0, 0, skip_l4#], defer[1]
        alu[rss_table_addr, BF_A(args, INSTR_RSS_TABLE_IDX_bf), AND, BF_MASK(INSTR_RSS_TABLE_IDX_bf), <<BF_L(INSTR_RSS_TABLE_IDX_bf)]

    crc_be[crc_32, --, l4_data]

    alu[proto_shf, BF_A(in_pkt_vec, PV_PROTO_bf), AND, 1]
    alu[proto_delta, proto_shf, B, 3]
    alu[proto_delta, --, B, proto_delta, <<indirect]
    alu[hash_type, hash_type, +, proto_delta]

skip_l4#:
    passert(BF_L(INSTR_RSS_TABLE_IDX_bf), "EQ", LOG2(NFP_NET_CFG_RSS_ITBL_SZ))
    passert(NIC_RSS_TBL_ADDR, "POWER_OF_2")
    passert(LOG2(NIC_RSS_TBL_ADDR), "GT", BF_M(INSTR_RSS_TABLE_IDX_bf))
    alu[rss_table_addr, rss_table_addr, OR, 1, <<(log2(NIC_RSS_TBL_ADDR))]

    local_csr_rd[CRC_REMAINDER]
    immed[*l$index2, 0]

    /* Select queue = rss_tbl[hash % NFP_NET_CFG_RSS_ITBL_SZ] */
    alu[rss_table_idx, (NFP_NET_CFG_RSS_ITBL_SZ - 1), AND, *l$index2++]
    cls[read, $rss_tbl_row, rss_table_addr, rss_table_idx, 1], sig_done[rss_tbl_sig]
    ctx_arb[rss_tbl_sig], defer[2], br[finalize#]
        pv_meta_push_type__sz1(in_pkt_vec, hash_type)
        bits_set__sz1(BF_AL(in_pkt_vec, PV_TX_HOST_RX_RSS_bf), 1)

queue_selected#:
    bitfield_extract__sz1(max_queue, BF_AML(args, INSTR_RSS_MAX_QUEUE_bf))
    bitfield_extract__sz1(queue, BF_AML(in_pkt_vec, PV_QUEUE_OFFSET_bf))
    alu[--, max_queue, -, queue]
    bhs[end#]

    br[begin#], defer[1]
        pv_set_queue_offset__sz1(in_pkt_vec, 0)

finalize#:
    __actions_restore_t_idx()

    br_bset[BF_AL(args, INSTR_RSS_V1_META_bf), end#], defer[1]
        /* CLS doesn't provide read8, required byte is in the top 8 bits */
        ld_field[BF_A(in_pkt_vec, PV_QUEUE_OFFSET_bf), 0001, $rss_tbl_row, >>24]; PV_QUEUE_OFFSET_bf

    pv_meta_push_type__sz1(in_pkt_vec, NFP_NET_META_HASH) // RSSv2

end#:
.end
#endm


#macro __actions_checksum(in_pkt_vec)
.begin
    .reg available_words
    .reg buf_offset
    .reg carries
    .reg cbs
    .reg checksum
    .reg csum_complete
    .reg csum_offset
    .reg data
    .reg data_history
    .reg data_len
    .reg encap
    .reg idx
    .reg ihl
    .reg include_mask
    .reg ip_offset
    .reg ipv4_delta
    .reg iteration_bytes
    .reg iteration_words
    .reg l4_len
    .reg l4_offset
    .reg l4_proto
    .reg last_bits
    .reg mem_addr
    .reg mu_addr
    .reg msk
    .reg neg_csum_field
    .reg offset
    .reg proto_shl
    .reg pkt_len
    .reg pkt_offset
    .reg remaining_words
    .reg shift
    .reg split_offset
    .reg state
    .reg tmp
    .reg work
    .reg zero_padded
    .reg write $checksum
    .sig sig_read
    .sig sig_write

    .set csum_complete
    .set csum_offset
    .set ip_offset
    .set l4_len
    .set l4_proto
    .set proto_shl

    __actions_read(state, 0xffff)

    passert(BF_L(PV_CSUM_OFFLOAD_bf), "EQ", 0)
    alu[msk, BF_A(in_pkt_vec, PV_CSUM_OFFLOAD_bf), OR, 1, <<BF_L(INSTR_CSUM_META_bf)]
    alu[state, state, AND, msk]
    beq[end#]

    immed[checksum, 0]
    immed[carries, 0]

    pv_get_length(pkt_len, in_pkt_vec)

    alu[data_len, pkt_len, -, 14]
    bgt[start#], defer[3]
        alu[remaining_words, --, B, data_len, >>2]
        immed[iteration_words, 0]
        immed[offset, (14 + 2)]

    br[end#]

#define_eval LOOP_UNROLL (0)
#while (LOOP_UNROLL < 32)
w/**/LOOP_UNROLL#:
    alu[checksum, checksum, +carry, *$index++]
    #define_eval LOOP_UNROLL (LOOP_UNROLL + 1)
#endloop
#undef LOOP_UNROLL

    alu[carries, carries, +carry, 0] // accumulate carries that would be lost to looping construct alu[]s

start#:
    pv_seek(idx, in_pkt_vec, offset, PV_SEEK_PAD_INCLUDED, --)

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

update_l4_csum#:
    // finalize pending checksum
    alu[checksum, checksum, +carry, 0]

    // extract work from state
    alu[work, --, B, state, >>24]

    // seek to L3 source address for pseudo-header
    pv_seek(in_pkt_vec, ip_offset)

    // calculate tail of L4 checksum (csum_complete -' head checksum)
    alu[checksum, --, ~B, checksum]
    alu[checksum, csum_complete, +, checksum]

    // L4 pseudo-header fields
    alu[checksum, checksum, +carry, l4_len]
    alu[checksum, checksum, +carry, l4_proto]

    // IPv4 addresses
    byte_align_be[--, *$index++], no_cc
    byte_align_be[data, *$index++], no_cc
    br_bset[proto_shl, 2, write_csum#], defer[3]
        alu[checksum, checksum, +carry, data]
        byte_align_be[data, *$index++], no_cc
        alu[checksum, checksum, +carry, data]

    // IPv6 addresses
#define_eval LOOP (0)
#while (LOOP < 5)
    byte_align_be[data, *$index++], no_cc
    alu[checksum, checksum, +carry, data]
#define_eval LOOP (LOOP + 1)
#endloop
#undef LOOP
    br[write_csum#], defer[2]
        byte_align_be[data, *$index++], no_cc
        alu[checksum, checksum, +carry, data]

update#:
    br!=byte[state, 3, 0, update_l4_csum#], defer[1]
        alu[checksum, checksum, +carry, carries]

    // first entry - save checksum complete for later
    alu[csum_complete, checksum, +carry, 0]

check_work#:
    alu[work, state, AND, (1 << BF_L(INSTR_CSUM_IL4_bf))]
    bne[process_l4#]

    alu[work, state, AND, (1 << BF_L(INSTR_CSUM_IL3_bf))]
    bne[process_l3#]

    alu[work, state, AND, (1 << BF_L(INSTR_CSUM_OL4_bf))]
    bne[process_l4#]

    alu[work, state, AND, (1 << BF_L(INSTR_CSUM_OL3_bf))]
    bne[process_l3#]

    // no more work
    __actions_restore_t_idx()
    pv_invalidate_cache(in_pkt_vec)
    br_bclr[state, BF_L(INSTR_CSUM_META_bf), end#]
    br[end#], defer[2]
        alu[*l$index2++, --, B, csum_complete]
        pv_meta_push_type__sz1(in_pkt_vec, NFP_NET_META_CSUM)

process_l4#:
    // determine L4 offset (inner / outer)
    alu[shift, 16, AND~, work, <<(4 - BF_L(INSTR_CSUM_IL4_bf))] // 16 if outer, else 0
    alu[iteration_words, shift, B, 0]
    ld_field_w_clr[offset, 0011, BF_A(in_pkt_vec, PV_HEADER_STACK_bf), >>indirect], load_cc
    br=byte[offset, 0, 0, invalid_offset#] // if L4 offset 0 done
                                           // assuming case of L3 offset = 0, L4 offset != 0 can't happen

    alu[l4_offset, 0xff, AND, offset] // l4_offset
    alu[l4_len, pkt_len, -, l4_offset]
    alu[data_len, l4_offset, -, 14]
    alu[remaining_words, --, B, data_len, >>2]

    // determine presence of outer encap
    alu[encap, l4_offset, XOR, BF_A(in_pkt_vec, PV_HEADER_STACK_bf)]
    alu[encap, 0xff, +8, encap] // 8-bit carry if l4_offset != inner offset
    alu[shift, 4, AND, encap, >>6] // 4 if l4_offset != inner, else 0
    alu[shift, shift, OR, encap, >>8] // 5 if l4_offset != inner, else 0

    // determine L4 protocol
    alu[proto_shl, shift, B, BF_A(in_pkt_vec, PV_PROTO_bf), <<1]
    alu[shift, (1 << 1), AND, proto_shl, >>indirect] // 2 if UDP, else 0
    alu[l4_proto, shift, B, ((0x11 << 2) | 0x6)]
    alu[l4_proto, 0x1f, AND, l4_proto, >>indirect]

    // determine offset of L3 IP addresses
    alu[ip_offset, 0xff, AND, offset, >>8]
    alu[ipv4_delta, 4, AND, proto_shl]
    alu[ip_offset, ip_offset, +, 8]
    alu[ip_offset, ip_offset, +, ipv4_delta]

    // determine offset of checksum field in packet
    alu[csum_offset, shift, B, (6 << 2)]
    alu[csum_offset, 0x16, AND, csum_offset, >>indirect] // 6 if UDP, else 16 if TCP
    alu[csum_offset, csum_offset, +, l4_offset]

    // subtract checksum field in packet from csum_complete
    pv_seek(in_pkt_vec, csum_offset)
    byte_align_be[--, *$index++]
    byte_align_be[data, *$index++]
    alu[neg_csum_field, --, ~B, data, >>16]
    alu[csum_complete, csum_complete, +16, neg_csum_field]
    alu[csum_complete, csum_complete, +carry, 0]

    ld_field[state, 1000, work, <<24]
    immed[offset, (14 + 2)]
    br[start#], defer[2]
        immed[checksum, 0]
        immed[carries, 0]

process_l3#:
    // determine IPv4 offset
    alu[shift, 16, AND~, work, <<(4 - BF_L(INSTR_CSUM_IL3_bf))] // 16 if outer, else 0
    alu[shift, shift, OR, 8] // 24 if inner, else 8
    alu[--, shift, OR, 0]
    alu[ip_offset, 0xff, AND, BF_A(in_pkt_vec, PV_HEADER_STACK_bf), >>indirect]
    beq[invalid_offset#]

    alu[csum_offset, ip_offset, +, 10]

    pv_seek(in_pkt_vec, ip_offset)

    byte_align_be[--, *$index++]
    byte_align_be[checksum, *$index++]
    alu[ihl, 0xf, AND, checksum, >>24]

    byte_align_be[data_history, *$index++]
    byte_align_be[data, *$index++]

    // subtract checksum field in packet from csum_complete
    alu[neg_csum_field, --, ~B, data]
    alu[csum_complete, csum_complete, +16, neg_csum_field]
    alu[csum_complete, csum_complete, +carry, 0]

    ld_field_w_clr[tmp, 1100, data] // zero checksum field for calc
    alu[checksum, checksum, +, data_history]
    alu[checksum, checksum, +carry, tmp]

    byte_align_be[data, *$index++], no_cc
    alu[checksum, checksum, +carry, data]

options#:
    br!=byte[ihl, 0, 5, options#], defer[3]
        byte_align_be[data, *$index++], no_cc
        alu[checksum, checksum, +carry, data]
        alu[ihl, ihl, -, 1], no_cc

write_csum#:
    // finalize pending checksum
    alu[checksum, checksum, +carry, 0]

    // fold checksum for write
    alu[tmp, --, B, checksum, >>16]
    alu[tmp, tmp, +16, checksum] // top half-word is 16-bit carry, bottom is checksum
    alu[checksum, --, B, tmp, <<16] // move checksum to top half-word
    alu[checksum, checksum, +, tmp] // add carry to checksum
    alu[checksum, --, ~B, checksum, >>16]

    br_bclr[BF_AL(in_pkt_vec, PV_CTM_ALLOCATED_bf), write_mu#], defer[3]
        alu[$checksum, --, B, checksum, <<16]
        alu[state, state, AND~, work]
        alu[buf_offset, csum_offset, +16, BF_A(in_pkt_vec, PV_OFFSET_bf)]

    bitfield_extract__sz1(cbs, BF_AML(in_pkt_vec, PV_CBS_bf)) ; PV_CBS_bf
    alu[split_offset, cbs, B, 1, <<8]
    alu[split_offset, --, B, split_offset, <<indirect]
    alu[--, split_offset, -, buf_offset]
    ble[write_mu#]

    mem[write8, $checksum, BF_A(in_pkt_vec, PV_CTM_ADDR_bf), csum_offset, 2], sig_done[sig_write]
    ctx_arb[sig_write], defer[2], br[check_work#]
        alu[csum_complete, csum_complete, +16, checksum]
        alu[csum_complete, csum_complete, +carry, 0]

write_mu#:
    alu[mu_addr, --, B, BF_A(in_pkt_vec, PV_MU_ADDR_bf), <<(31 - BF_M(PV_MU_ADDR_bf))]
    mem[write8, $checksum, mu_addr, <<8, buf_offset, 2], sig_done[sig_write]
    ctx_arb[sig_write], defer[2], br[check_work#]
        alu[csum_complete, csum_complete, +16, checksum]
        alu[csum_complete, csum_complete, +carry, 0]

invalid_offset#:
    br[check_work#], defer[1]
        alu[state, state, AND~, work]

last_bits#:
    alu[last_bits, (3 << 3), AND, data_len, <<3]
    beq[finalize#]

    alu[shift, 32, -, last_bits]
    alu[include_mask, shift, ~B, 0]
    alu[include_mask, --, B, include_mask, <<indirect]
    alu[zero_padded, include_mask, AND, *$index]
    alu[checksum, checksum, +, zero_padded]

finalize#:
    br!=byte[state, 0, 0, update#]

    __actions_restore_t_idx()

    br_bclr[state, BF_L(INSTR_CSUM_META_bf), end#]
    alu[checksum, checksum, +carry, carries]
    alu[*l$index2++, checksum, +carry, 0] // adding carries might cause another carry
    pv_meta_push_type__sz1(in_pkt_vec, NFP_NET_META_CSUM)

end#:
.end
#endm


#macro __actions_pop_vlan(io_pkt_vec)
.begin
    .reg msk
    .reg addr_hi
    .reg addr_lo
    .reg offsets
    .reg stack
    .reg write $mac[3]
    .xfer_order $mac
    .sig sig_write
    .sig sig_read

    __actions_read()

    pv_get_base_addr(addr_hi, addr_lo, io_pkt_vec)
    mem[read32, $__pv_pkt_data[0], addr_hi, <<8, addr_lo, 3], ctx_swap[sig_read], defer[2]
        alu[addr_lo, addr_lo, +, 4]
	    pv_invalidate_cache(io_pkt_vec)

    alu[$mac[0], --, B, $__pv_pkt_data[0]]
    alu[$mac[1], --, B, $__pv_pkt_data[1]]
    alu[$mac[2], --, B, $__pv_pkt_data[2]]

    mem[write32, $mac[0], addr_hi, <<8, addr_lo, 3], ctx_swap[sig_write], defer[2]
        alu[BF_A(io_pkt_vec, PV_LENGTH_bf), BF_A(io_pkt_vec, PV_LENGTH_bf), -, 4]
        alu[BF_A(io_pkt_vec, PV_OFFSET_bf), BF_A(io_pkt_vec, PV_OFFSET_bf), +, 4]

    __actions_restore_t_idx()

    // subtract 4 from each non-zero offset
    alu[msk, --, B, 0xff, <<24]
    alu[--, BF_A(io_pkt_vec, PV_HEADER_STACK_bf), +, msk]
    alu[stack, BF_A(io_pkt_vec, PV_HEADER_STACK_bf), AND~, msk], no_cc
    alu[msk, --, B, msk, >>8], no_cc
    alu[stack, stack, +, msk], no_cc
    alu[stack, stack, AND~, msk], no_cc
    alu[msk, --, B, msk, >>8], no_cc
    alu[stack, stack, +, msk], no_cc
    alu[stack, stack, AND~, msk], no_cc
    alu[stack, stack, +, 0xff], no_cc
    alu[stack, stack, AND~, 0xff], no_cc
    alu[stack, stack, +carry, 0]
    alu[stack, --, B, stack, >>rot6]
    alu[BF_A(io_pkt_vec, PV_HEADER_STACK_bf), BF_A(io_pkt_vec, PV_HEADER_STACK_bf), -, stack]

    immed[msk, NULL_VLAN]
    bits_set__sz1(BF_AL(io_pkt_vec, PV_VLAN_ID_bf), msk) ; PV_VLAN_ID_bf

.end
#endm


#macro __actions_push_vlan(io_pkt_vec)
.begin
    .reg msk
    .reg addr_hi
    .reg addr_lo
    .reg offsets
    .reg stack
    .reg vlan_id
    .reg vlan_tag
    .reg write $mac[4]
    .xfer_order $mac
    .sig sig_write
    .sig sig_read

    __actions_read(vlan_tag, 0xffff)

    pv_get_base_addr(addr_hi, addr_lo, io_pkt_vec)
    mem[read32, $__pv_pkt_data[0], addr_hi, <<8, addr_lo, 3], ctx_swap[sig_read], defer[2]
        alu[addr_lo, addr_lo, -, 4]
	    pv_invalidate_cache(io_pkt_vec)

    alu[$mac[0], --, B, $__pv_pkt_data[0]]
    alu[$mac[1], --, B, $__pv_pkt_data[1]]
    alu[$mac[2], --, B, $__pv_pkt_data[2]]
    alu[$mac[3], vlan_tag, or, 0x81, <<24]

    mem[write32, $mac[0], addr_hi, <<8, addr_lo, 4], ctx_swap[sig_write], defer[2]
        alu[BF_A(io_pkt_vec, PV_LENGTH_bf), BF_A(io_pkt_vec, PV_LENGTH_bf), +, 4]
        alu[BF_A(io_pkt_vec, PV_OFFSET_bf), BF_A(io_pkt_vec, PV_OFFSET_bf), -, 4]

    __actions_restore_t_idx()

    // Add 4 to each non-zero offset
    alu[msk, --, B, 0xff, <<24]
    alu[--, BF_A(io_pkt_vec, PV_HEADER_STACK_bf), +, msk]
    alu[stack, BF_A(io_pkt_vec, PV_HEADER_STACK_bf), AND~, msk], no_cc
    alu[msk, --, B, msk, >>8], no_cc
    alu[stack, stack, +, msk], no_cc
    alu[stack, stack, AND~, msk], no_cc
    alu[msk, --, B, msk, >>8], no_cc
    alu[stack, stack, +, msk], no_cc
    alu[stack, stack, AND~, msk], no_cc
    alu[stack, stack, +, 0xff], no_cc
    alu[stack, stack, AND~, 0xff], no_cc
    alu[stack, stack, +carry, 0]
    alu[stack, --, B, stack, >>rot6]
    alu[BF_A(io_pkt_vec, PV_HEADER_STACK_bf), BF_A(io_pkt_vec, PV_HEADER_STACK_bf), +, stack]

    immed[msk, NULL_VLAN]
    alu[vlan_id, vlan_tag, AND, msk]
    bits_clr__sz1(BF_AL(io_pkt_vec, PV_VLAN_ID_bf), msk) ; PV_VLAN_ID_bf
    bits_set__sz1(BF_AL(io_pkt_vec, PV_VLAN_ID_bf), vlan_id) ; PV_VLAN_ID_bf

.end
#endm


#macro actions_load(in_act_addr)
.begin
    .reg pkt_vec_addr
    .sig sig_actions

    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, 16, OVF_SUBTRACT_ONE)
    ov_clean()
    cls[read, $__actions[0], 0, in_act_addr, max_16], indirect_ref, defer[2], ctx_swap[sig_actions]
        .reg_addr __actions_t_idx 28 B
        alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
        alu[pkt_vec_addr, (PV_META_BASE_wrd * 4), OR, t_idx_ctx, >>(8 - log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1))]

    pv_reset(pkt_vec_addr, in_act_addr, __actions_t_idx, (NIC_MAX_INSTR *4))

.end
#endm


#macro actions_execute(io_pkt_vec, EGRESS_LABEL)
.begin
    .reg ebpf_addr
    .reg jump_idx
    .reg tx_args

next#:
    alu[jump_idx, --, B, *$index, >>INSTR_OPCODE_LSB]
    jump[jump_idx, ins_0#], targets[ins_0#, ins_1#, ins_2#, ins_3#, ins_4#, ins_5#, ins_6#, ins_7#, ins_8#, ins_9#, ins_10#, ins_11#, ins_12#, ins_13#, ins_14#, ins_15#, ins_16#, ins_17#, ins_18#]

    ins_0#: br[drop_act#]
    ins_1#: br[rx_wire#]
    ins_2#: br[mac_dst_match#]
    ins_3#: br[checksum#]
    ins_4#: br[rss#]
    ins_5#: br[tx_host#]
    ins_6#: br[rx_host#]
    ins_7#: br[tx_wire#]
    ins_8#: br[cmsg#]
    ins_9#: br[ebpf#]
    ins_10#: br[pop_vlan#]
    ins_11#: br[push_vlan#]
    ins_12#: br[mac_src_match#]
    ins_13#: br[veb_lookup#]
    ins_14#: br[pkt_pop#]
    ins_15#: br[pkt_push#]
    ins_16#: br[tx_vlan#]
    ins_17#: br[l2_switch_wire#]
    ins_18#: br[l2_switch_host#]

error_pkt_stack#:
    pv_stats_update(io_pkt_vec, ERROR_PKT_STACK, drop#)

drop_mismatch#:
    pv_stats_update(io_pkt_vec, RX_DISCARD_ADDR, drop#)

drop_act#:
    pv_stats_update(io_pkt_vec, RX_DISCARD_ACT, drop#)

rx_wire#:
    __actions_rx_wire(io_pkt_vec)
    __actions_next()

mac_dst_match#:
    __actions_dst_mac_match(io_pkt_vec, drop_mismatch#)
    __actions_next()

checksum#:
    __actions_checksum(io_pkt_vec)
    __actions_next()

rss#:
    __actions_rss(io_pkt_vec)
    __actions_next()

tx_host#:
    __actions_read(tx_args, 0xffff)
    pkt_io_tx_host(io_pkt_vec, tx_args, EGRESS_LABEL)
    __actions_restore_t_idx()
    __actions_next()

rx_host#:
    __actions_rx_host(io_pkt_vec, drop#)
    __actions_next()

tx_wire#:
    __actions_read(tx_args, 0xffff)
    pkt_io_tx_wire(io_pkt_vec, tx_args, EGRESS_LABEL)
    __actions_restore_t_idx()
    __actions_next()

pop_vlan#:
    __actions_pop_vlan(io_pkt_vec)
    __actions_next()

push_vlan#:
    __actions_push_vlan(io_pkt_vec)
    __actions_next()

mac_src_match#:
    __actions_src_mac_match(io_pkt_vec, drop_mismatch#)
    __actions_next()

veb_lookup#:
    __actions_veb_lookup(io_pkt_vec, drop#)
    __actions_next()

pkt_pop#:
    __actions_read()
    pv_pop(io_pkt_vec, error_pkt_stack#)
    __actions_next()

pkt_push#:
    __actions_read()
    pv_push(io_pkt_vec, error_pkt_stack#)
    __actions_restore_t_idx()
    __actions_next()

tx_vlan#:
    __actions_read()
    pkt_io_tx_vlan(io_pkt_vec, EGRESS_LABEL)

cmsg#:
    cmsg_desc_workq($__pkt_io_gro_meta, io_pkt_vec, EGRESS_LABEL)

ebpf#:
    __actions_read(ebpf_addr, 0xffff)
    ebpf_call(io_pkt_vec, ebpf_addr)

l2_switch_wire#:
    __actions_l2_switch_wire(io_pkt_vec, drop_mismatch#)
    __actions_next()

l2_switch_host#:
    __actions_l2_switch_host(io_pkt_vec)
    __actions_next()

.end
#endm

#endif
