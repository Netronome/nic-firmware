/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xdeadbeef

;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:0   0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:4   0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:8   0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:12  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:16  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:20  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:24  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:28  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:32  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:36  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:40  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:44  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:48  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:52  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:56  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:60  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:64  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:68  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:72  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:76  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:80  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:84  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:88  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:92  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:96  0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:100 0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:104 0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:108 0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:112 0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:116 0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:120 0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:124 0
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:128 0x01020304
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:132 0x05060708
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:136 0x090a0b0c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:140 0x0d0e0f10
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:144 0x11121314
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:148 0x15161718
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:152 0x191a1b1c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:156 0x1d1e1f20
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:160 0x21222324
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:164 0x25262728
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:168 0x292a2b2c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:172 0x2d2e2f30
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:176 0x31323334
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:180 0x35363738
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:184 0x393a3b3c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:188 0x3d3e3f40
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:192 0x41424344
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:196 0x45464748
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:200 0x494a4b4c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:204 0x4d4e4f50
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:208 0x51525354
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:212 0x55565758
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:216 0x595a5b5c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:220 0x5d5e5f60
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:224 0x61626364
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:228 0x65666768
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:232 0x696a6b6c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:236 0x6d6e6f70
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:240 0x71727374
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:244 0x75767778
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:248 0x797a7b7c
;TEST_INIT_EXEC nfp-rtsym i32.NIC_RSS_TBL:252 0x7d7e7f80

#include "actions_harness.uc"
#include <single_ctx_test.uc>

#include <config.h>
#include <gro_cfg.uc>
#include <global.uc>
#include <pv.uc>
#include <stdmac.uc>

local_csr_wr[NN_GET, 96]

test_assert_equal($__actions[1], 0xc0ffee)
test_assert_equal($__actions[2], 0xdeadbeef)

#macro rss_reset_test(in_pkt_vec)
    local_csr_wr[T_INDEX, (32 * 4)]
    immed[__actions_t_idx, (32 * 4)]
    pv_invalidate_cache(in_pkt_vec)
    immed[BF_A(in_pkt_vec, PV_QUEUE_OFFSET_bf), 0]
    immed[BF_A(in_pkt_vec, PV_META_TYPES_bf), 0]
#endm

.reg prev_hash
.reg hash

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

    alu[--, --, B, *l$index2--]
    alu[hash, --, B, *l$index2--]

    CHECK(hash, expected)
    move(prev_hash, hash)

    alu[tested_queue, 0xff, AND, BF_A(pkt_vec, PV_QUEUE_OFFSET_bf)]
    alu[expected_queue, hash, +, 1]
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
