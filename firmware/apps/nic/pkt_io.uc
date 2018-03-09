/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   pkt_io.uc
 * @brief  Libraries for packet reception and transmission.
 */

#ifndef _PKT_IO_UC
#define _PKT_IO_UC

#include <bitfields.uc>
#include <timestamp.uc>

#include <nfd_user_cfg.h>

#include <nfd_in.uc>
nfd_in_recv_init()

#include <nfd_out.uc>
nfd_out_send_init()

#include <gro.uc>
.if (ctx() == 0)
    gro_cli_declare()
    gro_cli_init()
    timestamp_enable()
.endif

#include "pv.uc"

.sig volatile __pkt_io_sig_epoch
.addr __pkt_io_sig_epoch 8

.reg volatile write $__pkt_io_gro_meta[GRO_META_SIZE_LW]
.xfer_order $__pkt_io_gro_meta

.sig volatile __pkt_io_sig_nbi
.addr __pkt_io_sig_nbi 9
.reg volatile read $__pkt_io_nbi_desc[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $__pkt_io_nbi_desc

.reg volatile __pkt_io_nfd_pkt_no
.reg_addr __pkt_io_nfd_pkt_no 29 B
.set __pkt_io_nfd_pkt_no
.sig volatile __pkt_io_sig_nfd
.addr __pkt_io_sig_nfd 10
.sig volatile __pkt_io_sig_nfd_retry
.set_sig __pkt_io_sig_nfd_retry
.addr __pkt_io_sig_nfd_retry 11
.reg volatile read $__pkt_io_nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $__pkt_io_nfd_desc

#define __PKT_IO_QUIESCE_NBI 1
#define __PKT_IO_QUIESCE_NFD 2
#define __PKT_IO_QUIESCE_ALL (__PKT_IO_QUIESCE_NBI | __PKT_IO_QUIESCE_NFD)
.sig volatile __pkt_io_sig_resume
.addr __pkt_io_sig_resume 12
.sig volatile __pkt_io_sig_quiesce_nbi
.addr __pkt_io_sig_quiesce_nbi 13
.sig volatile __pkt_io_sig_quiesce_nfd
.addr __pkt_io_sig_quiesce_nfd 14
.reg volatile __pkt_io_quiescent
.reg_addr __pkt_io_quiescent 27 A
.set __pkt_io_quiescent


#macro pkt_io_drop(in_pkt_vec)
    pv_free_buffers(pkt_vec)
    pv_get_gro_drop_desc($__pkt_io_gro_meta, pkt_vec)
#endm


#macro pkt_io_tx_host(in_pkt_vec, egress_q_base)
    pv_acquire_nfd_credit(in_pkt_vec, egress_q_base, rx_discards_no_buf_pci#)
    pv_get_gro_host_desc($__pkt_io_gro_meta, in_pkt_vec, egress_q_base)
    pv_stats_add_octets(in_pkt_vec)
#endm


#macro pkt_io_tx_wire(in_pkt_vec, egress_q_base)
.begin
    .reg pms_offset

    pv_write_nbi_meta(pms_offset, in_pkt_vec, tx_errors_offset#)
    pv_get_gro_wire_desc($__pkt_io_gro_meta, in_pkt_vec, egress_q_base, pms_offset)
    pv_stats_add_octets(in_pkt_vec)
.end
#endm


#macro __pkt_io_dispatch_nbi()
.begin
    .reg addr

    immed[addr, (PKT_NBI_OFFSET / 4)]
    mem[packet_add_thread, $__pkt_io_nbi_desc[0], addr, 0, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], sig_done[__pkt_io_sig_nbi]
.end
#endm


#macro __pkt_io_no_ctm_buffer()
.begin
    .reg future
    local_csr_wr[ACTIVE_FUTURE_COUNT_SIGNAL, &__pkt_io_sig_nfd_retry]
    local_csr_rd[TIMESTAMP_LOW]
    immed[future, 0]
    alu[future, future, +, 250] // 4000 cycles
    local_csr_wr[ACTIVE_CTX_FUTURE_COUNT, future]
.end
#endm


#macro __pkt_io_dispatch_nfd()
    pkt_buf_alloc_ctm(__pkt_io_nfd_pkt_no, PKT_BUF_ALLOC_CTM_SZ_256B, skip_dispatch#, __pkt_io_no_ctm_buffer)
    nfd_in_recv($__pkt_io_nfd_desc, 0, 0, 0, __pkt_io_sig_nfd, SIG_DONE)
skip_dispatch#:
#endm


#macro pkt_io_init(out_pkt_vec)
    immed[__pkt_io_quiescent, 0]
    alu[BF_A(out_pkt_vec, PV_QUEUE_IN_TYPE_bf), --, B, 1, <<BF_L(PV_QUEUE_IN_TYPE_bf)]
    __pkt_io_dispatch_nbi()
#endm


#macro __pkt_io_quiesce_wait_active(in_quiesce_source, RESUME_LABEL, in_active_source, RX_LABEL, QUIESCENCE_LABEL)
    alu[__pkt_io_quiescent, __pkt_io_quiescent, OR, __PKT_IO_QUIESCE_/**/in_quiesce_source]
    br=byte[__pkt_io_quiescent, 0, __PKT_IO_QUIESCE_ALL, QUIESCENCE_LABEL]
    ctx_arb[__pkt_io_sig_/**/in_active_source, __pkt_io_sig_resume], any
    br_signal[__pkt_io_sig_/**/in_active_source, RX_LABEL]
    br_signal[__pkt_io_sig_quiesce_/**/in_active_source, consume_quiesce_sig#]
consume_quiesce_sig#:
    immed[__pkt_io_quiescent, 0]
    br_signal[__pkt_io_sig_resume, RESUME_LABEL]
#endm


#macro pkt_io_rx(io_vec)
    br_bset[BF_AL(io_vec, PV_QUEUE_IN_TYPE_bf), nfd_dispatch#] // previous packet was NFD, dispatch another

nbi_dispatch#:
    br_signal[__pkt_io_sig_quiesce_nbi, quiesce_nbi#]
    __pkt_io_dispatch_nbi()

wait_nfd_priority#:
    ctx_arb[__pkt_io_sig_epoch, __pkt_io_sig_nbi, __pkt_io_sig_nfd, __pkt_io_sig_nfd_retry], any
    br_signal[__pkt_io_sig_nfd_retry, nfd_dispatch#]
    br_signal[__pkt_io_sig_epoch, wait_nfd_priority#]

clear_sig_rx_nfd#:
    br_!signal[__pkt_io_sig_nfd, clear_sig_rx_nbi#] // __pkt_io_sig_nbi is asserted

rx_nfd#:
    pv_init_nfd(io_vec, __pkt_io_nfd_pkt_no, $__pkt_io_nfd_desc)
    br[end#]

quiesce_nbi#:
    __pkt_io_quiesce_wait_active(NBI, nbi_dispatch#, nfd, rx_nfd#, quiescence#)

quiesce_nfd#:
    __pkt_io_quiesce_wait_active(NFD, nfd_dispatch#, nbi, rx_nbi#, quiescence#)

quiescence#:
    ctx_arb[__pkt_io_sig_resume]
    pkt_io_init(io_vec)

nfd_dispatch#:
    br_signal[__pkt_io_sig_quiesce_nfd, quiesce_nfd#]
    __pkt_io_dispatch_nfd()

wait_nbi_priority#:
    ctx_arb[__pkt_io_sig_epoch, __pkt_io_sig_nbi, __pkt_io_sig_nfd, __pkt_io_sig_nfd_retry], any
    br_signal[__pkt_io_sig_nfd_retry, nfd_dispatch#]
    br_signal[__pkt_io_sig_epoch, wait_nbi_priority#]

clear_sig_rx_nbi#:
    br_!signal[__pkt_io_sig_nbi, clear_sig_rx_nfd#] // __pkt_io_sig_nfd is asserted

rx_nbi#:
    pv_init_nbi(io_vec, $__pkt_io_nbi_desc)

end#:
#endm


#macro pkt_io_reorder(in_pkt_vec)
.begin
    .reg seq_ctx
    .reg seq_no

    pv_get_seq_ctx(seq_ctx, in_pkt_vec)
    pv_get_seq_no(seq_no, in_pkt_vec)

    gro_cli_send(seq_ctx, seq_no, $__pkt_io_gro_meta, 0)
.end
#endm


#endif
