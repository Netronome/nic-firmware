/*
 * Copyright 2014-2015 Netronome Systems, Inc. All rights reserved.
 *
 * @file          lib/nic_basic/nic_basic.h
 * @brief         ME level interface to the NIC library code
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _NIC_BASIC_H_
#define _NIC_BASIC_H_

#include <nfp.h>
#include <stdint.h>

#include <infra_basic/infra_basic.h>

#include "nic_ctrl.h"

/*
 * The PCI.IN and PCI.OUT blocks just handle transfer of descriptors
 * and packet buffers.  The application code has to perform some
 * operations to make the NFP operate as just a NIC.  This library
 * implements these operations.
 *
 * The configuration mechanism must be initialised by each ME
 * requiring notification using @nic_local_init().  When the NIC is
 * being re-configured by the host, the signal @nic_app_sig will be
 * asserted (on context 0) and the application code is then expected
 * to call @nic_local_reconfig().
 */

/*
 * This library currently only supports a single endpoint
 */


/**
 * Signal used during re-configuration
 */
__export extern SIGNAL nic_app_sig;


/**
 * Initialise the (application) local nic state
 *
 * Configure the application signal and write register.
 */
__intrinsic void nic_local_init(int sig_num, int reg_num);


/**
 * Check if a configuration change has been signaled.
 */
__intrinsic int nic_local_cfg_changed();


/**
 * Handle reconfiguration requests
 *
 * This function must be called by the application when nic_app_sig
 * has been asserted.  It updates the local state.
 *
 * @param enable_changed    Set if global enable changed, clear if not
 */
__intrinsic void nic_local_reconfig(uint32_t *enable_changed);

/**
 * Acknowledge that we have received and processed the reconfig request
 */
__intrinsic void nic_local_reconfig_done();


/*
 * Statistics and counter functions.
 */

/**
 * Update the statistic counters in the Control BAR
 *
 * The statistics counters in the control BAR need periodic updates.
 * They need to be gathered from a number of places, like the MAC or
 * the TM as well as pure software counters.
 *
 * This function must be called by a single context by the application
 * code and does not return.  It executes a endless loop to keep the
 * stats up-to-date.
 */
void nic_stats_loop();

/**
 * Maintain some additional counters for received/transmitted frames
 *
 * @param port          Port (physical network interface)
 * @param da            Pointer to the destination MAC address
 * @param frame_len     Length of the received frame
 *
 * The MAC does not maintain BC/MC byte counts, so we maintain them in
 * software.
 */
__intrinsic void nic_rx_cntrs(int port, void *da, int frame_len);
__intrinsic void nic_tx_cntrs(int port, void *da, int frame_len);

/**
 * Update the per RX ring packet and byte counters
 *
 * @param meta          Pointer to buffer/packet meta data
 * @param len           Frame length
 * @param port          Input port (physical network interface)
 * @param qid           The queue to increment
 */
__intrinsic void nic_rx_ring_cntrs(void *meta, uint16_t len,
                                   uint32_t port, uint32_t qid);

/**
 * Update the per TX ring packet and byte counters
 *
 * @param meta          Pointer to buffer/packet meta data
 * @param port          Output port (physical network interface)
 * @param qid           The queue to increment
 */
__intrinsic void nic_tx_ring_cntrs(void *meta, uint32_t port, uint32_t qid);

/**
 * Increment the RX/TX error and discard counters
 */
__intrinsic void nic_rx_error_cntr(int port);
__intrinsic void nic_tx_error_cntr(int port);
__intrinsic void nic_rx_discard_cntr(int port);
__intrinsic void nic_tx_discard_cntr(int port);


/**
 * General macros:
 *
 * Results from RX checks:
 * @NIC_RX_OK           Checks passed
 * @NIC_RX_DROP         Drop the packet, for whatever reason
 * @NIC_RX_CSUM_BAD     If the checksum is bad but the packet shouldn't
 *                      be dropped due to promiscuous mode.
 * If the interface is not in promiscuous mode any errors result in
 * @NIC_RX_DROP being set.
 *
 * Result from TX checks:
 * @NIC_TX_OK           Checks passed
 * @NIC_TX_DROP         Drop the packet, for whatever reason
 *
 * Miscellaneous:
 * @NIC_NO_VLAN         Used as a No VLAN present indication. Note this
 *                      can't be used for tci fields, just VLAN IDs.
 */
