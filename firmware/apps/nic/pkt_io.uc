#ifndef _PKT_IO_UC
#define _PKT_IO_UC

#include <bitfields.uc>

#include <nfd_user_cfg.h>

#include <nfd_in.uc>
nfd_in_recv_init()

#include <nfd_out.uc>
nfd_out_send_init()

#include <gro.uc>
.if (ctx() == 0)
    gro_cli_declare()
    gro_cli_init()
.endif

#include "pv.uc"
#include "nfd_cc.uc"

timestamp_enable()

.reg volatile write $__pkt_io_gro_meta[GRO_META_SIZE_LW]
.xfer_order $__pkt_io_gro_meta


#macro pkt_io_drop(in_pkt_vec)
    pv_free_buffers(pkt_vec)
    pv_get_gro_drop_desc($__pkt_io_gro_meta, pkt_vec)
#endm


#macro pkt_io_tx_host(in_pkt_vec, SUCCESS_LABEL, FAIL_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg pkt_len

    pv_acquire_nfd_credit(in_pkt_vec, FAIL_LABEL)

    pv_stats_update_nfd_sent(in_pkt_vec)
    pv_stats_add_tx_octets(in_pkt_vec)

    pv_get_gro_host_desc($__pkt_io_gro_meta, in_pkt_vec)

    br[SUCCESS_LABEL]
.end
#endm


#macro pkt_io_tx_wire(in_pkt_vec, SUCCESS_LABEL, FAIL_LABEL)
.begin
    #define PMS_OFFSET (128-16)

    .reg gro_prev_alu
    .reg ctm_addr

    .reg read $tmp

    .reg write $nbi_meta[2]
    .xfer_order $nbi_meta

    .reg write $prepend[4]
    .xfer_order $prepend

    .sig sig_wr_nbi_meta
    .sig sig_wr_prepend
    .sig sig_rd_prepend

    pv_get_ctm_base(ctm_addr, in_pkt_vec)

    // write NBI metadata
    pv_get_nbi_meta($nbi_meta, in_pkt_vec)
    mem[write32, $nbi_meta[0], ctm_addr, <<8, 0, 2], sig_done[sig_wr_nbi_meta]

    // build packet modifier script and MAC prepend
    #if (NFD_IN_DATA_OFFSET != 128)
       #error "Packet modifier script hard coded for NFD_IN_DATA_OFFSET = 128"
    #endif
    immed[$prepend[0], ((1 << 8) | (6 << 0)), <<16] // indirect packet modifier script, delete 4 bytes, pad
    immed[$prepend[1], 0] // offsets
    immed[$prepend[2], 0] // sop, to be deleted
    pv_get_mac_prepend($prepend[3], in_pkt_vec) // real sop

    // write prepends
    mem[write32, $prepend[0], ctm_addr, <<8, PMS_OFFSET, 4], sig_done[sig_wr_prepend]

    // build GRO descriptor for NBI transmission
    pv_get_gro_wire_desc($__pkt_io_gro_meta, in_pkt_vec, PMS_OFFSET)

    // ensure prepends have been written before releasing packet
    mem[read32, $tmp, ctm_addr, <<8, PMS_OFFSET, 1], sig_done[sig_rd_prepend]

    pv_stats_add_tx_octets(in_pkt_vec)

    ctx_arb[sig_wr_nbi_meta, sig_wr_prepend, sig_rd_prepend], br[SUCCESS_LABEL]

    #undef PMS_OFFSET
.end
#endm


.sig volatile __pkt_io_sig_nbi
.reg volatile read $__pkt_io_nbi_desc[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $__pkt_io_nbi_desc
#macro __pkt_io_dispatch_nbi()
.begin
    .reg addr
    immed[addr, (PKT_NBI_OFFSET / 4)]
    mem[packet_add_thread, $__pkt_io_nbi_desc[0], addr, 0, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], sig_done[__pkt_io_sig_nbi]
.end
#endm


.reg volatile __pkt_io_ctm_pkt_no
.sig volatile __pkt_io_sig_nfd
.sig volatile __pkt_io_sig_nfd_retry
.set_sig __pkt_io_sig_nfd_retry
.reg volatile read $__pkt_io_nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $__pkt_io_nfd_desc
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
    pkt_buf_alloc_ctm(__pkt_io_ctm_pkt_no, PKT_BUF_ALLOC_CTM_SZ_256B, skip_dispatch#, __pkt_io_no_ctm_buffer)
    nfd_in_recv($__pkt_io_nfd_desc, 0, 0, 0, __pkt_io_sig_nfd, SIG_DONE)
skip_dispatch#:
#endm


#macro pkt_io_init(out_pkt_vec)
    alu[BF_A(out_pkt_vec, PV_QUEUE_IN_NBI_bf), --, B, 0, <<BF_L(PV_QUEUE_IN_NBI_bf)]
    __pkt_io_dispatch_nbi()
#endm


#macro pkt_io_rx(io_vec, DROP_LABEL, RX_NBI_ERROR_LABEL, RX_NFD_ERROR_LABEL)
.begin
    .reg pkt_len

    br_bclr[BF_AL(io_vec, PV_QUEUE_IN_NBI_bf), nfd_dispatch#]

    // previously processed packet was from NBI
    __pkt_io_dispatch_nbi()

listen_with_nfd_priority#:
    br_signal[__pkt_io_sig_nfd_retry, nfd_dispatch#]
    br_signal[__pkt_io_sig_nfd, rx_nfd#]
    br_signal[__pkt_io_sig_nbi, rx_nbi#]
    ctx_arb[__pkt_io_sig_nbi, __pkt_io_sig_nfd, __pkt_io_sig_nfd_retry], any, br[listen_with_nbi_priority#]

nfd_dispatch#:
    // previously processed packet was from NFD
    __pkt_io_dispatch_nfd()

listen_with_nbi_priority#:
    br_signal[__pkt_io_sig_nbi, rx_nbi#]
    br_signal[__pkt_io_sig_nfd_retry, nfd_dispatch#]
    br_signal[__pkt_io_sig_nfd, rx_nfd#]
    ctx_arb[__pkt_io_sig_nbi, __pkt_io_sig_nfd, __pkt_io_sig_nfd_retry], any, br[listen_with_nfd_priority#]

rx_nbi#:
    pv_init_nbi(io_vec, $__pkt_io_nbi_desc, DROP_LABEL, RX_NBI_ERROR_LABEL)
    br[end#]

rx_nfd#:
    pv_init_nfd(io_vec, __pkt_io_ctm_pkt_no, $__pkt_io_nfd_desc, RX_NFD_ERROR_LABEL)

end#:
.end
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
