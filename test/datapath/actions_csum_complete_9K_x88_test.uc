/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x100
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_inc_pat_9K_x88.uc"

#include <single_ctx_test.uc>
#include <global.uc>
#include <bitfields.uc>


#macro checksum_pattern(csum, len)
.begin
    .reg count
    .reg last_byte
    .reg i
    .reg data

    immed[csum, 0]

    immed[i, 8]
    alu[count, len, -, 14]
    alu[last_byte, count, AND, 1]
    alu[count, --, B, count, >>1]
    beq[last_even#]

loop#:
    alu[data, 0, B, i, <<16]
    alu[i, i, +, 1]

    alu[count, count, -, 1]
    beq[last_odd#]

    alu[data, data, OR, i]
    alu[i, i, +, 1]

accumulate#:
    alu[csum, csum, +, data]
    alu[csum, csum, +carry, 0]
    alu[count, count, -, 1]
    bgt[loop#]

last_even#:
    alu[--, --, B, last_byte]
    beq[done#]

    alu[data, --, B, i, <<16]
    alu[data, data, AND, 0xff, <<24]
    br[finalize#]

last_odd#:
    alu[--, --, B, last_byte]
    beq[finalize#]

    alu[data, data, OR, i]
    alu[data, data, AND~, 0xff]

finalize#:
    alu[csum, csum, +, data]
    alu[csum, csum, +carry, 0]

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
    alu[BF_A(pkt_vec, PV_LENGTH_bf), --, B, length]

    __actions_checksum(pkt_vec)

    test_assert_equal(*$index, 0xdeadbeef)

    checksum_pattern(csum, length)
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
