/*
 * Copyright (C) 2015, Netronome Systems, Inc.  All rights reserved.
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
 * @file          lib/nic/_c/nic_switch.c
 * @brief         Switch implementation
 */

#include <net/eth.h>
#include <nfp/mem_cam.h>

/*
 * Globals for switch config from the host
 */

/* Switch control structure */
__export __emem struct nic_switch_ctrl nic_switch_control;

/* Mapping of TX queue to VPort */
__export __emem uint8_t nic_switch_txq_to_vport[NFP_NET_TXR_MAX];

/* Default RX queue per VPort */
__export __emem uint8_t nic_switch_default_rxq[NIC_SWITCH_VPORTS_MAX];

/* Table for per VPort VLANs.  Depending on how many we want/need to
 * support it might be more efficient to have a table, indexed by VLAN
 * ID containing a 64bit mask (a bit per vport) to check membership. */
#define NOVLAN8  NIC_SWITCH_NO_VLAN, NIC_SWITCH_NO_VLAN, NIC_SWITCH_NO_VLAN, \
                 NIC_SWITCH_NO_VLAN, NIC_SWITCH_NO_VLAN, NIC_SWITCH_NO_VLAN, \
                 NIC_SWITCH_NO_VLAN, NIC_SWITCH_NO_VLAN
#define NOVLAN32 { NOVLAN8, NOVLAN8, NOVLAN8, NOVLAN8 }
#define NOVLAN8_32 NOVLAN32, NOVLAN32, NOVLAN32, NOVLAN32, \
                   NOVLAN32, NOVLAN32, NOVLAN32, NOVLAN32
#define NOVLAN64_32 NOVLAN8_32, NOVLAN8_32, NOVLAN8_32, NOVLAN8_32, \
                    NOVLAN8_32, NOVLAN8_32, NOVLAN8_32, NOVLAN8_32
__export __emem uint16_t \
    nic_switch_vport_vlans[NIC_SWITCH_VPORTS_MAX][NIC_SWITCH_VLANS_MAX] \
    = { NOVLAN64_32 };

#undef NOVLAN8
#undef NOVLAN32
#undef NOVLAN8_32
#undef NOVLAN64_32

/* Hash table for Switch lookup */
CAMHT_DECLARE(nic_switch, NIC_SWITCH_ENTRIES, struct nic_switch_entry);

__intrinsic void
nic_switch_reconfig()
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    __xread struct nic_switch_ctrl sw_ctrl;
    __xread uint8_t txq_to_vport[NFP_NET_TXR_MAX];
    __xread uint8_t sw_default_rxq[NIC_SWITCH_VPORTS_MAX];

    mem_read64(&sw_ctrl, &nic_switch_control, sizeof(sw_ctrl));

    nic->sw_default_rx_vp = sw_ctrl.default_rx_vp;
    nic->sw_vp_spoof_en = swapw64(sw_ctrl.spoof_en);
    nic->sw_vp_bc_en = swapw64(sw_ctrl.bc_en);
    nic->sw_vp_mc_promisc_en = swapw64(sw_ctrl.mc_promisc_en);
    nic->sw_vp_vlan_promisc_en = swapw64(sw_ctrl.vlan_promisc_en);
    nic->sw_vp_promisc_en = swapw64(sw_ctrl.promisc_en);
    nic->sw_vp_rss_en = swapw64(sw_ctrl.rss_en);
    nic->sw_vp_has_defaultq = swapw64(sw_ctrl.has_defaultq);

    mem_read64(txq_to_vport, nic_switch_txq_to_vport, sizeof(txq_to_vport));
    reg_cp((void*)nic->sw_txq_to_vport, txq_to_vport, sizeof(txq_to_vport));

    mem_read64(sw_default_rxq, nic_switch_default_rxq, sizeof(sw_default_rxq));
    reg_cp((void*)nic->sw_default_rxq, sw_default_rxq, sizeof(sw_default_rxq));
}


__intrinsic int
nic_switch_rx_defaultq(int vport, uint8_t *qid)
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;
    int ret = NIC_RX_DROP;
    int q;

    if (!(nic->control[vport] & NFP_NET_CFG_CTRL_L2SWITCH)) {
        if (nic->rx_ring_en[vport]) {
            q = ffs64(nic->rx_ring_en[vport]);
            if (q != -1)
                *qid = q&0xff;
            else
                goto out;
            ret = NIC_RX_OK;
        }
        goto out;
    }

    if (nic->sw_vp_has_defaultq & VPORT_MASK(vport)) {
        *qid = nic->sw_default_rxq[vport];
        ret = NIC_RX_OK;
    }

out:
    return ret;
}

__intrinsic int
nic_switch_tx_vport(int vport, uint8_t qid)
{
    int ret;
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    if (!(nic->control[vport] & NFP_NET_CFG_CTRL_L2SWITCH))
        ret = 0;
    else
        ret = nic->sw_txq_to_vport[qid];

    return ret;
}


/*
 * Check if a VLAN is associated with a vport. Return 1 if matches, otherwise 0
 */
static __intrinsic int
nic_switch_vport_vlan(int vport, uint16_t tci)
{
     __xrw struct mem_cam_16bit cam;
     int ret = 0;

     cam.search.value = tci;
     mem_cam512_lookup16(&cam, nic_switch_vport_vlans[vport]);

     if (mem_cam_lookup_hit(cam))
         ret = 1;

     return ret;
}

