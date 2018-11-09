/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup_seq_multiple_add_test.c
 * @brief         Adds same sequential MAC's multiple times
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


#define NUM_TEST_MACS (MAC_LKUP_NUM_BUCKETS * 6)

__export __emem_n(0) struct mac_addr test_macs[NUM_TEST_MACS];

__export __imem_n(0) __align(MAC_LKUP_TABLE_SZ)
          struct mem_lkup_cam_r_48_64B_table_bucket_entry
          mac_lkup_tbl[MAC_LKUP_NUM_BUCKETS];


static void gen_seq_macs(void)
{
    uint32_t i;
    struct mac_addr mac;

    for (i = 0; i < NUM_TEST_MACS; i++) {
        test_macs[i].mac_dword = TEST_MAC + i;
    }
}


static void add_macs(void)
{
    uint32_t i;

    for (i = 0; i < NUM_TEST_MACS; i++) {
        if (mac_lkup_add(test_macs[i], NUM_TEST_MACS - i))
            test_fail();
    }
}


static void add_macs2(void)
{
    uint32_t i;

    for (i = 0; i < NUM_TEST_MACS; i++) {
        if (mac_lkup_add(test_macs[i], i))
            test_fail();
    }
}


/*Lookup MAC's that we expect to find*/
static void lookup_mac_expect(void)
{
    uint32_t i, result;
    __xrw struct mac_addr mac_lkup;

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


static void test(void)
{
    uint32_t i;

    //generate random macs
    gen_seq_macs();

    add_macs();

    add_macs2();
    lookup_mac_expect();
}


void main()
{
    single_ctx_test();
    trng_init();

    test();

    test_pass();
}
