/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 *
 * @file   single_ctx_test.uc
 * @brief  including this file kills all but one context
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include "test.uc"

.if (ctx() != 0)
    ctx_arb[kill]
.endif

