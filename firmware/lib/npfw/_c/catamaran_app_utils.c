/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file   lib/npfw/_c/catamaran_app_utils.c
 * @brief  Application-specific ME-based tool for configuring Catamaran NPFW
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include <platform.h>

#include <npfw/catamaran_app_utils.h>
#include <npfw/catamaran_utils.h>

/** Maximum number of channels per port. */
#ifndef MAX_CHANNELS_PER_PORT
#define MAX_CHANNELS_PER_PORT 8
#endif


/** Type for keeping track of configured MAC addresses. */
typedef struct {
    uint64_t mac_addr;   /** MAC address. */
    uint8_t  port_mask0; /** Port mask for NBI 0. */
    uint8_t  port_mask1; /** Port mask for NBI 1. */
} mac_match_info_t;

/** Internal data structure for keeping track of configured MAC addresses. */
__lmem __shared static mac_match_info_t curr_mac_addr[NS_PLATFORM_NUM_PORTS];


static __inline void
generate_mac_match_info(uint8_t port_en_mask, __lmem mac_match_info_t *info,
                        __lmem uint64_t *mac_addrs)
{
    unsigned int i;
    unsigned int port;

    /* Populate the information for each port. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        /* Check if the port is enabled. */
        if (port_en_mask & (1 << port)) {
            info[port].mac_addr = mac_addrs[port];

            if (port < NS_PLATFORM_NUM_PORTS_PER_MAC_0) {
                info[port].port_mask0 = 1 << port;
                info[port].port_mask1 = 0;
            } else {
                info[port].port_mask0 = 0;
                info[port].port_mask1 = 1 << port;
            }

            /* Update all port masks. */
            for (i = 0; i < port; ++i) {
                if (info[i].mac_addr == info[port].mac_addr) {
                    info[i].port_mask0    |= info[port].port_mask0;
                    info[i].port_mask1    |= info[port].port_mask1;
                    info[port].port_mask0  = info[i].port_mask0;
                    info[port].port_mask1  = info[i].port_mask1;
                }
            }
        } else {
            info[port].mac_addr   = 0;
            info[port].port_mask0 = 0;
            info[port].port_mask1 = 0;
        }
    }
}


static __inline int
mac_match_table_update(__lmem mac_match_info_t *old_info,
                       __lmem mac_match_info_t *new_info,
                       unsigned int cls_hash_idx)
{
    int found;
    unsigned int i;
    unsigned int port;
    __gpr uint64_t mac_addr;
    __gpr uint8_t port_mask0;
    __gpr uint8_t port_mask1;
    int err_code = 0;

    /* Add/update port entries. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        /* Check if anything to add/update. */
        port_mask0 = new_info[port].port_mask0;
        port_mask1 = new_info[port].port_mask1;

        if (!port_mask0 && !port_mask1)
            continue;

        /* Check if already updated. */
        mac_addr = new_info[port].mac_addr;
        found    = 0;

        for (i = 0; i < port; ++i) {
            if (mac_addr == new_info[i].mac_addr) {
                found = 1;
                break;
            }
        }

        if (found)
            continue;

        /* Check if updating a pre-existing entry. */
        for (i = 0; i < NS_PLATFORM_NUM_PORTS; ++i) {
            if (mac_addr == old_info[i].mac_addr) {
                /* Add/update entry in each NBI if anything changed. */
                if (port_mask0 && (port_mask0 != old_info[i].port_mask0))
                    err_code |= catamaran_mac_match_table_add(0, mac_addr,
                                                              port_mask0 << 8,
                                                              cls_hash_idx);

                if (port_mask1 && (port_mask1 != old_info[i].port_mask1))
                    err_code |= catamaran_mac_match_table_add(1, mac_addr,
                                                              port_mask1 << 8,
                                                              cls_hash_idx);

                /* Remove existing entry in each NBI if anything changed. */
                if (!port_mask0 && (port_mask0 != old_info[i].port_mask0))
                    catamaran_mac_match_table_remove(0, mac_addr,
                                                     cls_hash_idx);

                if (!port_mask1 && (port_mask1 != old_info[i].port_mask1))
                    catamaran_mac_match_table_remove(1, mac_addr,
                                                     cls_hash_idx);

                /* Mark as updated pre-existing entry. */
                found = 1;
                break;
            }
        }

        /* Add entry if not pre-existing. */
        if (!found) {
            /* Add any new entry to each NBI. */
            if (port_mask0)
                err_code |= catamaran_mac_match_table_add(0, mac_addr,
                                                          port_mask0 << 8,
                                                          cls_hash_idx);

            if (port_mask1)
                err_code |= catamaran_mac_match_table_add(1, mac_addr,
                                                          port_mask1 << 8,
                                                          cls_hash_idx);
        }
    }

    /* Remove unused port entries. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        /* Check if anything to add/update. */
        port_mask0 = old_info[port].port_mask0;
        port_mask1 = old_info[port].port_mask1;

        if (!port_mask0 && !port_mask1)
            continue;

        /* Check if already updated. */
        mac_addr = old_info[port].mac_addr;
        found    = 0;

        for (i = 0; i < port; ++i) {
            if (mac_addr == old_info[i].mac_addr) {
                found = 1;
                break;
            }
        }

        if (found)
            continue;

        /* Check if a current entry. */
        for (i = 0; i < NS_PLATFORM_NUM_PORTS; ++i) {
            if (mac_addr == new_info[i].mac_addr) {
                /* No need to update current entry. */
                found = 1;
                break;
            }
        }

        if (found)
            continue;

        /* Remove unused entry in each NBI. */
        if (port_mask0)
            catamaran_mac_match_table_remove(0, mac_addr, cls_hash_idx);

        if (port_mask1)
            catamaran_mac_match_table_remove(1, mac_addr, cls_hash_idx);
    }

    return err_code;
}


