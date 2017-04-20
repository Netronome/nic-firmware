#ifndef _ACTIONS_UC
#define _ACTIONS_UC

#include "app_config_instr.h"

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
    
    //Allow multicast addresses to pass
    br_bset[*$index, BF_L(MAC_MULTICAST_bf), is_multicast#]
    
    alu[--, mac[0], XOR, *$index++]
    bne[DROP_LABEL]
    alu[tmp, mac[1], XOR, *$index++]

    __actions_restore_t_idx()

    alu[--, --, B, tmp, >>16]
    bne[DROP_LABEL]
    
is_multicast#:
.end
#endm

#define ACTION_RSS_CFG_L3_BIT 0
#define ACTION_RSS_CFG_L4_BIT 1

#define L4_PROTO_TCP          6
#define L4_PROTO_UDP          17

#macro __actions_rss(in_pkt_vec)
.begin
    .reg data
    .reg ipv4_delta
    .reg key
    .reg offset
    .reg opcode
    .reg protocol
    .reg queue
    .reg shift
    .reg vlans

    __actions_read(opcode, --, --)
    __actions_read(key, --, --)

    // skip RSS for unkown L3 or bad IPv4 checksum
    br_bclr[BF_AL(in_pkt_vec, PV_PARSE_L3I_bf), skip_rss#]

    // skip RSS for MPLS packets
    bitfield_extract__sz1(--, BF_AML(in_pkt_vec, PV_PARSE_MPD_bf))
    bne[skip_rss#]

    // skip RSS for 3 or more VLAN tags
    bitfield_extract__sz1(vlans, BF_AML(in_pkt_vec, PV_PARSE_VLD_bf))
    br=byte[vlans, 0, 3, skip_rss#]

    local_csr_wr[CRC_REMAINDER, key]

    // seek to L3 protocol word
    alu[offset, --, B, vlans, <<2]
    alu[offset, offset, +, (14 - 4)]
    alu[ipv4_delta, (1 << 2), AND, BF_A(in_pkt_vec, PV_PARSE_L3I_bf), >>(BF_M(PV_PARSE_L3I_bf) - 2)]
    alu[offset, offset, +, ipv4_delta]
    pv_seek(in_pkt_vec, offset, 44)

    byte_align_be[--, *$index++]
    byte_align_be[protocol, *$index++]
    alu[shift, (1 << 3), AND, BF_A(in_pkt_vec, PV_PARSE_L3I_bf), >>(BF_M(PV_PARSE_L3I_bf) - 3)]

    // skip CRC over L3 if not requested
    br_bclr[opcode, ACTION_RSS_CFG_L3_BIT, skip_l3#], defer[3]
        alu[shift, shift, +, 8]
        alu[--, shift, OR, 0]
        alu[protocol, 0xff, AND, protocol, >>indirect]

    byte_align_be[data, *$index++]
    br_bset[BF_A(in_pkt_vec, PV_PARSE_L3I_bf), BF_M(PV_PARSE_L3I_bf), skip_l3#], defer[3]
        crc_be[crc_32, --, data]
        byte_align_be[data, *$index++]
        crc_be[crc_32, --, data]

    #define_eval LOOP (0)
    #while (LOOP < 6)
        byte_align_be[data, *$index++]
        crc_be[crc_32, --, data]
        #define_eval LOOP (LOOP + 1)
    #endloop
    #undef LOOP

skip_l3#:
    br_bclr[opcode, ACTION_RSS_CFG_L4_BIT, skip_l4#]

    alu[--, protocol, -, L4_PROTO_UDP]
    beq[process_l4#], defer[1]
        byte_align_be[data, *$index++]

    alu[--, protocol, -, L4_PROTO_TCP]
    bne[skip_l4#]

process_l4#:
    crc_be[crc_32, --, data]
    nop
    nop
    nop
    nop

skip_l4#:
    __actions_restore_t_idx()
    local_csr_rd[CRC_REMAINDER]
    immed[queue, 0]
    alu[queue, queue, AND, 7]
    pv_set_egress_queue(in_pkt_vec, queue)

skip_rss#:
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


#macro actions_execute(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL, SILENT_DROP_LABEL, ERROR_LABEL)
.begin
    .reg act_t_idx
    .reg addr
    .reg jump_idx

    .reg read $actions[NIC_MAX_INSTR]
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
    jump[jump_idx, i0#], targets[i0#, i1#, i2#, i3#, i4#, i5#, i6#]

        i0#: br[drop#]
        i1#: br[mtu#]
        i2#: br[mac#]
        i3#: br[rss#]
        i4#: br[checksum_complete#]
        i5#: br[tx_host#]
        i6#: br[tx_wire#]

drop#:
    br[SILENT_DROP_LABEL]

mtu#:
    __actions_check_mtu(in_pkt_vec, COUNT_DROP_LABEL)
    __actions_next()

mac#:
    __actions_check_mac(in_pkt_vec, SILENT_DROP_LABEL)
    __actions_next()

rss#:
    __actions_rss(in_pkt_vec)
    __actions_next()

checksum_complete#:
    pv_propagate_mac_csum_status(in_pkt_vec) // checksum unecessary for now
    __actions_next()

tx_host#:
    pkt_io_tx_host(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL)

tx_wire#:
    pkt_io_tx_wire(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL)

.end
#endm

#endif

