/*
 * Copyright 2018-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_lkup.h
 * @brief         Header file for MAC lookup functions
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _APP_MAC_LOOKUP_H_
#define _APP_MAC_LOOKUP_H_

#define MAC_LKUP_IN_USE_bit     (30)
#define MAC_LKUP_USED           (1 << MAC_LKUP_IN_USE_bit)
#define MAC_LKUP_BUCKET_SZ      64
#define MAC_LKUP_NUM_BUCKETS    (1 << 10)
#define MAC_LKUP_TABLE_SZ       (MAC_LKUP_NUM_BUCKETS * MAC_LKUP_BUCKET_SZ)

#if defined(__NFP_LANG_MICROC)
struct mac_addr {
    union {
        struct {
            uint8_t __unused[2];
            uint8_t mac_byte[6];
        };
        struct {
            uint32_t mac_word[2];
        };
        uint64_t mac_dword;
    };
};


/**
 * Add a MAC address to the MAC lookup table.
 *
 * @param mac           MAC address to add.
 * @param result        The result that future CAMR operations must return
 * @return              0 on success. 1 if no space can be found in the table.
 *
 * Bits 29..0 of the result are user definable. Multiple additions with the
 * same MAC is allowed. If the MAC is already in the table, the lookup result
 * value will be overwritten.
 */
uint8_t
mac_lkup_add(struct mac_addr mac, uint32_t result);


/**
 * Delete a MAC address to the MAC lookup table.
 *
 * @param mac           MAC address to delete
 * @return              0 on success. 1 if entry to delete is not found.
 *
 */
uint8_t
mac_lkup_del(struct mac_addr mac);

#endif
#endif /* _APP_MAC_LOOKUP_H_ */
