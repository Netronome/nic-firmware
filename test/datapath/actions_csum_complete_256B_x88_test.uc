/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x100
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_inc_pat_256B_x88.uc"

#include <single_ctx_test.uc>
#include <global.uc>
#include <bitfields.uc>

#macro checksum_pattern(csum, len)
.begin
    .reg i
    .reg data

    immed[csum, 0]
    immed[i, 14]

loop#:
    alu[i, i, +, 1]
    alu[data, 0, B, i, <<24]
    alu[--, len, -, i]
    beq[finalize#]

    alu[i, i, +, 1]
    alu[data, data, OR, i, <<16]
    alu[--, len, -, i]
    beq[finalize#]

    alu[i, i, +, 1]
    alu[data, data, OR, i, <<8]
    alu[--, len, -, i]
    beq[finalize#]

    alu[i, i, +, 1]
    alu[data, data, OR, i]

finalize#:
    alu[csum, csum, +, data]
    alu[csum, csum, +carry, 0]
    alu[--, len, -, i]
    bgt[loop#]

.end
#endm

.reg csum_offset
immed[csum_offset, -4]

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)
test_assert(pkt_len < 256)

.reg csum
.reg pv_csum
.reg length
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

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
