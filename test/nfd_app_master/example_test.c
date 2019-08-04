/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
    example microc test

    run from cmd line via:
     "make test"                   (run microcode tests, then microc tests)
     "make test_u"                 (run all microcode tests)
     "make test_c"                 (run all microc tests)
     "make test_c FILTER=example"  (run just this test)
*/

#include "test.c"

void main() {
    single_ctx_test();
    // test_fail();
    // test_assert(0);
    // test_assert_equal(0x22,0x23);
    // test_assert_unequal(0x22,0x22);
    test_pass();
}
