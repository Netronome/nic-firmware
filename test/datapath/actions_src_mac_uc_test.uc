/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x9012
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x12345678

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0x9012
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0x12345678

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_36=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_37=0xdeadbeef

#include "pkt_ipv4_udp_x88_src_mac.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>

.reg pkt_len
.reg ctm_base
.reg pkt_ctm_src_mac_byte
.reg ctm_scratch
.reg ctm_scratch_byte
.sig pkt_sig
.reg $byte_new
.reg $byte_old
.reg $list_mod

/* Packet starts at 0x80 */
immed[ctm_base, 0]
immed[ctm_scratch, 0x1000]
immed[pkt_ctm_src_mac_byte, 0x8e]

/* We modify each byte in turn */
move($byte_new, 0xFF000000)

pv_get_length(pkt_len, pkt_vec)
pv_invalidate_cache(pkt_vec)

/*---------------------------*/

test_action_reset()

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x9012)
test_assert_equal($__actions[1], 0x12345678)

/*
 * The MAC will match so should not be dropped.
 * Packet: 12:34:56:78:90:12
 * Action: 12:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_unexpected_error#)

/*---------------------------*/

/* Change packet byte 1 */
test_action_reset()

/* Modify packet byte */
mem[read8, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
pv_invalidate_cache(pkt_vec)

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x9012)
test_assert_equal($__actions[1], 0x12345678)

/*
 * The MAC will not match so should be dropped.
 * Packet: FF:34:56:78:90:12
 * Action: 12:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_expected_pass1#)
test_fail()
drop_expected_pass1#:

/* Modify the second instruction */
move($list_mod, $__actions[3])
alu[ctm_scratch_byte, ctm_scratch, +, 0]
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, ctm_scratch_byte, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[2], 0x9012)
test_assert_equal($__actions[3], 0xFF345678)

/*
 * The MAC will match so should not be dropped.
 * Packet: FF:34:56:78:90:12
 * Action: FF:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_unexpected_error#)

/* Restore action */
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Restore Packet */
move($byte_old,$byte_old)
mem[write8_be, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]

/*---------------------------*/

alu[pkt_ctm_src_mac_byte, pkt_ctm_src_mac_byte, + ,1]

/* Change packet byte 2 */
test_action_reset()

/* Modify packet byte */
mem[read8, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
pv_invalidate_cache(pkt_vec)

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x9012)
test_assert_equal($__actions[1], 0x12345678)

/*
 * The MAC will not match so should be dropped.
 * Packet: 12:FF:56:78:90:12
 * Action: 12:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_expected_pass2#)
test_fail()
drop_expected_pass2#:

/* Modify the second instruction */
move($list_mod, $__actions[3])
alu[ctm_scratch_byte, ctm_scratch, +, 1]
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, ctm_scratch_byte, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[2], 0x9012)
test_assert_equal($__actions[3], 0x12FF5678)

/*
 * The MAC will match so should not be dropped.
 * Packet: 12:FF:56:78:90:12
 * Action: 12:FF:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_unexpected_error#)

/* Restore action */
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Restore Packet */
move($byte_old,$byte_old)
mem[write8_be, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]

/*---------------------------*/

alu[pkt_ctm_src_mac_byte, pkt_ctm_src_mac_byte, + ,1]

/* Change packet byte 3 */
test_action_reset()

/* Modify packet byte */
mem[read8, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
pv_invalidate_cache(pkt_vec)

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x9012)
test_assert_equal($__actions[1], 0x12345678)

/*
 * The MAC will not match so should be dropped.
 * Packet: 12:34:FF:78:90:12
 * Action: 12:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_expected_pass3#)
test_fail()
drop_expected_pass3#:

/* Modify the second instruction */
move($list_mod, $__actions[3])
alu[ctm_scratch_byte, ctm_scratch, +, 2]
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, ctm_scratch_byte, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[2], 0x9012)
test_assert_equal($__actions[3], 0x1234FF78)

/*
 * The MAC will match so should not be dropped.
 * Packet: 12:34:FF:78:90:12
 * Action: 12:34:FF:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_unexpected_error#)

/* Restore action */
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Restore Packet */
move($byte_old,$byte_old)
mem[write8_be, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]

