/*
 * Copyright 2016 Netronome, Inc.
 *
 * @file          apps/nic/nic_tables.h
 * @brief         data structures for Core NIC tables
 *
 */
#ifndef _NIC_TABLES_H_
#define _NIC_TABLES_H_

#include <net/eth.h>
#include "nfd_user_cfg.h"

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
 *     Implemented in HASHMAP API.
 *
 *  2. vNIC to <SrcMAC, VLAN> mapping table
 *     This table is used for two processes, VLAN insertion and Spoof checking
 *     for packets arriving from a VM. (Use only for "VF-vNICs").
 *
 *  3. VLAN to vNICS mapping table
 *     A table that holds a vNICs bitmap per VLAN id (including the no-vlan
 *     id). This table will only be consulted for broadcast/multi-cast which
 *     should be on the slow path.
 */

#define NIC_NUM_VLANS   4096    /* 0-Special, 4095-No vlan */
#define NIC_MAX_VLAN_ID 4095
#define NIC_NO_VLAN_ID  4095

/* VNIC to <SrcMAC, VLAN, flags> mapping table entry */
struct nfp_vnic_setup_entry {
    union {
        struct {
            uint64_t src_mac;
            uint32_t vlan:16;
            uint32_t spoof_chk:1;
            uint32_t link_state_mode:2;
            uint32_t reserved:13;
            uint32_t spare;
        };
        uint32_t __raw[4];
    };
};

/**
 * Init nic tables
 */
__intrinsic void nic_tables_init();

/**
 * Load the VNIC setup entry for a given VNIC
 *
 * @param vid   The VNIC vid number
 * @param entry The returned entry
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int load_vnic_setup_entry(uint16_t vid,
                               __xread struct nfp_vnic_setup_entry *entry);

/**
 * Write the VNIC setup entry for a given vnic
 *
 * @param vid   The VNIC vid number
 * @param entry The entry to write
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int write_vnic_setup_entry(uint16_t vid,
                               __xwrite struct nfp_vnic_setup_entry *entry);

/**
 * Load the VLAN's VNIC members bitmap
 *
 * @param vlan_id   The VLAN id (can also be the NIC_NO_VLAN_ID)
 * @param members   The returned 64bit VNIC members bitmap
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int load_vlan_members(uint16_t vlan_id,
                                  __xread uint64_t *members);

/**
 * Sets the VLAN's VNIC members bitmap
 *
 * @param vlan_id   The VLAN id (can also be the NIC_NO_VLAN_ID)
 * @param members   The 64bit VNIC members bitmap to write
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int set_vlan_members(uint16_t vlan_id,
                                 __xwrite uint64_t *members);

/**
 * Adds a VNIC to the VLAN's VNIC members bitmap
 *
 * @param vlan_id   The VLAN id (can also be the NIC_NO_VLAN_ID)
 * @param vid       The VNIC vid to be added
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int add_vlan_member(uint16_t vlan_id, uint16_t vid);

/**
 * Remove a VNIC from the VLAN's VNIC members bitmap
 *
 * @param vlan_id   The VLAN id (can also be the NIC_NO_VLAN_ID)
 * @param vid       The VNIC vid to be removed
 *
 * @return 0 on success, -1 on failure
 */
__intrinsic int remove_vlan_member(uint16_t vlan_id, uint16_t vid);

#endif /* _NIC_TABLES_H_ */
