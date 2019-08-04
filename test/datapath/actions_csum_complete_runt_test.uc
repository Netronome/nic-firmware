/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x0
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_inc_pat_64B_x88.uc"

#include <single_ctx_test.uc>
#include <global.uc>

.reg write $zero
.sig sig_csum
.reg csum_offset
immed[$zero, 0]
immed[csum_offset, -4]
mem[write32, $zero, BF_A(pkt_vec, PV_CTM_ADDR_bf), csum_offset, 1], ctx_swap[sig_csum]

.reg csum
.reg pv_csum
.reg length
immed[length, 0]
.while (length < 15)
    local_csr_wr[T_INDEX, (32 * 4)]
    immed[__actions_t_idx, (32 * 4)]

    immed[BF_A(pkt_vec, PV_META_TYPES_bf), 0]
    alu[BF_A(pkt_vec, PV_LENGTH_bf), --, B, length]

    __actions_checksum(pkt_vec)

    test_assert_equal(*$index, 0xdeadbeef)

    alu[--, --, B, *l$index2--]
    alu[pv_csum, --, B, *l$index2--]

    test_assert_equal(pv_csum, 0)

    test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)

    alu[length, length, +, 1]
.endw

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
