/*
 * Copyright(C) 2017-2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file  action_parse.c
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

volatile __shared __lmem union instruction_format _action_list[NIC_MAX_INSTR];

__intrinsic void
cfg_act_read_queue(uint32_t qid)
{
    SIGNAL sig;
    __gpr uint32_t addr = NIC_CFG_INSTR_TBL_ADDR;
    __xread uint32_t xwr_instr[NIC_MAX_INSTR];

    addr = addr + qid * NIC_MAX_INSTR * 4;

    cls_read(&xwr_instr, (__cls void *)addr, sizeof(xwr_instr));
    reg_cp((void *)_action_list, xwr_instr, sizeof(xwr_instr));
}

__intrinsic void
cfg_act_read_host(uint32_t pcie, uint32_t queue)
{
    cfg_act_read_queue((pcie << 6) | queue);
}

__intrinsic void
cfg_act_read_wire(const uint32_t pcie, uint32_t port)
{
    cfg_act_read_queue((1 << 8) | port);
}

static void parse_action_list(void)
{
    __gpr uint32_t i = 0;
    __gpr union instruction_format action;
    __gpr union instruction_format action_next;

    while ((_action_list[i].value != 0) && (i < NIC_MAX_INSTR))  {

        action = _action_list[i++];
        switch (action.op) {

            case INSTR_DROP:
                /* First instruction cannot be drop */
                test_assert_unequal(i - 1 , 0);
                /* Terminate processing */
                goto check_length;

            case INSTR_RX_WIRE:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_DST_MAC_MATCH);
                break;

            case INSTR_DST_MAC_MATCH:
                /* actions length: 2 words (note ++i below)*/
                action_next = _action_list[++i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_CHECKSUM);
                break;

            case INSTR_CHECKSUM:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_RSS);
                break;

           case INSTR_RSS:
                /* actions length: 2 words (note ++i below)*/
                action_next = _action_list[++i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_TX_HOST);
                break;

            case INSTR_TX_HOST:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_RX_HOST);
                break;

            case INSTR_RX_HOST:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_TX_WIRE);
                break;

            case INSTR_TX_WIRE:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_CMSG);
                break;

            case INSTR_CMSG:
                /* terminal action, no need to check pipeline bit*/
                /* Terminate processing */
                goto check_length;

            case INSTR_EBPF:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_POP_VLAN);
                break;

            case INSTR_POP_VLAN:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_PUSH_VLAN);
                break;

            case INSTR_PUSH_VLAN:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_SRC_MAC_MATCH);
                break;

            case INSTR_SRC_MAC_MATCH:
                /* actions length: 2 words (note ++i below)*/
                action_next = _action_list[++i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_VEB_LOOKUP);
                break;

            case INSTR_VEB_LOOKUP:
                /* actions length: 2 words (note ++i below)*/
                action_next = _action_list[++i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_POP_PKT);
                break;

            case INSTR_POP_PKT:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_PUSH_PKT);
                break;

            case INSTR_PUSH_PKT:
                /* actions length: 1 word*/
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action_next.op, INSTR_TX_VLAN);
                break;

            case INSTR_TX_VLAN:
                /* terminal action, no need to check pipeline bit*/
                /* Terminate processing */
                goto check_length;

            case INSTR_L2_SWITCH_WIRE:
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action.value, INSTR_L2_SWITCH_HOST);
                 break;

            case INSTR_L2_SWITCH_HOST:
                action_next = _action_list[i];
                if (action_next.pipeline)
                    test_assert_equal(action.value, 0);
                break;

            default:
                test_assert_equal(action.value, 0);
                break;

        }
    }

check_length:
    if (i > NIC_MAX_INSTR)
        test_assert_equal(i, NIC_MAX_INSTR);

}

void verify_host_action_list(const uint32_t pcie, uint32_t queue)
{
    cfg_act_read_host(pcie, queue);
    parse_action_list();
}

void verify_wire_action_list(const uint32_t pcie, uint32_t vnic)
{
    cfg_act_read_wire(pcie, vnic);
    parse_action_list();
}

