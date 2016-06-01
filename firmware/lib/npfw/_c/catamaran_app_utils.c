/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file   lib/npfw/_c/catamaran_app_utils.c
 * @brief  Application-specific ME-based tool for configuring Catamaran NPFW
 */


#include <platform.h>

#include <npfw/catamaran_app_utils.h>
#include <npfw/catamaran_utils.h>

/** Maximum number of channels per port. */
#ifndef MAX_CHANNELS_PER_PORT
#define MAX_CHANNELS_PER_PORT 8
#endif

__intrinsic void
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
