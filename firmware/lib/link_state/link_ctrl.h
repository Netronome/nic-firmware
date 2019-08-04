/**
 * Copyright (C) 2016-2017,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          link_ctrl.h
 * @brief         Code for configuring the Ethernet link.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#ifndef _LINK_CTRL_H_
#define _LINK_CTRL_H_


#include <nfp.h>
#include <stdint.h>


/* *** MAC CSR Sync ME Functions *** */

/**
 * Notify MAC CSR sync ME to recache MAC CSR state.
 *
 * @param mac_isl        MAC island to query
 * @param mac_core       MAC core to query
 * @param mac_core_port  MAC core port to check
 */
__intrinsic void mac_csr_sync_recache(unsigned int mac_isl,
                                      unsigned int mac_core,
                                      unsigned int mac_core_port);

/**
 * Start MAC CSR sync ME.
 *
 * @param disable_gpio_poll  Disables polling of the GPIO
 *
 * @note Polling of the GPIO should only be enabled for Carbon 2x25G
 */
__intrinsic void mac_csr_sync_start(uint32_t disable_gpio_poll);


/* *** MAC RX Enable/Disable Functions *** */

/**
 * Check if the MAC RX is enabled for a given port.
 *
 * @param mac_isl        MAC island to query
 * @param mac_core       MAC core to query
 * @param mac_core_port  MAC core port to check
 *
 * @return 0 = disabled, 1 = enabled
 */
__intrinsic int mac_eth_check_rx_enable(unsigned int mac_isl,
                                        unsigned int mac_core,
                                        unsigned int mac_core_port);

/**
 * Disable the MAC RX for a given port.
 *
 * @param mac_isl        MAC island to configure
 * @param mac_core       MAC core to configure
 * @param mac_core_port  MAC core port to disable
 * @param num_lanes      Number of lanes associated with the port
 *
 * @note This function is not safe for multi-threaded use.
 */
__intrinsic int mac_eth_disable_rx(unsigned int mac_isl,
                                    unsigned int mac_core,
                                    unsigned int mac_core_port,
                                    unsigned int num_lanes);

/**
 * Enable the MAC RX for a given port.
 *
 * @param mac_isl        MAC island to configure
 * @param mac_core       MAC core to configure
 * @param mac_core_port  MAC core port to enable
 *
 * @note This function is not safe for multi-threaded use.
 */
__intrinsic void mac_eth_enable_rx(unsigned int mac_isl, unsigned int mac_core,
                                   unsigned int mac_core_port);


/* *** MAC TX Flush Enable/Disable Functions *** */

/**
 * Check if the MAC TX flush is enabled for a given port.
 *
 * @param mac_isl        MAC island to query
 * @param mac_core       MAC core to query
 * @param mac_core_port  MAC core port to check
 *
 * @return 0 = disabled, 1 = enabled
 */
__intrinsic int mac_eth_check_tx_flush_enable(unsigned int mac_isl,
                                              unsigned int mac_core,
                                              unsigned int mac_core_port);

/**
 * Disable the MAC TX flush for a given port.
 *
 * @param mac_isl        MAC island to configure
 * @param mac_core       MAC core to configure
 * @param mac_core_port  MAC core port to disable TX flush
 *
 * @note This function is not safe for multi-threaded use.
 */
__intrinsic void mac_eth_disable_tx_flush(unsigned int mac_isl,
                                          unsigned int mac_core,
                                          unsigned int mac_core_port);

/**
 * Enable the MAC TX flush for a given port.
 *
 * @param mac_isl        MAC island to configure
 * @param mac_core       MAC core to configure
 * @param mac_core_port  MAC core port to enable TX flush
 *
 * @note This function is not safe for multi-threaded use.
 */
__intrinsic void mac_eth_enable_tx_flush(unsigned int mac_isl,
                                         unsigned int mac_core,
                                         unsigned int mac_core_port);


/* *** NBI TM Queue Enable/Disable Functions *** */

/**
 * Disable the NBI TM queue.
 *
 * @param nbi_isl  NBI island to configure
 * @param tm_q     NBI TM queue to disable
 *
 * @note This function is not safe for multi-threaded use.
 */
__intrinsic void nbi_tm_disable_queue(unsigned int nbi_isl, unsigned int tm_q);

/**
 * Enable the NBI TM queue.
 *
 * @param nbi_isl  NBI island to configure
 * @param tm_q     NBI TM queue to enable
 *
 * @note This function is not safe for multi-threaded use.
 */
__intrinsic void nbi_tm_enable_queue(unsigned int nbi_isl, unsigned int tm_q);


#endif /* _LINK_CTRL_H_ */
