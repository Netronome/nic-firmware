/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup_lock_test.c
 * @brief         Tests the tests the mac_lkup_tbl_bucket_wait and
 *                mac_lkup_tbl_bucket_release functions
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include "defines.h"
#include "test.c"
#include "app_mac_lkup.c"
#include "app_mac_lkup.h"
#include <nfp/mem_lkup.h>
#include "trng.c"
#include "trng.h"


static void test(void)
{
    uint32_t i;

    for (i = 0; i < MAC_LKUP_NUM_BUCKETS; i++) {
        mac_lkup_tbl_bucket_wait(i);
        mac_lkup_tbl_bucket_release(i);
    }
}


void main()
{
    single_ctx_test();
    trng_init();

    test();

    test_pass();
}
