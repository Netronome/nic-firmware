// Stereoscopic Locomotive Interleaved Cryptographic CRC Hash
#ifndef _SLICC_HASH
#define _SLICC_HASH

#include <aggregate.uc>
#include <lm_handle.uc>
#include <passert.uc>
#include <stdmac.uc>
#include <unroll.uc>
#include <timestamp.uc>

#include "slicc_hash.h"

#define_eval SLICC_HASH_PAD_NN_ADDR     (SLICC_HASH_PAD_NN_IDX << 2)

#macro _slicc_hash_lm_handle_define()
    #define_eval _SLICC_HASH_LM_HANDLE 2
    #define_eval _SLICC_HASH_LM_INDEX  *l$index2
#endm

#macro _slicc_hash_lm_handle_undef()
    #undef _SLICC_HASH_LM_HANDLE
    #undef _SLICC_HASH_LM_INDEX
#endm

#define _slicc_hash_init_INSTRUCTIONS 3
#macro _slicc_hash_init()
    alu[_SLICC_HASH_STATE[0], _SLICC_HASH_LENGTH, XOR, *n$index++]
    crc_be[crc_32, copy, _SLICC_HASH_STATE[0]]
    alu[_SLICC_HASH_STATE[1], --, B,  _SLICC_HASH_STATE[0], <<rot21]
#endm


/* _slicc_hash_step()
 *
 * The primary purpose of each round is to efficiently incorporate an additional word of
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
#define _slicc_hash_step_INSTRUCTIONS 4
#macro _slicc_hash_step(IDX)
    alu[_SLICC_HASH_STATE[(IDX % 2)], _SLICC_HASH_STATE[(IDX % 2)], +carry, _SLICC_HASH_LM_INDEX++]
    crc_be[crc_32, copy, _SLICC_HASH_STATE[(IDX % 2)]], no_cc
#if (IDX < (_SLICC_HASH_MAX_KEY_LENGTH - 1))
    alu[_SLICC_HASH_STATE[((IDX + 1) % 2)], _SLICC_HASH_STATE[((IDX + 1) % 2)], XOR, *n$index++], no_cc
    dbl_shf[_SLICC_HASH_STATE[(IDX % 2)], copy, _SLICC_HASH_STATE[(IDX % 2)], >>indirect], no_cc
#endif
#endm


#macro slicc_hash(out_hash, in_key_address, in_key_length, MAX_KEY_LENGTH)
.begin
    #define_eval _SLICC_HASH_STATE out_hash
    #define_eval _SLICC_HASH_LENGTH in_key_length
    #define_eval _SLICC_HASH_MAX_KEY_LENGTH MAX_KEY_LENGTH

    .reg copy

    _slicc_hash_lm_handle_define()

    local_csr_wr[ACTIVE_LM_ADDR_/**/_SLICC_HASH_LM_HANDLE, in_key_address] ; (_SLICC_HASH_LM_HANDLE)
    local_csr_wr[NN_GET, SLICC_HASH_PAD_NN_IDX]
    local_csr_wr[CRC_REMAINDER, _SLICC_HASH_LENGTH]

    unroll_for_each(in_key_length, 0, (MAX_KEY_LENGTH - 1), _slicc_hash_step, _slicc_hash_step, _slicc_hash_init)

    _slicc_hash_lm_handle_undef()

    // finalization mix to combine _SLICC_HASH_STATE[0] and _SLICC_HASH_STATE[1]
    alu[_SLICC_HASH_STATE[(MAX_KEY_LENGTH % 2)], _SLICC_HASH_STATE[((MAX_KEY_LENGTH + 1) % 2)], XOR, _SLICC_HASH_STATE[(MAX_KEY_LENGTH % 2)]], no_cc
    dbl_shf[_SLICC_HASH_STATE[((MAX_KEY_LENGTH + 1) % 2)], copy, _SLICC_HASH_STATE[((MAX_KEY_LENGTH + 1) % 2)], >>indirect], no_cc
    alu[_SLICC_HASH_STATE[(MAX_KEY_LENGTH % 2)], _SLICC_HASH_STATE[(MAX_KEY_LENGTH % 2)], +carry, _SLICC_HASH_STATE[((MAX_KEY_LENGTH + 1) % 2)]]
    alu[_SLICC_HASH_STATE[(MAX_KEY_LENGTH % 2)], --, B, _SLICC_HASH_STATE[(MAX_KEY_LENGTH % 2)], <<rot16], no_cc
    alu[_SLICC_HASH_STATE[1], _SLICC_HASH_STATE[(MAX_KEY_LENGTH % 2)], +carry, copy]

    local_csr_rd[CRC_REMAINDER]
    immed[_SLICC_HASH_STATE[0], 0]
.end
#endm


#endif
