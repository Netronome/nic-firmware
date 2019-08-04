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

/* Test __pv_lso_fixup() on an IPv6 pkt, not last segment */

#define PV_TEST_SIZE_LW (PV_SIZE_LW/2)

.sig s
.reg addrlo
.reg addrhi
.reg loop_cntr
.reg loop_cntr_masked
.reg tmp
.reg addr
.reg args
.reg value
.reg pkt_no
.reg drop_flag
.reg expected[20]
.reg write $nfd_desc_wr[NFD_IN_META_SIZE_LW]
.reg volatile read $nfd_desc_rd[NFD_IN_META_SIZE_LW]
.xfer_order $nfd_desc_wr
.xfer_order $nfd_desc_rd
.reg read $pkt_rd[20]
.xfer_order $pkt_rd

move(args, (6000 << 2))
move(addr, 0x00)

move($nfd_desc_wr[0], 0)
move($nfd_desc_wr[1], 0x13000000) // buf_addr
alu[$nfd_desc_wr[3], --, B, pkt_vec[0], <<16] // data_len

// TX_LSO = 1, lso seq cnt = 2, mss  = 1
alu[value, --, B, 1, <<BF_L(NFD_IN_FLAGS_TX_LSO_fld)]
alu[value, value, OR, 2, <<BF_L(NFD_IN_LSO_SEQ_CNT_fld)]
alu[value, value, OR, 1, <<BF_L(NFD_IN_LSO_MSS_fld)]
alu[$nfd_desc_wr[2], --, B, value]

move(pkt_no, 0) // anything other than 0 causes the test to time out


aggregate_zero(expected, PV_TEST_SIZE_LW)

aggregate_zero(pkt_vec, PV_SIZE_LW)

mem[write32, $nfd_desc_wr[0], 0, <<8, addr, NFD_IN_META_SIZE_LW], ctx_swap[s]

mem[read32,  $nfd_desc_rd[0], 0, <<8, addr, NFD_IN_META_SIZE_LW], ctx_swap[s]


pv_init_nfd(pkt_vec, pkt_no, $nfd_desc_rd, args, error#)


// Check PV

alu[value, --, B, $nfd_desc_rd[3], >>16] // Packet Length
alu[value, value, OR, NFD_IN_BLM_REG_BLS, <<BF_L(PV_BLS_bf)]
alu[expected[0], value, OR, pkt_no, <<16] // Packet Number
alu[expected[0], expected[0], OR, 32, <<BF_L(PV_CTM_ISL_bf)] // CTM Island

move(expected[1], 0x13000000) // Split = 0, MU Buffer Address [39:11]

move(value, 0x80000080) // A = 1, Offset = 0x80
alu[expected[2], value, OR, pkt_no, <<16] // Packet Number

immed[value, PV_GRO_NFD_START]
alu[expected[3], PROTO_IPV6_TCP, OR, value, <<8]

#define_eval _PV_OUTER_L3_OFFSET (14)
#define_eval _PV_OUTER_L4_OFFSET (14 + 40)
#define_eval _PV_INNER_L3_OFFSET (_PV_OUTER_L3_OFFSET)
#define_eval _PV_INNER_L4_OFFSET (_PV_OUTER_L4_OFFSET)
move(expected[5], ((_PV_OUTER_L3_OFFSET << 24) | (_PV_OUTER_L4_OFFSET << 16) | \
                   (_PV_INNER_L3_OFFSET <<  8) | (_PV_INNER_L4_OFFSET <<  0)))
move(expected[6], 0x000fff00)

alu[expected[8], --, B, $nfd_desc_rd[3], >>16] // Original Packet Length

#define_eval _PV_CHK_LOOP 0

#while (_PV_CHK_LOOP < PV_TEST_SIZE_LW)

    #define_eval _PKT_VEC 'pkt_vec[/**/_PV_CHK_LOOP/**/]'
    move(value, _PKT_VEC)

    #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
    test_assert_equal(value, _PV_INIT_EXPECT)

    #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

#endloop

alu[expected[7], --, B, $nfd_desc_rd[3], >>16] // Original Packet Length
test_assert_equal(pre_meta[7], expected[7])


// Check packet data in CTM

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

move(addrlo, 0x80)
move(addrhi, 0)

// nfp6000 indirect format requires 1 less
alu[value, --, B, 19, <<8]
alu[--, value, OR, 1, <<7]
mem[read32, $pkt_rd[0], addrhi, <<8, addrlo, max_20], ctx_swap[s], indirect_ref

#define_eval _PV_CHK_LOOP 0

#while (_PV_CHK_LOOP <= 19)

    #define_eval _PKT_VEC '$pkt_rd[/**/_PV_CHK_LOOP/**/]'
    move(value, _PKT_VEC)

    #define_eval _PKT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
    test_assert_equal(value, _PKT_EXPECT)

    #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

#endloop


test_pass()


error#:
    test_fail()


PV_HDR_PARSE_SUBROUTINE#:
pv_hdr_parse_subroutine(pkt_vec)

PV_SEEK_SUBROUTINE#:
pv_seek_subroutine(pkt_vec)
