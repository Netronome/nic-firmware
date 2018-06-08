;TEST_INIT_EXEC nfp-mem i32.ctm:0x80     0x00154d0a 0x0d1a6805 0xca306ab8 0x86dd6aaa
;TEST_INIT_EXEC nfp-mem i32.ctm:0x90     0xaaaaff00 0x11fffe80 0x00000000 0x00000200
;TEST_INIT_EXEC nfp-mem i32.ctm:0xa0     0x0bfffe00 0x03003555 0x55556666 0x66667777
;TEST_INIT_EXEC nfp-mem i32.ctm:0xb0     0x77778888 0x8888d87e 0x12b5ff00 0x00000800
;TEST_INIT_EXEC nfp-mem i32.ctm:0xc0     0x0000ffff 0xff00404d 0x8e6f97ad 0x001e101f
;TEST_INIT_EXEC nfp-mem i32.ctm:0xd0     0x000186dd 0x65555555 0xff0006ff 0xfe800000
;TEST_INIT_EXEC nfp-mem i32.ctm:0xe0     0x00000000 0x02000bff 0xfe000300 0x35555555
;TEST_INIT_EXEC nfp-mem i32.ctm:0xf0     0x66666666 0x77777777 0x88888888 0xcb580050
;TEST_INIT_EXEC nfp-mem i32.ctm:0x100    0xea8d9a10 0xffffffff 0x51ffffff 0x5106ffff
;TEST_INIT_EXEC nfp-mem i32.ctm:0x110    0x97ae878f 0x08377a4d 0x85a1fec4 0x97a27c00
;TEST_INIT_EXEC nfp-mem i32.ctm:0x120    0x784648ea 0x31ab0538 0xac9ca16e 0x8a809e58
;TEST_INIT_EXEC nfp-mem i32.ctm:0x130    0xa6ffc15f

#include <aggregate.uc>
#include <stdmac.uc>

#include <pv.uc>

.reg pkt_vec[PV_SIZE_LW]
aggregate_zero(pkt_vec, PV_SIZE_LW)
move(pkt_vec[0], 0xb4)
move(pkt_vec[2], 0x80)
move(pkt_vec[4], 0x3fc0)
move(pkt_vec[5], ((3 << BF_L(PV_PARSE_STS_bf)) |
                  (((14 + 40 + 8 + 8 + 14 + 40) / 2) << BF_L(PV_PARSE_L4_OFFSET_bf)) |
                  (2 << BF_L(PV_PARSE_L3I_bf))))
move(pkt_vec[6], ((14 + 40 + 8 + 8 + 14) / 2) << BF_L(PV_PARSE_L3_OFFSET_bf))
