/*
 * Copyright 2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file  vnic_setup.c
 * @brief This file contains functions to setup parts of a vNIC's BAR for
 *        for unit testing.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <assert.h>
#include <nfp.h>
#include <nfp_chipres.h>

#include <stdint.h>

#include <platform.h>
#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp/cls.h>
#include <nfp6000/nfp_me.h>

#include <std/reg_utils.h>
#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>
#include <vnic/nfd_common.h>
#include <vnic/shared/nfd_vf_cfg_iface.h>
#include <shared/nfp_net_ctrl.h>
#include <nic_basic/nic_basic.h>
#include "app_config_tables.h"
#include "app_config_instr.h"

void reset_cfg_msg(struct nfd_cfg_msg *cfg_msg, uint32_t vid, uint32_t error)
{
    cfg_msg->__raw = 0;
    cfg_msg->vid = vid;
    cfg_msg->error = error;
}

void setup_pf_mac(const int pcie, uint32_t vid, uint64_t mac)
{
    __xwrite uint32_t mac_xw[2];
    mac_xw[0] = (uint32_t)(mac >> 16);
    mac_xw[1] = (uint32_t)((mac & 0xffff | (pcie << 6) | (vid)) << 16);
    mem_write64(&mac_xw[0], (__mem void*) (nfd_cfg_bar_base(pcie, vid) +
                                        NFP_NET_CFG_MACADDR), sizeof(mac_xw));
}

void setup_vf_mac(const int pcie, uint32_t vid, uint64_t mac)
{
    __xwrite uint32_t mac_xw[2];
    mac_xw[0] = (uint32_t)(mac >> 16);
    mac_xw[1] = (uint32_t)(mac & 0xffff);
    mem_write64(&mac_xw[0], (__mem void*) (nfd_cfg_bar_base(pcie, vid) +
                                        NFP_NET_CFG_MACADDR), sizeof(mac_xw));
}
void setup_sriov_mb(const int pcie, uint32_t vf, uint32_t flags)
{
    __xwrite uint32_t sriov_mb_data[4];
    struct sriov_mb mb;
    __emem __addr40 uint8_t *vf_cfg_base = nfd_vf_cfg_base(pcie, 0, NFD_VF_CFG_SEL_MB);

    mb.__raw[0] = 0;
    mb.__raw[1] = 0;
    mb.__raw[2] = 0;
    mb.__raw[3] = 0;

    mb.vf = vf;
    mb.update_flags = flags;

    ctassert(sizeof(struct sriov_mb) == 4 * sizeof(uint32_t));

    sriov_mb_data[0] = mb.__raw[0];
    sriov_mb_data[1] = mb.__raw[1];
    sriov_mb_data[2] = mb.__raw[2];
    sriov_mb_data[3] = mb.__raw[3];

    mem_write32(&sriov_mb_data, vf_cfg_base, sizeof(struct sriov_mb));
}

void setup_sriov_cfg_data(const int pcie, uint32_t vf, uint64_t mac, uint16_t vlan, uint8_t flags)
{
    struct sriov_cfg sriov_cfg_data;
     __xwrite uint32_t wr[4];
     __emem __addr40 uint8_t *vf_cfg_base = nfd_vf_cfg_base(pcie, vf, NFD_VF_CFG_SEL_VF);

     sriov_cfg_data.__raw[0] = 0;
     sriov_cfg_data.__raw[1] = 0;
     sriov_cfg_data.__raw[2] = 0;
     sriov_cfg_data.__raw[3] = 0;

     sriov_cfg_data.mac_hi = (uint32_t)((mac >> 16));
     sriov_cfg_data.mac_lo = (uint16_t)((mac & 0xffff));
     sriov_cfg_data.vlan_tag = vlan;
     sriov_cfg_data.ctrl_flags = flags;

     ctassert(sizeof(struct sriov_cfg) == 4 * sizeof(uint32_t));

     wr[0] = sriov_cfg_data.__raw[0];
     wr[1] = sriov_cfg_data.__raw[1];
     wr[2] = sriov_cfg_data.__raw[2];
     wr[3] = sriov_cfg_data.__raw[3];
     mem_write32(&wr, vf_cfg_base, sizeof(struct sriov_cfg));
}


uint32_t pcie_is_present(int pcie)
{
    uint32_t pcie_bitmap = 0;

#ifdef NFD_PCIE0_EMEM
    pcie_bitmap |= 1;
#endif

#ifdef NFD_PCIE1_EMEM
    pcie_bitmap |= (1 << 1);
#endif

#ifdef NFD_PCIE2_EMEM
    pcie_bitmap |= (1 << 2);
#endif

#ifdef NFD_PCIE3_EMEM
    pcie_bitmap |= (1 << 3);
#endif

    return (pcie_bitmap >> pcie) & 1;
}


