/*
 * Copyright 2014-2015 Netronome, Inc.
 *
 * @file          lib/nic/nic_ctrl.h
 * @brief         Control interface for NIC data structures from the host
 */


#ifndef _NIC_CTRL_H_
#define _NIC_CTRL_H_

#if defined(__NFP_LANG_MICROC)
#include <nfp.h>
#include <stdint.h>

#include <net/eth.h>
#endif

#if defined(__STDC__)
#include <stdint.h>

#ifndef NET_ETH_ALEN
#define NET_ETH_ALEN 6
#endif

/* XXX Let's hope this doesn't cause any name-space conflicts */
struct eth_addr {
    uint8_t  a[NET_ETH_ALEN];
};
#endif

/**
 * @NIC_SWITCH_VPORTS_MAX       Max number of VPorts
 * @NIC_SWITCH_VLANS_MAX        Max number of VLANS per VPort
 * @NIC_SWITCH_ENTRIES          Max MAC/VLAN or MAC entries in the switch
 * @NIC_SWITCH_NO_VPORT         Used to indicate no VPort for default ports
 * @NIC_SWITCH_NO_VLAN          Used to indicate lack of VLAN ID
 */
#define NIC_SWITCH_VPORTS_MAX   64
#define NIC_SWITCH_VLANS_MAX    32
#define NIC_SWITCH_ENTRIES      2048
#define NIC_SWITCH_NO_VPORT     0xff
#define NIC_SWITCH_NO_VLAN      0xffff

/**
 * Switch control structure
 */
struct nic_switch_ctrl {
    uint32_t default_rx_vp;     /* 0x00 Default VPort for receive */
    uint32_t pad;

    uint64_t spoof_en;          /* 0x08 Bitmask for VPs with spoofing enabled */
    uint64_t bc_en;             /* 0x10 Bitmask for VPs with BC allowed */
    uint64_t mc_promisc_en;     /* 0x18 Bitmask for VPs with MC allowed */
    uint64_t vlan_promisc_en;   /* 0x20 Bitmask for VPs with VLAN promisc set */
    uint64_t promisc_en;        /* 0x28 Bitmask for VPs with promisc enabled */
    uint64_t rss_en;            /* 0x30 Bitmask per VPs with RSS is enabled */
    uint64_t has_defaultq;      /* 0x38 Does vport have a default Q? */
};

/**
 * Switch MAC/VLAN data structure
 *
 * This is a hash table with @NIC_SWITCH_ENTRIES entries.  Each entry is
 * @nic_switch_key_entry in size and contains the key (@nic_switch_key)
 * and the destination queue.  The entry is padded so that 4 entries
 * fit nicely within a cacheline.
 */
__packed struct nic_switch_key {
    union {
        struct {
            struct eth_addr da;
            uint16_t pad;
            uint32_t vlan;
        };
        uint32_t vals[3];
    };
};

__packed struct nic_switch_entry {
    struct nic_switch_key key;
    uint32_t vport;
};

#endif /* _NIC_CTRL_H_ */
