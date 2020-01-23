/*
 * Copyright (C) 2015-2020 Netronome Systems, Inc. All rights reserved.
 *
 * @file          apps/nic/app_config_tables.h
 * @brief         Header file for App Config ME local functions/declarations
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _APP_CONFIG_TABLES_H_
#define _APP_CONFIG_TABLES_H_

#include <app_config_instr.h>
#include <app_mac_vlan_config_cmsg.h>

/* from linux errno-base.h */
#define ENOSPC  28
#define EINVAL  22

enum cfg_msg_err {
    NO_ERROR = 0,

    /* Note: Negative values are errors. */
    MAC_VLAN_ADD_FAIL = ENOSPC,
    MAC_VLAN_WRONG_VF = -2,

    /* Note: Positive values are warnings. */
    MAC_VLAN_DELETE_WARN = 1,
};

/* MAC address building macros */
#define MAC64_FROM_SRIOV_CFG(cfg)     (((uint64_t) (cfg).mac_hi << 16) | (cfg).mac_lo)
#define MAC64_FROM_VEB_KEY(key)       (((uint64_t) (key).mac_addr_hi << 32) | (key).mac_addr_lo)
#define VEB_KEY_FROM_MAC64(key, mac)  do { \
    key.__raw[0] = 0; \
    key.mac_addr_hi = mac >> 32; \
    key.mac_addr_lo = mac; \
} while (0);

typedef struct {
    union instruction_format instr[NIC_MAX_INSTR];
    uint32_t count;
    uint32_t prev;
} __lmem __shared action_list_t;

void cfg_act_build_vf(action_list_t *acts, uint32_t pcie, uint32_t vid,
                      uint32_t pf_control, uint32_t vf_control);

void cfg_act_build_pf(action_list_t *acts, uint32_t pcie, uint32_t vid,
                      uint32_t veb_up, uint32_t control, uint32_t update);

void cfg_act_build_ctrl(action_list_t *acts, uint32_t pcie, uint32_t vid);

void cfg_act_build_veb_vf(action_list_t *acts, uint32_t pcie, uint32_t vid,
                          uint32_t pf_control, uint32_t vf_control,
                          uint32_t update);

void cfg_act_build_veb_pf(action_list_t *acts, uint32_t pcie, uint32_t vid,
                          uint32_t control, uint32_t update);

void cfg_act_write_host(uint32_t pcie, uint32_t vid, action_list_t *acts);

void cfg_act_build_nbi(action_list_t *acts, uint32_t pcie, uint32_t vid,
                       uint32_t veb_up, uint32_t control, uint32_t update);

void cfg_act_write_wire(uint32_t port, action_list_t *acts);

void cfg_act_write_host(uint32_t pcie, uint32_t vid, action_list_t *acts);

void cfg_act_build_nbi_down(action_list_t *acts, uint32_t pcie, uint32_t vid);

void cfg_act_build_pcie_down(action_list_t *acts, uint32_t pcie, uint32_t vid);

enum cfg_msg_err cfg_act_write_veb(uint32_t vid,
                                   __lmem struct nic_mac_vlan_key *veb_key,
                                   action_list_t *acts);

int cfg_act_vf_up(uint32_t pcie, uint32_t vid, uint32_t pf_control,
                  uint32_t vf_control, uint32_t update);

int cfg_act_vf_down(uint32_t pcie, uint32_t vid);

int cfg_act_pf_up(uint32_t pcie, uint32_t vid, uint32_t veb_up,
                  uint32_t control, uint32_t update);

int cfg_act_pf_down(uint32_t pcie, uint32_t vid);
/**
 * Initialize app ME NN registers
 */
void init_nn_tables();

#endif /* _APP_CONFIG_TABLES_H_ */
