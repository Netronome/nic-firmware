#include <nfd_tlv.uc>

#define _PORT 0
#while (_PORT < NS_PLATFORM_NUM_PORTS)
    nfd_tlv_init(0, NFD_PF2VID(_PORT), NFP_NET_CFG_TLV_TYPE_ME_FREQ, 4, NS_PLATFORM_TCLK)
    nfd_tlv_init(0, NFD_PF2VID(_PORT), NFP_NET_CFG_TLV_TYPE_END, 0, --)
    #define_eval _PORT (_PORT + 1)
#endloop
