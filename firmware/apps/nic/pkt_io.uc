/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   pkt_io.uc
 * @brief  Libraries for packet reception and transmission.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _PKT_IO_UC
#define _PKT_IO_UC

#include <bitfields.uc>
#include <timestamp.uc>

#include <nfd_user_cfg.h>
#include <nfd_cfg.uc>

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
.addr $__pkt_io_nbi_desc[0] 52
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
.addr $__pkt_io_nfd_desc[0] 48
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
    pv_free($__pkt_io_gro_meta, pkt_vec)
#endm


#macro pkt_io_rx_host(io_vec, in_mtu, DROP_LABEL)
    #pragma warning(push)
    #pragma warning(disable:5009) // rx_host is only invoked when $__pkt_io_nfd_desc ready
    pv_init_nfd(io_vec, __pkt_io_nfd_pkt_no, $__pkt_io_nfd_desc, in_mtu, DROP_LABEL)
    #pragma warning(pop)
#endm


#macro pkt_io_tx_host(io_pkt_vec, in_tx_args, IN_LABEL)
.begin
    .reg bls
    .reg buf_sz
    .reg addr_hi
    .reg addr_lo
    .reg meta_len
    .reg min_rxb
    .reg mu_addr
    .reg multicast
    .reg pci_isl
    .reg pci_q
    .reg read $rxb
    .reg read $nfd_credits
    .reg write $nfd_desc[4]
    .xfer_order $nfd_desc
    .sig sig_nfd
    .sig sig_rd

    #ifdef PV_MULTI_PCI
        alu[pci_isl, 3, AND, in_tx_args, >>6]
    #endif
    alu[pci_q, in_tx_args, +8, BF_A(io_pkt_vec, PV_QUEUE_OFFSET_bf)]
    alu[pci_q, pci_q, AND, 0x3f]

    bitfield_extract__sz1(bls, BF_AML(io_pkt_vec, PV_BLS_bf))
    passert(BF_L(PV_MAC_DST_MC_bf), "EQ", BF_L(INSTR_TX_CONTINUE_bf))
    passert(BF_L(PV_MAC_DST_MC_bf), "EQ", (BF_L(INSTR_TX_MULTICAST_bf) + 1))
    alu[multicast, BF_A(io_pkt_vec, PV_MAC_DST_MC_bf), AND, in_tx_args, <<1]
    alu[multicast, multicast, OR, in_tx_args]
    br_bset[multicast, BF_L(INSTR_TX_CONTINUE_bf), multicast#]

check_mru#:
    pv_meta_write(meta_len, io_pkt_vec)
    pv_get_required_host_buf_sz(buf_sz, io_pkt_vec, meta_len)
    alu[min_rxb, in_tx_args, AND, BF_MASK(INSTR_TX_HOST_MIN_RXB_bf), <<BF_L(INSTR_TX_HOST_MIN_RXB_bf)]
    alu[--, min_rxb, -, buf_sz]
    bmi[buf_sz_check#]

check_credits#:
    #ifdef PV_MULTI_PCI
        alu[addr_hi, (__NFD_DIRECT_ACCESS | NFD_PCIE_ISL_BASE), OR, pci_isl]
        alu[addr_hi, --, B, addr_hi, <<24]
    #else
        alu[addr_hi, --, B, (__NFD_DIRECT_ACCESS | NFD_PCIE_ISL_BASE), <<24]
    #endif
    alu[addr_lo, --, B, pci_q, <<(log2(NFD_OUT_ATOMICS_SZ))]
    ov_single(OV_IMMED8, 1)
    mem[test_subsat_imm, $nfd_credits, addr_hi, <<8, addr_lo, 1], indirect_ref, ctx_swap[sig_nfd]

    alu[--, --, B, $nfd_credits]
    beq[drop_buf_pci#]

    br=byte[bls, 0, 3, tx_nfd#]

#ifdef PV_MULTI_PCI
    pv_get_gro_host_desc($__pkt_io_gro_meta, io_pkt_vec, buf_sz, meta_len, pci_isl, pci_q)
#else
    pv_get_gro_host_desc($__pkt_io_gro_meta, io_pkt_vec, buf_sz, meta_len, 0, pci_q)
#endif

tx_stats_update#:
    pv_stats_tx_host(io_pkt_vec, pci_isl, pci_q, multicast, IN_LABEL, end#)

multicast#:
    pv_multicast_init(io_pkt_vec, bls, check_mru#)

tx_nfd#:
    pv_multicast_resend(io_pkt_vec)
    immed[addr_lo, nfd_out_ring_info]
    #ifdef PV_MULTI_PCI
        alu[addr_lo, addr_lo, OR, pci_isl, <<(log2(NFD_OUT_RING_INFO_ITEM_SZ))]
    #endif

    local_csr_wr[ACTIVE_LM_ADDR_0, addr_lo]

    pv_get_nfd_host_desc($nfd_desc, io_pkt_vec, buf_sz, meta_len, pci_q)

    alu[addr_hi, *l$index0, AND, 0xff, <<24]
    ld_field_w_clr[addr_lo, 0011, *l$index0]
    mem[qadd_work, $nfd_desc[0], addr_hi, <<8, addr_lo, 4], sig_done[sig_nfd]
    ctx_arb[sig_nfd], br[tx_stats_update#]

buf_sz_check#:
    move(addr_hi, (_fl_buf_sz_cache >> 8))
    alu[addr_lo, --, B, pci_q, <<2]
#ifdef PV_MULTI_PCI
    alu[addr_lo, addr_lo, OR, pci_isl, <<(6 + 2)]
#endif
    mem[read32, $rxb, addr_hi, <<8, addr_lo, 1], ctx_swap[sig_rd]
    alu[--, $rxb, -, buf_sz]
    bge[check_credits#]

#ifdef PV_MULTI_PCI
    alu[pci_q, pci_q, OR, pci_isl, <<6]
#endif
    pv_stats_update(io_pkt_vec, RX_DISCARD_MRU, pci_q, safe_drop#)

drop_buf_pci#:
#ifdef PV_MULTI_PCI
    alu[pci_q, pci_q, OR, pci_isl, <<6]
#endif
    pv_stats_update(io_pkt_vec, RX_DISCARD_PCI, pci_q, --)

safe_drop#:
    br_bset[multicast, BF_L(INSTR_TX_CONTINUE_bf), drop_later_or_ignore#]

    /* this TX_HOST is the last action */
    br=byte[bls, 0, 3, IN_LABEL]
    br[drop#]

drop_later_or_ignore#:
    /* more actions follow */
    br=byte[bls, 0, 3, end#]
    pv_get_gro_mu_free_desc($__pkt_io_gro_meta, io_pkt_vec)

end#:
.end
#endm


#macro pkt_io_rx_wire(io_vec, in_rx_args)
    #pragma warning(push)
    #pragma warning(disable:5009) // rx_wire is only invoked when $__pkt_io_nbi_desc ready
    pv_init_nbi(io_vec, $__pkt_io_nbi_desc, in_rx_args)
    #pragma warning(pop)
#endm


#macro pkt_io_tx_wire(in_pkt_vec, in_tx_args, IN_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg bls
    .reg multicast
    .reg nbi
    .reg tm_q
    .reg pms_offset
    .reg resend_desc[4]

    // CTM buffer is required for TX via NBI
    passert(BF_L(PV_MAC_DST_MC_bf), "EQ", BF_L(INSTR_TX_CONTINUE_bf))
    passert(BF_L(PV_MAC_DST_MC_bf), "EQ", (BF_L(INSTR_TX_MULTICAST_bf) + 1))
    br_bclr[BF_AL(in_pkt_vec, PV_CTM_ALLOCATED_bf), error_no_ctm#], defer[3]
        bitfield_extract__sz1(bls, BF_AML(in_pkt_vec, PV_BLS_bf))
        alu[multicast, BF_A(in_pkt_vec, PV_MAC_DST_MC_bf), AND, in_tx_args, <<1]
        alu[multicast, multicast, OR, in_tx_args]

    pv_write_nbi_meta(pms_offset, in_pkt_vec, error_offset#)

    #if (NBI_COUNT > 1)
        bitfield_extract__sz1(nbi, BF_AML(in_tx_args, INSTR_TX_WIRE_NBI_bf)) ; INSTR_TX_WIRE_NBI_bf
    #endif
    alu[tm_q, in_tx_args, AND~, (((~BF_MASK(INSTR_TX_WIRE_TMQ_bf)) & 0xffff) >> 8), <<8]

    br=byte[bls, 0, 3, tx_nbi#]

    pv_get_gro_wire_desc($__pkt_io_gro_meta, in_pkt_vec, nbi, tm_q, pms_offset)

    br_bset[multicast, BF_L(INSTR_TX_CONTINUE_bf), multicast#]

terminate#:
    pv_stats_tx_wire(in_pkt_vec, IN_LABEL)

error_no_ctm#:
    pv_stats_update(in_pkt_vec, TX_ERROR_NO_CTM, safe_drop#)

error_offset#:
    pv_stats_update(in_pkt_vec, TX_ERROR_OFFSET, --)

safe_drop#:
    br_bset[multicast, BF_L(INSTR_TX_CONTINUE_bf), drop_later_or_ignore#]

    /* this TX_HOST is the last action */
    br=byte[bls, 0, 3, IN_LABEL]
    br[drop#]

drop_later_or_ignore#:
    /* more actions follow */
    br=byte[bls, 0, 3, end#]
    pv_get_gro_mu_free_desc($__pkt_io_gro_meta, in_pkt_vec)

multicast#:
    pv_multicast_init(in_pkt_vec, bls, continue#)

tx_nbi#:
    pv_multicast_resend(in_pkt_vec)
    pv_setup_packet_ready(addr_hi, addr_lo, in_pkt_vec, nbi, tm_q, pms_offset)
    nbi[packet_ready_multicast_dont_free, $, addr_hi, <<8, addr_lo], indirect_ref

    br_bclr[multicast, BF_L(INSTR_TX_CONTINUE_bf), terminate#]

continue#:
    pv_stats_tx_wire(in_pkt_vec)

end#:
.end
#endm


#macro pkt_io_tx_vlan(io_pkt_vec, IN_LABEL)
.begin
    .reg addr_hi
    .reg addr_lo
    .reg map_base
    .reg meta_len
    .reg min_rxb
    .reg pci_q
    .reg buf_sz
    .reg src_q
    .reg vlan_id
    .reg vlan_ports[2] // top six bits of vlan_ports[0] used to store base queue when processing flips to 2nd word
    .reg null_vlan_id
    .reg read $vf_rxb
    .reg read $nfd_credits
    .reg write $nfd_desc[4]
    .xfer_order $nfd_desc
    .reg read $vlan_ports[2]
    .xfer_order $vlan_ports
    .reg $mac[3]
    .xfer_order $mac
    .sig sig_nfd
    .sig sig_rd
    .sig sig_wr

    immed[map_base, (_vf_vlan_cache >> 16), <<(16 - 8)]

    bitfield_extract(vlan_id, BF_AML(io_pkt_vec, PV_VLAN_ID_bf))
    alu[addr_lo, --, B, vlan_id, <<3]

    mem[read32, $vlan_ports[0], map_base, <<8, addr_lo, 2], ctx_swap[sig_rd], defer[2]
        immed[null_vlan_id, NULL_VLAN]
        immed[addr_lo, nfd_out_ring_info] // note, TX_VLAN does not support multi-PCIe

    local_csr_wr[ACTIVE_LM_ADDR_0, addr_lo]

    bitfield_extract__sz1(src_q, BF_AML(io_pkt_vec, PV_QUEUE_IN_bf)) ; PV_QUEUE_IN_bf
    pv_get_base_addr(addr_hi, addr_lo, io_pkt_vec)

    alu[--, vlan_id, -, null_vlan_id]
    beq[null_vlan#], defer[3]
        alu[min_rxb, 0xff, ~AND, $vlan_ports[0], >>(26-8)]
        alu[vlan_ports[0], $vlan_ports[0], AND~, 0x3f, <<26]
        alu[vlan_ports[1], --, B, $vlan_ports[1]]

strip_vlan#:
    mem[read32, $mac[0], addr_hi, <<8, addr_lo, 3], ctx_swap[sig_rd], defer[2]
        alu[addr_lo, addr_lo, +, 4]
        alu[BF_A(io_pkt_vec, PV_OFFSET_bf), BF_A(io_pkt_vec, PV_OFFSET_bf), +, 4]
    alu[$mac[0], --, B, $mac[0]]
    alu[$mac[1], --, B, $mac[1]]
    #pragma warning(disable:5009)
    #pragma warning(disable:4700)
    mem[write32, $mac[0], addr_hi, <<8, addr_lo, 3], ctx_swap[sig_wr], defer[2]
    #pragma warning(default:4700)
        alu[$mac[2], --, B, $mac[2]]
    #pragma warning(default:5009)
        alu[BF_A(io_pkt_vec, PV_LENGTH_bf), BF_A(io_pkt_vec, PV_LENGTH_bf), -, 4]

null_vlan#:
    pv_meta_write(meta_len, io_pkt_vec, addr_hi, addr_lo)
    pv_get_nfd_host_desc($nfd_desc, io_pkt_vec, meta_len)
    pv_get_required_host_buf_sz(buf_sz, io_pkt_vec, meta_len)

tx_vlan_loop#:
    alu[--, --, B, vlan_ports[1]]
    beq[check_done#]

    ffs[pci_q, vlan_ports[1]]
    alu[pci_q, pci_q, OR, vlan_ports[0], >>26]
    alu[vlan_ports[1], vlan_ports[1], AND~, 1, <<indirect]

    alu[--, src_q, -, pci_q]
    beq[tx_vlan_loop#]

    alu[--, min_rxb, -, buf_sz]
    bmi[vf_buf_sz_check#]

packet_fits#:
    alu[addr_hi, --, B, (__NFD_DIRECT_ACCESS | NFD_PCIE_ISL_BASE), <<24]
    alu[addr_lo, --, B, pci_q, <<(log2(NFD_OUT_ATOMICS_SZ))]
    ov_single(OV_IMMED8, 1)
    mem[test_subsat_imm, $nfd_credits, addr_hi, <<8, addr_lo, 1], indirect_ref, ctx_swap[sig_nfd]

    alu[--, --, B, $nfd_credits]
    beq[no_tx_continue#]

    pv_multicast_resend(io_pkt_vec)

    pv_update_nfd_desc_queue($nfd_desc, io_pkt_vec, buf_sz, meta_len, pci_q)

    alu[addr_hi, *l$index0, AND, 0xff, <<24]
    ld_field_w_clr[addr_lo, 0011, *l$index0]
    mem[qadd_work, $nfd_desc[0], addr_hi, <<8, addr_lo, 4], ctx_swap[sig_nfd]

    pv_stats_tx_host(io_pkt_vec, 0, pci_q, --, tx_vlan_loop#, --)

vf_buf_sz_check#:
    move(addr_hi, (_fl_buf_sz_cache >> 8))
    alu[addr_lo, --, B, pci_q, <<2]
    mem[read32, $vf_rxb, addr_hi, <<8, addr_lo, 1], ctx_swap[sig_rd]
    alu[--, $vf_rxb, -, buf_sz]
    bge[packet_fits#]

    pv_stats_update(io_pkt_vec, RX_DISCARD_MRU, pci_q, tx_vlan_loop#)

no_tx_continue#:
    pv_stats_update(io_pkt_vec, RX_DISCARD_PCI, pci_q, tx_vlan_loop#)

pop_error#:
    pv_stats_update(io_pkt_vec, ERROR_PKT_STACK, IN_LABEL)

check_done#:
    alu[vlan_ports[1], vlan_ports[0], AND~, 0x3f, <<26]
    bne[tx_vlan_loop#], defer[1]
        alu[vlan_ports[0], --, B, 32, <<26]

    alu[--, vlan_id, -, null_vlan_id]
    beq[IN_LABEL]

    pv_pop(io_pkt_vec, pop_error#)

    immed[vlan_id, NULL_VLAN]
    alu[addr_lo, --, B, vlan_id, <<3]
    mem[read32, $vlan_ports[0], map_base, <<8, addr_lo, 2], ctx_swap[sig_rd]

    pv_get_base_addr(addr_hi, addr_lo, io_pkt_vec)

    alu[vlan_ports[1], --, B, $vlan_ports[1]]
    br[null_vlan#], defer[2]
        alu[min_rxb, 0xff, ~AND, $vlan_ports[0], >>(26-8)]
        alu[vlan_ports[0], $vlan_ports[0], AND~, 0x3f, <<26]

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
    alu[BF_A(out_pkt_vec, PV_QUEUE_IN_TYPE_bf), --, B, 0, <<BF_L(PV_QUEUE_IN_TYPE_bf)]
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


#macro pkt_io_rx(out_act_addr, io_vec)
    br_bclr[BF_AL(io_vec, PV_QUEUE_IN_TYPE_bf), nfd_dispatch#] // previous packet was NFD, dispatch another

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
    br[end#], defer[2]
        passert(NIC_CFG_INSTR_TBL_ADDR, "EQ", 0)
        alu[out_act_addr, 0xff, AND, BF_A($__pkt_io_nfd_desc, NFD_IN_QID_fld)]
        alu[out_act_addr, --, B, out_act_addr, <<(log2(NIC_MAX_INSTR * 4))]

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
    passert(NIC_CFG_INSTR_TBL_ADDR, "EQ", 0)
    dbl_shf[out_act_addr, 1, BF_A($__pkt_io_nbi_desc, CAT_PORT_bf), >>BF_L(CAT_PORT_bf)] ; CAT_PORT_bf
    alu[out_act_addr, --, B, out_act_addr, <<(log2(NIC_MAX_INSTR * 4))]

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
