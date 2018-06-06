/*
 * Copyright 2016 Netronome, Inc.
 *
 * @file          apps/nic/nic_tables.c
 * @brief         allocate tables for Core NIC
 *
 */
#include <nfp.h>
#include <stdint.h>
#include <nfp/mem_bulk.h>
#include <vnic/nfd_common.h>

#include "nic_tables.h"

/* vid to <SrcMAC, VLAN, flags> mapping table */
__export __shared __imem_n(0) __addr40
	__align(sizeof(struct nfp_vnic_setup_entry))
	struct nfp_vnic_setup_entry nic_vnic_setup_map_tbl[NVNICS];

/* VLAN to vid mapping table */
__export __shared __mem uint64_t nic_vlan_to_vnics_map_tbl[NIC_NUM_VLANS];

__intrinsic void
nic_tables_init()
{
    int i;
    __xwrite struct nfp_vnic_setup_entry vnic_entry_wr =
        {0, NIC_NO_VLAN_ID, 0, 0, 0};

    for (i = 0; i < NVNICS; i++)
        write_vnic_setup_entry(i , &vnic_entry_wr);
}

__intrinsic int
load_vnic_setup_entry(uint16_t vid,
                      __xread struct nfp_vnic_setup_entry *entry)
{
    int ret = 0;

    if (vid < NVNICS)
        mem_read32(entry, &nic_vnic_setup_map_tbl[vid],
                   sizeof(struct nfp_vnic_setup_entry));
    else
        ret = -1;

    return ret;
}

__intrinsic int
write_vnic_setup_entry(uint16_t vid,
                       __xwrite struct nfp_vnic_setup_entry *entry)
{
    int ret = 0;

    if (vid < NVNICS)
        mem_write32(entry, &nic_vnic_setup_map_tbl[vid],
                    sizeof(struct nfp_vnic_setup_entry));
    else
        ret = -1;

    return ret;
}

__intrinsic int
load_vlan_members(uint16_t vlan_id, __xread uint64_t *members)
{
    int ret = 0;

    if (vlan_id <= NIC_MAX_VLAN_ID)
        mem_read64(members, &nic_vlan_to_vnics_map_tbl[vlan_id],
                   sizeof(uint64_t));
    else
        ret = -1;

    return ret;
}

__intrinsic int
set_vlan_members(uint16_t vlan_id, __xwrite uint64_t *members)
{
    int ret = 0;

    if (vlan_id <= NIC_MAX_VLAN_ID)
        mem_write64(members, &nic_vlan_to_vnics_map_tbl[vlan_id], sizeof(uint64_t));
    else
        ret = -1;

    return ret;
}

__intrinsic int
add_vlan_member(uint16_t vlan_id, uint16_t vid)
{
    int ret = 0;

    __xread uint64_t members_r;
    __xwrite uint64_t members_w;
    uint64_t new_member;

    if (vlan_id <= NIC_MAX_VLAN_ID) {
        mem_read64(&members_r, &nic_vlan_to_vnics_map_tbl[vlan_id],
                   sizeof(uint64_t));
        new_member = ((uint64_t)1 << vid);
        members_w = members_r | new_member;
        mem_write64(&members_w, &nic_vlan_to_vnics_map_tbl[vlan_id],
                    sizeof(uint64_t));
    } else {
        ret = -1;
    }

    return ret;
}

__intrinsic int
remove_vlan_member(uint16_t vlan_id, uint16_t vid)
{
    int ret = 0;

    __xread uint64_t members_r;
    __xwrite uint64_t members_w;
    uint64_t rem_member;

    if (vlan_id <= NIC_MAX_VLAN_ID) {
        mem_read64(&members_r, &nic_vlan_to_vnics_map_tbl[vlan_id],
                   sizeof(uint64_t));
        rem_member = ~((uint64_t)1 << vid);
        members_w = members_r & rem_member;
        mem_write64(&members_w, &nic_vlan_to_vnics_map_tbl[vlan_id],
                    sizeof(uint64_t));
    } else {
        ret = -1;
    }

    return ret;
}
