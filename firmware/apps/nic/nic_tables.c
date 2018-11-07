/*
 * Copyright (c) 2016-2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file          apps/nic/nic_tables.c
 * @brief         allocate tables for Core NIC
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <nfp.h>
#include <stdint.h>
#include <nfp/mem_bulk.h>
#include <vnic/nfd_common.h>

#include "nic_tables.h"

__intrinsic int
load_vlan_members(uint32_t pcie, uint16_t vlan_id, __xread uint64_t *members)
{
    int ret = 0;

    if (vlan_id <= NIC_MAX_VLAN_ID)
        mem_read64(members, &nic_vlan_to_vnics_map_tbl[pcie][vlan_id],
                   sizeof(uint64_t));
    else
        ret = -1;

    return ret;
}


__intrinsic int
add_vlan_member(uint32_t pcie, uint16_t vlan_id, uint16_t vid)
{
    __emem __addr40 uint8_t *bar_base = nfd_cfg_bar_base(pcie, vid);

    __xread uint64_t members_r;
    __xwrite uint64_t members_w;
    __xread uint32_t rxb_r;
    uint64_t new_member;
    uint64_t min_rxb;

    if (vlan_id > NIC_MAX_VLAN_ID)
        return -1;

    mem_read64(&members_r, &nic_vlan_to_vnics_map_tbl[pcie][vlan_id], sizeof(uint64_t));
    min_rxb = (members_r >> 58);
    mem_read32(&rxb_r, (__mem void*) (bar_base + NFP_NET_CFG_FLBUFSZ), sizeof(rxb_r));
    if ((members_r & ((1ull << NFD_MAX_VFS) - 1)) == 0)
        min_rxb = ((rxb_r >> 8) & 0x3f);
    else
        min_rxb = min_rxb < ((rxb_r >> 8) & 0x3f) ? min_rxb : ((rxb_r >> 8) & 0x3f);
    members_w = (members_r | (1ull << vid)) & ((1ull << NFD_MAX_VFS) - 1) | (min_rxb << 58);
    mem_write64(&members_w, &nic_vlan_to_vnics_map_tbl[pcie][vlan_id], sizeof(uint64_t));

    return 0;
}

__intrinsic int
remove_vlan_member(uint32_t pcie, uint16_t vid)
{
    __emem __addr40 uint8_t *bar_base = nfd_cfg_bar_base(pcie, vid);

    __xread uint64_t members_r;
    __xwrite uint64_t members_w;
    __xread uint32_t rxb_r;
    uint64_t members;
    uint64_t min_rxb;
    uint16_t vid_idx;
    uint32_t vlan;

    for (vlan = 0; vlan <= NIC_MAX_VLAN_ID; ++vlan) {
        mem_read64(&members_r, &nic_vlan_to_vnics_map_tbl[pcie][vlan], sizeof(uint64_t));
        members = members_r & ((1ull << NFD_MAX_VFS) - 1);
        members &= ~(1ull << vid);
        if (members) {
            min_rxb = (1 << 6) - 1;
            for (vid_idx = 0; NFD_MAX_VFS && vid_idx < NFD_MAX_VFS; vid_idx++) {
                if (members & (1ull << vid_idx)) {
                    mem_read32(&rxb_r,
                               (__mem void*) (nfd_cfg_bar_base(pcie, vid_idx) +
                               NFP_NET_CFG_FLBUFSZ), sizeof(rxb_r));
                    min_rxb = (min_rxb < (rxb_r >> 8) & 0x3f) ? min_rxb : (rxb_r >> 8) & 0x3f;
                }
            }
            members |= (min_rxb << 56);
        }
        members_w = members;
        mem_write64(&members_w, &nic_vlan_to_vnics_map_tbl[pcie][vlan], sizeof(uint64_t));
    }

    return 0;
}
