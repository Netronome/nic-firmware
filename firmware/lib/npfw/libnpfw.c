/*
 * Copyright 2016 Netronome Systems, Inc. All rights reserved.
 *
 * @file   lib/npfw/libnpfw.c
 * @brief  Functions to interface with the Catamaran NPFW
 *
 * This file contains the micro-C API for configuring the Catamaran NPFW via
 * the ME.  The purpose of this library is to provide a simple interface for
 * configuring the Catamaran NPFW.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _LIBNPFW_C_
#define _LIBNPFW_C_


#include "catamaran_app_utils.h"
#include "catamaran_utils.h"
#include "nbi_cpp.h"
#include "nbipc_mem.h"

/* Include other micro-C files. */
#include "_c/catamaran_app_utils.c"
#include "_c/catamaran_utils.c"
#include "_c/nbi_cpp.c"
#include "_c/nbipc_mem.c"

#endif /* ndef _LIBNPFW_C_ */
