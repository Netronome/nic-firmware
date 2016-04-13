/*
 * Copyright 2014-2015 Netronome, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @file          lib/nic/_c/nic_tx.c
 * @brief         NIC TX processing
 */

#ifndef _LIBNIC_NIC_TX_C_
#define _LIBNIC_NIC_TX_C_

#include <nfp.h>
#include <stdint.h>

#include <net/eth.h>
#include <nfp6000/nfp_me.h>

#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_in.h>

__intrinsic int
nic_tx_l1_checks(int port)
{
    __gpr int ret = NIC_TX_OK;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

   /* Drop if down */
    if (!(nic->control & NFP_NET_CFG_CTRL_ENABLE)) {
        NIC_LIB_CNTR(&nic_cnt_tx_drop_down);
        ret = NIC_TX_DROP;
    }

    return ret;
}


__intrinsic int
nic_tx_mtu_check(int port, int vlan, int frame_len)
{
    __gpr int ret = NIC_TX_OK;
    __gpr int max_frame_sz;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    /* Without VLANs the max frame size is MTU + Ethernet header */
    max_frame_sz = nic->mtu + NET_ETH_LEN;

    if (vlan)
        max_frame_sz += NET_8021Q_LEN;

    /* Drop if frame exceeds MTU */
    if (frame_len > max_frame_sz) {
        nic_tx_error_cntr(port);
        NIC_LIB_CNTR(&nic_cnt_tx_drop_mtu);
        ret = NIC_TX_DROP;
    }

    return ret;
}

__intrinsic int
nic_tx_vlan_add(int port, void *meta, void *tci)
{
    int ret = 0;
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    /* If VLAN adding is disabled, we are done */
    if (!(nic->control & NFP_NET_CFG_CTRL_TXVLAN))
        goto out;

    /* If no VLAN in TX descriptor, we are done */
    if (in_desc->flags & PCIE_DESC_TX_VLAN) {
        *(uint16_t *)tci = in_desc->vlan;
        ret = 1;
    }

out:
    return ret;
}

__intrinsic void
nic_tx_csum_offload(int port, void *meta, unsigned int *l3_csum,
                    unsigned int *l4_csum)
{
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;

    *l3_csum = 0;
    *l4_csum = 0;

    if (in_desc->flags & PCIE_DESC_TX_CSUM) {
        if (in_desc->flags & PCIE_DESC_TX_ENCAP) {
            if (in_desc->flags & PCIE_DESC_TX_O_IP4_CSUM)
                *l3_csum = 1;
        } else {
            if (in_desc->flags & PCIE_DESC_TX_IP4_CSUM)
                *l3_csum = 1;
            if (in_desc->flags &
                (PCIE_DESC_TX_TCP_CSUM | PCIE_DESC_TX_UDP_CSUM))
                *l4_csum = 1;
        }
    }
}

__intrinsic int
nic_tx_encap(void *meta)
{
    __gpr int ret = 0;
    struct pcie_in_nfp_desc *in_desc = (struct pcie_in_nfp_desc *)meta;

    if (in_desc->flags & (PCIE_DESC_TX_ENCAP_VXLAN | PCIE_DESC_TX_ENCAP_GRE))
        ret = 1;
    else
        ret = 0;

    return ret;
}

#endif /* _LIBNIC_NIC_TX_C_ */
/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
