/* Test for macro pv_init_nfd. Not testing lso_fixup */
;TEST_INIT_EXEC nfp-mem i32.ctm:0x000  0xc3020344 0x05060708 0xa5320b0c 0x02030401
;TEST_INIT_EXEC nfp-mem i32.ctm:0x010  0x00000000 0x6200fff0 0xff00ffff 0x00ffffff
;TEST_INIT_EXEC nfp-mem i32.ctm:0x020  0x01020304 0x85060708 0x090a0b0c 0x0d0e0f10
;TEST_INIT_EXEC nfp-mem i32.ctm:0x030  0x01020304 0x05060708 0x090a0b0c 0x0d0e0f10
;TEST_INIT_EXEC nfp-mem i32.ctm:0x040  0x03faaa37 0x0401abc0 0x00000b0c 0x01112222

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
.reg value
.reg pkt_no
.reg drop_flag
.reg exp[8]
.reg volatile read $nfd_desc[NFD_IN_META_SIZE_LW]
.xfer_order $nfd_desc

 move(daddr, 0x00)
 move(i,0)

.while (i < NUM_TEST_ITERATIONS)

    #define pkt_vec *l$index1

    pv_init(pkt_vec, 0)

    move(pkt_no, i)


    // read in nfd descriptor for this iteration
    mem[read32, $nfd_desc[0], 0, <<8, daddr, NFD_IN_META_SIZE_LW], ctx_swap[s]


    // set up expected data

    // drop flag
    alu[drop_flag, --, B, $nfd_desc[1], >>31]

    // lword 0
    ld_field_w_clr[exp[0], 1100, pkt_no, <<16] // pkt num
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
    alu[exp[2], exp[2], OR, 1, <<31] // ctm allocated

    // lword 3
    move(tmp1, ~(0x100 - NFD_IN_NUM_SEQRS)) // seq num & seq ctx
    alu[exp[3], $nfd_desc[0], AND, tmp1]
    #ifdef PV_MULTI_PCI
        alu[tmp1, 3, AND, $nfd_desc[0], >>6] // seq ctx
        alu[exp[3], --, B, tmp1, <<log2(NFD_IN_NUM_SEQRS)]
    #endif
    alu[exp[3], exp[3], +, PV_GRO_NFD_START]
    alu[exp[3], --, B, exp[3], <<8]
    ld_field_w_clr[tmp1, 0001, $nfd_desc[0], >>24] // meta
    alu[tmp1, tmp1, AND, 0x7f]
    ld_field[exp[3], 0001, tmp1]

    // lword 4
    .if (drop_flag)
        move(exp[4], 0) // seek not set
    .else
        move(exp[4], 0x03fc0) // seek
    .endif
    alu[tmp1, 3, AND, $nfd_desc[2], >>29] // tcp csum
    alu[exp[4], exp[4], OR, tmp1]
    alu[tmp1, 1, AND, $nfd_desc[2], >>28] // udp csum
    alu[exp[4], exp[4], OR, tmp1]

    // lword 5
    .if (drop_flag)
        move(exp[5],0x000f0000) // MPD,VLD not set, but
    .else                       //  also not cleared from prior iteration
        move(exp[5],0x000f0000) // MPD,VLD not parsed
    .endif

    // lword 6
    alu[tmp1, $nfd_desc[0], AND, 0x7f] // qid
    alu[exp[6], --, B, tmp1, <<23]
    alu[exp[6], exp[6], OR, 1, <<31] // q type

    // lword 7
    move(exp[7], 0)


    pv_init_nfd(pkt_vec, pkt_no, $nfd_desc)

    .if ( drop_flag )
        test_assert_equal(i, 0xfe)
        test_fail()
    .endif

    br[pv_data_check#]

    tx_errors_pci#:
        .if (!drop_flag )
            test_assert_equal(i, 0xff)
            test_fail()
        .endif

    pv_data_check#:

    #define_eval _PV_TEST_LOOP 0

    #while (_PV_TEST_LOOP <= 7)

        move(value, pkt_vec[_PV_TEST_LOOP])

        #define_eval _PV_TEST_EXPECT 'exp[/**/_PV_TEST_LOOP/**/]'

        test_assert_equal(value, _PV_TEST_EXPECT)

        #define_eval _PV_TEST_LOOP (_PV_TEST_LOOP + 1)

    #endloop

    alu[i, i, +, 1]
    alu[daddr, daddr, +, 0x10]

.endw

test_pass()
