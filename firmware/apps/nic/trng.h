/*
 * Copyright (C) 2015-2017 Netronome Systems, Inc. All rights reserved.
 *
 * @file          apps/nic/trng.h
 * @brief         Header file for trng.c
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

 #ifndef __TRNG_H__
 #define __TRNG_H__

 // TRNG defines

 // addresses
 #define TRNG_ASYNC_RING           0x00
 #define TRNG_ASYNC_TEST           0x04
 #define TRNG_ASYNC_CMD            0x08
 #define TRNG_ASYNC_STATUS         0x0C
 #define TRNG_ASYNC_CFG            0x10
 #define TRNG_LFSR_CFG             0x20
 #define TRNG_WHITEN_CONTROL       0x24
 #define TRNG_WHITEN_CONFIG        0x28
 #define TRNG_MON_PERIOD           0x30
 #define TRNG_MON_ONES             0x34
 #define TRNG_MON_ONES_MIN         0x38
 #define TRNG_MON_ONES_MAX         0x3c
 #define TRNG_MON_MAX_RUN_LEN      0x40
 #define TRNG_LOCK                 0x50
 #define TRNG_ALERT                0x54

 #define CLS_TRNG_XPB_DEVICE_ID      12
 #define TH_TRNG_data                 0

 #define CLS_PERIPHERAL_TRNG_DATA      0x60000
 #define CLS_PERIPHERAL_TRNG_DATA_ALT  0x60001

__intrinsic void trng_init();

__intrinsic void trng_init_add_delay(const int delay_count);

__intrinsic void trng_rd64(uint32_t *trng_hi, uint32_t *trng_lo);

#endif // __TRNG_H__
