#include <single_ctx_test.uc>
#include <config.h>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.sig s
.reg addr
.reg value
.reg temp
.reg rtn_reg
.reg loop_cntr
.reg loop_cntr1
.reg error_expected_flag
.reg expected[PV_SIZE_LW]
.reg volatile read  $nbi_desc_rd[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.reg volatile write $nbi_desc_wr[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $nbi_desc_rd
.xfer_order $nbi_desc_wr

#define pkt_vec *l$index1

move(error_expected_flag, 0)

load_addr[rtn_reg, error_expected_ret#]

pv_init(pkt_vec, 0)

move(addr, 0x80)


/* Test PV Seq Ctx field */

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
move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0)
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0x7)

    .if (loop_cntr == 0)
        move(error_expected_flag, 1)
    .else
        move(error_expected_flag, 0)
    .endif

    alu[$nbi_desc_wr[2], --, B, loop_cntr, <<8]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)

    .if (loop_cntr == 0)
        br[test_fail#] // should always get error for this case, so should never get here
    .endif


error_expected_ret#:

    alu[expected[3], --, B, loop_cntr, <<8]
    alu[expected[3], expected[3], AND, 3, <<8]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

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
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xffff)

    alu[temp, --, B, 1, <<8]
    alu[$nbi_desc_wr[2], temp, OR, loop_cntr, <<16]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[expected[3], temp, OR, loop_cntr, <<16]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

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
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
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

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[expected[5], --, B, loop_cntr, <<29]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV L3I, MPD and VLD fields */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
alu[$nbi_desc_wr[3], --, B, 2, <<12] // TCP
alu[$nbi_desc_wr[4], --, B, MAC_PREPEND_BYTES, <<8] // L4 Offset
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0x3f)

    alu[$nbi_desc_wr[7], --, B, loop_cntr, <<16]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[expected[5], --, B, loop_cntr, <<16]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV L4 Offset fields using OL4 = TCP */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
alu[$nbi_desc_wr[3], --, B, 3, <<12] // TCP
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= (0xff-MAC_PREPEND_BYTES))

    alu[temp, loop_cntr, +, MAC_PREPEND_BYTES]
    alu[$nbi_desc_wr[4], --, B, temp, <<8]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[temp, --, B, loop_cntr, >>1]
    alu[expected[5], --, B, temp, <<22]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV L4 Offset fields using OL4 = UDP */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
alu[$nbi_desc_wr[3], --, B, 2, <<12] // UDP
move($nbi_desc_wr[4], 0)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= (0xff-MAC_PREPEND_BYTES))

    alu[temp, loop_cntr, +, MAC_PREPEND_BYTES]
    alu[$nbi_desc_wr[4], --, B, temp, <<8]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[temp, --, B, loop_cntr, >>1]
    alu[expected[5], --, B, temp, <<22]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV L4 Offset fields using OL4 fields other than TCP and UDP */

/* If OL4 is not TCP or UDP:
 * If the PV VLD bits are >= 2    the L4 Offset will not be written
 * If the PV MPD bits are not = 0 the L4 Offset will not be written
 * If the PV L3I bits are = 0     the L4 Offset will not be written
 * If there are IPv6 Extension Headers other than hop-by-hop(H), routing(R) and destination(D) the L4 Offset will not be written
 * Otherwise the L4 offset field will be written
 */

move($nbi_desc_wr[0], 64)
move($nbi_desc_wr[1], 0)
move($nbi_desc_wr[2], 0x100)
move($nbi_desc_wr[3], 0)
alu[$nbi_desc_wr[4], --, B, 0xff, <<8] // HP-Off0
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0)

