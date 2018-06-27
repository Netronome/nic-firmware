/*
    app_master_cfg_sriov_update_mac_test

    verify handle_sriov_update update mac operation
*/

#include "test.c"

#include <nfp/mem_ring.h>
#include <pkt/pkt.h>
#include <config.h>
#include <app_config_instr.h>
#include <nic_tables.h>
#include <nfd_cfg.h>
#include <nfd_user_cfg.h>
#include <nfd_common.h>
#include <nfd_vf_cfg_iface_abi2.h>
#include <app_mac_vlan_config_cmsg.h>
#include <maps/cmsg_map_types.h>

/* stub allocation of _pf0_net_vf_cfg2 usually in nfd_svc.list, from
   file nfd_vf_cfg_iface.uc at macro nfd_vf_cfg_declare() */
__declspec(shared export emem0 aligned(NFD_VF_CFG_SZ)) \
  char pf0_net_vf_cfg2[NFD_VF_CFG_MB_SZ + (NFD_MAX_VFS * NFD_VF_CFG_SZ)];

#define CMSG_DESC_LW 3

#define VEB_KEY_MAC_HI_FROM_BAR(_hi)      (((_hi) >> 16) & 0xffff)
#define VEB_KEY_MAC_LO_FROM_BAR(_hi, _lo) ((((_hi) << 16) & 0xffff0000) | (_lo))

#define NET_ETH_LEN 14

#define SET_PIPELINE_BIT(prev, current) \
    ((current) - (prev) == 1) ? 1 : 0;

extern void
handle_sriov_update(uint32_t pf_vid, uint32_t pf_control, uint32_t pf_update);

