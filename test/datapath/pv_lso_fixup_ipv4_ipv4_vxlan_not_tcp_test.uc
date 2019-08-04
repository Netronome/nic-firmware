/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_ipv4_ipv4_lso_vxlan_tcp_x80.uc"

#include <config.h>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

#define PV_TEST_SIZE_LW (PV_SIZE_LW/2)

.sig s
.reg addrhi
.reg addrlo
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
move(value, 0x46020001) // IPV4_CS = TX_LSO = ENCAP = 1, lso seq cnt = 2, mss  = 1
alu[$out_nfd_desc[2], --, B, value]
move($out_nfd_desc[3], 0)

// write out nfd descriptor
mem[write32, $out_nfd_desc[0], 0, <<8, addrlo, NFD_IN_META_SIZE_LW], ctx_swap[s]

// read in nfd descriptor
mem[read32, $in_nfd_desc[0], 0, <<8, addrlo, NFD_IN_META_SIZE_LW], ctx_swap[s]


// try PROTO_IPV4_UDP_VXLAN_IPV4_UDP, PROTO_IPV4_UDP_VXLAN_IPV4_UNKNOWN, PROTO_IPV4_UDP_VXLAN_IPV4_FRAGMENT

#define_eval _PV_OUTER_L3_OFFSET (14)
#define_eval _PV_OUTER_L4_OFFSET (14 + 20)
#define_eval _PV_INNER_L3_OFFSET (14 + 20 + 8 + 8 + 14)
#define_eval _PV_INNER_L4_OFFSET (14 + 20 + 8 + 8 + 14 + 20)

move(addrhi, ((0x13000000 << 3) & 0xffffffff))

move(loop_cnt, 0)

