/*
 * Copyright 2014-2015 Netronome Systems, Inc. All rights reserved.
 *
 * @file          lib/nic_basic/libnic_basic.c
 * @brief         Implementation of the NIC functions
 *
 * XXX The implementation currently only supports a single NIC
 *     instance and several internal data structures need duplicating
 *     to support additional instances.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _NIC_LIBNIC_BASIC_C_
#define _NIC_LIBNIC_BASIC_C_


#include <assert.h>
#include <nfp.h>
#include <stdint.h>

#include <infra_basic/infra_basic.h>

#include <lu/cam_hash.h>
#include <net/eth.h>
#include <net/ip.h>

#include <nfp/me.h>
#include <nfp/mem_atomic.h>
#include <nfp/mem_bulk.h>

#include <std/event.h>
#include <std/hash.h>
#include <std/reg_utils.h>
#include <std/synch.h>

#include "nic_basic.h"
#include "shared/nfp_net_ctrl.h"
#include "nic_ctrl.h"


/* Include other C files. The order matters. nic_internal.c defines
 * global data structures. */
#include "_c/nic_internal.c"
#include "_c/nic_stats.c"

#endif /* _NIC_LIBNIC_BASIC_C_ */

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
