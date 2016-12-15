/**
 * Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
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
 * @file          link_state.c
 * @brief         Code for checking the Ethernet link status
 */


#include <assert.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_mac.h>

#include <link_state/link_state.h>


__intrinsic void
mac_eth_all_link_state(__lmem uint32_t eth_port_mask[],
                       __lmem uint32_t link_state_mask[],
                       unsigned int num_mac_islands)
{
    unsigned int mac_isl;

    /* Check the parameters */
    assert(num_mac_islands <= MAX_MAC_ISLANDS_PER_NFP);

    /* check the link status for each MAC island */
    for (mac_isl = 0; mac_isl < num_mac_islands; ++mac_isl) {
        link_state_mask[mac_isl] =
            mac_eth_island_link_state(mac_isl, eth_port_mask[mac_isl]);
    }
}


__intrinsic uint32_t
mac_eth_island_link_state(unsigned int mac_isl, uint32_t eth_port_mask)
{
    unsigned int link;
    uint32_t link_state_mask = 0x0;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);

    /* Check the link state of all of the specified ports */
    for (link = 0; link < MAX_ETH_PORTS_PER_MAC_ISL; ++link) {
        if (eth_port_mask & (1 << link)) {
            /* Check the current link state */
            if (mac_eth_port_link_state(mac_isl, link) == LINK_UP) {
                link_state_mask |= 0x1 << link;
            }
        }
    }

    return link_state_mask;
}


__intrinsic enum link_state
mac_eth_port_link_state(unsigned int mac_isl, unsigned int eth_port)
{
    uint32_t eth_status;
    unsigned int mac_core;
    unsigned int mac_core_port;
    enum link_state link_state = LINK_DOWN;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);
    assert(eth_port < MAX_ETH_PORTS_PER_MAC_ISL);

    /* Determine the MAC core and the port on the MAC core */
    mac_core      = ETH_PORT_TO_MAC_CORE(eth_port);
    mac_core_port = ETH_PORT_TO_MAC_CORE_PORT(eth_port);

    /* Check the status of the link */
    eth_status = xpb_read(NFP_MAC_XPB_OFF(mac_isl)
                          | NFP_MAC_ETH(mac_core)
                          | NFP_MAC_ETH_SEG_STS(mac_core_port));

    if (!(eth_status
          & (NFP_MAC_ETH_SEG_STS_PHY_LOS
             | NFP_MAC_ETH_SEG_STS_RX_REMOTE_FAULT
             | NFP_MAC_ETH_SEG_STS_RX_LOCAL_FAULT))) {
        link_state = LINK_UP;
    }

    return link_state;
}
