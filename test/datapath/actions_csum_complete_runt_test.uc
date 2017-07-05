;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_60=0x0
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_61=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_inc_pat_64B_x88.uc"

#include <single_ctx_test.uc>
#include <global.uc>

.reg volatile read $instr[2]
.xfer_order $instr
.addr $instr[0] 60

.reg read $csum
.reg write $zero
.sig sig_csum
.reg csum_offset
immed[$zero, 0]
immed[csum_offset, -4]
mem[write32, $zero, BF_A(pkt_vec, PV_CTM_ADDR_bf), csum_offset, 1], ctx_swap[sig_csum]

.reg csum
.reg length
immed[length, 0]
.while (length < 15)
    local_csr_wr[T_INDEX, (60 * 4)]
    immed[__actions_t_idx, (60 * 4)]

    immed[BF_A(pkt_vec, PV_META_TYPES_bf), 0]
    immed[BF_A(pkt_vec, PV_META_LENGTH_bf), 0]
    alu[BF_A(pkt_vec, PV_LENGTH_bf), --, B, length]

    __actions_checksum_complete(pkt_vec)

    test_assert_equal(*$index, 0xdeadbeef)

    mem[read32, $csum, BF_A(pkt_vec, PV_CTM_ADDR_bf), csum_offset, 1], ctx_swap[sig_csum]
    test_assert_equal($csum, 0)

    test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), 0)

    alu[length, length, +, 1]
.endw

test_pass()

