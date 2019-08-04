/*
 * Copyright 2016-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_mac_vlan_config_cmsg.h
 * @brief         NIC application MAC+VLAN lookup cmsg table config
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _APP_MAC_VLAN_CONFIG_CMSG_H_
#define _APP_MAC_VLAN_CONFIG_CMSG_H_

/* *** NIC MAC+VLAN Table Configuration Settings. *** */

#define NIC_MAC_VLAN_TABLE__NUM_ENTRIES 0x60000

/* *** NIC MAC+VLAN table result types. *** */
#define NIC_MAC_VLAN_RES_TYPE_TO_HOST 0
#define NIC_MAC_VLAN_RES_TYPE_TO_WIRE 1
#define NIC_MAC_VLAN_RES_TYPE_LACP    2

/* *** NIC MAC+VLAN Data Structures. *** */

#define NIC_MAC_VLAN_KEY_SIZE_LW   2

#define MAP_CMSG_IN_WQ_SZ	4096

#define SRIOV_QUEUE  64

#define CMESG_DISPATCH_OK       1
#define CMESG_DISPATCH_FAIL     0xffffffff

/** Lookup key for the MAC+VLAN table. */
#if defined(__NFP_LANG_MICROC)
    struct nic_mac_vlan_key {
        union {
            struct {
                unsigned int vlan_id  : 12; /**< VLAN ID */
                unsigned int __unused : 4;
                uint16_t mac_addr_hi;       /**< Upper 2 bytes of MAC address */
                uint32_t mac_addr_lo;       /**< Lower 4 bytes of MAC address */
            };
            uint32_t __raw[NIC_MAC_VLAN_KEY_SIZE_LW];
        };
    };

    #define NIC_MAC_VLAN_RESULT_SIZE_LW 16
    uint32_t action_list[(NIC_MAC_VLAN_RESULT_SIZE_LW)];

    #define NIC_MAC_VLAN_ENTRY_SIZE_LW \
        (NIC_MAC_VLAN_KEY_SIZE_LW + NIC_MAC_VLAN_RESULT_SIZE_LW)

    /** Lookup entry for MAC+VLAN table. */
    struct nic_mac_vlan_entry {
        union {
            struct {
                struct nic_mac_vlan_key key;
                uint32_t action_list[(NIC_MAC_VLAN_RESULT_SIZE_LW)];
            };
            uint32_t __raw[NIC_MAC_VLAN_ENTRY_SIZE_LW];
        };
    };

    #define NIC_MAC_VLAN_CMSG_SIZE_LW  \
        (NIC_MAC_VLAN_KEY_SIZE_LW + 4) //check this

    /** Cmsg st MAC+VLAN Structure for table. */
    struct nic_mac_vlan_cmsg {
        union {
            struct {
                uint32_t word0;  /* CMSG_TYPE_MAP_xxx add, delete, lookup, getnext, getfirst */
                uint32_t tid;
                uint32_t count;
                uint32_t flags;
                struct nic_mac_vlan_key key;
            };
            uint32_t __raw[NIC_MAC_VLAN_CMSG_SIZE_LW];
        };
    };


    /* CTM allocation credits */
    __asm {.alloc_mem _pkt_buf_ctm_credits cls island 8}
    #define PKT_BUF_CTM_CREDITS_LINK \
        (__cls struct ctm_pkt_credits *) _link_sym(_pkt_buf_ctm_credits)

    /* *** NIC MAC+VLAN Table Functions. *** */

    /**
    * Add a MAC+VLAN entry to the NIC MAC+VLAN table.
    *
    * @param key           Key for the entry to add
    * @param action_list   Address of the SRIOV action list
    * @param operation     Add/Del Entry
    */
    int32_t nic_mac_vlan_entry_op_cmsg(__lmem struct nic_mac_vlan_key *key,
                                       __lmem uint32_t *action_list,
                                       const int operation);
#endif
#endif /* ndef _APP_MAC_VLAN_CONFIG_CMSG_H_ */
