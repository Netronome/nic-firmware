;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x3ff
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xdeadbeef

#include <pkt_io.uc>
#include <single_ctx_test.uc>
#include <global.uc>
#include <actions.uc>
#include <bitfields.uc>

.reg protocol
.reg volatile write $nbi_desc[(NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))]
.xfer_order $nbi_desc
.reg addr
.sig s

move(addr, 0x80)

#define pkt_vec *l$index1

pv_init(pkt_vec, 0)

//set up CATAMARAN vector
move(__pkt_io_nfd_pkt_no, 0)

move($nbi_desc[0], ((0x40<<BF_L(CAT_PKT_LEN_bf)) | 1<<BF_L(CAT_BLS_bf)))
move($nbi_desc[1], 0)
move($nbi_desc[2], (0x2<<BF_L(CAT_SEQ_CTX_bf))]
move($nbi_desc[3], (CAT_L3_TYPE_IP<<BF_L(CAT_L3_TYPE_bf)) | (5<<(BF_L(CAT_L3_CLASS_bf))))
move($nbi_desc[4], 0)
move($nbi_desc[5], 0)
move($nbi_desc[6], 0)
move($nbi_desc[7], (0x1<<BF_L(MAC_PARSE_L3_bf) | 0x2 << BF_L(MAC_PARSE_STS_bf)))

mem[write32, $nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

mem[read32,  $__pkt_io_nbi_desc[0], 0, <<8, addr, (NBI_IN_META_SIZE_LW + (MAC_PREPEND_BYTES / 4))], ctx_swap[s]

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]
nop
nop

__actions_rx_wire(pkt_vec, drop_mtu#, drop_proto#, error_parse#)

bitfield_extract__sz1(protocol, BF_AML(pkt_vec, PV_PROTO_bf))

test_assert_equal(protocol, 0x0)

test_assert_equal(*$index, 0xdeadbeef)

test_pass()

error_parse#:
drop_mtu#:
drop_proto#:
test_fail()
