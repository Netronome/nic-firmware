/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include "actions_harness.uc"
#include "global.uc"

.sig s
.reg addr
.reg value
.reg loop_cntr
.reg expected_hdr_stack
.reg expected_proto
.reg in_args
.reg volatile write $pkt_data_wr[20]
.xfer_order $pkt_data_wr
.reg pkt_vec[PV_SIZE_LW]


/* IPv6 pkt with 1 Extension Header */
move($pkt_data_wr[0],  0x00163ec4)
move($pkt_data_wr[1],  0x23450000)
move($pkt_data_wr[2],  0x0b000200)
move($pkt_data_wr[3],  0x86dd6030)
move($pkt_data_wr[4],  0x00000010)
move($pkt_data_wr[5],  0x2bfffe80) // Next Header is in 31:24
move($pkt_data_wr[6],  0x00000000)
move($pkt_data_wr[7],  0x00000200)
move($pkt_data_wr[8],  0x0bfffe00)
move($pkt_data_wr[9],  0x02003555)
move($pkt_data_wr[10], 0x55556666)
move($pkt_data_wr[11], 0x66667777)
move($pkt_data_wr[12], 0x77778888)
move($pkt_data_wr[13], 0x88881100)
move($pkt_data_wr[14], 0x00000000)
move($pkt_data_wr[15], 0x0000003f)
move($pkt_data_wr[16], 0x003f0008)
move($pkt_data_wr[17], 0x9b680c79)
move($pkt_data_wr[18], 0x8ce90000)

move(loop_cntr, 0)

.while (loop_cntr < 4)

    aggregate_zero(pkt_vec, PV_SIZE_LW)
    move(pkt_vec[0], 0x46)
    move(pkt_vec[2], 0x80)
    move(pkt_vec[3], 0x0)
    move(pkt_vec[4], 0x3fc0)
    move(pkt_vec[5], 0)

    move(in_args, 0x12b51c00)

    move(expected_hdr_stack, (14 << 24) | ((14+40+8) << 16) | (14 << 8) | (14+40+8))
    move(expected_proto, 0x1)

    /* Loop thru these Extension Headers
       hop   0
       dest 60  0x3c
       rout 43  0x2b
       frag 44  0x2c
     */

    .if (loop_cntr == 0)
        move($pkt_data_wr[5], 0x00fffe80) /* Hop-by-Hop */
    .elif (loop_cntr == 1)
        move($pkt_data_wr[5], 0x3cfffe80) /* Destination Options */
    .elif (loop_cntr == 2)
        move($pkt_data_wr[5], 0x2bfffe80) /* Routing */
    .elif (loop_cntr == 3)
        move($pkt_data_wr[5], 0x2cfffe80) /* Fragment */
        move(expected_hdr_stack, ((14 << 24) | (14 << 8)))
        move(expected_proto, 0x5)
    .endif

    move(addr, 0x80)

    // nfp6000 indirect format requires 1 less
    alu[value, --, B, 18, <<8]
    alu[--, value, OR, 1, <<7]
    mem[write32, $pkt_data_wr[0], 0, <<8, addr, max_19], ctx_swap[s], indirect_ref

    pv_seek(pkt_vec, 0, (PV_SEEK_INIT | PV_SEEK_DEFAULT))
    alu[--, --, B, *$index++]
    alu[--, --, B, *$index++]
    alu[--, --, B, *$index++]

    pv_hdr_parse(pkt_vec, in_args, check_result#)

check_result#:

    test_assert_equal(BF_A(pkt_vec, PV_HEADER_STACK_bf), expected_hdr_stack)
    test_assert_equal(BF_A(pkt_vec, PV_PROTO_bf), expected_proto)

    alu[loop_cntr, loop_cntr, +, 1]

.endw

test_pass()

PV_HDR_PARSE_SUBROUTINE#:
pv_hdr_parse_subroutine(pkt_vec)

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
