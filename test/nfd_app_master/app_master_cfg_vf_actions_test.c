/*
    app_master_cfg_vf_actions_test

    verify that cfg_act_build_veb sets up correct action list
    for vf port
*/

#include "test.c"

#include <config.h>
#include <app_config_instr.h>
#include <app_config_tables.h>
#include <nfd_cfg.h>
#include <nfd_common.h>
#include <nfd_user_cfg.h>
#include <nfd_vf_cfg_iface_abi2.h>
#include <nfp_net_ctrl.h>
#include <nic_tables.h>

extern void
cfg_act_build_veb_vf(action_list_t *acts, uint32_t pcie, uint32_t vid,
                     uint32_t pf_control, uint32_t vf_control, uint32_t update);

#define NET_ETH_LEN 14

#define SET_PIPELINE_BIT(prev, current) \
    ((current) - (prev) == 1) ? 1 : 0;

void main() {

    int count, rv, pass;
    int vid = 1;
    uint32_t mtu = 9216;
    __xwrite uint32_t mtu_xfr = mtu;
    uint32_t pf_control, vf_control;
    uint32_t update = 0x0;
    __emem __addr40 uint8_t *bar_base = NFD_CFG_BAR_ISL(NIC_PCI, vid);
    __lmem union instruction_format exp[NIC_MAX_INSTR];
    __xrw struct nfp_vnic_setup_entry entry;
    action_list_t acts;

    single_ctx_test();

    nic_tables_init();

    mem_write32(&mtu_xfr, (__mem void*)(bar_base + NFP_NET_CFG_MTU),
                sizeof(mtu));

    entry.src_mac = 0x12345678;

    /* 2 passes */
    for ( pass = 0; pass <= 1; pass++ ) {

        reg_zero(exp, sizeof(exp));
        vf_control = 0;

        switch ( pass ) {

        /* csum complete, vlan configured */
        case 0:
            pf_control = NFP_NET_CFG_CTRL_CSUM_COMPLETE;
            entry.vlan = 32;
            entry.spoof_chk = 0;
            entry.link_state_mode = 2;
            exp[0].op = INSTR_POP_VLAN;
            exp[1].op = INSTR_CHECKSUM;
            exp[1].args = 0x6;
            exp[1].pipeline =
                SET_PIPELINE_BIT(INSTR_POP_VLAN, INSTR_CHECKSUM);
            exp[2].op = INSTR_TX_HOST;
            exp[2].args = NFD_VID2QID(vid, 0);
            exp[2].pipeline =
                SET_PIPELINE_BIT(INSTR_CHECKSUM, INSTR_TX_HOST);
            exp[3].value = 0;
            break;

        /* csum complete, no vlan configured */
        case 1:
            pf_control = NFP_NET_CFG_CTRL_CSUM_COMPLETE;
            entry.vlan = NIC_NO_VLAN_ID;
            entry.spoof_chk = 0;
            entry.link_state_mode = 2;
            exp[0].op = INSTR_CHECKSUM;
            exp[0].args = 0x6;
            exp[1].op = INSTR_TX_HOST;
            exp[1].args = NFD_VID2QID(vid, 0);
            exp[1].pipeline =
                SET_PIPELINE_BIT(INSTR_CHECKSUM, INSTR_TX_HOST);
            exp[2].value = 0;
            break;

        default:
            test_assert_equal(pass, 1);
            break;
        }

        rv = write_vnic_setup_entry(vid, &entry);
        assert(!rv);

        cfg_act_build_veb_vf(&acts, 0, vid, pf_control, vf_control, update);

        for (count = 0; count < 3; count++)
            test_assert_equal(acts.instr[count].value, exp[count].value);

    }

    test_pass();
}
