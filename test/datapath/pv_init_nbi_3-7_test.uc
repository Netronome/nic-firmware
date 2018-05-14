#include <single_ctx_test.uc>
#include <config.h>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

#define SIZE_LW 16

.sig s
.reg addr
.reg value
.reg temp
.reg rtn_reg
.reg loop_cntr
.reg loop_cntr1
.reg mtu
.reg error_expected_flag
.reg expected[SIZE_LW]
.reg volatile read  $nbi_desc_rd[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.reg volatile write $nbi_desc_wr[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $nbi_desc_rd
.xfer_order $nbi_desc_wr

#define pkt_vec *l$index1

move(loop_cntr, 0)
.while (loop_cntr < 1024)
    move(pkt_vec++, 0)
    alu[loop_cntr, loop_cntr, +, 1]
.endw

move(error_expected_flag, 0)
move(mtu, 0xfff)

load_addr[rtn_reg, error_expected_ret#]

pv_init(pkt_vec, 0)

move(addr, 0x80)

/* Test PV Seq Ctx field */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x200)
move($nbi_desc_wr[3], 0)
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x20000)
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)
move(expected[8], 0)
move(expected[9], 0xfff)
move(expected[10], 0)
move(expected[11], 0)
move(expected[12], 0)
move(expected[13], 0)
move(expected[14], 0)
move(expected[15], 0)

move(loop_cntr, 1)

.while (loop_cntr <= 0x7)

    .if (loop_cntr == 0)
        move(error_expected_flag, 1)
    .else
        move(error_expected_flag, 0)
    .endif

    alu[$nbi_desc_wr[2], --, B, loop_cntr, <<8]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)

    .if (loop_cntr == 0)
        br[test_fail#] // should always get error for this case, so should never get here
    .endif

error_expected_ret#:

    alu[expected[3], --, B, loop_cntr, <<8]
    alu[expected[3], expected[3], AND, 3, <<8]
    alu[expected[3], expected[3], OR, 0xff]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packge
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw

/* Test PV Sequence Number field */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
move($nbi_desc_wr[3], 0)
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0)
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)
move(expected[8], 0)
move(expected[9], 0xfff)

move(loop_cntr, 0)

.while (loop_cntr <= 0xffff)

    alu[temp, --, B, 1, <<8]
    alu[$nbi_desc_wr[2], temp, OR, loop_cntr, <<16]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_set_ingress_queue__sz1(pkt_vec, 0, 64)
    pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)

    alu[expected[3], temp, OR, loop_cntr, <<16]
    alu[expected[3], expected[3], OR, 0xff]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packge
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw


/* PV Seek already tested, rest of word doesn't apply for nbi */


/* Test PV P_STS field */
move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
move($nbi_desc_wr[3], 0)
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x000001ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xf)

    .if (loop_cntr >= 8)
        move(temp, 0x1fc00000) // Set all bits between P_STS and L3
        alu[$nbi_desc_wr[7], temp, OR, loop_cntr, <<29]
    .else
        alu[$nbi_desc_wr[7], --, B, loop_cntr, <<29]
    .endif

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_set_ingress_queue__sz1(pkt_vec, 0, 64)
    pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)


    //alu[expected[5], --, B, loop_cntr, <<29]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packge
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw

/* Test PV Ingress Queue field */

/* First try MType field in Metadata */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0)
move($nbi_desc_wr[3], 0)
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x000001ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 7)

    alu[temp, --, B, 1, <<8]
    alu[$nbi_desc_wr[2], temp, OR, loop_cntr, <<4]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_set_ingress_queue__sz1(pkt_vec, 0, 64)
    pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)


    move(temp, 0x1)
    alu[temp, temp, AND, loop_cntr] // mask off all but LSB
    alu[expected[6], expected[6], AND~, 1, <<30]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packge
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw


/* Now try Port field in Metadata */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
move($nbi_desc_wr[3], 0)
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x000001ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xff)

    alu[$nbi_desc_wr[4], --, B, loop_cntr, <<24]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    alu[temp, --, B, loop_cntr, <<6]
    pv_set_ingress_queue__sz1(pkt_vec, temp, 64)
    pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)


    alu[expected[6], expected[6], AND~, 0xff, <<23]
    alu[expected[6], expected[6], OR, loop_cntr, <<23]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packge
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw


