;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_60=0x0
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_61=0xdeadbeef

#include "actions_harness.uc"

#include "pkt_inc_pat_9K_x88.uc"

#include <single_ctx_test.uc>
#include <global.uc>
#include <bitfields.uc>

.reg volatile read $instr[2]
.xfer_order $instr
.addr $instr[0] 60

#macro checksum_pattern(csum, len)
.begin
    .reg count
    .reg last_byte
    .reg i
    .reg data

    immed[csum, 0]

    immed[i, 8]
    alu[count, len, -, 14]
    alu[last_byte, count, AND, 1]
    alu[count, --, B, count, >>1]
    beq[last_even#]

loop#:
    alu[data, 0, B, i, <<16]
    alu[i, i, +, 1]

    alu[count, count, -, 1]
    beq[last_odd#]

    alu[data, data, OR, i]
    alu[i, i, +, 1]

accumulate#:
    alu[csum, csum, +, data]
    alu[csum, csum, +carry, 0]
    alu[count, count, -, 1]
    bgt[loop#]

last_even#:
    alu[--, --, B, last_byte]
    beq[done#]

    alu[data, --, B, i, <<16]
    alu[data, data, AND, 0xff, <<24]
    br[finalize#]

last_odd#:
    alu[--, --, B, last_byte]
    beq[finalize#]

    alu[data, data, OR, i]
    alu[data, data, AND~, 0xff]

finalize#:
    alu[csum, csum, +, data]
    alu[csum, csum, +carry, 0]

done#:
.end
#endm

.reg read $csum
.sig sig_csum
.reg csum_offset
immed[csum_offset, -4]

.reg pkt_len
pv_get_length(pkt_len, pkt_vec)

.reg csum
.reg length
immed[length, 15]
.while (length <= pkt_len)
    local_csr_wr[T_INDEX, (60 * 4)]
    immed[__actions_t_idx, (60 * 4)]

    immed[BF_A(pkt_vec, PV_META_TYPES_bf), 0]
    immed[BF_A(pkt_vec, PV_META_LENGTH_bf), 0]
    alu[BF_A(pkt_vec, PV_LENGTH_bf), --, B, length]

    __actions_checksum_complete(pkt_vec)

    test_assert_equal(*$index, 0xdeadbeef)

    checksum_pattern(csum, length)
    mem[read32, $csum, BF_A(pkt_vec, PV_CTM_ADDR_bf), csum_offset, 1], ctx_swap[sig_csum]
    test_assert_equal($csum, csum)

    test_assert_equal(BF_A(pkt_vec, PV_META_TYPES_bf), NFP_NET_META_CSUM)

    alu[length, length, +, 1]
.endw

test_pass()

