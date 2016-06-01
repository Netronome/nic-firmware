/*
 * Copyright 2016 Netronome, Inc.
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
 * @file   lib/npfw/libnpfw.c
 * @brief  Functions to interface with the Catamaran NPFW
 *
 * This file contains the micro-C API for configuring the Catamaran NPFW via
 * the ME.  The purpose of this library is to provide a simple interface for
 * configuring the Catamaran NPFW.
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
