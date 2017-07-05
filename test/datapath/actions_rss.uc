;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_62=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_63=0xdeadbeef
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_96=0x04030201
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_97=0x08070605
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_98=0x0c0b0a09
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_99=0x100f0e0d
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_100=0x14131211
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_101=0x18171615
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_102=0x1c1b1a19
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_103=0x201f1e1d
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_104=0x24232221
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_105=0x28272625
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_106=0x2c2b2a29
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_107=0x302f2e2d
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_108=0x34333231
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_109=0x38373635
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_110=0x3c3b3a39
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_111=0x403f3e3d
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_112=0x44434241
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_113=0x48474645
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_114=0x4c4b4a49
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_115=0x504f4e4d
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_116=0x54535251
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_117=0x58575655
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_118=0x5c5b5a59
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_119=0x605f5e5d
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_120=0x64636261
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_121=0x68676665
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_122=0x6c6b6a69
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_123=0x706f6e6d
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_124=0x74737271
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_125=0x78777675
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_126=0x7c7b7a79
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.NextNeighbor_127=0x807f7e7d

#include <single_ctx_test.uc>

#include "actions_harness.uc"

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

.reg read $opcodes[3]
.xfer_order $opcodes
.addr $opcodes[0] 61
.set $opcodes[0]
.set $opcodes[1]
.set $opcodes[2]

local_csr_wr[NN_GET, 96]

test_assert_equal($opcodes[1], 0xc0ffee)
test_assert_equal($opcodes[2], 0xdeadbeef)

.reg nn_idx
.reg nn_entry
.reg nn_data
.reg nn_expected
move(nn_idx, 0)
.while (nn_idx < 32)
    move(nn_data, *n$index++)
    alu[nn_entry, 0xff, AND, nn_data]
    alu[nn_expected, --, B, nn_idx, <<2]
    alu[nn_expected, nn_expected, +, 1]
    test_assert_equal(nn_entry, nn_expected)
    alu[nn_entry, 0xff, AND, nn_data, >>8]
    alu[nn_expected, nn_expected, +, 1]
    test_assert_equal(nn_entry, nn_expected)
    alu[nn_entry, 0xff, AND, nn_data, >>16]
    alu[nn_expected, nn_expected, +, 1]
    test_assert_equal(nn_entry, nn_expected)
    alu[nn_entry, 0xff, AND, nn_data, >>24]
    alu[nn_expected, nn_expected, +, 1]
    test_assert_equal(nn_entry, nn_expected)
    alu[nn_idx, nn_idx, +, 1]
.endw

#macro rss_reset_test(in_pkt_vec)
    local_csr_wr[T_INDEX, (61 * 4)]
    immed[__actions_t_idx, (61 * 4)]
    pv_invalidate_cache(in_pkt_vec)
    immed[BF_A(in_pkt_vec, PV_META_LENGTH_bf), 0]
    immed[BF_A(in_pkt_vec, PV_QUEUE_OUT_bf), 0]
    immed[BF_A(in_pkt_vec, PV_META_TYPES_bf), 0]
#endm

.reg prev_hash

#macro rss_validate(in_pkt_vec, TARGET_HASH_TYPE, CHECK, expected)
.begin
    .reg meta_type
    .reg hash_type
    .reg read $hash
    .sig sig_read
    .reg hash_offset
    .reg tested_queue
    .reg expected_queue

    alu[meta_type, 0xf, AND, BF_A(pkt_vec, PV_META_TYPES_bf)]
    test_assert_equal(meta_type, NFP_NET_META_HASH)
    alu[hash_type, 0xf, AND, BF_A(pkt_vec, PV_META_TYPES_bf), >>4]
    test_assert_equal(hash_type, TARGET_HASH_TYPE)

    move(hash_offset, -4)
    mem[read32, $hash, BF_A(pkt_vec, PV_CTM_ADDR_bf), hash_offset, 1], ctx_swap[sig_read]
    CHECK($hash, expected)
    move(prev_hash, $hash)

    alu[tested_queue, 0xff, AND, BF_A(pkt_vec, PV_QUEUE_OUT_bf)]
    alu[expected_queue, $hash, +, 1]
    alu[expected_queue, expected_queue, AND, 0x7f]
    .if (==0)
        immed[expected_queue, 0x80]
    .endif
    test_assert_equal(tested_queue, expected_queue)

    test_assert_equal(*$index, 0xdeadbeef)
.end
#endm


#macro rss_validate_range(pkt_vec, HASH_TYPE, MODE, start, finish)
.begin
    .reg pkt_offset
    .reg $data
    .reg delta
    .sig sig_data

    move(delta, 0x01000000)
    move(pkt_offset, start)
   .while (pkt_offset < finish)
        rss_reset_test(pkt_vec)
        mem[read8, $data, BF_A(pkt_vec, PV_CTM_ADDR_bf), pkt_offset, 1], ctx_swap[sig_data]
        alu[$data, $data, +, delta]
        mem[write8, $data, BF_A(pkt_vec, PV_CTM_ADDR_bf), pkt_offset, 1], ctx_swap[sig_data]
        __actions_rss(pkt_vec)
        #if (streq('MODE', 'incl'))
           rss_validate(pkt_vec, HASH_TYPE, test_assert_unequal, prev_hash)
        #elif (streq('MODE', 'excl'))
           rss_validate(pkt_vec, HASH_TYPE, test_assert_equal, prev_hash)
        #else
           #error "expecting MODE = incl | excl"
        #endif
        alu[pkt_offset, pkt_offset, +, 1]
    .endw
.end
#endm

