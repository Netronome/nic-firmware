#include <nfd_user_cfg.h>

#include <ov.uc>

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

.num_contexts 4

/* Optimization and simplifying assumptions */
// - 4 CTX mode
// - LM Index 0 is reserved for local use (code that does not call into other code)
// - Single NBI
// - Single PCIe

#macro pkt_tx_host(out_gro_meta, in_pkt_vec, in_egress_queue, SUCCESS_LABEL, FAIL_LABEL)
    pv_get_gro_host_desc(out_gro_meta, in_pkt_vec, in_egress_queue)
    nfd_cc_acquire(0, egress_queue, FAIL_LABEL)
    br[SUCCESS_LABEL]
#endm

#macro pkt_tx_wire(out_gro_meta, in_pkt_vec, in_egress_queue, SUCCESS_LABEL, FAIL_LABEL)
.begin
    #define PMS_OFFSET (128-16)
    
    .reg gro_prev_alu
    .reg ctm_addr

    .reg read $dummy

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
    immed[$prepend[0], ((1 << 15) | (3 << 1)), <<16] // direct packet modifier script, delete 4 bytes
    immed[$prepend[1], 0] // pad
    immed[$prepend[2], 0] // sop, to be deleted
    pv_get_mac_prepend($prepend[3], in_pkt_vec) // real sop
    
    // write prepends
    mem[write32, $prepend[0], ctm_addr, <<8, PMS_OFFSET, 4], sig_done[sig_wr_prepend]
    
    // build GRO descriptor for NBI transmission
    pv_get_gro_wire_desc(out_gro_meta, in_pkt_vec, in_egress_queue, PMS_OFFSET)
 
    // ensure prepends have been written before releasing packet   
    mem[read32, $dummy, ctm_addr, <<8, PMS_OFFSET, 1], sig_done[sig_rd_prepend]

    ctx_arb[sig_wr_nbi_meta, sig_wr_prepend, sig_rd_prepend], br[SUCCESS_LABEL]
    
    #undef PMS_OFFSET
.end
#endm 

timestamp_enable()

.reg write $gro_meta[GRO_META_SIZE_LW]
.xfer_order $gro_meta

.reg pkt_vec[PV_SIZE_LW]

.reg ingress_queue
.reg egress_queue

.reg seq_ctx
.reg seq_no

pv_init(pkt_vec)

immed[egress_queue, 0]

br[ingress#]

drop#:
    pv_get_gro_drop_desc($gro_meta, pkt_vec)
    pv_free_buffers(pkt_vec)

egress#:
    pv_get_seq_ctx(seq_ctx, pkt_vec) 
    pv_get_seq_no(seq_no, pkt_vec) 
    gro_cli_send(seq_ctx, seq_no, $gro_meta, 0) 

ingress#:
    pv_listen(pkt_vec, ingress_queue, drop#)

    pv_propagate_mac_csum_status(pkt_vec)

    .if (BIT(pkt_vec[4], 7))
        alu[egress_queue, egress_queue, +, 1]
        alu[egress_queue, egress_queue, AND, 7]
        pkt_tx_host($gro_meta, pkt_vec, egress_queue, egress#, drop#)
    .else
        pkt_tx_wire($gro_meta, pkt_vec, 0, egress#, drop#)
    .endif
nop
