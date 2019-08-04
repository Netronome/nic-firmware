/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x100
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_all_ones_9K_x88.uc"

#include <single_ctx_test.uc>
#include <global.uc>
#include <bitfields.uc>

#macro checksum_ones(csum, len)
.begin
    .reg count
    .reg data
    .reg rem

    immed[data, 0xffffffff]
    immed[csum, 0]

    alu[count, len, -, 14]
    alu[rem, count, AND, 3]
    alu[count, --, B, count, >>2]

.while (count > 0)
    alu[csum, csum, +, data]
    alu[csum, csum, +carry, 0]
    alu[csum, csum, +carry, 0]
    alu[count, count, -, 1]
.endw

    .if (rem == 1)
        immed[data, 0xff00, <<16]
        alu[csum, csum, +, data]
        alu[csum, csum, +carry, 0]
        alu[csum, csum, +carry, 0]
    .elif (rem == 2)
        immed[data, 0xffff, <<16]
        alu[csum, csum, +, data]
        alu[csum, csum, +carry, 0]
        alu[csum, csum, +carry, 0]
    .elif (rem == 3)
        alu[data, --, ~B, 0xff]
        alu[csum, csum, +, data]
        alu[csum, csum, +carry, 0]
        alu[csum, csum, +carry, 0]
    .endif

done#:
.end
#endm

#macro fail_alloc_macro
    br[fail#]
#endm

.reg csum_offset
immed[csum_offset, -4]

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)

.reg csum
.reg pv_csum
.reg length

.reg pkt_num

#define PKT_NUM_i 0
#while PKT_NUM_i < 0x100
    move(pkt_num, PKT_NUM_i)
    pkt_buf_free_ctm_buffer(--, pkt_num)
    #define_eval PKT_NUM_i (PKT_NUM_i + 1)
#endloop
#undef PKT_NUM_i

pkt_buf_alloc_ctm(pkt_num, 3, fail#, fail_alloc_macro)

test_assert_equal(pkt_num, 0)

move(pkt_vec[2], 0x80000088)

immed[length, 15]
.while (length <= pkt_len)
    local_csr_wr[T_INDEX, (32 * 4)]
    immed[__actions_t_idx, (32 * 4)]

    immed[BF_A(pkt_vec, PV_META_TYPES_bf), 0]
    //immed[BF_A(pkt_vec, PV_META_LENGTH_bf), 0]
    alu[BF_A(pkt_vec, PV_LENGTH_bf), --, B, length]

    __actions_checksum(pkt_vec)

    test_assert_equal(*$index, 0xdeadbeef)

    checksum_ones(csum, length)
    //mem[read32, $csum, BF_A(pkt_vec, PV_CTM_ADDR_bf), csum_offset, 1], ctx_swap[sig_csum]

    alu[--, --, B, *l$index2--]
    alu[pv_csum, --, B, *l$index2--]

    test_assert_equal(pv_csum, csum)

    test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), NFP_NET_META_CSUM)

    alu[length, length, +, 1]
.endw

test_pass()

fail#:
test_fail()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
