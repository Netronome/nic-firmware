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
 * @file   lib/npfw/catamaran_utils.h
 * @brief  ME-based interface for configuring Catamaran NPFW
 */

#ifndef _CATAMARAN_UTILS_H_
#define _CATAMARAN_UTILS_H_

#include <nfp.h>
#include <ppc_api/catamaran_defs.h>


/**
 * Catamaran channel-to-port table entry type.
 */
struct catamaran_chan2port_entry {
    unsigned int port;      /** Port number */
    unsigned int port_mode; /** Port mode of operation */
};


/* Catamaran channel-to-port table configuration API. */

/**
 * Retrieves Catamaran channel-to-port table entries.
 *
 * @param nbi         NBI island to read from (0/1)
 * @param chan_start  First channel to retrieve
 * @param chan_end    Last channel to retrieve
 * @param entries     Local memory location to transfer the channel-to-port
 *                    information to, must point to data structure large enough
 *                    to hold the information for all of the specified channels
 */
__intrinsic void catamaran_chan2port_table_get(
                     unsigned int nbi, unsigned int chan_start,
                     unsigned int chan_end,
                     __lmem struct catamaran_chan2port_entry *entries);

/**
 * Configures Catamaran channel-to-port table entries.
 *
 * @param nbi         NBI island to configure (0/1)
 * @param chan_start  First channel to configure
 * @param chan_end    Last channel to configure
 * @param entries     Local memory location to transfer the channel-to-port
 *                    information from, must point to data structure containing
 *                    the information for all of the specified channels
 */
__intrinsic void catamaran_chan2port_table_set(
                     unsigned int nbi, unsigned int chan_start,
                     unsigned int chan_end,
                     __lmem struct catamaran_chan2port_entry *entries);


#endif /* ndef _CATAMARAN_UTILS_H_ */
