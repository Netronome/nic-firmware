/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * @file   test.uc
 * @brief  Microcode unit test library functions
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#ifndef __TEST_UC
#define __TEST_UC

#include <stdmac.uc>

#macro test_pass()
    local_csr_wr[MAILBOX_0, 0x01]
    ctx_arb[kill]
#endm


#macro test_fail(fail_type)
.begin
    .reg sts
    local_csr_wr[MAILBOX_0, fail_type]
    local_csr_rd[ACTIVE_CTX_STS]
    immed[sts, 0]
    local_csr_wr[MAILBOX_1, sts]
    ctx_arb[kill]
.end
#endm


#macro test_fail()
    test_fail(0xff)
#endm


#macro test_assert(ASSERT)
    .if_unsigned(ASSERT)
    .else
        test_fail(0xfa) ; fail assert
    .endif
#endm


#macro test_assert_equal(tested, expected)
.begin
    .reg lhs
    .reg rhs
    move(lhs, tested)
    move(rhs, expected)
    .if_unsigned(lhs != rhs)
        local_csr_wr[MAILBOX_2, lhs]
        local_csr_wr[MAILBOX_3, rhs]
        test_fail(0xfc) ; fail compare
    .endif
.end
#endm


#macro test_assert_unequal(tested, expected)
.begin
    .reg lhs
    .reg rhs
    move(lhs, tested)
    move(rhs, expected)
   .if_unsigned(lhs == rhs)
       local_csr_wr[MAILBOX_2, lhs]
       test_fail(0xfe) ; fail equal
   .endif
.end
#endm


#ifndef _ACTIONS_UC
.if (0)
    ebpf_reentry#:
.endif
#endif

#endif

