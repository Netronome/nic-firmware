/*
    nic_tables_test

    test operation of nic_tables.c code
*/

#include "test.c"

#include <vnic/nfd_common.h>
#include <config.h>
#include <nfd_user_cfg.h>
#include <nic_tables.h>

void main() {

    uint32_t i, j;
    int rv;
    __xrw uint32_t phys_port;
    __xrw uint64_t members;
    uint64_t members_exp;
    __xrw struct nfp_vnic_setup_entry entry;
    struct nfp_vnic_setup_entry entry_exp;
    __xwrite uint32_t rxb_xfr;
    __emem __addr40 uint8_t *bar_base = NFD_CFG_BAR_ISL(NIC_PCI, i);


    single_ctx_test();

    nic_tables_init();

    rxb_xfr = 0;
    mem_write32(&rxb_xfr, (__mem void*)(bar_base + NFP_NET_CFG_FLBUFSZ),
                sizeof(rxb_xfr));

    /* vnic setup entries */

    entry_exp.__raw[0] = 0;
    entry_exp.__raw[1] = 0;
    entry_exp.__raw[2] = 0;
    entry_exp.__raw[3] = 0;
    entry_exp.src_mac = 0xabcd1234;
    entry_exp.spoof_chk = 0;
    entry_exp.link_state_mode = 2;

    for (i = 0; i < 4; i++) {

        entry_exp.vlan = i;

        entry = entry_exp;

        rv = write_vnic_setup_entry(i, &entry);
        assert(!rv);

        rv = load_vnic_setup_entry(i, &entry);
        assert(!rv);

        for (j = 0; j < 4; j++)
            test_assert_equal(entry.__raw[j], entry_exp.__raw[j]);
    }


    /* vlan vnic members bitmap */

    for (i = 0; i < 4096; i++) {
        members_exp = 0;
        for (j = 0; j < 2; j++) {
            mem_write32(&rxb_xfr, (__mem void*)(bar_base + NFP_NET_CFG_FLBUFSZ),
                        sizeof(rxb_xfr));
            rv = add_vlan_member(i, j);
            assert(!rv);
            rv = load_vlan_members(i, &members);
            assert(!rv);
            members_exp |= 1 << j;
            test_assert_equal(members, members_exp);
        }
    }

    for (i = 0; i < 4096; i++) {
        //members_exp = -1;
        members_exp = 3;
        for (j = 0; j < 2; j++) {
            rv = remove_vlan_member(i, j);
            assert(!rv);
            rv = load_vlan_members(i, &members);
            assert(!rv);
            members_exp &= ~(1 << j);
            test_assert_equal(members, members_exp);
        }
    }

    test_pass();
}
