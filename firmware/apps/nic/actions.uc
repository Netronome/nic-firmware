#ifndef _ACTIONS_UC
#define _ACTIONS_UC

#include "pv.uc"
#include "pkt_io.uc"

#macro actions_execute(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL, SILENT_DROP_LABEL, ERROR_LABEL)
.begin
    .reg queue
    .reg src_ip

     pv_get_ingress_queue(queue, in_pkt_vec)

    .if (BIT(queue, 7))
        pv_seek(in_pkt_vec, 26, 4)
        byte_align_be[--, *$index++]
        byte_align_be[src_ip, *$index]
        alu[queue, src_ip, AND, 0x7]
        pv_set_egress_queue(in_pkt_vec, queue)
        pkt_io_tx_host(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL)
    .else
        pkt_io_tx_wire(in_pkt_vec, EGRESS_LABEL, COUNT_DROP_LABEL)
    .endif
.end
#endm

#endif

