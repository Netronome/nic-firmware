/*
 * Copyright 2014-2015 Netronome, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @file          lib/nic_basic/libnic_basic.c
 * @brief         Implementation of the NIC functions
 *
 * XXX The implementation currently only supports a single NIC
 *     instance and several internal data structures need duplicating
 *     to support additional instances.
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
#include "pcie_desc.h"
#include "shared/nfp_net_ctrl.h"
#include "nic_ctrl.h"


/* Include other C files. The order matters. nic_internal.c defines
 * global data structures. */
#include "_c/nic_internal.c"
#include "_c/nic_rx.c"
#include "_c/nic_tx.c"
#include "_c/nic_stats.c"
#include "_c/nic_switch.c"

#endif /* _NIC_LIBNIC_BASIC_C_ */

/* -*-  Mode:C; c-basic-offset:4; tab-width:4 -*- */
