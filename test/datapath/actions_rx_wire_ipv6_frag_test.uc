/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x0
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

;TEST_INIT_EXEC nfp-mem i32.ctm:0x80   0x00000000 0x00000000 0x001d0994 0x6538685b
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90   0x35c061b6 0x86dd6002 0x128905b0 0x2c402607
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0   0xf01003f9 0x00000000 0x00000000 0x10012607
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0   0xf01003f9 0x00000000 0x00000011 0x00001100
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0   0x0001f88e 0xb46618db 0x18db150b 0x791606fd
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0   0x14ff0729 0x08076578 0x616d706c 0x65080774
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0   0x65737441 0x70700801 0x31080774 0x65737441
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0   0x70700809 0xfd000001 0x4f2368c7 0x8e140419
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100  0x02271015 0xfd138868 0x68686868 0x68686868
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110  0x68686868 0x68686868 0x68686868 0x68686868
;TEST_INIT_EXEC nfp-mem i32.ctm:0x120  0x68686868 0x68686868 0x68686868 0x68686868
;TEST_INIT_EXEC nfp-mem i32.ctm:0x130  0x68686868 0x68686868 0x68686868 0x68686868
;TEST_INIT_EXEC nfp-mem i32.ctm:0x140  0x68686868 0x68686868 0x68686868 0x68686868
;TEST_INIT_EXEC nfp-mem i32.ctm:0x150  0x68686868 0x68686868 0x68686868 0x68686868

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
.reg pkt_num
.sig s

#define PKT_NUM_i 0
#while PKT_NUM_i < 0x100
    move(pkt_num, PKT_NUM_i)
    pkt_buf_free_ctm_buffer(--, pkt_num)
    #define_eval PKT_NUM_i (PKT_NUM_i + 1)
#endloop
#undef PKT_NUM_i

move(addr, 0x200)

#define pkt_vec *l$index1

//set up CATAMARAN vector

move($nbi_desc[0], ((0x40<<BF_L(CAT_PKT_LEN_bf)) | 1<<BF_L(CAT_BLS_bf)))
move($nbi_desc[1], 0)
move($nbi_desc[2], (0x2<<BF_L(CAT_SEQ_CTX_bf))]
move($nbi_desc[3], (CAT_L3_TYPE_IP<<BF_L(CAT_L3_TYPE_bf)) | (5<<(BF_L(CAT_L3_CLASS_bf))))
move($nbi_desc[4], (1<<BF_L(CAT_V4_FRAG_bf)))
move($nbi_desc[5], 0)
move($nbi_desc[6], 0)
move($nbi_desc[7], (0x1<<BF_L(MAC_PARSE_L3_bf) | 0x7 << BF_L(MAC_PARSE_STS_bf)))

mem[write32, $nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

mem[read32,  $__pkt_io_nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]
nop
nop

__actions_rx_wire(pkt_vec)

bitfield_extract__sz1(protocol, BF_AML(pkt_vec, PV_PROTO_bf))

test_assert_equal(protocol, 0x5)

test_assert_equal(*$index, 0xdeadbeef)

test_pass()

PV_HDR_PARSE_SUBROUTINE#:
pv_hdr_parse_subroutine(pkt_vec)

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
