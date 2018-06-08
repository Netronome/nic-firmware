;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x3ff
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x12b51c00
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xdeadbeef

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80  0x00000000 0x00000000 0x00154d0e 0x04a50800
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90  0x273d254e 0x81000065 0x81000258 0x08004500
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0  0x003c18f1 0x00008001 0x9e7cc0a8 0x0101c0a8
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0  0x01020800 0x2b5c0200 0x20006162 0x63646566
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0  0x6768696a 0x6b6c6d6e 0x6f707172 0x73747576
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0  0x77616263 0x64656667 0x68690000

#include <pkt_io.uc>
#include <single_ctx_test.uc>
#include <actions.uc>
#include <bitfields.uc>
#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg protocol
.reg volatile write $nbi_desc[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $nbi_desc
.reg addr
.sig s

.reg o_l3_offset
.reg o_l4_offset
.reg i_l3_offset
.reg i_l4_offset
.reg proto
.reg expected_o_l3_offset
.reg expected_o_l4_offset
.reg expected_i_l3_offset
.reg expected_i_l4_offset
.reg expected_proto
.reg pkt_num

#define PKT_NUM_i 0
#while PKT_NUM_i < 0x100
    move(pkt_num, PKT_NUM_i)
    pkt_buf_free_ctm_buffer(--, pkt_num)
    #define_eval PKT_NUM_i (PKT_NUM_i + 1)
#endloop
#undef PKT_NUM_i

move(addr, 0x200)
move(expected_i_l3_offset, (14 + 4 + 4))
move(expected_i_l4_offset, 0)
move(expected_o_l3_offset, (14 + 4 + 4))
move(expected_o_l4_offset,0)
move(expected_proto, 6)

#define pkt_vec *l$index1
pv_init(pkt_vec, 0)

move(pkt_vec[4], 0x3fc0)

//set up CATAMARAN vector
move($nbi_desc[0], ((0x52<<BF_L(CAT_PKT_LEN_bf)) | 0<<BF_L(CAT_BLS_bf)))
move($nbi_desc[1], 0)
move($nbi_desc[2], (0x2<<BF_L(CAT_SEQ_CTX_bf))]
move($nbi_desc[3], (CAT_L3_TYPE_IP<<BF_L(CAT_L3_TYPE_bf)))
move($nbi_desc[4], 0)
move($nbi_desc[5], 0)
move($nbi_desc[6], 0)
move($nbi_desc[7], (0x0<<BF_L(MAC_PARSE_L3_bf) | 0x0 << BF_L(MAC_PARSE_STS_bf) | 0x2<<BF_L(MAC_PARSE_VLAN_bf)))

mem[write32, $nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

mem[read32,  $__pkt_io_nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]
nop
nop

__actions_rx_wire(pkt_vec, drop_mtu#, drop_proto#, error_parse#)

test_assert_equal(*$index, 0xdeadbeef)

bitfield_extract__sz1(proto, BF_AML(pkt_vec, PV_PROTO_bf))
bitfield_extract__sz1(i_l4_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_INNER_L4_bf))
bitfield_extract__sz1(i_l3_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_INNER_IP_bf))
bitfield_extract__sz1(o_l4_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_L4_bf))
bitfield_extract__sz1(o_l3_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_IP_bf))


test_assert_equal(proto, expected_proto)
test_assert_equal(i_l3_offset, expected_i_l3_offset)
test_assert_equal(i_l4_offset, expected_i_l4_offset)
test_assert_equal(o_l3_offset, expected_o_l3_offset)
test_assert_equal(o_l4_offset, expected_o_l4_offset)

test_pass()

error#:
error_parse#:
drop_mtu#:
drop_proto#:
test_fail()

#pragma warning(push)
#pragma warning(disable: 4701)
#pragma warning(disable: 5116)
PV_HDR_PARSE_SUBROUTINE#:
pv_hdr_parse_subroutine(pkt_vec, port_tun_args)
#pragma warning(pop)
