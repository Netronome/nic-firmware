#include <nfd_tlv.uc>

#define _PCI 0

#define _PORT 0
#while (_PORT < NS_PLATFORM_NUM_PORTS)
    #define_eval _VID NFD_PF2VID(_PORT)
    #include "tlv_stats.uc" // stats must go first
    nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_STATS_BASE_MASK, 4, 0)
    nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
    nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_END, 0, --)
    #define_eval _PORT (_PORT + 1)
#endloop
