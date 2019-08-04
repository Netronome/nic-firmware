/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file  slicc_hash.uc
 * @brief Stereoscopic Locomotive Interleaved Cryptographic CRC Hash
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _SLICC_HASH
#define _SLICC_HASH

#include <passert.uc>
#include <preproc.uc>
#include <stdmac.uc>

#include "slicc_hash.h"

#define_eval SLICC_HASH_PAD_NN_ADDR     (SLICC_HASH_PAD_NN_IDX << 2)

#macro slicc_hash_init_nn()
.begin
        .reg act_ctx_sts
        .reg offset
        .reg pad_base
        .reg reflect_base
        .reg $pad[8]
        .xfer_order $pad
        .sig sig_reflect
        .sig volatile sig_reflected
        .sig sig_pad

        .if (ctx() == 0)
            local_csr_rd[active_ctx_sts]
            immed[act_ctx_sts, 0]
            alu[reflect_base, 0xf, AND, act_ctx_sts, >>3]
            alu[reflect_base, --, B, reflect_base, <<17]
            alu[reflect_base, reflect_base, OR, __ISLAND, <<24]
            alu[reflect_base, reflect_base, OR, &sig_reflected, <<10]
            alu[reflect_base, reflect_base, OR, 0x01, <<9]
            alu[reflect_base, reflect_base, OR, SLICC_HASH_PAD_NN_IDX, <<2]

            move(pad_base, (SLICC_HASH_PAD_DATA >> 8))

            passert(SLICC_HASH_PAD_SIZE_LW, "MULTIPLE_OF", 8)
            move(offset, 0)
            .while (offset < (SLICC_HASH_PAD_SIZE_LW * 4))
                mem[read32, $pad[0], pad_base, <<8, offset, 8], ctx_swap[sig_pad]
                aggregate_copy($pad, $pad, 8)
                .set_sig sig_reflected
                ct[ctnn_write, $pad[0], reflect_base, offset, 8], ctx_swap[sig_reflect]
                alu[offset, offset, +, (8 * 4)]
                ctx_arb[sig_reflected]
                // work around for SDN-1658 / THS-163
                .repeat
                    timestamp_sleep(3)
                .until (!SIGNAL(sig_reflected))
            .endw
        .endif
.end
#endm

/* The primary purpose of each round is to efficiently incorporate an additional word of
 * the input key into the internal hash state. In doing so, the goal is to have each bit
 * of the input word affect as many bits of the internal state as possible. Additionally,
 * it should not be possible to manipulate the input key in such a way as to cause hash
 * collisions. For this reason, the internal state is permuted during each step by XORing
 * it with a randomly generated cryptographic pad, such that the effect of prior bits of
 * the input key on the internal state cannot be predicted.
 *
 * SLICC_HASH maintains 96 bits of internal state. A 32 bit residual is updated using the
 * CRC32 algorithm during each round. The remaining two words of state are updated in an
 * interleaved fashion. This interleaving was initially undertaken purely to optimize
 * instruction usage, however, it also serves another useful purpose - it proliferates
 * the direct effect of any given input word into later stages (ie. after the effect of
 * subsequent input words have been incorporated into the internal state). The collapse
 * of the internal state into fewer bits is thus delayed. These two words of state each
 * maintain a very different perspective of the input key, hence the stereoscopic nature
 * of this hash.
 *
 * In a given round, summation with the input key is used to update one of the two
 * stereoscopic views. The addition operation is chosen because of its ability to cascade
 * via carries into more significant bit positions. In this way, the specific value of
 * any given bit has the capacity to affect more than its own bit position in the state.
 * Carries out of the most significant bit position are preserved and incorporated in
 * subsequent rounds for the same reason (in order to affect more bit positions of the
 * internal state).
 *
 * Instead of utilizing each subsequent word of the input key to update the CRC32, the
 * cumulative value of the current perspective of the internal state is used. By feeding
 * the CRC32 using the accumulated state, which also incorporates cryptographic permutations
 * from prior rounds, the properties of the cyclic redundancy calculation that could otherwise
 * be exploited to cause collisions in the CRC32 residual space are effectively thwarted.
 * Using the accumulated state also serves to provide for better mixing of input bits, since
 * the cumlative prior state is reincorporated into the CRC32 calculation in new and different
 * ways during each round. This way, the mixing provided by the CRC32 function is amplified.
 *
 * Next, the internal state of the neighboring stereoscoptic perspective is permuted using
 * the cryptographic pad. Since the output of the hash is not visible to attackers in
 * typical applications, it is safe to reuse the same pad for each subsequent invocation
 * of the hash (to do otherwise would obviously render the hash function pretty useless in
 * practice). The pad should be generated during initialization using a secure random
 * generator and can be recomputed periodically at the cost of changing the hash function
 * output for a given input key (in practice, invalidating caches based on the hash). The
 * subtlety here is that the locomotion of state provided in the next instruction is
 * specified by the least significant 5 bits of the neighboring stereoscopic perspective.
 *
 * Finally, the state bits are moved (the locomotion), so that every subsequent input bit
 * has opportunity to influence differing output bit positions. The movement is provided
 * for by a rotation instead of a shift operation so that no entropy is lost to being
 * shifted out of a register. Precisely which bits of state are influenced by which bits
 * of input are specified by the accumulated and unpredictable prior state of the other
 * stereoscopic perspective. Through the cumulative rotations in subsequent rounds, the
 * values in differing bit positions of the previously processed input words will come to
 * bear on the degree of locomotion incurred in the alternative perspective.
 *
 */