__cls __align(4) struct ctm_pkt_credits pkt_buf_ctm_credits;

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

    uint32_t pf_vid = 1;
    uint32_t pf_control = 1;
    uint32_t pf_update = 1;
    uint32_t vlan_id = 4090;
    int i,j,pass;
    __gpr struct sriov_mb sriov_mb_data;
    __xwrite struct sriov_mb sriov_mb_data_xfr;
    __gpr struct sriov_cfg sriov_cfg_data;
    __xwrite struct sriov_cfg sriov_cfg_data_xfr;
    __gpr struct nfp_vnic_setup_entry entry;
    __xrw struct nfp_vnic_setup_entry entry_xfr;
    __emem __addr40 uint8_t *vf_cfg_base = NFD_VF_CFG_BASE_LINK(NIC_PCI);
    __xread struct nic_mac_vlan_cmsg cmsg_data;
    __gpr struct nic_mac_vlan_key vlan_key_exp;
    unsigned int q_idx;
    mem_ring_addr_t q_base;
    __xread uint32_t workq_data[CMSG_DESC_LW];
    uint32_t ctm_pnum;
    uint32_t emem_dst;
    uint32_t exp, val;
    uint32_t prev_mac_lo, prev_mac_hi;
    __addr40 uint8_t *emem_ptr;
    uint32_t mtu = 9216;
    __xwrite uint32_t mtu_xfr = mtu;
    __emem __addr40 uint8_t *bar_base = NFD_CFG_BAR_ISL(NIC_PCI, pf_vid);
    __xread union instruction_format actions_xfr[NIC_MAX_INSTR];
    __lmem union instruction_format actions_exp[NIC_MAX_INSTR];


    single_ctx_test();

    /* init ctm buf credits for usein nic_mac_vlan_entry_op_cmsg */
    pkt_ctm_init_credits(&pkt_buf_ctm_credits, 20, 20);

    /* init blm */
    blm_test_init();

    /* init mtu */
    mem_write32(&mtu_xfr, (__mem void*)(bar_base + NFP_NET_CFG_MTU),
                sizeof(mtu));


    /* clear vnic set up table */
    nic_tables_init();

    /* init vnic setup entry */
    reg_zero(&entry, sizeof(entry));
    entry.src_mac = 0;
    entry.vlan = vlan_id;
    entry.spoof_chk = 0;
    entry.link_state_mode = NFD_VF_CFG_CTRL_LINK_STATE_AUTO;
    entry_xfr = entry;
    if ( write_vnic_setup_entry(pf_vid, &entry_xfr)
         == -1 )
        test_fail();

    /*
      pass 0: set up mac entry when none already setup
      pass 1: setup a new mac address, so the one setup
                 during pass 0 has to be deleted
      pass 2: send in the same mac address already setup
    */

    for (pass = 0; pass <= 2; pass++) {

        /* init cfg mailbox entry */

        reg_zero(&sriov_mb_data, sizeof(sriov_mb_data));
        sriov_mb_data.vf = pf_vid;
        sriov_mb_data.update_flags = NFD_VF_CFG_MB_CAP_MAC;
        sriov_mb_data_xfr = sriov_mb_data;
        mem_write32(&sriov_mb_data_xfr, vf_cfg_base, sizeof(struct sriov_mb));

        reg_zero(&sriov_cfg_data, sizeof(sriov_cfg_data));
        if ( pass == 0 ) {
            sriov_cfg_data.mac_hi = 0x12345678;
            sriov_cfg_data.mac_lo = 0x5566;
        } else {
            sriov_cfg_data.mac_hi = 0xdeadface;
            sriov_cfg_data.mac_lo = 0xa5a5;
        }
        sriov_cfg_data.ctrl_trusted = 1;
        sriov_cfg_data.ctrl_rss = 0;
        sriov_cfg_data.ctrl_spoof = 0;
        sriov_cfg_data.ctrl_link_state = NFD_VF_CFG_CTRL_LINK_STATE_ENABLE;
        sriov_cfg_data_xfr = sriov_cfg_data;
        mem_write32(&sriov_cfg_data_xfr,
                    NFD_VF_CFG_ADDR(vf_cfg_base, sriov_mb_data.vf),
                    sizeof(struct sriov_cfg));

        /* invoke the handler routine */

        handle_sriov_update(pf_vid, pf_control, pf_update);


        /* check format of ctrl msg request in nfd workq for
           pass 0 and 1. For pass 2, the mac address isn't
           changed so there should be no table updates */

        if ( pass < 2 ) {

            /* for pass 1, there are two requests. the 1st is
               to add a new mac entry, and the 2nd is to delete
               the old entry */

            for ( j = 0; j < 2; j++ ) {

                /* check workq */

                q_idx = _link_sym(MAP_CMSG_Q_IDX);
                q_base = (_link_sym(MAP_CMSG_Q_BASE) >> 8) & 0xff000000;
                mem_workq_add_thread(q_idx, q_base, &workq_data,
                                     sizeof(workq_data));

                ctm_pnum = workq_data[0] >> 16;
                exp = ((__ISLAND<<26) | (ctm_pnum<<16));
                test_assert_equal(workq_data[0], exp);

                emem_dst = workq_data[1];
                exp = emem_dst; /* (useless test) */
                test_assert_equal(workq_data[1], exp);

                exp = SRIOV_QUEUE<<16;
                test_assert_equal(workq_data[2], exp);


                /* check format of ctrl mssg in emem */

                emem_ptr = (__mem uint8_t *)((uint64_t)emem_dst << 11) +
                    NFD_IN_DATA_OFFSET;
                mem_read32_swap(&cmsg_data, emem_ptr, sizeof(cmsg_data));

                if ( j == 1 )
                    test_assert_equal(cmsg_data.word0, CMSG_TYPE_MAP_DELETE |
                                      (CMSG_MAP_VERSION<<8));
                else
                    test_assert_equal(cmsg_data.word0, CMSG_TYPE_MAP_ADD |
                                      (CMSG_MAP_VERSION<<8));

                test_assert_equal(cmsg_data.tid, SRIOV_TID<<24);
                test_assert_equal(cmsg_data.count, 0);
                test_assert_equal(cmsg_data.flags, 0);

                vlan_key_exp.__raw[0] = 0;
                vlan_key_exp.__raw[1] = 0;
                vlan_key_exp.vlan_id = entry.vlan;
                if ( j == 1 ) {
                    vlan_key_exp.mac_addr_hi =
                        VEB_KEY_MAC_HI_FROM_BAR(prev_mac_hi);
                    vlan_key_exp.mac_addr_lo =
                        VEB_KEY_MAC_LO_FROM_BAR(prev_mac_hi, prev_mac_lo);
                } else {
                    vlan_key_exp.mac_addr_hi =
                        VEB_KEY_MAC_HI_FROM_BAR(sriov_cfg_data.mac_hi);
                    vlan_key_exp.mac_addr_lo =
                        VEB_KEY_MAC_LO_FROM_BAR(sriov_cfg_data.mac_hi,
                                                sriov_cfg_data.mac_lo);
                }
                test_assert_equal(cmsg_data.key.__raw[0], vlan_key_exp.__raw[0]);
                test_assert_equal(cmsg_data.key.__raw[1], vlan_key_exp.__raw[1]);


                /* check the action list in emem */

                emem_ptr = (__mem uint8_t *)((uint64_t)emem_dst << 11) +
                    NFD_IN_DATA_OFFSET + 80;
                mem_read32(&actions_xfr, emem_ptr, sizeof(actions_xfr));

                reg_zero(actions_exp, sizeof(actions_exp));
                actions_exp[0].instr = INSTR_RX_VEB;
                actions_exp[0].param = mtu + NET_ETH_LEN + 1;
                actions_exp[1].instr = INSTR_STRIP_VLAN;
                actions_exp[1].pipeline = 0;
                actions_exp[2].instr = INSTR_TX_HOST;
                actions_exp[2].param = NFD_VID2QID(pf_vid, 0);
                actions_exp[2].pipeline =
                    SET_PIPELINE_BIT(INSTR_STRIP_VLAN, INSTR_TX_HOST);
                actions_exp[3].value = 0;

                for (i = 0; i < sizeof(actions_exp) / sizeof(uint32_t); i++)
                    test_assert_equal(actions_xfr[i].value,
                                      actions_exp[i].value);

                if ( pass != 1 ) /* only have 2 requests during pass 1 */
                    break;
            }

        } /* for pass 0,1

        /* save mac addr for next pass */
        prev_mac_hi = sriov_cfg_data.mac_hi;
        prev_mac_lo = sriov_cfg_data.mac_lo;


        /* check update to vnic setup entry */

        reg_zero(&entry, sizeof(entry));
        if ( pass == 0 ) {
            entry.src_mac = (uint64_t)0x12345678 << 32;
            entry.src_mac = entry.src_mac | (uint64_t)0x00005566;
        } else {
            entry.src_mac = (uint64_t)0xdeadface << 32;
            entry.src_mac = entry.src_mac | (uint64_t)0x0000a5a5;
        }
        entry.vlan = vlan_id;
        entry.spoof_chk = 0;
        entry.link_state_mode = NFD_VF_CFG_CTRL_LINK_STATE_AUTO;

        load_vnic_setup_entry(pf_vid, &entry_xfr);

        test_assert_equal(entry_xfr.__raw[0], entry.__raw[0]);
        test_assert_equal(entry_xfr.__raw[1], entry.__raw[1]);
        test_assert_equal(entry_xfr.__raw[2], entry.__raw[2]);
        test_assert_equal(entry_xfr.__raw[3], entry.__raw[3]);

    }

    test_pass();
}