/*---------------------------*/

alu[pkt_ctm_src_mac_byte, pkt_ctm_src_mac_byte, + ,1]

/* Change packet byte 4 */
test_action_reset()

/* Modify packet byte */
mem[read8, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
pv_invalidate_cache(pkt_vec)

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x9012)
test_assert_equal($__actions[1], 0x12345678)

/*
 * The MAC will not match so should be dropped.
 * Packet: 12:34:56:FF:90:12
 * Action: 12:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_expected_pass4#)
test_fail()
drop_expected_pass4#:

/* Modify the second instruction */
move($list_mod, $__actions[3])
alu[ctm_scratch_byte, ctm_scratch, +, 3]
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, ctm_scratch_byte, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[2], 0x9012)
test_assert_equal($__actions[3], 0x123456FF)

/*
 * The MAC will match so should not be dropped.
 * Packet: 12:34:56:FF:90:12
 * Action: 12:34:56:FF:90:12
 */
__actions_src_mac_match(pkt_vec, drop_unexpected_error#)

/* Restore action */
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[3], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Restore Packet */
move($byte_old,$byte_old)
mem[write8_be, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]

/*---------------------------*/

alu[pkt_ctm_src_mac_byte, pkt_ctm_src_mac_byte, + ,1]

/* Change packet byte 5 */
test_action_reset()

/* Modify packet byte */
mem[read8, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
pv_invalidate_cache(pkt_vec)

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x9012)
test_assert_equal($__actions[1], 0x12345678)

/*
 * The MAC will not match so should be dropped.
 * Packet: 12:34:56:78:FF:12
 * Action: 12:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_expected_pass5#)
test_fail()
drop_expected_pass5#:

/* Modify the second instruction */
move($list_mod, $__actions[2])
alu[ctm_scratch_byte, ctm_scratch, +, 2]
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, ctm_scratch_byte, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[2], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[2], 0xFF12)
test_assert_equal($__actions[3], 0x12345678)

/*
 * The MAC will match so should not be dropped.
 * Packet: 12:34:56:78:FF:12
 * Action: 12:34:56:78:FF:12
 */
__actions_src_mac_match(pkt_vec, drop_unexpected_error#)

/* Restore action */
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[2], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Restore Packet */
move($byte_old,$byte_old)
mem[write8_be, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]

/*---------------------------*/

alu[pkt_ctm_src_mac_byte, pkt_ctm_src_mac_byte, + ,1]

/* Change packet byte 6 */
test_action_reset()

/* Modify packet byte */
mem[read8, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]
pv_invalidate_cache(pkt_vec)

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[0], 0x9012)
test_assert_equal($__actions[1], 0x12345678)

/*
 * The MAC will not match so should be dropped.
 * Packet: 12:34:56:78:90:FF
 * Action: 12:34:56:78:90:12
 */
__actions_src_mac_match(pkt_vec, drop_expected_pass6#)
test_fail()
drop_expected_pass6#:

/* Modify the second instruction */
move($list_mod, $__actions[2])
alu[ctm_scratch_byte, ctm_scratch, +, 3]
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[write8_be, $byte_new, ctm_base, ctm_scratch_byte, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[2], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Ensure the action list is setup for this test */
test_assert_equal($__actions[2], 0x90FF)
test_assert_equal($__actions[3], 0x12345678)

/*
 * The MAC will match so should not be dropped.
 * Packet: 12:34:56:78:90:FF
 * Action: 12:34:56:78:90:FF
 */
__actions_src_mac_match(pkt_vec, drop_unexpected_error#)

/* Restore action */
mem[write32, $list_mod, ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]
mem[read32, $__actions[2], ctm_base, ctm_scratch, 1], ctx_swap[pkt_sig]

/* Restore Packet */
move($byte_old,$byte_old)
mem[write8_be, $byte_old, ctm_base, pkt_ctm_src_mac_byte, 1], ctx_swap[pkt_sig]

/*---------------------------*/

/* Ensure the *$index pointer is positioned correctly */
test_assert_equal(*$index++, 0xc0ffee)
test_assert_equal(*$index++, 0xdeadbeef)

test_pass()

drop_unexpected_error#:

test_fail()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
