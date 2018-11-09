/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup.c
 * @brief         MAC lookup libraries.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <assert.h>
#include <nfp.h>
#include <nfp_chipres.h>

#include <stdint.h>

#include <platform.h>
#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp/mem_lkup.h>
#include <nfp/mem_atomic.h>
#include <nfp/cls.h>
#include <nfp6000/nfp_me.h>
#include <std/reg_utils.h>

#include <app_mac_lkup.h>

/*
 * Global declarations
 */

__export __imem_n(0) __align(MAC_LKUP_TABLE_SZ)
          struct mem_lkup_cam_r_48_64B_table_bucket_entry
          mac_lkup_tbl[MAC_LKUP_NUM_BUCKETS];


/*A lock per table bucket, to ensure thread safety*/
__export __imem_n(0) uint32_t mac_lkup_tbl_lock[MAC_LKUP_NUM_BUCKETS >> 5];


__inline void
mac_lkup_tbl_bucket_wait(uint32_t table_idx)
{
    uint32_t lock_idx = table_idx >> 5;
    uint32_t shf = (table_idx & 31);
    uint32_t test_msk = 1 << shf;
    __xrw uint32_t test = test_msk;

    do {
        mem_test_set(&test,
            (__mem40 void *) &(mac_lkup_tbl_lock[lock_idx]),
            sizeof(test));

        if ((test & test_msk) == 0)
            break;

        sleep(NS_PLATFORM_TCLK * 100); //100us
    } while (1);
}


__inline void
mac_lkup_tbl_bucket_release(uint32_t table_idx)
{
    uint32_t lock_idx = table_idx >> 5;
    __xwrite uint32_t test = 1 << (table_idx & 31);

    mem_bitclr(&test, (__mem40 void *) &(mac_lkup_tbl_lock[lock_idx]),
        sizeof(test));
}


/**
 * Adds a MAC address and lookup result to the MAC lookup table.
 */
