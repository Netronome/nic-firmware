/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xeeeeeee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xeeeeeee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xdeadbeef
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0xdeadbeef

#include "pkt_ipv4_udp_x88.uc"
#include <global.uc>
#include "actions_harness.uc"
#include "actions_classify_veb_insertion.uc"

.reg expected_pv_broadcast
.reg key[2]
.reg action[2]
.reg entries
.reg tmp
.reg $mem_wr
.sig wr_sig

#define TEST_ENTRIES 2000

#define KEY_LO 0xFFF00011
#define KEY_HI 0
#define ACT_LO 0xFFFF0000
#define ACT_HI 0xFFFF0000

move(key[0], KEY_LO)
move(key[1], KEY_HI)
move(action[0], ACT_LO)
move(action[1], ACT_HI)

alu[entries, --, B, 0]

move(expected_pv_broadcast, NULL_VLAN<<BF_L(PV_VLAN_ID_bf))

.while(entries < TEST_ENTRIES)

	//modify packet to match modified key
	move($mem_wr, key[1])
	mem[write32, $mem_wr, BF_A(pkt_vec, PV_CTM_ADDR_bf), 2, 1], ctx_swap[wr_sig]

	veb_entry_insert(key, action, continue#)
continue#:

    local_csr_wr[T_INDEX, (32 * 4)]
	immed[__actions_t_idx, (32 * 4)]

	alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
	nop
	local_csr_wr[T_INDEX, __actions_t_idx]
    nop
    nop
    nop

	__actions_veb_lookup(pkt_vec, discards_filter_mac#)

    //test_assert_equal(pkt_vec[PV_VLAN_wrd], expected_pv_broadcast)

	ld_field_w_clr[tmp, 0001, action[0], >>24]
	ld_field[tmp, 0010, action[0], >>8]
	ld_field[tmp, 0100, action[0], <<8]
	ld_field[tmp, 1000, action[0], <<24]

	test_assert_equal($__actions[0], tmp)
	test_assert_equal(*$index++, tmp)

	ld_field[tmp, 0001, action[1], >>24]
	ld_field[tmp, 0010, action[1], >>8]
	ld_field[tmp, 0100, action[1], <<8]
	ld_field[tmp, 1000, action[1], <<24]

	test_assert_equal($__actions[1], tmp)
	test_assert_equal(*$index++, tmp)

	alu_op(key[1], key[1], +, 1)
	alu_op(action[0], action[0], +, 1)

	alu[entries, entries, +, 1]

.endw

test_pass()

discards_filter_mac#:
error_map_fd#:
lookup_not_found#:
test_fail()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
