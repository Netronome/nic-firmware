/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup_empty_table_test.c
 * @brief         Tests the MAC lookup table by attempting to lookup MAC's
 *                that aren't in the table
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

__export __emem_n(0) struct mac_addr test_macs[NUM_TEST_MACS];

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

/*Lookup MAC's that we DON'T expect to find*/
static void lookup_mac_dont_expect(void)
{
    uint32_t i, result;
    __xrw struct mac_addr mac_lkup;

    for (i = 0; i < NUM_TEST_MACS; i++) {
        mac_lkup.mac_word[0] = test_macs[i].mac_word[1];
        mac_lkup.mac_word[1] = test_macs[i].mac_word[0];

        mem_lkup_cam_r_48_64B(&mac_lkup.mac_word[0],
            (__mem40 void *) mac_lkup_tbl,
            0, sizeof(mac_lkup.mac_dword), sizeof(mac_lkup_tbl));

        result = mac_lkup.mac_word[0];
        test_assert_equal(result, 0);
    }

}


static void test(void)
{
    //generate random macs
    gen_random_macs();

    //lookup the macs (don't expect to find them)
    lookup_mac_dont_expect();
}


void main()
{
    single_ctx_test();
    trng_init();

    test();

    test_pass();
}
