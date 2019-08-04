/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _ACTIONS_HARNESS_UC
#define _ACTIONS_HARNESS_UC

#include <actions.uc>
#include <single_ctx_test.uc>

#macro test_action_reset()
    immed[__actions_t_idx, (32 * 4)]
    local_csr_wr[T_INDEX, __actions_t_idx]
    nop
    nop
    nop
#endm


.if (0)
    tx_errors_offset#:
    drop#:
    egress#:
    actions#:
    ebpf_reentry#:
    .reentry
    test_fail()
.endif

#endif
