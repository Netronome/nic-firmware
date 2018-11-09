/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup_empty_table_test.c
 * @brief         Tests the mac_lkup_add function by adding random MAC's
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
#include "app_master_test.h"

#define NUM_TEST_MACS (NVNICS_ABSOLUTE_MAX * NFD_MAX_ISL + NFD_MAX_ISL)

__export __mem struct mac_addr test_macs[NUM_TEST_MACS];

__export __imem_n(0) __align(MAC_LKUP_TABLE_SZ)
          struct mem_lkup_cam_r_48_64B_table_bucket_entry
          mac_lkup_tbl[MAC_LKUP_NUM_BUCKETS];


static void gen_random_macs(void)
{
    uint32_t i;
    struct mac_addr mac;

    for (i = 0; i < NUM_TEST_MACS; i++) {

        trng_rd64(&mac.mac_word[1], &mac.mac_word[0]);

        /* Make sure no Multicast */
        mac.mac_word[1] &= 0xFEFFFFFF;
        /* Local assigned bit set */
        mac.mac_word[1] |= 0x02000000;
        mac.mac_word[0] = mac.mac_word[0] >> 16;
        test_macs[i].mac_dword = mac.mac_dword;
    }
}

static void add_macs(void)
{
    uint32_t i;

    for (i = 0; i < NUM_TEST_MACS; i++) {
        if (mac_lkup_add(test_macs[i], i))
            test_fail();
    }
}

static void test(void)
{
    uint32_t i, result;
    __xrw struct mac_addr mac_lkup;

    //generate random macs
    gen_random_macs();

    //add all the MACS to the lookup table
    add_macs();

    //lookup the MACS previously added
    for (i = 0; i < NUM_TEST_MACS; i++) {
        mac_lkup.mac_word[0] = test_macs[i].mac_word[1];
        mac_lkup.mac_word[1] = test_macs[i].mac_word[0];

        mem_lkup_cam_r_48_64B(&mac_lkup.mac_word[0],
            (__mem40 void *) mac_lkup_tbl,
            0, sizeof(mac_lkup.mac_dword), sizeof(mac_lkup_tbl));

        result = mac_lkup.mac_word[0] & MAC_LKUP_USED;
        test_assert_equal(result, MAC_LKUP_USED);

        result = mac_lkup.mac_word[0] & ~MAC_LKUP_USED;
        test_assert_equal(result, i);
    }
}


void main()
{
    single_ctx_test();
    trng_init();

    test();

    test_pass();
}
