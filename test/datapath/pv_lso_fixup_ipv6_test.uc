/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_ipv6_tcp_lso_fixup.uc"

#include <config.h>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

#define PV_TEST_SIZE_LW (PV_SIZE_LW/2)

.sig s
.reg tmp
.reg addr
.reg value
.reg expected[20]
.reg volatile write $out_nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $out_nfd_desc
.reg volatile read $in_nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $in_nfd_desc
.reg read $pkt_rd[20]
.xfer_order $pkt_rd

#define_eval _PV_L3_OFFSET (14)
#define_eval _PV_L4_OFFSET (14 + 40)

move(addr, 0x2000)

move($out_nfd_desc[0], 0)
move($out_nfd_desc[1], 0)
move(value, 0x04020001) // IPV4_CS = 0, TX_LSO = 1, lso seq cnt = 2, mss  = 1
alu[$out_nfd_desc[2], --, B, value]
move($out_nfd_desc[3], 0)

// write out nfd descriptor
mem[write32, $out_nfd_desc[0], 0, <<8, addr, NFD_IN_META_SIZE_LW], ctx_swap[s]

// read in nfd descriptor
mem[read32, $in_nfd_desc[0], 0, <<8, addr, NFD_IN_META_SIZE_LW], ctx_swap[s]

// pv_init_nfd() does this
pv_seek(pkt_vec, ETH_MAC_SIZE, PV_SEEK_INIT)
move(pkt_vec[3], PROTO_IPV6_TCP)
move(pkt_vec[5], ((_PV_L3_OFFSET << 24) | (_PV_L4_OFFSET << 16) | \
                  (_PV_L3_OFFSET <<  8) | (_PV_L4_OFFSET <<  0)))


__pv_lso_fixup(pkt_vec, $in_nfd_desc, lso_done#, error#)

error#:
test_fail()

lso_done#:

// Check PV

aggregate_zero(expected, PV_SIZE_LW)

move(expected[0], 0x4e)
move(expected[1], 0x13000000)
move(expected[2], 0x80)
move(expected[3], PROTO_IPV6_TCP)
move(expected[4], 0x0)
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
move(expected[3],  0x86dd6fff)
move(expected[4],  0xffff0018) // Total Length = PV Packet Length(0x4e) - (14 + 40)
move(expected[5],  0x06fffe80)
move(expected[6],  0x00000000)
move(expected[7],  0x00000200)
move(expected[8],  0x0bfffe00)
move(expected[9],  0x03003555)
move(expected[10], 0x55556666)
move(expected[11], 0x66667777)
move(expected[12], 0x77778888)
move(expected[13], 0x8888ffff)
move(expected[14], 0xffff0000)
move(expected[15], 0x0001ffff) // Seq num = 1 (TCP_SEQ += (mss * (lso_seq - 1)))
move(expected[16], 0xffff51f2) // LSO_END = 0, so clear FIN, RST, PSH
move(expected[17], 0xffffffff)
move(expected[18], 0xffff6acf)
move(expected[19], 0x14990000)

move(tmp, 0x80)
move(addr, ((0x13000000 << 3) & 0xffffffff))

// nfp6000 indirect format requires 1 less
alu[value, --, B, 19, <<8]
alu[--, value, OR, 1, <<7]
mem[read32, $pkt_rd[0], addr, <<8, tmp, max_20], ctx_swap[s], indirect_ref

#define_eval _PV_CHK_LOOP 0

#while (_PV_CHK_LOOP <= 19)

    #define_eval _PKT_VEC '$pkt_rd[/**/_PV_CHK_LOOP/**/]'
    move(value, _PKT_VEC)

    #define_eval _PKT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
    test_assert_equal(value, _PKT_EXPECT)

    #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

#endloop


test_pass()

PV_SEEK_SUBROUTINE#:
    pv_seek_subroutine(pkt_vec)

