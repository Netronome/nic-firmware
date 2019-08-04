/**
 * Copyright (C) 2015-2017,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          link_state.h
 * @brief         Code for checking the Ethernet link state.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#ifndef _LINK_STATE_H_
#define _LINK_STATE_H_


#include <nfp.h>
#include <stdint.h>


/* Maximum Ethernet ports per MAC core and MAC island */
#define MAX_ETH_PORTS_PER_MAC_CORE 12
#define MAX_MAC_CORES_PER_MAC_ISL  2
#define MAX_ETH_PORTS_PER_MAC_ISL                            \
    (MAX_ETH_PORTS_PER_MAC_CORE * MAX_MAC_CORES_PER_MAC_ISL)

/* Maximum number of MAC islands supported on the NFP */
#define MAX_MAC_ISLANDS_PER_NFP    2

/** Macro function to determine the MAC core number for the port */
#define ETH_PORT_TO_MAC_CORE(_p)      (_p < MAX_ETH_PORTS_PER_MAC_CORE ? 0 : 1)
#define ETH_PORT_TO_MAC_CORE_PORT(_p)           \
    (_p % (unsigned)MAX_ETH_PORTS_PER_MAC_CORE)


/** Type to enumerate the state of a link */
enum link_state {
    LINK_DOWN = 0,
    LINK_UP   = 1
};


/**
 * Check the link states of the specified ports for each MAC island
 *
 * @param eth_port_mask    Bit mask to specify ports to check for each MAC
 * @param link_state_mask  Bit mask array to hold the link state for each MAC
 * @param num_mac_islands  Number of MAC islands to check
 * @param is_1ge_mask      Bit mask array of which ports are 1 GE
 */
__intrinsic void mac_eth_all_link_state(__lmem uint32_t eth_port_mask[],
                                        __lmem uint32_t link_state_mask[],
                                        __lmem uint32_t is_1ge_mask[],
                                        unsigned int num_mac_islands);


/**
 * Check the link states of the specified ports on a MAC island
 *
 * @param mac_isl        The MAC island to check
 * @param eth_port_mask  The bit mask for each port on the MAC island to check
 * @param is_1ge_mask    The bit mask of which ports are 1 GE
 *
 * @return - The link state of the specified ports on the island
 *
 * @note 'mac_isl' range is from 0 to (MAX_MAC_ISLANDS_PER_NFP - 1)
 */
__intrinsic uint32_t mac_eth_island_link_state(unsigned int mac_isl,
                                               uint32_t eth_port_mask,
                                               uint32_t is_1ge_mask);

/**
 * Check the link state of the specified port on the MAC island
 *
 * @param mac_isl   The MAC island to check
 * @param eth_port  The port on the MAC island
 * @param is_1ge    Indicates whether the port is 1 GE (1 = 1 GE, 0 = not 1 GE)
 *
 * @return - The link state of the specified port
 *
 * @note 'mac_isl' range is from 0 to (MAX_MAC_ISLANDS_PER_NFP - 1)
 * @note 'eth_port' range is from 0 to (MAX_ETH_PORTS_PER_MAC_ISL - 1)
 */
__intrinsic enum link_state mac_eth_port_link_state(unsigned int mac_isl,
                                                    unsigned int eth_port,
                                                    unsigned int is_1ge);


#endif /* _LINK_STATE_H_ */
