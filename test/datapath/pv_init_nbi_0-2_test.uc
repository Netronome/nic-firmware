/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>
#include <config.h>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

#define SIZE_LW 16

.sig s
.reg addr
.reg mtu
.reg tunnel_args
.reg value
.reg temp
.reg loop_cntr
.reg expected[SIZE_LW]
.reg volatile read  $nbi_desc_rd[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.reg volatile write $nbi_desc_wr[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $nbi_desc_rd
.xfer_order $nbi_desc_wr

.reg global rtn_addr_reg
.set rtn_addr_reg

#define pkt_vec *l$index1

move(loop_cntr, 0)
.while (loop_cntr < 1024)
    move(pkt_vec++, 0)
    alu[loop_cntr, loop_cntr, +, 1]
.endw

move(mtu, 0x3fff)
move(addr, 0x80)
move(tunnel_args, 0)

/* Test PV Packet Length, CBS and A fields */

//move($nbi_desc_wr[0], ((64<<BF_L(CAT_PKT_LEN_bf)) | 0<<BF_L(CAT_BLS_bf)))
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], (1<<BF_L(CAT_SEQ_CTX_bf))]
move($nbi_desc_wr[3], (CAT_L3_TYPE_IP<<BF_L(CAT_L3_TYPE_bf) | 3<<BF_L(CAT_L4_TYPE_bf)))
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], (3<<BF_L(MAC_PARSE_L3_bf) | 2 << BF_L(MAC_PARSE_STS_bf)))

move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x00000202) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x000fff00)
move(expected[7], 0)
move(expected[8], 0)
move(expected[9], 0)
move(expected[10], 0)
move(expected[11], 0)
move(expected[12], 0)
move(expected[13], 0)
move(expected[14], 0)
move(expected[15], 0)

move(loop_cntr, 64)

.while (loop_cntr <= 0x2800)

    move($nbi_desc_wr[0], loop_cntr)

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd, tunnel_args)

    alu[expected[0], loop_cntr, -, MAC_PREPEND_BYTES]

    alu[temp, loop_cntr, +, PKT_NBI_OFFSET]
    .if  (temp > 1024)
        move(expected[1], 0x60000000) // ctm buffer size = 2048
    .elif  (temp > 512)
        move(expected[1], 0x40000000) // ctm buffer size = 1024
    .elif  (temp > 256)
        move(expected[1], 0x20000000) // ctm buffer size = 512
    .else
        move(expected[1], 0x00000000) // ctm buffer size = 256
    .endif


    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packet
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif


        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        #if (_PV_CHK_LOOP != 5)
            test_assert_equal(value, _PV_INIT_EXPECT)
        #endif

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw

/* Test PV BLS field */

alu[$nbi_desc_wr[0], --, B, 0]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x000002ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x000fff00)
move(expected[7], 0)
move(expected[8], 0)
move(expected[9], 0)

move(loop_cntr, 0)

.while (loop_cntr < 4)

    alu[$nbi_desc_wr[0], 64, OR, loop_cntr, <<14]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd, tunnel_args)


    alu[expected[0], (64 - MAC_PREPEND_BYTES), OR, loop_cntr, <<14]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packet
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif


        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV Packet Number field */

move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], (1<<BF_L(CAT_SEQ_CTX_bf))]
move($nbi_desc_wr[3], (CAT_L3_TYPE_IP<<BF_L(CAT_L3_TYPE_bf) | 3<<BF_L(CAT_L4_TYPE_bf)))
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], (3<<BF_L(MAC_PARSE_L3_bf) | 2 << BF_L(MAC_PARSE_STS_bf)))

move(expected[1], 0)
move(expected[3], 0x00000202) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x000fff00)
move(expected[7], 0)

move(loop_cntr, 0)

// Go past size of Packet Number field to test CTM Number doesn't leak into PV Packet Number
.while (loop_cntr <= 0x400)

    alu[temp, --, B, loop_cntr, <<16]
    .if (loop_cntr == 0x400)
        alu[temp, temp, OR, 0xfc, <<BF_L(PV_CTM_ISL_bf)] // Set all CTM Number bits
    .endif
    alu[$nbi_desc_wr[0], 64, OR, temp]
    alu[expected[0], (64 - MAC_PREPEND_BYTES), OR, temp]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd, tunnel_args)


    move(temp, 0x3ff)
    alu[temp, temp, AND, loop_cntr] // mask off CTM Number bits
    move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
    alu[expected[2], expected[2], OR, temp, <<16]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packet
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'

        #if (_PV_CHK_LOOP != 5)
            test_assert_equal(value, _PV_INIT_EXPECT)
        #endif

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV MU Buffer Address [39:11] field */
/* Can't brute force it, get timeout */

alu[$nbi_desc_wr[0], --, B, 64]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x000002ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x000fff00)
move(expected[7], 0)

move(loop_cntr, 0)

// Go past end of field to test all 1s */
.while (loop_cntr <= 0x20000000)

    .if (loop_cntr == 0x20000000)
        move($nbi_desc_wr[1], 0x1fffffff) // Test all 1s
    .else
        move($nbi_desc_wr[1], loop_cntr)
    .endif

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd, tunnel_args)


    .if (loop_cntr == 0x20000000)
        move(expected[1], 0x1fffffff)
    .else
        move(expected[1], loop_cntr)
    .endif

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packet
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    .if (loop_cntr == 0)
        move(loop_cntr, 1)
    .else
        alu[loop_cntr, --, B, loop_cntr, <<1]
    .endif

.endw



/* Test Packet Metadata Rsv field don't leak into PV CBS field */

alu[$nbi_desc_wr[0], --, B, 64]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x000002ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x000fff00)
move(expected[7], 0)

move(loop_cntr, 1)

.while (loop_cntr <= 0x3)

    alu[$nbi_desc_wr[1], --, B, loop_cntr, <<29]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd, tunnel_args)


    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packet
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV S field */

alu[$nbi_desc_wr[0], --, B, 64]
alu[$nbi_desc_wr[1], --, B, 0]
alu[$nbi_desc_wr[2], --, B, 1, <<8] // Seq
alu[$nbi_desc_wr[3], --, B, 0]
alu[$nbi_desc_wr[4], --, B, 0]
alu[$nbi_desc_wr[5], --, B, 0]
alu[$nbi_desc_wr[6], --, B, 0]
alu[$nbi_desc_wr[7], --, B, 0]

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x000002ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x000fff00)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr < 2)

    alu[$nbi_desc_wr[1], --, B, loop_cntr, <<31]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd, tunnel_args)


    alu[expected[1], --, B, loop_cntr, <<31]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packet
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



test_pass()

PV_HDR_PARSE_SUBROUTINE#:
pv_hdr_parse_subroutine(pkt_vec)

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
