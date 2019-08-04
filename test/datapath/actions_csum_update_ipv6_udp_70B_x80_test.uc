/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0xf
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_ipv6_udp_csums_zero_70B_x80.uc"

#include <single_ctx_test.uc>
#include <global.uc>
#include <bitfields.uc>

#macro test_read_csum(out_csum, in_offset)
.begin
    .reg addr
    .reg read $csum
    .sig sig_read

    move(addr, 0x80)
    mem[read8, $csum, addr, in_offset, 2], ctx_swap[sig_read]
    alu[out_csum, --, B, $csum, >>16]
.end
#endm


#macro test_write_csum(in_offset, in_csum)
.begin
    .reg addr
    .reg write $csum
    .sig sig_write

    move(addr, 0x80)
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
test_read_csum(csum, 0x3c)
test_assert_equal(csum, 0)

// test outer L4 checksum update (zero in packet)
bits_set__sz1(BF_AL(pkt_vec, PV_CSUM_OFFLOAD_OL4_bf), 1)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x3c)
test_assert_equal(csum, 0x7ce3)

// test outer L4 checksum update (garbage in packet)
immed[csum, 0x1234]
test_write_csum(0x3c, csum)
test_action_reset()
__actions_checksum(pkt_vec)
test_assert_equal(*$index, 0xdeadbeef)
test_read_csum(csum, 0x3c)
test_assert_equal(csum, 0x7ce3)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
