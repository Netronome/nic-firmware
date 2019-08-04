/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_ipv6_lso_mpls_fixup.uc"

#include <config.h>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

#define PV_TEST_SIZE_LW (PV_SIZE_LW/2)

.sig s
.reg addrlo
.reg addrhi
.reg value
.reg loop_cnt
.reg expected[21]
.reg volatile write $out_nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $out_nfd_desc
.reg volatile read $in_nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $in_nfd_desc
.reg read $pkt_rd[21]
.xfer_order $pkt_rd
.reg write $protocol

move(addrlo, 0x2000)

move($out_nfd_desc[0], 0)
move($out_nfd_desc[1], 0)
move(value, 0x04020001) // IPV4_CS = 0, TX_LSO = 1, lso seq cnt = 2, mss  = 1
alu[$out_nfd_desc[2], --, B, value]
move($out_nfd_desc[3], 0)

// write out nfd descriptor
mem[write32, $out_nfd_desc[0], 0, <<8, addrlo, NFD_IN_META_SIZE_LW], ctx_swap[s]

// read in nfd descriptor
mem[read32, $in_nfd_desc[0], 0, <<8, addrlo, NFD_IN_META_SIZE_LW], ctx_swap[s]


// try PROTO_IPV6_UDP, PROTO_IPV6_UNKNOWN, PROTO_IPV6_FRAGMENT

#define_eval _PV_L3_OFFSET (0)
#define_eval _PV_L4_OFFSET (0)

move(addrhi, ((0x13000000 << 3) & 0xffffffff))

move(loop_cnt, 0)

.while (loop_cnt < 3)

    // pv_init_nfd() does this
    pv_seek(pkt_vec, ETH_MAC_SIZE, PV_SEEK_INIT)
    .if (loop_cnt == 0)
        move(pkt_vec[3], PROTO_MPLS_IPV6_UDP)
    .elif (loop_cnt == 1)
        move(pkt_vec[3], PROTO_MPLS_IPV6_UNKNOWN)
    .else
        move(pkt_vec[3], PROTO_MPLS_IPV6_FRAGMENT)
    .endif
    move(pkt_vec[5], ((_PV_L3_OFFSET << 24) | (_PV_L4_OFFSET << 16) | \
                      (_PV_L3_OFFSET <<  8) | (_PV_L4_OFFSET <<  0)))


    __pv_lso_fixup(pkt_vec, $in_nfd_desc, lso_done#, error#)

lso_done#:
test_fail()

error#:

    // Check PV

    aggregate_zero(expected, PV_SIZE_LW)

    move(expected[0], 0x54)
    move(expected[1], 0x13000000)
    move(expected[2], 0x80)
    .if (loop_cnt == 0)
        move(expected[3], PROTO_MPLS_IPV6_UDP)
    .elif (loop_cnt == 1)
        move(expected[3], PROTO_MPLS_IPV6_UNKNOWN)
    .else
        move(expected[3], PROTO_MPLS_IPV6_FRAGMENT)
    .endif
    move(expected[5], ((_PV_L3_OFFSET << 24) | (_PV_L4_OFFSET << 16) | \
                       (_PV_L3_OFFSET <<  8) | (_PV_L4_OFFSET <<  0)))

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < PV_TEST_SIZE_LW)

        #define_eval _PKT_VEC 'pkt_vec[/**/_PV_CHK_LOOP/**/]'
        move(value, _PKT_VEC)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop


    // Check packet data

    move(expected[0],  0x00154d12)
    move(expected[1],  0x2cc60000)
    move(expected[2],  0x0b000300)
    move(expected[3],  0x88470000)
    move(expected[4],  0x21006fff)
    move(expected[5],  0xffffff00)
    move(expected[6],  0x06fffe80)
    move(expected[7],  0x00000000)
    move(expected[8],  0x00000200)
    move(expected[9],  0x0bfffe00)
    move(expected[10], 0x03003555)
    move(expected[11], 0x55556666)
    move(expected[12], 0x66667777)
    move(expected[13], 0x77778888)
    move(expected[14], 0x8888ffff)
    move(expected[15], 0xffff0000)
    move(expected[16], 0x0000ffff)
    move(expected[17], 0xffff51ff)
    move(expected[18], 0xffffffff)
    move(expected[19], 0xffff6acf)
    move(expected[20], 0x14990000)

    move(addrlo, 0x80)

    // nfp6000 indirect format requires 1 less
    alu[value, --, B, 20, <<8]
    alu[--, value, OR, 1, <<7]
    mem[read32, $pkt_rd[0], addrhi, <<8, addrlo, max_21], ctx_swap[s], indirect_ref

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= 20)

        #define_eval _PKT_VEC '$pkt_rd[/**/_PV_CHK_LOOP/**/]'
        move(value, _PKT_VEC)

        #define_eval _PKT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PKT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cnt, loop_cnt, +, 1]
.endw


test_pass()

PV_SEEK_SUBROUTINE#:
    pv_seek_subroutine(pkt_vec)