.reg __slicc_hash_ret_addr
.reg __slicc_hash_copy
.reg __slicc_hash_state[2]
.reg __slicc_hash_tail_mask
.if (0)
.subroutine
.begin
    .reg tmp

    #define LOOP 0

    #while (LOOP < (SLICC_HASH_PAD_SIZE_LW - 3))
        __slicc_hash_round/**/LOOP#:
        alu[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[(LOOP % 2)], +carry, *l$index0++]
        crc_be[crc_32, __slicc_hash_copy, __slicc_hash_state[(LOOP % 2)]], no_cc
        alu[__slicc_hash_state[((LOOP + 1) % 2)], __slicc_hash_state[((LOOP + 1) % 2)], XOR, *n$index++], no_cc
        dbl_shf[__slicc_hash_state[(LOOP % 2)], __slicc_hash_copy, __slicc_hash_state[(LOOP % 2)], >>indirect], no_cc
        #define_eval LOOP (LOOP + 1)
    #endloop

    __slicc_hash_round/**/LOOP#:
        alu[tmp, __slicc_hash_tail_mask, AND, *l$index0++], no_cc
        alu[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[(LOOP % 2)], +carry, tmp]
        alu[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[(LOOP % 2)], XOR, *n$index++]
        crc_be[crc_32, __slicc_hash_copy, __slicc_hash_state[(LOOP % 2)]]

    mul_step[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[((LOOP + 1) % 2)]], 32x32_start
    mul_step[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[((LOOP + 1) % 2)]], 32x32_step1
    mul_step[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[((LOOP + 1) % 2)]], 32x32_step2
    mul_step[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[((LOOP + 1) % 2)]], 32x32_step3
    mul_step[__slicc_hash_state[(LOOP % 2)], __slicc_hash_state[((LOOP + 1) % 2)]], 32x32_step4
    mul_step[__slicc_hash_state[0], --], 32x32_last
    mul_step[__slicc_hash_state[1], --], 32x32_last2

    #undef LOOP

    rtn[__slicc_hash_ret_addr], defer[3]
        local_csr_rd[CRC_REMAINDER]
        .reg_addr __slicc_hash_state[0] 3 B
        immed[__slicc_hash_state[0], 0]
         .reg_addr __slicc_hash_state[1] 4 B
        alu[__slicc_hash_state[1], __slicc_hash_state[0], XOR, __slicc_hash_state[1]]
.end
.endsub
.endif

