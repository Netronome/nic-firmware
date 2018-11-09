/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup_random_capacity_test.c
 * @brief         Add 256 random MAC's repeatedly to check MAC lookup table capacity
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

#define REQ_SUPPORTED_MACS  256

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


static uint32_t add_macs(void)
{
    uint32_t i;
    for (i = 0; i < NUM_TEST_MACS; i++) {
        if (mac_lkup_add(test_macs[i], i)) {
            if (i < REQ_SUPPORTED_MACS)
                test_fail();
            else
                break;
        }
    }
    return i;
}


/*Lookup MAC's that we expect to find*/
static void lookup_mac_expect(uint32_t num)
{
    uint32_t i, result;
    __xrw struct mac_addr mac_lkup;

    for (i = 0; i < num; i++) {
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


static void del_macs(uint32_t num)
{
    uint32_t i;

    for (i = 0; i < num; i++) {
        if (mac_lkup_del(test_macs[i]))
            test_fail();
    }
}


static void test(void)
{
    uint32_t i, amt_added;

    for (i = 0; i < 1000; i++) {
        //generate random macs
        gen_random_macs();

        //add all the MACS to the lookup table
        amt_added = add_macs();

        //lookup the MACS previously added
        lookup_mac_expect(amt_added);

        del_macs(amt_added);
    }

}


void main()
{
    single_ctx_test();
    trng_init();

    test();

    test_pass();
}
