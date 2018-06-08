;TEST_INIT_EXEC nfp-mem i32.ctm:0x80     0x00154d0a 0x0d1a6805 0xca306ab8 0x080045aa
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90     0xff00de06 0x40004011 0x51370501 0x01020501
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0     0x0101d87e 0x12b5ff00 0x00000800 0x0000ffff
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0     0xff00404d 0x8e6f97ad 0x001e101f 0x00010800
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0     0x4555ff00 0x7a9f4000 0x40067588 0xc0a80164
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0     0xd5c7b3a6 0xcb580050 0xea8d9a10 0xffffffff
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0     0x51ffffff 0x5106ffff 0x97ae878f 0x08377a4d
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0     0x85a1fec4 0x97a27c00 0x784648ea 0x31ab0538
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100    0xac9ca16e 0x8a809e58 0xa6ffc15f

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0x8c)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((3 << BF_L(PV_PARSE_STS_bf)) |
                  (((14 + 20 + 8 + 8 + 14 + 20) / 2) << BF_L(PV_PARSE_L4_OFFSET_bf)) |
                  (2 << BF_L(PV_PARSE_L3I_bf))))
move(pkt_vec[6], ((14 + 20 + 8 + 8 + 14) / 2) << BF_L(PV_PARSE_L3_OFFSET_bf))
