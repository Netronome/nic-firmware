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

#define _VID 0
#while (_VID < NVNICS)
    #ifdef NFD_PCIE0_EMEM
        #if (NFD_VID_IS_PF(_VID) || NFD_VID_IS_VF(_VID))
            nfd_tlv_init(0, _VID, NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
            nfd_tlv_init(0, _VID, NFP_NET_CFG_TLV_TYPE_END, 0, --)
        #endif
    #endif
    #ifdef NFD_PCIE1_EMEM
        #if (NFD_VID_IS_PF(_VID) || NFD_VID_IS_VF(_VID))
            nfd_tlv_init(1, _VID, NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
            nfd_tlv_init(1, _VID, NFP_NET_CFG_TLV_TYPE_END, 0, --)
        #endif
    #endif
    #ifdef NFD_PCIE2_EMEM
        #if (NFD_VID_IS_PF(_VID) || NFD_VID_IS_VF(_VID))
            nfd_tlv_init(2, _VID, NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
            nfd_tlv_init(2, _VID, NFP_NET_CFG_TLV_TYPE_END, 0, --)
        #endif
    #endif
    #ifdef NFD_PCIE3_EMEM
        #if (NFD_VID_IS_PF(_VID) || NFD_VID_IS_VF(_VID))
            nfd_tlv_init(3, _VID, NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
            nfd_tlv_init(3, _VID, NFP_NET_CFG_TLV_TYPE_END, 0, --)
        #endif
    #endif
    #define_eval _VID (_VID + 1)
#endloop
