/*
 * Copyright 2016 Netronome, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @file   lib/npfw/catamaran_app_utils.h
 * @brief  Application-specific ME-based tool for configuring Catamaran NPFW
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
