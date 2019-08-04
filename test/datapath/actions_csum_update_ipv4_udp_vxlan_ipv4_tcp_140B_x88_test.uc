/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xf
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_ipv4_udp_vxlan_ipv4_tcp_csums_zero_140B_x88.uc"

#include <single_ctx_test.uc>
#include <global.uc>
#include <bitfields.uc>

#macro test_read_csum(out_csum, in_offset)
.begin
    .reg addr
    .reg read $csum
    .sig sig_read

    move(addr, 0x88)
    mem[read8, $csum, addr, in_offset, 2], ctx_swap[sig_read]
    alu[out_csum, --, B, $csum, >>16]
.end
#endm


#macro test_write_csum(in_offset, in_csum)
.begin
    .reg addr
    .reg write $csum
    .sig sig_write

    move(addr, 0x88)
    alu[$csum, --, B, in_csum, <<16]
    mem[write8, $csum, addr, in_offset, 2], ctx_swap[sig_write]
.end
#endm
.reg csum

// test noop
bits_clr__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_bf), 0xf)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0)

// test outer L3 checksum update (zero in packet)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_OL3_bf), 1)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0x5064)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0)

// test outer L3 checksum update (garbage in packet)
immed[csum, 0x1234]
test_write_csum(0x18, csum)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0x5064)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0)

// test outer L4 checksum update (zero in packet)
bits_clr__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_bf), 0xf)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_OL4_bf), 1)
test_action_reset()
test_write_csum(0x18, 0)
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0x928b)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0)

// test outer L4 checksum update (garbage in packet)
immed[csum, 0x1234]
test_write_csum(0x28, csum)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0x928b)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0)

// add L3 checksum updates (zero in packet)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_OL3_bf), 1)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_IL3_bf), 1)
test_write_csum(0x28, 0)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0x5064)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0x1df9)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0x7492)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0)

// test inner L3 checksum update (garbage in packet)
immed[csum, 0x1234]
test_write_csum(0x4a, csum)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0x5064)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0x1df9)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0x7492)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0)

// test inner L4 checksum update (zero in packet)
bits_clr__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_bf), 0xf)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_IL3_bf), 1)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_IL4_bf), 1)
test_write_csum(0x18, 0)
test_write_csum(0x28, 0)
test_write_csum(0x4a, 0)
test_write_csum(0x64, 0)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0x7492)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0x5106)

// test inner L4 checksum update (garbage in packet)
immed[csum, 0x1234]
test_write_csum(0x64, csum)
test_write_csum(0x4a, csum)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0x7492)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0x5106)

// test all checksum updates (zero in packet)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_bf), 0xf)
immed[csum, 0]
test_write_csum(0x18, csum)
test_write_csum(0x28, csum)
test_write_csum(0x4a, csum)
test_write_csum(0x64, csum)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x18)
test_assert_equal(csum, 0x5064)
test_read_csum(csum, 0x28)
test_assert_equal(csum, 0xccf2)
test_read_csum(csum, 0x4a)
test_assert_equal(csum, 0x7492)
test_read_csum(csum, 0x64)
test_assert_equal(csum, 0x5106)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
