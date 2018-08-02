/*
    app_master_cfg_vf_actions_test

    verify that app_config_sriov_port sets up correct action list
    for vf port
*/

#include "test.c"

#include <config.h>
#include <app_config_instr.h>
#include <nfd_cfg.h>
#include <nfd_common.h>
#include <nfd_user_cfg.h>
#include <nfd_vf_cfg_iface_abi2.h>
#include <nfp_net_ctrl.h>
#include <nic_tables.h>

extern void
app_config_sriov_port(uint32_t vid, __lmem uint32_t *action_list,
                      uint32_t control, uint32_t update);

#define NET_ETH_LEN 14

#define SET_PIPELINE_BIT(prev, current) \
    ((current) - (prev) == 1) ? 1 : 0;

void main() {

    int i, rv, pass;
    int vid = 1;
    uint32_t mtu = 9216;
    __xwrite uint32_t mtu_xfr = mtu;
    uint32_t control;
    uint32_t update = 0x0;
    __emem __addr40 uint8_t *bar_base = NFD_CFG_BAR_ISL(NIC_PCI, vid);
    __lmem union instruction_format actions[NIC_MAX_INSTR], exp[NIC_MAX_INSTR];
    __xrw struct nfp_vnic_setup_entry entry;

    single_ctx_test();

    nic_tables_init();

    mem_write32(&mtu_xfr, (__mem void*)(bar_base + NFP_NET_CFG_MTU),
                sizeof(mtu));

    entry.src_mac = 0x12345678;

    /* 4 passes */
    for ( pass = 0; pass <= 3; pass++ ) {

        reg_zero(actions, sizeof(actions));
        reg_zero(exp, sizeof(exp));

        switch ( pass ) {

        /* csum complete, vlan configured */
        case 0:
            control = NFP_NET_CFG_CTRL_CSUM_COMPLETE;
            entry.vlan = 32;
            entry.spoof_chk = 0;
            entry.link_state_mode = 2;
            exp[0].instr = INSTR_POP_VLAN;
            exp[1].instr = INSTR_CHECKSUM_COMPLETE;
            exp[2].instr = INSTR_TX_HOST;
            exp[2].param = NFD_VID2QID(vid, 0);
            exp[2].pipeline =
                SET_PIPELINE_BIT(INSTR_CHECKSUM_COMPLETE, INSTR_TX_HOST);
            break;

        /* no csum complete, vlan configured */
        case 1:
            control = 0;
            entry.vlan = 32;
            entry.spoof_chk = 0;
            entry.link_state_mode = 2;
            exp[0].instr = INSTR_POP_VLAN;
            exp[1].instr = INSTR_TX_HOST;
            exp[1].param = NFD_VID2QID(vid, 0);
            exp[1].pipeline =
                SET_PIPELINE_BIT(INSTR_POP_VLAN, INSTR_TX_HOST);
            exp[2].value = 0;
            break;

        /* csum complete, no vlan configured */
        case 2:
            control = NFP_NET_CFG_CTRL_CSUM_COMPLETE;
            entry.vlan = NIC_NO_VLAN_ID;
            entry.spoof_chk = 0;
            entry.link_state_mode = 2;
            exp[0].instr = INSTR_CHECKSUM_COMPLETE;
            exp[1].instr = INSTR_TX_HOST;
            exp[1].param = NFD_VID2QID(vid, 0);
            exp[1].pipeline =
                SET_PIPELINE_BIT(INSTR_CHECKSUM_COMPLETE, INSTR_TX_HOST);
            exp[2].value = 0;
            break;

        /* no csum complete, no vlan configured */
        case 3:
            control = 0;
            entry.vlan = NIC_NO_VLAN_ID;
            entry.spoof_chk = 0;
            entry.link_state_mode = 2;
            exp[0].instr = INSTR_TX_HOST;
            exp[0].param = NFD_VID2QID(vid, 0);
            exp[0].pipeline =
                SET_PIPELINE_BIT(INSTR_POP_VLAN, INSTR_TX_HOST);
            exp[1].value = 0;
            exp[2].value = 0;
            break;

        default:
            test_assert_equal(pass, 1);
            break;
        }

        rv = write_vnic_setup_entry(vid, &entry);
        assert(!rv);

        app_config_sriov_port(vid, &actions[0].value, control, update);

        for (i = 0; i < sizeof(actions) / sizeof(uint32_t); i++)
            test_assert_equal(actions[i].value, exp[i].value);

    }

    test_pass();
}