move(expected[0], (64 - MAC_PREPEND_BYTES))
move(expected[1], 0)
move(expected[2], 0x80000088) // A always set, PKT_NBI_OFFSET = 128
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xf)

    .if ((loop_cntr == 2) || (loop_cntr == 3))
        br[cont_loop#]
    .endif

    alu[$nbi_desc_wr[3], --, B, loop_cntr, <<12]

    move(loop_cntr1, 0)

    .while (loop_cntr1 <= 18) // PV VLD(4) + PV MPD(4) + PV L3I(4) + Meta IPv6(7)

        alu[temp, loop_cntr1, AND, 3]
        .if (loop_cntr1 < 4)
            alu[temp, temp, OR, 1, <<4] // have to set L3 to something other than 0 to test VLN
            alu[$nbi_desc_wr[7], --, B, temp, <<16] // VLN
        .elif (loop_cntr1 < 8)
            alu[temp, temp, OR, 1, <<2] // have to set L3 to something other than 0 to test MPL
            alu[$nbi_desc_wr[7], --, B, temp, <<18] // MPL
        .elif (loop_cntr1 < 12)
            alu[$nbi_desc_wr[7], --, B, temp, <<20] // L3
        .else
            alu[temp, loop_cntr1, +, 10]
            alu[--, temp, B, 0]
            alu[temp, --, B, 1, <<indirect]
            alu[temp, temp, OR, 1, <<20] // have to set L3 to something other than 0 to test IPv6 bits
            alu[$nbi_desc_wr[7], --, B, temp]
        .endif

        mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

        mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

        pv_init_nbi(pkt_vec, $nbi_desc_rd)


        /* If OL4 is not TCP or UDP:
         * If the PV VLD bits are >= 2    the L4 Offset will not be written
         * If the PV MPD bits are not = 0 the L4 Offset will not be written
         * If the PV L3I bits are = 0     the L4 Offset will not be written
         * If there are IPv6 Extension Headers other than hop-by-hop(H), routing(R) and destination(D) the L4 Offset will not be written
         * Otherwise the L4 offset field will be written
         */

        /* Assume the L4 Offset will be written */
        alu[expected[5], --, B, 0x7b, <<22]

        move(temp, 0)

        .if ((loop_cntr1 > 1) && (loop_cntr1 < 4))
            move(temp, 1)
        .endif
        .if ((loop_cntr1 > 4) && (loop_cntr1 < 8))
            move(temp, 1)
        .endif
        .if (loop_cntr1 == 8)
            move(temp, 1)
        .endif
        .if (loop_cntr1 > 14)
            move(temp, 1)
        .endif
        .if (temp == 1)
            move(expected[5], 0)
        .endif

        /* Or in L3, MPL, VLN bits */

        alu[temp, loop_cntr1, AND, 3]
        .if (loop_cntr1 < 4)
            alu[expected[5], expected[5], OR, temp, <<16] // VLD
            alu[expected[5], expected[5], OR, 1, <<20] // had to set L3 to something other than 0 to test VLN
        .elif (loop_cntr1 < 8)
            alu[expected[5], expected[5], OR, temp, <<18] // MPD
            alu[expected[5], expected[5], OR, 1, <<20] // had to set L3 to something other than 0 to test MPL
        .elif (loop_cntr1 < 12)
            alu[expected[5], expected[5], OR, temp, <<20] // L3I
        .else
            alu[expected[5], expected[5], OR, 1, <<20] // had to set L3 to something other than 0 to test IPv6 bits
        .endif

        #define_eval _PV_CHK_LOOP 0

        #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

            move(value, pkt_vec++)

            #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
            test_assert_equal(value, _PV_INIT_EXPECT)

            #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

        #endloop

xxx#:
        alu[loop_cntr1, loop_cntr1, +, 1]

    .endw

cont_loop#:
    alu[loop_cntr, loop_cntr, +, 1]

.endw



/* Test PV Checksum field */

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
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xffff)

    alu[$nbi_desc_wr[7], --, B, loop_cntr]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    alu[expected[5], --, B, loop_cntr]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

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
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 7)

    alu[temp, --, B, 1, <<8]
    alu[$nbi_desc_wr[2], temp, OR, loop_cntr, <<4]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    move(temp, 0x1)
    alu[temp, temp, AND, loop_cntr] // mask off all but LSB
    alu[expected[6], --, B, temp, <<30]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

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
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xff)

    alu[$nbi_desc_wr[4], --, B, loop_cntr, <<24]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    /* The "N" bit of the PV NBI Ingress Queue is actually an "or" of MType[0] and Port[7] */

    alu[expected[6], --, B, loop_cntr, <<23]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

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
move(expected[3], 0x00000100) // Seq
move(expected[4], 0x00003fc0) // Seek
move(expected[5], 0)
move(expected[6], 0)
move(expected[7], 0)

