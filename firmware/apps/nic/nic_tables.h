/*
 * Copyright (c) 2016-2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file          apps/nic/nic_tables.h
 * @brief         data structures for Core NIC tables
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _NIC_TABLES_H_
#define _NIC_TABLES_H_

#include <net/eth.h>
#include "nfd_user_cfg.h"
#include <vnic/shared/nfd_cfg.h>

struct vlan_filter_cfg {
    union {
        struct {
            uint16_t proto;
            uint16_t vlan;
        };
        uint32_t __raw[1];
    };
};

/* The Core NIC requires the following tables:
 *
 *  1. VLAN+MAC lookup table
 *     Used for looking up the destination vNIC for a given packet (either
 *     from host or wire) based on the destination MAC address and the VLAN.
 *     Implemented separately via HASHMAP API.
 *
 *  2. VLAN to vNICS mapping table
 *     A table that holds a vNICs bitmap per VLAN id (including the no-vlan
 *     id). This table is cached in CTM for data path broadcast/multi-cast.
 */

#define NIC_NUM_VLANS   4096    /* 0-Special, 4095-No vlan */
#define NIC_MAX_VLAN_ID 4095
#define NIC_NO_VLAN_ID  4095

/* VLAN to vid mapping table */
__export __shared __mem uint64_t nic_vlan_to_vnics_map_tbl[NFD_MAX_ISL][NIC_NUM_VLANS];


/**
 * Load the VLAN's VNIC members bitmap
 *
 * @param pcie      PCIe number (0..3)
 * @param vlan_id   The VLAN id (can also be the NIC_NO_VLAN_ID)
 * @param members   The returned 64bit VNIC members bitmap
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int load_vlan_members(uint32_t pcie, uint16_t vlan_id,
                                  __xread uint64_t *members);

/**
 * Adds a VNIC to the VLAN's VNIC members bitmap
 *
 * @param pcie      PCIe number (0..3)
 * @param vlan_id   The VLAN id (can also be the NIC_NO_VLAN_ID)
 * @param vid       The VNIC vid to be added
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int add_vlan_member(uint32_t pcie, uint16_t vlan_id, uint16_t vid);

/**
 * Remove a VNIC from the VLAN's VNIC members bitmap
 *
 * @param pcie      PCIe number (0..3)
 * @param vid       The VNIC vid to be removed
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int remove_vlan_member(uint32_t pcie, uint16_t vid);

#endif /* _NIC_TABLES_H_ */
