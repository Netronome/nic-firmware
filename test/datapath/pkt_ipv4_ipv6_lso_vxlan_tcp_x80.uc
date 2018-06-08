;TEST_INIT_EXEC nfp-mem i32.ctm:0x80     0x00154d0a 0x0d1a6805 0xca306ab8 0x080045aa
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90     0xff00de06 0x40004011 0x50640501 0x01020501
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0     0x0101d87e 0x12b5ff00 0x00000800 0x0000ffff
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0     0xff00404d 0x8e6f97ad 0x001e101f 0x000186dd
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0     0x65555555 0xff0006ff 0xfe800000 0x00000000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0     0x02000bff 0xfe000300 0x35555555 0x66666666
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0     0x77777777 0x88888888 0xcb580050 0xea8d9a10
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0     0xffffffff 0x51ffffff 0x5106ffff 0x97ae878f
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100    0x08377a4d 0x85a1fec4 0x97a27c00 0x784648ea
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110    0x31ab0538 0xac9ca16e 0x8a809e58 0xa6ffc15f

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0xa0)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((3 << BF_L(PV_PARSE_STS_bf)) |
                  (((14 + 20 + 8 + 8 + 14 + 40) / 2) << BF_L(PV_PARSE_L4_OFFSET_bf)) |
                  (2 << BF_L(PV_PARSE_L3I_bf))))
move(pkt_vec[6], ((14 + 20 + 8 + 8 + 14) / 2) << BF_L(PV_PARSE_L3_OFFSET_bf))