.while (loop_cnt < 3)

    // pv_init_nfd() does this
    pv_seek(pkt_vec, ETH_MAC_SIZE, PV_SEEK_INIT)
    .if (loop_cnt == 0)
        move(pkt_vec[3], PROTO_IPV4_UDP_VXLAN_IPV4_UDP)
        move(pkt_vec[5], ((_PV_OUTER_L3_OFFSET << 24) | (_PV_OUTER_L4_OFFSET << 16) | \
                      (_PV_INNER_L3_OFFSET <<  8) | (_PV_INNER_L4_OFFSET <<  0)))
    .elif (loop_cnt == 1)
        move(pkt_vec[3], PROTO_IPV4_UDP_VXLAN_IPV4_UNKNOWN)
        move(pkt_vec[5], ((_PV_OUTER_L3_OFFSET << 24) | (_PV_INNER_L3_OFFSET <<  8)))
    .else
        move(pkt_vec[3], PROTO_IPV4_UDP_VXLAN_IPV4_FRAGMENT)
        move(pkt_vec[5], ((_PV_OUTER_L3_OFFSET << 24) | (_PV_INNER_L3_OFFSET <<  8)))
    .endif

    __pv_lso_fixup(pkt_vec, $in_nfd_desc, lso_done#, error#)

lso_done#:
test_fail()

error#:

    // Check PV

    aggregate_zero(expected, PV_SIZE_LW)

    move(expected[0], 0x8c)
    move(expected[1], 0x13000000)
    move(expected[2], 0x80)
    .if (loop_cnt == 0)
        move(expected[3], PROTO_IPV4_UDP_VXLAN_IPV4_UDP)
        move(expected[5], ((_PV_OUTER_L3_OFFSET << 24) | (_PV_OUTER_L4_OFFSET << 16) | \
                       (_PV_INNER_L3_OFFSET <<  8) | (_PV_INNER_L4_OFFSET <<  0)))
    .elif (loop_cnt == 1)
        move(expected[3], PROTO_IPV4_UDP_VXLAN_IPV4_UNKNOWN)
        move(expected[5], ((_PV_OUTER_L3_OFFSET << 24) | (_PV_INNER_L3_OFFSET <<  8)))
    .else
        move(expected[3], PROTO_IPV4_UDP_VXLAN_IPV4_FRAGMENT)
        move(expected[5], ((_PV_OUTER_L3_OFFSET << 24) | (_PV_INNER_L3_OFFSET <<  8)))
    .endif

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < PV_TEST_SIZE_LW)

        #define_eval _PKT_VEC 'pkt_vec[/**/_PV_CHK_LOOP/**/]'
        move(value, _PKT_VEC)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop


    // Check Outer Ethernet hdr and first 2 bytes of Outer IPv4 hdr

    move(expected[0], 0x00154d0a)
    move(expected[1], 0x0d1a6805)
    move(expected[2], 0xca306ab8)
    move(expected[3], 0x080045aa)

    move(addrlo, 0x80)
    mem[read32, $pkt_rd[0], addrhi, <<8, addrlo, 4], ctx_swap[s]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= 3)

        #define_eval _PKT_VEC '$pkt_rd[/**/_PV_CHK_LOOP/**/]'
        move(value, _PKT_VEC)

        #define_eval _PKT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PKT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop


    // Check Outer IPv4 hdr, Outer UDP hdr, VXLAN hdr

    move(expected[0], 0x45aaff00)
    move(expected[1], 0xde064000)
    move(expected[2], 0x4011ffff)
    move(expected[3], 0x05010102)
    move(expected[4], 0x05010101)
    move(expected[5], 0xd87e12b5) // Outer UDP hdr starts here
    move(expected[6], 0xff000000)
    move(expected[7], 0x08000000) // VXLAN hdr starts here
    move(expected[8], 0xffffff00)

    alu[addrlo, addrlo, +, 14]
    // nfp6000 indirect format requires 1 less
    alu[value, --, B, 8, <<8]
    alu[--, value, OR, 1, <<7]
    mem[read32, $pkt_rd[0], addrhi, <<8, addrlo, max_9], ctx_swap[s], indirect_ref

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= 8)

        #define_eval _PKT_VEC '$pkt_rd[/**/_PV_CHK_LOOP/**/]'
        move(value, _PKT_VEC)

        #define_eval _PKT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PKT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop


    // Check Inner Ethernet hdr and first 2 bytes of Inner IPv4 hdr

    move(expected[0], 0x404d8e6f)
    move(expected[1], 0x97ad001e)
    move(expected[2], 0x101f0001)
    move(expected[3], 0x08004555)

    alu[addrlo, addrlo, +, (20+8+8)]
    mem[read32, $pkt_rd[0], addrhi, <<8, addrlo, 4], ctx_swap[s]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= 3)

        #define_eval _PKT_VEC '$pkt_rd[/**/_PV_CHK_LOOP/**/]'
        move(value, _PKT_VEC)

        #define_eval _PKT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PKT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop


    // Check Inner IPv4 hdr, Inner TCP hdr, Payload

    move(expected[0],  0x4555ff00)
    move(expected[1],  0x7a9f4000)
    move(expected[2],  0x4006ffff)
    move(expected[3],  0xc0a80164)
    move(expected[4],  0xd5c7b3a6)
    move(expected[5],  0xcb580050) // TCP hdr starts here
    move(expected[6],  0xea8d9a10)
    move(expected[7],  0xffffffff)
    move(expected[8],  0x51ffffff)
    move(expected[9],  0xffffffff)
    move(expected[10], 0x97ae878f)
    move(expected[11], 0x08377a4d)
    move(expected[12], 0x85a1fec4)
    move(expected[13], 0x97a27c00)
    move(expected[14], 0x784648ea)
    move(expected[15], 0x31ab0538)
    move(expected[16], 0xac9ca16e)
    move(expected[17], 0x8a809e58)
    move(expected[18], 0xa6ffc15f)

    alu[addrlo, addrlo, +, 14]

    // nfp6000 indirect format requires 1 less
    alu[value, --, B, 18, <<8]
    alu[--, value, OR, 1, <<7]
    mem[read32, $pkt_rd[0], addrhi, <<8, addrlo, max_19], ctx_swap[s], indirect_ref

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= 18)

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