/*
 * Match MAC and VLAN to vport. Returns vport ID or -1 on mismatch
 */
static __intrinsic int
nic_switch_mac_vlan(void *mac, uint16_t vlan)
{
    __gpr struct nic_switch_key key;
    __xread struct nic_switch_entry entry;
    __gpr int idx;
    __gpr int ret = -1;

    ctassert(__is_in_reg_or_lmem(mac));

    reg_zero(&key, sizeof(key));

    if (__is_in_lmem(mac)) {
        ((__gpr uint32_t *)&key.da)[0] = ((__lmem uint32_t *)mac)[0];
        ((__gpr uint16_t *)&key.da)[2] = ((__lmem uint16_t *)mac)[2];
    } else {
        ((__gpr uint32_t *)&key.da)[0] = ((__gpr uint32_t *)mac)[0];
        ((__gpr uint16_t *)&key.da)[2] = ((__gpr uint16_t *)mac)[2];
    }

    key.vlan = vlan;

    idx = CAMHT_LOOKUP_IDX(nic_switch, &key);
    if (idx < 0)
        goto out;

    mem_read64(&entry, &CAMHT_KEY_TBL(nic_switch)[idx], sizeof(entry));

    if (reg_eq(&entry.key, &key, sizeof(key)))
        ret = entry.vport;

out:
    return ret;

}


__intrinsic uint64_t
nic_switch(int in_vport, void *sa, void *da, uint16_t vlan,
           __gpr int *uplink)
{
    __shared __lmem volatile struct nic_local_state *nic = &nic_lstate;

    __gpr uint64_t in_mask;
    __gpr uint64_t out_mask;
    __gpr uint64_t tmp_mask;

    __gpr int vlan_match;
    __gpr int out_vport;
    __gpr int tmp0, tmp1;

    ctassert(__is_in_reg_or_lmem(sa));
    ctassert(__is_in_reg_or_lmem(da));

    out_mask = 0;
    *uplink = 0;


    /* If the switch is not enabled. Return VPort 0 if received from
     * uplink or set uplink when received from any other vport. */
    if (!(nic->control[in_vport] & NFP_NET_CFG_CTRL_L2SWITCH)) {
        if (in_vport == NIC_SWITCH_UPLINK)
            out_mask = VPORT_MASK(0);
        else
            *uplink = 1;
        goto out;
    }

    if (in_vport != NIC_SWITCH_UPLINK) {

        in_mask = VPORT_MASK(in_vport);

        if (!(nic->sw_vp_spoof_en & in_mask)) {

            vlan_match = nic_switch_vport_vlan(in_vport, vlan);
            if (!(nic->sw_vp_promisc_en & in_mask) && !vlan_match)
                goto out;

            tmp0 = nic_switch_mac_vlan(sa, vlan);
            tmp1 = nic_switch_mac_vlan(sa, NIC_NO_VLAN);
            if (tmp0 != in_vport && tmp1 != in_vport)
                goto out;
        }

        if (!(nic->control[in_vport] & NFP_NET_CFG_CTRL_L2SWITCH_LOCAL)) {
            *uplink = 1;
            goto out;
        }
    }

    if (NIC_IS_BC_ADDR(da)) {
        out_mask |= nic->sw_vp_bc_en;
    } else {

        if (NIC_IS_MC_ADDR(da))
            out_mask |= nic->sw_vp_mc_promisc_en;

        out_vport = nic_switch_mac_vlan(da, vlan);
        if (out_vport >= 0)
            out_mask |= VPORT_MASK(out_vport);

        out_vport = nic_switch_mac_vlan(da, NIC_NO_VLAN);
        if (out_vport >= 0)
            out_mask |= VPORT_MASK(out_vport);
    }

    tmp_mask = out_mask;
    while (tmp_mask) {
        out_vport = ffs64(tmp_mask);
        tmp_mask &= ~VPORT_MASK(out_vport);

        vlan_match = nic_switch_vport_vlan(out_vport, vlan);
        if (!(nic->sw_vp_vlan_promisc_en & VPORT_MASK(out_vport)) &&
            !vlan_match)
            out_mask &= ~VPORT_MASK(out_vport);
    }

    if (NIC_IS_BC_ADDR(da) || NIC_IS_MC_ADDR(da) || !out_mask)
        *uplink = 1;

    out_mask |= nic->sw_vp_promisc_en;

    if (!out_mask && nic->sw_default_rx_vp != NIC_SWITCH_NO_VPORT)
        out_mask |= VPORT_MASK(nic->sw_default_rx_vp);

    if (in_vport != NIC_SWITCH_UPLINK)
        out_mask &= ~in_mask;

out:
    /* Maintain some counters */
    if (in_vport == NIC_SWITCH_UPLINK) {
        if (out_mask & ~VPORT_MASK(ffs64(out_mask)))
            NIC_LIB_CNTR(&nic_cnt_rx_switch_multi);
    } else {
        if (out_mask)
            NIC_LIB_CNTR(&nic_cnt_tx_switch_int);
    }

    return out_mask;
}

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
