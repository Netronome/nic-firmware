/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <single_ctx_test.uc>

#include "pkt_bc_ipv4_udp_x88.uc"

#include <global.uc>

#include <pv.uc>

.reg type
pv_seek(pkt_vec, 0, (PV_SEEK_INIT | PV_SEEK_DEFAULT))
__pv_get_mac_dst_type(type, pkt_vec)

test_assert_equal(type, 3)

test_pass()

PV_SEEK_SUBROUTINE#:
   pv_seek_subroutine(pkt_vec)
