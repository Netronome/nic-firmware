/*
 * Copyright 2016 Netronome Systems, Inc. All rights reserved.
 *
 * @file   lib/npfw/catamaran_utils.h
 * @brief  ME-based interface for configuring Catamaran NPFW
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _CATAMARAN_UTILS_H_
#define _CATAMARAN_UTILS_H_

#include <nfp.h>
#include <stdint.h>

#include <ppc_api/catamaran_defs.h>


/**
 * Catamaran channel-to-port table entry result.
 */
struct catamaran_chan2port_entry {
    uint8_t port;      /** Port number. */
    uint8_t port_mode; /** Port mode of operation. */
};


/* Catamaran configuration support API. */

/**
 * Initializes support structures and CLS hash for configuring Catamaran.
 *
 * @param nbi  NBI island to read the Catamaran configuration from (0/1)
 */
void catamaran_support_setup(unsigned int nbi);


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
void catamaran_chan2port_table_get(
         unsigned int nbi, unsigned int chan_start, unsigned int chan_end,
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
void catamaran_chan2port_table_set(
         unsigned int nbi, unsigned int chan_start, unsigned int chan_end,
         __lmem struct catamaran_chan2port_entry *entries);


/* Catamaran MAC matching table configuration API. */

/**
 * Adds a Catamaran MAC match table entry.
 *
 * @param nbi           NBI island to configure (0/1)
 * @param mac_addr      MAC address of the entry to add
 * @param result        The MAC match entry result to add (1-65535)
 * @param cls_hash_idx  CLS hash index to use (0-7)
 * @return              0 if entry is available, -1 if entry is unavailable
 */
int catamaran_mac_match_table_add(unsigned int nbi, uint64_t mac_addr,
                                  uint16_t result, unsigned int cls_hash_idx);

/**
 * Looks up and retrieves Catamaran MAC match table entry.
 *
 * @param nbi           NBI island to read from (0/1)
 * @param mac_addr      MAC address to look up
 * @param entry         Local memory location to transfer the MAC match
 *                      information to, if found
 * @param cls_hash_idx  CLS hash index to use (0-7)
 * @return              The MAC match entry result (1-65535), or -1 if entry is
 *                      not found
 */
int catamaran_mac_match_table_get(unsigned int nbi, uint64_t mac_addr,
                                  unsigned int cls_hash_idx);

/**
 * Removes a Catamaran MAC match table entry.
 *
 * @param nbi           NBI island to configure (0/1)
 * @param mac_addr      MAC address of the entry to remove
 * @param cls_hash_idx  CLS hash index to use (0-7)
 * @return              0 if entry is found, -1 if entry is not found
 */
int catamaran_mac_match_table_remove(unsigned int nbi, uint64_t mac_addr,
                                     unsigned int cls_hash_idx);


#endif /* ndef _CATAMARAN_UTILS_H_ */