move(loop_cntr, 0)

.while (loop_cntr <= 0xff)

    .if (loop_cntr >= 0x80)
        move($nbi_desc_wr[2], 0x110)
    .else
        move($nbi_desc_wr[2], 0x100)
    .endif

    alu[temp, loop_cntr, AND, 0x7f]
    alu[$nbi_desc_wr[4], --, B, temp, <<24]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)


    /* The "N" bit of the PV NBI Ingress Queue is actually an "or" of MType[0] and Port[7] */

    alu[expected[6], --, B, loop_cntr, <<23]

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

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
move(expected[3], 0xffff0000)
move(expected[4], 0x00003fc0)
move(expected[5], 0xfeffffff)
move(expected[6], 0x7f800000)
move(expected[7], 0)


mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

pv_init_nbi(pkt_vec, $nbi_desc_rd)

br[test_fail#] // should always get error, so should never get here


error_expected_ret1#:

#define_eval _PV_CHK_LOOP 0

#while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

    move(value, pkt_vec++)

    #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
    test_assert_equal(value, _PV_INIT_EXPECT)

    #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

#endloop



/* Test all fields in PV are filled in when any "rx_errors_parse#" occurs */

move(error_expected_flag, 2)

load_addr[rtn_reg, error_expected_ret2#]

move($nbi_desc_wr[0], 0x03ffffff)
move($nbi_desc_wr[1], 0x9fffffff)
move($nbi_desc_wr[2], 0xffff0100)
move($nbi_desc_wr[3], 0x3000)
move($nbi_desc_wr[4], 0xff00ff00)
move($nbi_desc_wr[5], 0)
move($nbi_desc_wr[6], 0)
move($nbi_desc_wr[7], 0xe03fffff)

move(expected[0], 0x3fffff7)
move(expected[1], 0xffffffff)
move(expected[2], 0x83ff0088)
move(expected[3], 0xffff0100)
move(expected[4], 0x00003fc0)
move(expected[5], 0xfeffffff)
move(expected[6], 0x7f800000)
move(expected[7], 0)


move(loop_cntr, 1)

.while (loop_cntr <= 0x3)

    alu[$nbi_desc_wr[5], --, B, loop_cntr, <<30]

    mem[write32, $nbi_desc_wr[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    mem[read32,  $nbi_desc_rd[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

    pv_init_nbi(pkt_vec, $nbi_desc_rd)

    br[test_fail#] // should always get error, so should never get here

error_expected_ret2#:

    #define_eval _PV_CHK_LOOP 0

    #while (_PV_CHK_LOOP <= (PV_SIZE_LW-1))

        move(value, pkt_vec++)

        #define_eval _PV_INIT_EXPECT 'expected[/**/_PV_CHK_LOOP/**/]'
        test_assert_equal(value, _PV_INIT_EXPECT)

        #define_eval _PV_CHK_LOOP (_PV_CHK_LOOP + 1)

    #endloop

    alu[loop_cntr, loop_cntr, +, 1]

.endw



test_pass()


rx_discards_proto#:
    .if (error_expected_flag == 1)
        rtn[rtn_reg]
        nop
        nop
        nop
    .endif
    br[test_fail#]

rx_errors_parse#:
    .if (error_expected_flag == 2)
        rtn[rtn_reg]
        nop
        nop
        nop
    .endif


test_fail#:

test_fail()