#define NIC_RX_OK               0
#define NIC_RX_DROP             1
#define NIC_RX_CSUM_BAD         2

#define NIC_TX_OK               (NIC_RX_OK)
#define NIC_TX_DROP             (NIC_RX_DROP)

#define NIC_NO_VLAN             0xff


/*
 * Receive functions
 */

/**
 * Perform Layer 1 checks for received packets
 *
 * @param port          Input port (physical network interface)
 *
 * Returns @NIC_RX_OK on success and @NIC_RX_DROP when checks failed.
 *
 * Checks performed include:
 * - Device enabled
 * - RX rings enabled
 * - MTU check
 *
 * The function also maintains counters in case a packet is dropped.
 */
__intrinsic int nic_rx_l1_checks(int port);


/**
 * Perform MTU check for received packets
 *
 * @param port          Input port (physical network interface)
 * @param csum          Checksum prepend word
 * @param frame_len     Length of the received frame
 *
 * Returns @NIC_RX_OK on success and @NIC_RX_DROP when checks failed.
 *
 * The MTU check takes into account the presence of one or more VLAN
 * tags (as indicated by the checksum prepend word @csum).  @frame_len
 * is expected to be the size of the full frame, including FCS.
 *
 * The function also maintains counters in case a packet is dropped.
 */
__intrinsic int nic_rx_mtu_check(int port, uint32_t csum, int frame_len);


/**
 * Perform checksum checks for received packets and set RX descriptor flags
 *
 * @param port          Input port (physical network interface)
 * @param csum          Checksum prepend word
 * @param meta          Pointer to buffer/packet meta data
 *
 * Returns @NIC_RX_OK on success and @NIC_RX_CSUM_BAD when checks fail.
 *
 * This function only applies to the outermost header
 *
 * The function also maintains counters in case a packet is marked as bad csum.
 *
 * @meta must be in GPRs or LMEM and is assumed to be a struct pkt_meta *.
 */
__intrinsic int nic_rx_csum_checks(int port, uint32_t csum, void *meta);


/**
 * Perform L2 sanity checks on the source and destination MAC address
 *
 * @param port          Input port (physical network interface)
 * @param sa            Pointer to the source MAC address
 * @param da            Pointer to the destination MAC address
 *
 * Returns @NIC_RX_OK on success and @NIC_RX_DROP when checks failed
 * and the NIC is not in promiscuous mode.
 *
 * The function also maintains counters in case a packet is dropped.
 *
 * @da must be in GPRs or LMEM and is assumed to be a struct eth_addr *.
 */
__intrinsic int nic_rx_l2_checks(int port, void *sa, void *da);


/**
 * Should the VLAN be stripped?
 *
 * @param port          Input port (physical network interface)
 * @param tci           Tag control information (VLAN plus flags)
 * @param meta          Pointer to buffer/packet meta data
 *
 * Returns 0 if the VLAN should not be stripped and 1 if the caller
 * should remove the VLAN tag from the received frame.  If the NIC is
 * configured to strip the VLAN, @tci will be added to RX descriptor
 * passed in as part of the meta data.
 *
 * Must only be called if frame has a valid 802.1Q header.
 *
 * @meta must be in GPRs or LMEM and is assumed to be a struct pkt_meta *.
 */
__intrinsic int nic_rx_vlan_strip(int port, uint16_t tci, void *meta);


__intrinsic void nic_rx_finalise_meta(void *meta, uint16_t len);

__intrinsic void * nic_rx_vxlan_ports();

/**
 * Are we on promisc mode?
 *
 * @param port          Input port (physical network interface)
 *
 * Returns 0 if the NIC is not configured in promisc mode and 1 if it
 * is.
 */
__intrinsic int nic_rx_promisc(int port);


/* RSS flags */
#define NIC_RSS_IP4    (1 << 0)     /* outer or generic IPv4 */
#define NIC_RSS_IP6    (1 << 1)     /* outer or generic IPv6 */
#define NIC_RSS_TCP    (1 << 2)     /* outer or generic TCP */
#define NIC_RSS_UDP    (1 << 3)       /* outer or generic UDP */
#define NIC_RSS_FRAG   (1 << 4)     /* outer or generic fragmented */
#define NIC_RSS_NVGRE  (1 << 5)     /* NVGRE encapsulated packet */
#define NIC_RSS_VXLAN  (1 << 6)     /* VXLAN encapsulated packet */
#define NIC_RSS_I_IP4  (1 << 7)     /* inner IPv4 */
#define NIC_RSS_I_IP6  (1 << 8)     /* inner IPv6 */
#define NIC_RSS_I_TCP  (1 << 9)     /* inner TCP */
#define NIC_RSS_I_UDP  (1 << 10)    /* inner UDP */

