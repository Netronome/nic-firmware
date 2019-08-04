/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef NFD_CFG_BASE_DECL_C
#define NFD_CFG_BASE_DECL_C

#ifdef NFD_PCIE0_EMEM
NFD_CFG_BASE_DECLARE(0);
NFD_VF_CFG_DECLARE(0)
#endif
#ifdef NFD_PCIE1_EMEM
NFD_CFG_BASE_DECLARE(1);
NFD_VF_CFG_DECLARE(1)
#endif
#ifdef NFD_PCIE2_EMEM
NFD_CFG_BASE_DECLARE(2);
NFD_VF_CFG_DECLARE(2)
#endif
#ifdef NFD_PCIE3_EMEM
NFD_CFG_BASE_DECLARE(3);
NFD_VF_CFG_DECLARE(3)
#endif

#endif