#macro slicc_hash_words(out_hash, in_salt, in_addr, in_len_words, in_tail_mask)
.begin
    .reg offset

    #if (is_ct_const(in_len_words))
        passert(in_len_words, "GE", 0)
        passert(in_len_words, "LE", (SLICC_HASH_PAD_SIZE_LW - 2))
        move(offset, ((SLICC_HASH_PAD_SIZE_LW - 2 - in_len_words) * 4))
    #else
        alu[offset, (SLICC_HASH_PAD_SIZE_LW - 2), -, in_len_words]
        blo[overflow#]
        alu[offset, --, B, offset, <<2]
    #endif

    local_csr_wr[NN_GET, SLICC_HASH_PAD_NN_IDX]
    local_csr_wr[CRC_REMAINDER, in_len_words]

    #if (is_rt_const(in_addr) || is_ct_const(in_addr) && in_addr > 255)
        .reg addr
        move(addr, in_addr)
        local_csr_wr[ACTIVE_LM_ADDR_0, addr]
    #else
        local_csr_wr[ACTIVE_LM_ADDR_0, in_addr]
    #endif

    move(__slicc_hash_tail_mask, in_tail_mask)

    #if (is_ct_const(in_salt) && in_salt > 255)
        .reg salt
        move(salt, in_salt)
        alu[__slicc_hash_state[0], salt, XOR, *n$index++]
    #else
        alu[__slicc_hash_state[0], in_salt, XOR, *n$index++]
    #endif

    preproc_jump_targets(__slicc_hash_round, (SLICC_HASH_PAD_SIZE_LW - 2))
    jump[offset, __slicc_hash_round0#], targets[PREPROC_LIST], defer[3]
        crc_be[crc_32, __slicc_hash_copy, __slicc_hash_state[0]]
        alu[__slicc_hash_state[1], __slicc_hash_tail_mask, XOR, *n$index++]
        load_addr[__slicc_hash_ret_addr, end#]

#if (!is_ct_const(in_len_words))
overflow#:
    .reg_addr __slicc_hash_state[0] 3 B
    immed[__slicc_hash_state[0], 0]
    .reg_addr __slicc_hash_state[1] 4 B
    immed[__slicc_hash_state[1], 0]
#endif

end#:
    .use __slicc_hash_state[0]
    .reg_addr out_hash[0] 3 B
    .set out_hash[0]
    .use __slicc_hash_state[1]
    .reg_addr out_hash[1] 4 B
    .set out_hash[1]
.end
#endm


#macro slicc_hash_words(out_hash, in_salt, in_addr, in_len_words)
    slicc_hash_words(out_hash, in_salt, in_addr, in_len_words, 0xffffffff)
#endm


#macro slicc_hash_bytes(out_hash, in_salt, in_addr, in_len_bytes, ENDIAN)
.begin
    .reg msk
    .reg shift
    .reg words

    #if (streq('ENDIAN', 'LE'))
        alu[shift, (3 << 3), AND, in_len_bytes, <<3]
        #if (is_ct_const(in_len_bytes))
            beq[skip#], defer[2]
                immed[words, ((in_len_bytes + 3) / 4)]
        #else
            beq[skip#], defer[3]
                alu[words, in_len_bytes, +, 3]
                alu[words, --, B, words, >>2]
        #endif
            alu[msk, shift, ~B, 0]
        alu[msk, --, ~B, msk, <<indirect]
        skip#:
    #elif (streq('ENDIAN', 'BE'))
        #if (is_ct_const(in_len_bytes))
            immed[words, ((in_len_bytes + 3) / 4)]
            immed[shift, (((in_len_bytes + 3) % 4) * 8)]
        #else
            alu[words, in_len_bytes, +, 3]
            alu[shift, (3 << 3), AND, words, <<3]
            alu[words, --, B, words, >>2]
        #endif
        alu[msk, shift, B, 0xff, <<24]
        asr[msk, msk, >>indirect]
    #else
        #error "slicc_hash_bytes(): unknown byte order: " ENDIAN
    #endif

    slicc_hash_words(out_hash, in_salt, in_addr, words, msk)
.end
#endm


#macro slicc_hash_bytes(out_hash, in_salt, in_addr, in_len_bytes)
    slicc_hash_bytes(out_hash, in_salt, in_addr, in_len_bytes, BE)
#endm

#endif