/**
 * Perform RSS if configured
 *
 * @param vport         VPort
 * @param l3            Pointer to the L3 header (IPv4 or IPv6)
 * @param l4            Pointer to the L4 header (UDP or TCP) or Null
 * @param i_l3          Pointer to the inner L3 header (IPv4 or IPv6)
 * @param i_l4          Pointer to the inner L4 header (UDP or TCP) or Null
 * @param flags         Indicate type of L3 and L4 header
 * @param hash_type     Pointer for a return value for the hash_type
 * @param meta          Pointer to buffer/packet meta data
 *
 * Returns the computed hash value and sent the RX queue in the meta
 * data.  If RSS is not configured for the packet type this function
 * returns zero and @hash_type is set to zero.
 *
 * @flags must be a valid combination of:
 * @NIC_RSS_IP4:        @l3 points to a IPv4 header
 * @NIC_RSS_IP6:        @l3 points to a IPv6 header
 * @NIC_RSS_TCP:        @l4 points to a TCP header
 * @NIC_RSS_UDP:        @l4 points to a UDP header
 * @NIC_RSS_FRAG:       The IP packet is fragmented (IPv6 only)
 * @NIC_RSS_NVGRE       NVGRE encapsulated packet
 * @NIC_RSS_VXLAN       VXLAN encapsulated packet/
 * @NIC_RSS_I_IP4       @i_l3 points to inner IPv4
 * @NIC_RSS_I_IP6       @i_l3 points to inner IPv6
 * @NIC_RSS_I_TCP       @i_l4 points to inner TCP
 * @NIC_RSS_I_UDP       @i_l4 points to inner UDP
 *
 * @l3, @l4, @i_l3, @i_l4 and @meta must be in GPRs or LMEM.
 */
__intrinsic uint32_t nic_rx_rss(int vport, void *o_l3, void *o_l4,
                                void *i_l3, void *i_l4, int flags,
                                void *hash_type, void *meta, uint32_t *qid);


/*
 * Transmit functions
 */

/**
 * Perform Layer 1 checks before transmitting packets
 *
 * @param port          Output port (physical network interface)
 *
 * Returns @NIC_TX_OK on success and @NIC_TX_DROP when checks failed.
 *
 * This checks if the device is enabled and drops the packet of not.
 *
 * The function also maintains counters in case a packet is dropped.
 */
__intrinsic int nic_tx_l1_checks(int port);


/**
 * Verify that the to be transmitted packet complies with the MTU
 *
 * @param port          Output port (physical network interface)
 * @param vlan          Boolean indicating if a VLAN is present
 * @param frame_len     Length of the frame
 *
 * Returns @NIC_TX_OK on success and @NIC_TX_DROP when checks failed.
 *
 * The function also maintains counters in case a packet is dropped.
 */
__intrinsic int nic_tx_mtu_check(int port, int vlan, int frame_len);


/**
 * Should a VLAN be added?
 *
 * @param port          Input port (physical network interface)
 * @param meta          Pointer to buffer/packet meta data
 *
 * Returns 0 if no VLAN should be added. If 1 is returned the 802.1Q
 * TCI is returned in @tci.
 *
 * @meta must be in GPRs or LMEM and is assumed to be a struct pkt_meta *.
 */
__intrinsic int nic_tx_vlan_add(int port, void *meta, void *tci);


/**
 * Should csum be offload?
 *
 * @param port          Input port (physical network interface)
 * @param meta          Pointer to buffer/packet meta data
 * @param l3_csum       Pointer to return L3 CSUM required
 * @param l4_csum       Pointer to return L4 CSUM required
 *
 */
__intrinsic void nic_tx_csum_offload(int port, void *meta,
                                     unsigned int *l3_csum,
                                     unsigned int *l4_csum);

/**
 * Is this an encapsulated packet?
 *
 * @param meta          Pointer to buffer/packet meta data
 *
 */
__intrinsic int nic_tx_encap(void *meta);



#endif /* !_NIC_BASIC_H_ */

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
