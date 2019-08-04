/*
 * Copyright 2016 Netronome Systems, Inc. All rights reserved.
 *
 * @file   lib/npfw/catamaran_app_utils.h
 * @brief  Application-specific ME-based tool for configuring Catamaran NPFW
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _CATAMARAN_APP_UTILS_H_
#define _CATAMARAN_APP_UTILS_H_

#include <nfp.h>
#include <stdint.h>


/** Initializes Catamaran channel-to-port table. */
void init_catamaran_chan2port_table(void);


/**
 * Populates/updates Catamaran MAC matching table.
 *
 * @param port_en_mask  Mask of enabled ports
 * @param mac_addrs     List of MAC addresses for each port, must point to data
 *                      structure containing the information for all ports
 * @param cls_hash_idx  CLS hash index to use (0-7)
 * @return              0 if no errors, -1 if error populating the table
 */
int update_catamaran_mac_match_table(uint8_t port_en_mask,
                                                 __lmem uint64_t *mac_addrs,
                                                 unsigned int cls_hash_idx);


#endif /* ndef _CATAMARAN_APP_UTILS_H_ */