/* Now try 7-bit Port field and LSB of MType field in Metadata */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
move($nbi_desc_wr[3], 0)
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // PKT_NBI_OFFSET = 128
move(expected[3], 0x000001ff) // Seq
move(expected[4], 0x00000000) // Seek
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xff)

    .if (loop_cntr >= 0x80)
        move($nbi_desc_wr[2], 0x110)
    .else
        move($nbi_desc_wr[2], 0x100)
    .endif
    alu[$nbi_desc_wr[4], --, B, loop_cntr, <<24]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    alu[temp, --, B, loop_cntr, <<6]
    pv_set_ingress_queue__sz1(pkt_vec, temp, 64)
    pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)

    alu[expected[6], expected[6], AND~, 0xff, <<23]
    alu[expected[6], expected[6], OR, loop_cntr, <<23]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < SIZE_LW)

        move(value, pkt_vec++)
        // derived from packge
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw


/* PV Metadata Type Fields word always set to 0, already tested */



/* Test all fields in PV are filled in when a "rx_discards_proto#" occurs */

move(error_expected_flag, 1)

load_addr[rtn_reg, error_expected_ret1#]

move($nbi_desc_wr[0], 0x03ffffff)
move($nbi_desc_wr[1], 0x9fffffff)
move($nbi_desc_wr[2], 0xffff0000)
move($nbi_desc_wr[3], 0x3000)
move($nbi_desc_wr[4], 0xff00ff00)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0xe03fffff)

move(expected[0], 0x3fffff7)
move(expected[1], 0xffffffff)
move(expected[2], 0x83ff0088)
move(expected[3], 0xffff00ff)
move(expected[4], 0x00000000)
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)


mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

pv_set_ingress_queue__sz1(pkt_vec, 0, 64)
pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)

br[test_fail#] // should always get error, so should never get here


error_expected_ret1#:

#define_eval _PV_CHK_LOOP 0

#while (_PV_CHK_LOOP < SIZE_LW)

    move(value, pkt_vec++)
    // derived from packge
    #if (_PV_CHK_LOOP == 4)
        alu[value, value, AND~, 0xc]
    #endif

    #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
#if (_PV_CHK_LOOP < 8)
    test_assert_equal(value, _PV_INIT_EXPECT)
#endif

    #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

#endloop


/* Test all fields in PV are filled in when any "rx_errors_parse#" occurs */

move(error_expected_flag, 2)

load_addr[rtn_reg, error_expected_ret2#]

move($nbi_desc_wr[0], 0x03ff00ff)
move($nbi_desc_wr[1], 0x9fffffff)
move($nbi_desc_wr[2], 0xffff0100)
move($nbi_desc_wr[3], 0x3000)
move($nbi_desc_wr[4], 0xff00ff00)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0xe03fffff)

move(expected[0], 0x3ff00f7)
move(expected[1], 0xbfffffff)
move(expected[2], 0x83ff0088)
move(expected[3], 0xffff01ff)
move(expected[4], 0x00000000)
move(expected[5], 0)
move(expected[6], 0x00000000)
move(expected[7], 0)


move(loop_cntr, 1)

.while (loop_cntr <= 0x3)

    alu[$nbi_desc_wr[5], --, B, loop_cntr, <<30]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_set_ingress_queue__sz1(pkt_vec, 0, 64)
    pv_init_nbi(pkt_vec, $nbi_desc_rd, mtu, drop#, fail#, fail#)

    br[test_fail#] // should always get error, so should never get here

error_expected_ret2#:

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP < PV_SIZE_LW)

        move(value, pkt_vec++)
        // derived from packge
        #if (_PV_CHK_LOOP == 4)
            alu[value, value, AND~, 0xc]
        #endif

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
#if (_PV_CHK_LOOP < 8)
        test_assert_equal(value, _PV_INIT_EXPECT)
#endif
        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw

test_pass()


drop#:
    .if (error_expected_flag == 1)
        rtn[rtn_reg]
        nop
        nop
        nop
    .endif
    br[test_fail#]

fail#:
    .if (error_expected_flag == 2)
        rtn[rtn_reg]
        nop
        nop
        nop
    .endif


test_fail#:

test_fail()
