/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup_empty_table_del_test.c
 * @brief         Tests that deleting MAC's form empty table returns error
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


/*Attempt to delete MACS in empty table*/
static void del_macs(void)
{
    uint32_t i;

    for (i = 0; i < NUM_TEST_MACS; i++) {
        if (mac_lkup_del(test_macs[i]) == 0)
            test_fail();
    }
}


static void test(void)
{
    uint32_t i;

    //generate random macs
    gen_random_macs();
    //Try delete the macs from the table.
    del_macs();
}


void main()
{
    single_ctx_test();
    trng_init();

    test();

    test_pass();
}
