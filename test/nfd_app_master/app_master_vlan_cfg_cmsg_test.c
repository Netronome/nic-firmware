/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/*
    app_master_vlan_cfg_cmsg_test

    verify operation of nic_mac_vlan_entry_op_cmsg
*/

#include "defines.h"
#include "test.c"
#include "app_master_test.h"
#include "app_mac_vlan_config_cmsg.c"

#include <nfp/mem_ring.h>
#include <pkt/pkt.h>
#include <config.h>
#include <app_config_instr.h>
#include <nfd_cfg.h>
#include <nfd_user_cfg.h>
#include <nfd_common.h>
#include <nfd_vf_cfg_iface_abi2.h>
#include <app_mac_vlan_config_cmsg.h>
#include <maps/cmsg_map_types.h>


#define CMSG_DESC_LW 3

#define NET_ETH_LEN 14

#define SET_PIPELINE_BIT(prev, current) \
    ((current) - (prev) == 1) ? 1 : 0;


/* initialize blm buffer ring for test */
#define BLM_TEST_BUF_SIZE (1 << 11)
#define BLM_TEST_BUFFERS 16
__declspec(shared export emem0 aligned(BLM_TEST_BUF_SIZE)) \
uint32_t blm_test_mem[BLM_TEST_BUFFERS][BLM_TEST_BUF_SIZE];

static void blm_test_init() {
    int i;

    mem_ring_setup(__link_sym("BLM_NBI8_BLQ1_EMU_QID"),
                   (__mem void *)__link_sym("_BLM_NBI8_BLQ1_EMU_Q_BASE"),
                   4096);

    for (i = 0; i < BLM_TEST_BUFFERS; i++) {
        __xrw uint32_t addr = (uint32_t)((uint64_t)&blm_test_mem[i] >> 11);
        mem_ring_put(__link_sym("BLM_NBI8_BLQ1_EMU_QID"),
                     MEM_RING_GET_MEMADDR(_BLM_NBI8_BLQ1_EMU_Q_BASE),
                     &addr,
                     sizeof(addr));
    }
}

void main() {

    int rv, pass, i;
    uint32_t vlan, mac_hi, mac_lo;
    __lmem struct nic_mac_vlan_key lkp_key, lkp_key_exp;
    __lmem union instruction_format actions[NIC_MAX_INSTR];
    __lmem union instruction_format actions_exp[NIC_MAX_INSTR];
    __xread union instruction_format actions_xfr[NIC_MAX_INSTR];
    uint32_t mtu = 9216;
    uint32_t oper;
    unsigned int q_idx;
    mem_ring_addr_t q_base;
    __xread uint32_t workq_data[CMSG_DESC_LW];
    uint32_t ctm_pnum;
    uint32_t emem_dst;
    __addr40 uint8_t *emem_ptr;
    uint32_t exp;
    __xread struct nic_mac_vlan_cmsg cmsg_data;

    single_ctx_test();

    pkt_ctm_init_credits(PKT_BUF_CTM_CREDITS_LINK, 20, 20);

    blm_test_init();

    for (pass = 0; pass < 8; pass++) {

        vlan = (0xface - pass) & 0xffff;
        mac_hi = (0x1122 + pass) & 0xffff;
        mac_lo = 0x88995566 + pass;
        if ( pass & 1 )
            oper = CMSG_TYPE_MAP_ADD;
        else
            oper = CMSG_TYPE_MAP_DELETE;

        reg_zero(&lkp_key, sizeof(struct nic_mac_vlan_key));
        lkp_key.vlan_id = vlan;
        lkp_key.mac_addr_hi = mac_hi;
        lkp_key.mac_addr_lo = mac_lo;

        reg_zero(actions, sizeof(actions));
        actions[0].op = INSTR_TX_HOST;
        actions[0].args = NFD_VID2QID(pass, 0);
        actions[1].value = 0;

        /* invoke the routine being tested */

        rv = nic_mac_vlan_entry_op_cmsg(&lkp_key, (__lmem uint32_t *)&actions[0], oper);
        test_assert(rv);

        /* check format of ctrl msg request in nfd workq */

        q_idx = _link_sym(MAP_CMSG_Q_IDX);
        q_base = (_link_sym(MAP_CMSG_Q_BASE) >> 8) & 0xff000000;
        mem_workq_add_thread(q_idx, q_base, &workq_data, sizeof(workq_data));

        ctm_pnum = workq_data[0] >> 16;
        exp = ((__ISLAND<<26) | (ctm_pnum<<16));
        test_assert_equal(workq_data[0], exp);

        emem_dst = workq_data[1]; /* useless test */
        exp = emem_dst;
        test_assert_equal(workq_data[1], exp);

        exp = SRIOV_QUEUE<<16;
        test_assert_equal(workq_data[2], exp);

        /* check format of ctrl mssg in emem */

        emem_ptr = (__mem uint8_t *)((uint64_t)emem_dst << 11) +
            NFD_IN_DATA_OFFSET;
        mem_read32_swap(&cmsg_data, emem_ptr, sizeof(cmsg_data));

        test_assert_equal(cmsg_data.word0, oper | (CMSG_MAP_VERSION<<8));
        test_assert_equal(cmsg_data.tid, SRIOV_TID<<24);
        test_assert_equal(cmsg_data.count, 0);
        test_assert_equal(cmsg_data.flags, 0);

        lkp_key_exp.__raw[0] = 0;
        lkp_key_exp.__raw[1] = 0;
        lkp_key_exp.vlan_id = vlan;
        lkp_key_exp.mac_addr_hi = mac_hi;
        lkp_key_exp.mac_addr_lo = mac_lo;

        test_assert_equal(cmsg_data.key.__raw[0], lkp_key_exp.__raw[0]);
        test_assert_equal(cmsg_data.key.__raw[1], lkp_key_exp.__raw[1]);

        /* check the action list in emem */

        emem_ptr = (__mem uint8_t *)((uint64_t)emem_dst << 11) +
            NFD_IN_DATA_OFFSET + 80;
        mem_read32(&actions_xfr, emem_ptr, sizeof(actions_xfr));

        reg_zero(actions_exp, sizeof(actions_exp));
        actions_exp[0].op = INSTR_TX_HOST;
        actions_exp[0].args = NFD_VID2QID(pass, 0);
        actions_exp[1].value = 0;

        for (i = 0; i < sizeof(actions_exp) / sizeof(uint32_t); i++)
            test_assert_equal(actions_xfr[i].value, actions_exp[i].value);
    }

    test_pass();
}
