/**
 * Copyright (C) 2015-2017,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          link_state.c
 * @brief         Code for checking the Ethernet link status
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include <assert.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_mac.h>

#include <link_state/link_state.h>


__intrinsic void
mac_eth_all_link_state(__lmem uint32_t eth_port_mask[],
                       __lmem uint32_t link_state_mask[],
                       __lmem uint32_t is_1ge_mask[],
                       unsigned int num_mac_islands)
{
    unsigned int mac_isl;

    /* Check the parameters */
    assert(num_mac_islands <= MAX_MAC_ISLANDS_PER_NFP);

    /* check the link status for each MAC island */
    for (mac_isl = 0; mac_isl < num_mac_islands; ++mac_isl) {
        link_state_mask[mac_isl] =
            mac_eth_island_link_state(mac_isl, eth_port_mask[mac_isl],
                                      is_1ge_mask[mac_isl]);
    }
}


__intrinsic uint32_t
mac_eth_island_link_state(unsigned int mac_isl, uint32_t eth_port_mask,
                          uint32_t is_1ge_mask)
{
    unsigned int link;
    unsigned int is_1ge;
    uint32_t link_state_mask = 0x0;

    /* Check the parameters */
    assert(mac_isl < MAX_MAC_ISLANDS_PER_NFP);

    /* Check the link state of all of the specified ports */
    for (link = 0; link < MAX_ETH_PORTS_PER_MAC_ISL; ++link) {
        if (eth_port_mask & (1 << link)) {
            /* Check the current link state */
            is_1ge = (is_1ge_mask >> link) & 0x1;

            if (mac_eth_port_link_state(mac_isl, link, is_1ge) == LINK_UP) {
                link_state_mask |= 0x1 << link;
            }
        }
    }

    return link_state_mask;
}


__intrinsic enum link_state
mac_eth_port_link_state(unsigned int mac_isl, unsigned int eth_port,
                        unsigned int is_1ge)
{
    uint32_t eth_status;
    uint32_t pcs_status;
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
    eth_status = (xpb_read(NFP_MAC_XPB_OFF(mac_isl)
                           | NFP_MAC_ETH(mac_core)
                           | NFP_MAC_ETH_SEG_STS(mac_core_port))
                  & (NFP_MAC_ETH_SEG_STS_PHY_LOS
                     | NFP_MAC_ETH_SEG_STS_RX_REMOTE_FAULT
                     | NFP_MAC_ETH_SEG_STS_RX_LOCAL_FAULT));

    if (is_1ge) {
        pcs_status = (xpb_read(NFP_MAC_XPB_OFF(mac_isl)
                               | NFP_MAC_ETH(mac_core)
                               | NFP_MAC_ETH_SEG_SGMII_PCS_STS(mac_core_port))
                      & NFP_MAC_ETH_SEG_SGMII_PCS_STS_LINK_STS);
    } else {
        pcs_status = (xpb_read(NFP_MAC_XPB_OFF(mac_isl)
                               | NFP_MAC_ETH(mac_core)
                               | NFP_MAC_ETH_CHAN_PCS_SEG(mac_core_port)
                               | NFP_MAC_ETH_CHAN_PCS_STS1)
                      & NFP_MAC_ETH_CHAN_PCS_STS1_ETH_PCS_RCV_LINK_STS);
    }

    if (!eth_status && pcs_status) {
        link_state = LINK_UP;
    }

    return link_state;
}
