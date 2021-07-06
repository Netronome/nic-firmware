/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg pkt_offset
.reg pms_offset
.reg pkt_vec[PV_SIZE_LW]

move(BF_A(pkt_vec, PV_NUMBER_bf), 0)
move(BF_A(pkt_vec, PV_MU_ADDR_bf), 0)
move(BF_A(pkt_vec, PV_CSUM_OFFLOAD_bf), 0)

#if (!IS_NFPTYPE(__NFP3800))

    move(pkt_offset, 0)
    .while (pkt_offset < 44)
        move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
        pv_write_nbi_meta(pms_offset, pkt_vec, expected_fail_lower_bound#)
        test_fail()
        expected_fail_lower_bound#:
        alu[pkt_offset, pkt_offset, +, 1]
    .endw

    .while (pkt_offset < 253)
        move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
        pv_write_nbi_meta(pms_offset, pkt_vec, fail#)
        alu[pkt_offset, pkt_offset, +, 1]
    .endw

    .while (pkt_offset < 16383)
        move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
        pv_write_nbi_meta(pms_offset, pkt_vec, expected_fail_upper_bound#)
        test_fail()
        expected_fail_upper_bound#:
        alu[pkt_offset, pkt_offset, +, 1]
    .endw

#else  /* For NFP3800 */

    /* NFP3800 disabled Packet Modifier (PM) by default. ME should not prepend PMS
     * before packet data, but 4 bytes mac prepend is still needed.
     * When ME sending packet ready command to TM, a packet offset value need to
     * be filled into the descriptor, the following is supported offset extracted from
     * EAS_nbi_traffic_manager.pdf page 40:
     * PM Disabled case:
     * Packet can start from any arbitrary start byte):
     * Encoding is 0=8, 1=12, 2=16, 3=20, 4=24 ... 126=512 (StartOffset*4 + 8)
     * this provides 4B alignment
     * ByteOffset provides the actual starting byte with the 4B alignment
     *
     * Currently we do not use ByteOffset, so, packet offset keeps 4B aligned.
     * and the packet offset supported is: 8, 12, 16, ..., 512.
     * One thing should be noted that this packet offset is not pkt_offset variable
     * in this file, this offset is actually the mac prepend offset, because
     * TM will require packet data with this packet offset, and the 4 byte mac prepend
     * is actually included in the packet data required.
     * while the pkt_offset is actually the real offset of packet L2 header which will
     * be written into pakcet descriptor. And pv_write_nbi_meta() will subtract 4 to
     * get the data offset ready to be transmited. And then the following software will
     * map this offset to StartOffset of Packet Ready Command.
     * So, pkt_offset should be in 12, 16, 20, ..., 516. */

    /* Packet Offset 0 to 11 is not supported */
    move(pkt_offset, 0)
    .while (pkt_offset < 12)
        move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
        pv_write_nbi_meta(pms_offset, pkt_vec, lower_done#)
        test_fail()
        lower_done#:
        alu[pkt_offset, pkt_offset, +, 1]
    .endw

    /* Only packet offset 12, 16, 20, ..., 516 is supported */
    .while (pkt_offset < 517)
        move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
        alu[--, pkt_offset, AND, 0x3]
        bne[expected_fail#]

        pv_write_nbi_meta(pms_offset, pkt_vec, fail#)
        br[done#]

        expected_fail#:
        pv_write_nbi_meta(pms_offset, pkt_vec, done#)
        test_fail()

        done#:
        alu[pkt_offset, pkt_offset, +, 1]
    .endw

    /* Packet offset lager than 516 is not supported, the OFFSET field is 13 bits,
     * So, the maximum value is 8192. */
    .while (pkt_offset < 8192)
        move(BF_A(pkt_vec, PV_OFFSET_bf), pkt_offset)
        pv_write_nbi_meta(pms_offset, pkt_vec, upper_done#)
        test_fail()
        upper_done#:
        alu[pkt_offset, pkt_offset, +, 1]
    .endw

#endif

test_pass()

fail#:

test_fail()