uint8_t
mac_lkup_add(struct mac_addr mac, uint32_t result)
{
    __gpr uint64_t mac_lkup_key;
    __xrw uint32_t entry_xw[4];
    __xrw uint32_t result_xw[4];
    __gpr struct mem_lkup_cam_r_48_64B_table_bucket_dataline1_3 dataline_1_3;
    __gpr struct mem_lkup_cam_r_48_64B_table_bucket_dataline4 dataline4;
    __gpr uint32_t key_lower;
    __gpr uint32_t key_middle;
    __gpr uint32_t key_upper;
    SIGNAL sig1, sig2;

    unsigned int table_idx =
        mac.mac_word[1] &
        (MEM_LKUP_CAM_64B_NUM_ENTRIES(sizeof(mac_lkup_tbl)) - 1);
    uint64_t key_shf = MEM_LKUP_CAM_64B_KEY_OFFSET(0, sizeof(mac_lkup_tbl));

    mac_lkup_tbl_bucket_wait(table_idx);

    mac_lkup_key = mac.mac_dword >> key_shf;

    key_lower = (mac_lkup_key & 0xffff);
    key_middle = (mac_lkup_key >> 16ull) & 0xffff;
    key_upper = (mac_lkup_key >> 32ull) & 0xffff;

   //Try to add to the bucket. Start at entry 0
try0:
    mem_read_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline1),
        sizeof(entry_xw));

    reg_cp(&dataline_1_3.raw[0], entry_xw, sizeof(entry_xw));

    if (dataline_1_3.result0 & MAC_LKUP_USED) {
        //This entry is used, check if the key is the same
        if ((dataline_1_3.lookup_key_lower0 != key_lower) ||
            (dataline_1_3.lookup_key_middle0 != key_middle) ||
            (dataline_1_3.lookup_key_upper0 != key_upper))
            //Key is different, try next entry in bucket.
            goto try1;
    }

    //The entry is not used. OR it is used, but the key is the same. Add it.
    dataline_1_3.lookup_key_lower0 = key_lower;
    dataline_1_3.lookup_key_middle0 = key_middle;
    dataline_1_3.lookup_key_upper0 = key_upper;

    dataline_1_3.result0 = result & 0x3fffffff | MAC_LKUP_USED;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));

    mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline1),
        sizeof(entry_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try1:
    mem_read_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw));

    reg_cp(&dataline4.raw[0], result_xw, sizeof(result_xw));

    if (dataline4.result1 & MAC_LKUP_USED) {
        if ((dataline_1_3.lookup_key_lower1 != key_lower) ||
            (dataline_1_3.lookup_key_middle1 != key_middle) ||
            (dataline_1_3.lookup_key_upper1 != key_upper))
            goto try2;
    }

    dataline_1_3.lookup_key_lower1 = key_lower;
    dataline_1_3.lookup_key_middle1 = key_middle;
    dataline_1_3.lookup_key_upper1 = key_upper;

    dataline4.result1 = result & 0x3fffffff | MAC_LKUP_USED;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));
    reg_cp(result_xw, &dataline4.raw[0], sizeof(result_xw));

    __mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline1),
        sizeof(entry_xw), sizeof(entry_xw), sig_done, &sig1);

    __mem_write_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw), sizeof(result_xw), sig_done, &sig2);

    wait_for_all(&sig1, &sig2);

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try2:
    mem_read_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline2),
        sizeof(entry_xw));

    reg_cp(&dataline_1_3.raw[0], entry_xw, sizeof(entry_xw));

    if (dataline_1_3.result0 & MAC_LKUP_USED) {
        if ((dataline_1_3.lookup_key_lower0 != key_lower) ||
            (dataline_1_3.lookup_key_middle0 != key_middle) ||
            (dataline_1_3.lookup_key_upper0 != key_upper))
            goto try3;
    }

    dataline_1_3.lookup_key_lower0 = key_lower;
    dataline_1_3.lookup_key_middle0 = key_middle;
    dataline_1_3.lookup_key_upper0 = key_upper;

    dataline_1_3.result0 = result & 0x3fffffff | MAC_LKUP_USED;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));

    mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline2),
        sizeof(entry_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try3:
    if (dataline4.result3_upper & (MAC_LKUP_USED >> 16)) {
        if ((dataline_1_3.lookup_key_lower1 != key_lower) ||
            (dataline_1_3.lookup_key_middle1 != key_middle) ||
            (dataline_1_3.lookup_key_upper1 != key_upper))
            goto try4;
    }

    dataline_1_3.lookup_key_lower1 = key_lower;
    dataline_1_3.lookup_key_middle1 = key_middle;
    dataline_1_3.lookup_key_upper1 = key_upper;

    dataline4.result3_lower = result & 0xffff;
    dataline4.result3_upper = (result >> 16 ) & 0x7fff | MAC_LKUP_USED >> 16;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));
    reg_cp(result_xw, &dataline4.raw[0], sizeof(result_xw));

    __mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline2),
        sizeof(entry_xw), sizeof(entry_xw), sig_done, &sig1);

    __mem_write_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw), sizeof(result_xw), sig_done, &sig2);

    wait_for_all(&sig1, &sig2);

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try4:
    mem_read_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline3),
        sizeof(entry_xw));

    reg_cp(&dataline_1_3.raw[0], entry_xw, sizeof(entry_xw));

    if (dataline_1_3.result0 & MAC_LKUP_USED) {
        if ((dataline_1_3.lookup_key_lower0 != key_lower) ||
            (dataline_1_3.lookup_key_middle0 != key_middle) ||
            (dataline_1_3.lookup_key_upper0 != key_upper))
            goto try5;
    }

    dataline_1_3.lookup_key_lower0 = key_lower;
    dataline_1_3.lookup_key_middle0 = key_middle;
    dataline_1_3.lookup_key_upper0 = key_upper;

    dataline_1_3.result0 = result & 0x3fffffff | MAC_LKUP_USED;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));

    mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline3),
        sizeof(entry_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try5:
    if (dataline4.result5 & MAC_LKUP_USED) {
        if ((dataline_1_3.lookup_key_lower1 != key_lower) ||
            (dataline_1_3.lookup_key_middle1 != key_middle) ||
            (dataline_1_3.lookup_key_upper1 != key_upper)) {
            //Cannot add this entry. There is no space in the bucket.
            //Return with failure.
            mac_lkup_tbl_bucket_release(table_idx);
            return 1;
        }
    }

    dataline_1_3.lookup_key_lower1 = key_lower;
    dataline_1_3.lookup_key_middle1 = key_middle;
    dataline_1_3.lookup_key_upper1 = key_upper;

    dataline4.result5 = result & 0x3fffffff | MAC_LKUP_USED;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));
    reg_cp(result_xw, &dataline4.raw[0], sizeof(result_xw));

    __mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline3),
        sizeof(entry_xw), sizeof(entry_xw), sig_done, &sig1);

    __mem_write_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw), sizeof(result_xw), sig_done, &sig2);

    wait_for_all(&sig1, &sig2);

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;
}

/**
 * Deletes a MAC address from the MAC lookup table.
 */
