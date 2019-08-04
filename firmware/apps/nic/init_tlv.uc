/* Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file   init_tlv.uc
 * @brief  Initialize NFD config TLVs in VNIC BARs
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <nfd_tlv.uc>
#include <nfd_user_cfg.h>
#include <nfd_common.h>

#define _PCI 0

#define _VID 0
#while (_VID < NVNICS)
    #if (NFD_VID_IS_PF(_VID) || NFD_VID_IS_VF(_VID))
        nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
        nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_END, 0, --)
    #endif
    #define_eval _VID (_VID + 1)
#endloop
