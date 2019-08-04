/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* Test for macro pv_init_nfd. Not testing lso_fixup */
;TEST_INIT_EXEC nfp-mem i32.ctm:0x000  0x43020344 0x05060708 0x01320b0c 0x02030401
;TEST_INIT_EXEC nfp-mem i32.ctm:0x010  0x43020344 0x05060708 0x01320b0c 0x02030401
;TEST_INIT_EXEC nfp-mem i32.ctm:0x020  0x23020304 0x85060708 0x090a0b0c 0x02000402
;TEST_INIT_EXEC nfp-mem i32.ctm:0x030  0x33020304 0x05060708 0x090a0b0c 0x020e0402
;TEST_INIT_EXEC nfp-mem i32.ctm:0x040  0x03faaa37 0x0401abc0 0x00000b0c 0x01110222

#define NULL_VLAN 0xfff

#include <single_ctx_test.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

#define NUM_TEST_ITERATIONS 5
#define NFD_IN_META_SIZE_LW 4

.sig s
.reg i
.reg tmp1, tmp2
.reg daddr
.reg args
.reg value
.reg pkt_no
.reg drop_flag
.reg exp[8]
.reg volatile read $nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $nfd_desc

.reg volatile read $__actions[NIC_MAX_INSTR]
.addr $__actions[0] 32
.xfer_order $__actions
.reg volatile __actions_t_idx

#define pkt_vec *l$index1

.reg pkt_vec_addr
.reg_addr __actions_t_idx 28 B
alu[__actions_t_idx, --, B, 0]
alu[pkt_vec_addr, (PV_META_BASE_wrd * 4), OR, t_idx_ctx, >>(8 - log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1))]

move(args, (6000 << 2))
move(daddr, 0x00)
move(i,0)

pv_reset(pkt_vec_addr, 0, __actions_t_idx, 64)


.while (i < NUM_TEST_ITERATIONS)

    move(pkt_no, i)


    // read in nfd descriptor for this iteration
    mem[read32, $nfd_desc[0], 0, <<8, daddr, NFD_IN_META_SIZE_LW], ctx_swap[s]

    // set up expected data

    // drop flag
    alu[drop_flag, --, B, $nfd_desc[1], >>31]

    // lword 0
    ld_field_w_clr[exp[0], 1100, pkt_no, <<16] // pkt num
    alu[exp[0], exp[0], OR, 32,<<BF_L(PV_CTM_ISL_bf)]
    ld_field_w_clr[tmp1, 0011, $nfd_desc[3], >>16] // pkt len
    ld_field_w_clr[tmp2, 0001, $nfd_desc[0], >>24]
    alu[tmp2, tmp2, AND, 0x7f]
    alu[exp[0], exp[0], +, tmp1]
    alu[exp[0], exp[0], -, tmp2]
    alu[exp[0], exp[0], OR, NFD_IN_BLM_REG_BLS, <<14] // bls

    // lword 1
    move(tmp1, 0x1fffffff) // mu addr
    alu[exp[1], $nfd_desc[1], AND, tmp1]
    ld_field_w_clr[tmp2, 0011, $nfd_desc[3], >>16] // split
    alu[tmp1, NFD_IN_DATA_OFFSET, +, tmp2]
    .if (tmp1 > 256)
        alu[exp[1], exp[1], OR, 1, <<31]
    .endif

    // lword 2
    ld_field_w_clr[exp[2], 1100, pkt_no, <<16] // pkt num
    ld_field[exp[2], 0011, NFD_IN_DATA_OFFSET] // offset
    // lword 3
    move(tmp1, ~(0x100 - NFD_IN_NUM_SEQRS)) // seq num & seq ctx
    alu[exp[3], $nfd_desc[0], AND, tmp1]
    #ifdef PV_MULTI_PCI
        alu[tmp1, 3, AND, $nfd_desc[0], >>6] // seq ctx
        alu[exp[3], --, B, tmp1, <<log2(NFD_IN_NUM_SEQRS)]
    #endif
    alu[exp[3], exp[3], +, PV_GRO_NFD_START]
    alu[exp[3], --, B, exp[3], <<8]
    alu[tmp1, --, B, 0xff]
    ld_field[exp[3], 0001, tmp1]
   .if (! drop_flag)
        alu[tmp1, --, B, 0xff]
        ld_field[exp[3], 0001, tmp1]
    .endif

    // lword 4
    move(exp[4], 0) // seek
    alu[tmp1, 3, AND, $nfd_desc[2], >>29] // tcp csum
    alu[exp[4], exp[4], OR, tmp1]
    alu[tmp1, 1, AND, $nfd_desc[2], >>28] // udp csum
    alu[exp[4], exp[4], OR, tmp1]

    // lword 5
    .if (drop_flag)
        move(exp[5],0x00000000) // stacked offsets - to be added
        move(exp[6], 0)
    .else                       //  also not cleared from prior iteration
        move(exp[5],0x00000000) // stacked offsets - to be added
        move(exp[6], 0x000fff00)
    .endif

    // lword 6

    // lword 7
    move(exp[7], 0)
    move(pkt_vec[6], 0)
    pv_init_nfd(pkt_vec, pkt_no, $nfd_desc, args, error#)

    .if ( drop_flag )
        test_assert_equal(i, 0xfe)
        test_fail()
    .endif

    alu[exp[2], exp[2], OR, 1, <<31] // ctm allocated

    br[pv_data_check#]

    error#:
        alu[exp[2], exp[2], AND~, 1, <<31]
        .if (!drop_flag )
            test_assert_equal(i, 0xff)
            test_fail()
        .endif

    pv_data_check#:

    #define_eval _PV_TEST_LOOP 0

    #while (_PV_TEST_LOOP <= 7)

        move(value, pkt_vec[_PV_TEST_LOOP])

        #define_eval _PV_TEST_EXPECT 'exp[/**/_PV_TEST_LOOP/**/]'

        #pragma warning(disable:4701)
        test_assert_equal(value, _PV_TEST_EXPECT)
        #pragma warning(default:4701)

        #define_eval _PV_TEST_LOOP (_PV_TEST_LOOP + 1)

    #endloop

    alu[i, i, +, 1]
    alu[daddr, daddr, +, 0x10]

.endw

test_pass()

PV_HDR_PARSE_SUBROUTINE#:
    pv_hdr_parse_subroutine(pkt_vec)

PV_SEEK_SUBROUTINE#:
    pv_seek_subroutine(pkt_vec)