uint8_t
mac_lkup_del(struct mac_addr mac)
{
    __gpr uint64_t mac_lkup_key;
    __xrw uint32_t entry_xw[4];
    __xrw uint32_t result_xw[4];
    __gpr struct mem_lkup_cam_r_48_64B_table_bucket_dataline1_3 dataline_1_3;
    __gpr struct mem_lkup_cam_r_48_64B_table_bucket_dataline4 dataline4;
    __gpr uint32_t key_lower;
    __gpr uint32_t key_middle;
    __gpr uint32_t key_upper;
    SIGNAL sig1, sig2;

    unsigned int table_idx = mac.mac_word[1] &
        (MEM_LKUP_CAM_64B_NUM_ENTRIES(sizeof(mac_lkup_tbl)) - 1);
    uint64_t key_shf = MEM_LKUP_CAM_64B_KEY_OFFSET(0, sizeof(mac_lkup_tbl));

    mac_lkup_tbl_bucket_wait(table_idx);

    mac_lkup_key = mac.mac_dword >> key_shf;

    key_lower = (mac_lkup_key & 0xffff);
    key_middle = (mac_lkup_key >> 16ull) & 0xffff;
    key_upper = (mac_lkup_key >> 32ull) & 0xffff;

try0:
    mem_read_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline1),
        sizeof(entry_xw));

    reg_cp(&dataline_1_3.raw[0], entry_xw, sizeof(entry_xw));

    //Check if this key is in entry 0. If it is, "delete" it by setting
    //the result field to 0. If it is not, try entry 1 and so on.
    if ((dataline_1_3.result0 & MAC_LKUP_USED) &&
        (dataline_1_3.lookup_key_lower0 == key_lower) &&
        (dataline_1_3.lookup_key_middle0 == key_middle) &&
        (dataline_1_3.lookup_key_upper0 == key_upper))

        dataline_1_3.result0 = 0;
    else
        goto try1;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));

    mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline1),
        sizeof(entry_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try1:
    mem_read_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw));

    reg_cp(&dataline4.raw[0], result_xw, sizeof(result_xw));

    if ((dataline4.result1 & MAC_LKUP_USED) &&
        (dataline_1_3.lookup_key_lower1 == key_lower) &&
        (dataline_1_3.lookup_key_middle1 == key_middle) &&
        (dataline_1_3.lookup_key_upper1 == key_upper))

        dataline4.result1 = 0;
    else
        goto try2;

    reg_cp(result_xw, &dataline4.raw[0], sizeof(result_xw));

    mem_write_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try2:
    mem_read_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline2),
        sizeof(entry_xw));

    reg_cp(&dataline_1_3.raw[0], entry_xw, sizeof(entry_xw));

    if ((dataline_1_3.result0 & MAC_LKUP_USED) &&
        (dataline_1_3.lookup_key_lower0 == key_lower) &&
        (dataline_1_3.lookup_key_middle0 == key_middle) &&
        (dataline_1_3.lookup_key_upper0 == key_upper))

        dataline_1_3.result0 = 0;
    else
        goto try3;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));

    mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline2),
        sizeof(entry_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try3:
    if (dataline4.result3_upper & (MAC_LKUP_USED >> 16) &&
        (dataline_1_3.lookup_key_lower1 == key_lower) &&
        (dataline_1_3.lookup_key_middle1 == key_middle) &&
        (dataline_1_3.lookup_key_upper1 == key_upper)) {

        dataline4.result3_lower = 0;
        dataline4.result3_upper = 0;
    } else
        goto try4;

    reg_cp(result_xw, &dataline4.raw[0], sizeof(result_xw));

    mem_write_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try4:
    mem_read_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline3),
        sizeof(entry_xw));

    reg_cp(&dataline_1_3.raw[0], entry_xw, sizeof(entry_xw));

    if ((dataline_1_3.result0 & MAC_LKUP_USED) &&
        (dataline_1_3.lookup_key_lower0 == key_lower) &&
        (dataline_1_3.lookup_key_middle0 == key_middle) &&
        (dataline_1_3.lookup_key_upper0 == key_upper))

        dataline_1_3.result0 = 0;
    else
        goto try5;

    reg_cp(entry_xw, &dataline_1_3.raw[0], sizeof(entry_xw));

    mem_write_atomic(entry_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline3),
        sizeof(entry_xw));

    mac_lkup_tbl_bucket_release(table_idx);
    return 0;

try5:
    if ((dataline4.result5 & MAC_LKUP_USED) &&
        (dataline_1_3.lookup_key_lower1 == key_lower) &&
        (dataline_1_3.lookup_key_middle1 == key_middle) &&
        (dataline_1_3.lookup_key_upper1 == key_upper))

        dataline4.result5 = 0;
    else {
        //The entry wasn't found in the bucket. Return error.
        mac_lkup_tbl_bucket_release(table_idx);
        return 1;
    }

    reg_cp(result_xw, &dataline4.raw[0], sizeof(result_xw));

    mem_write_atomic(result_xw,
        (__mem40 void *) &(mac_lkup_tbl[table_idx].dataline4),
        sizeof(result_xw));

    mac_lkup_tbl_bucket_release(table_idx);

    return 0;
}

