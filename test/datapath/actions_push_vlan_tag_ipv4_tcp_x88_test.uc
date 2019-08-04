/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xaaa

#include "pkt_ipv4_tcp_x88.uc"

#include "actions_harness.uc"
#include "single_ctx_test.uc"

.reg etype
.reg orig_offset
.reg orig_l3_offset
.reg orig_l4_offset
.reg orig_pkt_len
.reg exp_offset
.reg exp_l3_offset
.reg exp_l4_offset
.reg exp_pkt_len
.reg new_offset
.reg new_l3_offset
.reg new_l4_offset
.reg new_pkt_len
.reg pkt_addr
.sig sig_rd

local_csr_wr[T_INDEX, (32 * 4)]
nop
nop
nop

pv_get_length(orig_pkt_len, pkt_vec)
bitfield_extract(orig_l3_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_IP_bf))
bitfield_extract(orig_l4_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_L4_bf))
bitfield_extract(orig_offset, BF_AML(pkt_vec, PV_OFFSET_bf))

alu[exp_offset, orig_offset, -, 4]
alu[exp_l3_offset, orig_l3_offset, +, 4]
alu[exp_l4_offset, orig_l4_offset, +, 4]
alu[exp_pkt_len, orig_pkt_len, +, 4]

__actions_push_vlan(pkt_vec)

pv_get_length(new_pkt_len, pkt_vec)
bitfield_extract(new_l3_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_IP_bf))
bitfield_extract(new_l4_offset, BF_AML(pkt_vec, PV_HEADER_OFFSET_OUTER_L4_bf))
bitfield_extract(new_offset, BF_AML(pkt_vec, PV_OFFSET_bf))

test_assert_equal(new_offset, exp_offset)
test_assert_equal(new_l3_offset, exp_l3_offset)
test_assert_equal(new_l4_offset, exp_l4_offset)
test_assert_equal(new_pkt_len, exp_pkt_len)

bitfield_extract__sz1(pkt_addr, BF_AML(pkt_vec, PV_CTM_ADDR_bf)) ; PV_CTM_ADDR_bf
mem[read32, $__pv_pkt_data[0], pkt_addr, 0, 5], ctx_swap[sig_rd]
test_assert_equal($__pv_pkt_data[0], 0x00888888)
test_assert_equal($__pv_pkt_data[1], 0x99999999)
test_assert_equal($__pv_pkt_data[2], 0xaaaaaaaa)
test_assert_equal($__pv_pkt_data[3], 0x81000aaa)
ld_field_w_clr[etype, 0011, $__pv_pkt_data[4], >>16]
test_assert_equal(etype, 0x0800)

test_pass()
