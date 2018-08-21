#include <nfd_tlv.uc>
#include <nfd_user_cfg.h>
#include <nfd_common.h>

#define _PCI 0

#define _VID 0
#while (_VID < NVNICS)
    #if (NFD_VID_IS_PF(_VID) || NFD_VID_IS_VF(_VID))
        #include "tlv_stats.uc" // stats must go first
        nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_STATS_BASE_MASK, 4, 0)
        nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
        nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_END, 0, --)
    #endif
    #define_eval _VID (_VID + 1)
#endloop