void
init_catamaran_chan2port_table(void)
{
    unsigned int chan;
    unsigned int entry_cnt;
    unsigned int port;
    __lmem struct catamaran_chan2port_entry entries[MAX_CHANNELS_PER_PORT];

    /* Set the configuration for each port. */
    for (port = 0; port < NS_PLATFORM_NUM_PORTS; ++port) {
        /* Set the configuration for each channel assigned to the port. */
        entry_cnt = 0;

        for (chan = NS_PLATFORM_MAC_CHANNEL_LO(port);
             chan <= NS_PLATFORM_MAC_CHANNEL_HI(port);
             ++chan) {
            entries[entry_cnt].port      = port;
            entries[entry_cnt].port_mode = CATAMARAN_CHAN_MODE_MAC_DA_MATCH;
            ++entry_cnt;
        }

        /* Commit the configuration for the port. */
        catamaran_chan2port_table_set(NS_PLATFORM_MAC_CORE(port),
                                      NS_PLATFORM_MAC_CHANNEL_LO(port),
                                      NS_PLATFORM_MAC_CHANNEL_HI(port),
                                      entries);
    }
}


int
update_catamaran_mac_match_table(uint8_t port_en_mask,
                                 __lmem uint64_t *mac_addrs,
                                 unsigned int cls_hash_idx)
{
    int err_code;
    unsigned int i;
    __lmem mac_match_info_t temp_mac_addr[NS_PLATFORM_NUM_PORTS];

    /* Determine the new MAC address information for all ports. */
    generate_mac_match_info(port_en_mask, temp_mac_addr, mac_addrs);

    /* Update the MAC match tables w/ the new information. */
    err_code = mac_match_table_update(curr_mac_addr, temp_mac_addr,
                                      cls_hash_idx);

    /* Store the new MAC address information. */
    for (i = 0; i < NS_PLATFORM_NUM_PORTS; ++i) {
        curr_mac_addr[i].mac_addr   = temp_mac_addr[i].mac_addr;
        curr_mac_addr[i].port_mask0 = temp_mac_addr[i].port_mask0;
        curr_mac_addr[i].port_mask1 = temp_mac_addr[i].port_mask1;
    }

    return err_code;
}
