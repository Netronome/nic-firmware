/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x12b51c00
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00000000 0x00000000 0x00163ec4 0x23450000
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x0b000200 0x86dd6030 0x00000010 0x8cfffe80
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x00000000 0x00000200 0x0bfffe00 0x02003555
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x55556666 0x66667777 0x77778888 0x88881100
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0x00000000 0x0000003f 0x003f0008 0x9b680c79
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0  0x8ce90000

#define NFD_CFG_CLASS_VERSION   0
#define NFD_CFG_CLASS_DEFAULT 0

#include <pkt_io.uc>
#include <single_ctx_test.uc>
#include <global.uc>
#include <actions.uc>
#include <bitfields.uc>

.reg protocol
.reg volatile write $nbi_desc[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $nbi_desc
.reg addr
.sig s

.reg o_l4_offset
.reg o_l3_offset
.reg i_l4_offset
.reg i_l3_offset
.reg proto
.reg expected_o_l3_offset
.reg expected_o_l4_offset
.reg expected_i_l3_offset
.reg expected_i_l4_offset
.reg expected_proto
.reg pkt_len
.reg pkt_num

#define PKT_NUM_i 0
#while PKT_NUM_i < 0x100
    move(pkt_num, PKT_NUM_i)
    pkt_buf_free_ctm_buffer(--, pkt_num)
    #define_eval PKT_NUM_i (PKT_NUM_i + 1)
#endloop
#undef PKT_NUM_i

move(addr, 0x200)
move(expected_i_l3_offset, 14)
move(expected_i_l4_offset, 0)
move(expected_o_l3_offset, 14)
move(expected_o_l4_offset,0)
move(expected_proto, 4)

#define pkt_vec *l$index1

//set up CATAMARAN vector
move($nbi_desc[0], ((0x52<<BF_L(CAT_PKT_LEN_bf)) | 0<<BF_L(CAT_BLS_bf)))
move($nbi_desc[1], 0)
move($nbi_desc[2], (0x2<<BF_L(CAT_SEQ_CTX_bf))]
move($nbi_desc[3], 0)
move($nbi_desc[4], 0)
move($nbi_desc[5], 0)
move($nbi_desc[6], 0)
move($nbi_desc[7], (0x0<<BF_L(MAC_PARSE_L3_bf) | 0x0 << BF_L(MAC_PARSE_STS_bf) | 0x0<<BF_L(MAC_PARSE_VLAN_bf)))

mem[write32, $nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

mem[read32,  $__pkt_io_nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]
nop
nop

__actions_rx_wire(pkt_vec)

test_assert_equal(*$index, 0xdeadbeef)

bitfield_extract__sz1(proto, BF_AML(pkt_vec, PV_PROTO_bf))
bitfield_extract__sz1(i_l4_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_INNER_L4_bf))
bitfield_extract__sz1(i_l3_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_INNER_IP_bf))
bitfield_extract__sz1(o_l4_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_L4_bf))
bitfield_extract__sz1(o_l3_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_IP_bf))

test_assert_equal(proto, expected_proto)
test_assert_equal(i_l4_offset, expected_i_l4_offset)
test_assert_equal(i_l3_offset, expected_i_l3_offset)
test_assert_equal(o_l4_offset, expected_o_l4_offset)
test_assert_equal(o_l3_offset, expected_o_l3_offset)

test_pass()

PV_HDR_PARSE_SUBROUTINE#:
pv_hdr_parse_subroutine(pkt_vec)

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
