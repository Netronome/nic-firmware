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
    alu[--, mac[0], XOR, *$index++]
    bne[DROP_LABEL]
    alu[tmp, mac[1], XOR, *$index++]

    __actions_restore_t_idx()

    alu[--, --, B, tmp, >>16]
    bne[DROP_LABEL]
.end
#endm


#macro __actions_rss(in_pkt_vec)
.begin
    .reg src_ip
    .reg queue

    __actions_read(--, --, --)
    __actions_read(--, --, --)

    pv_seek(in_pkt_vec, 26, 4)
    byte_align_be[--, *$index++]
    byte_align_be[src_ip, *$index]

    __actions_restore_t_idx()

    alu[queue, src_ip, AND, 0x7]
    pv_set_egress_queue(in_pkt_vec, queue)
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
    __actions_nop(1)
    __actions_next()

tx_host#:
    pkt_io_tx_host(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL)

tx_wire#:
    pkt_io_tx_wire(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL)

.end
#endm

#endif

