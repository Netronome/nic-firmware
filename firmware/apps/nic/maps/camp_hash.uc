/*
 * Copyright (c) 2015-2016 Netronome Systems, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _CAMP_HASH
#define _CAMP_HASH

#include <lm_handle.uc>
#include <passert.uc>
#include <stdmac.uc>
#include <unroll.uc>

#define CAMP_HASH_PAD_NN_IDX    64
#define CAMP_HASH_PAD_SIZE_LW   32

#define_eval CAMP_HASH_PAD_NN_ADDR   (CAMP_HASH_PAD_NN_IDX << 2)

#macro _camp_hash_define_LM_HANDLE()
    lm_handle_alloc(_CAMP_HASH_LM_HANDLE)
    #define_eval _CAMP_HASH_LM_HANDLE _LM_NEXT_HANDLE
    #define_eval _CAMP_HASH_LM_INDEX _LM_NEXT_INDEX
#endm

#macro camp_hash_init(MAX_KEY_LENGTH, pad_xfer)
.begin

    .init_csr mecsr:CtxEnables.NNreceiveConfig 0x2 const ; 0x2=NN path from CTM MiscEngine

    // Remove until THSDK-2266 fixed .declare_resource worker_nn global (128 * 4)
    // Allocate resource for NN registers to enable linker conflict check
    // Remove until THSDK-2266 fixed .alloc_resource CAMP_HASH_NN_BASE worker_nn+CAMP_HASH_PAD_NN_ADDR global (CAMP_HASH_PAD_SIZE_LW * 4) 4

    passert(MAX_KEY_LENGTH, "LE", (CAMP_HASH_PAD_SIZE_LW - 2))

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
    #define CAMP_HASH_MEM imem1
#elsei
    #define CAMP_HASH_MEM imem
#endif

    .alloc_mem CAMP_HASH_PAD_DATA CAMP_HASH_MEM global (CAMP_HASH_PAD_SIZE_LW * 4) 256

    // FUTURE TODO: wait here until CAMP_HASH_PAD_DATA is initialized with secure random data from the host
    // for now simply do a static init (to keep hash outputs predictable for debugging purposes)
    passert (CAMP_HASH_PAD_SIZE_LW, "EQ", 32)
    .init CAMP_HASH_PAD_DATA    0x05e37dc7 0x820bfd7f 0xc0a8d1d3 0x1e7433f4 \
                                0xa4e17724 0x22efe253 0xd04ea6bd 0xae676609 \
                                0xe4354df6 0xa76b008c 0xa8dec911 0x4a573ca8 \
                                0x2a85c196 0x31d0a299 0x5dae2d36 0x5ba9ea1f \
                                0x6c37b38f 0x3aee5498 0x2421f934 0x01f1ae08 \
                                0x993a96e7 0x9a1a6bf3 0x0bbc6452 0x57d85210 \
                                0xb1b60e52 0xee86be25 0x51cdac42 0x22d6cd1d \
                                0x15b6fa5f 0xc56d11f3 0xc8a2c9bb 0xe13a69d5

#ifndef _CAMP_HASH_INIT_EXECUTED

    // Execute the following only once per ME

    #define _CAMP_HASH_INIT_EXECUTED

    .reg offset
    .reg pad_base
    .reg reflect_base
    .sig sig_reflect
    .sig sig_reflected
    .sig sig_pad

    .if (ctx() == 0)
        local_csr_rd[ACTIVE_CTX_STS]
        immed[reflect_base, 0]
        alu[reflect_base, 0xf, AND, reflect_base, >>3]
        alu[reflect_base, --, B, reflect_base, <<17]
        alu[reflect_base, reflect_base, OR, __ISLAND, <<24]
        alu[reflect_base, reflect_base, OR, &sig_reflected, <<10]
        alu[reflect_base, reflect_base, OR, 0x01, <<9]
        alu[reflect_base, reflect_base, OR, CAMP_HASH_PAD_NN_IDX, <<2]


        move(pad_base, (CAMP_HASH_PAD_DATA >> 8))

        passert(CAMP_HASH_PAD_SIZE_LW, "MULTIPLE_OF", 8)
        move(offset, 0)
        .while (offset < (CAMP_HASH_PAD_SIZE_LW * 4))
            mem[read32, pad_xfer[0], pad_base, <<8, offset, 8], ctx_swap[sig_pad]
            aggregate_copy(pad_xfer, pad_xfer, 8)
            .set_sig sig_reflected
            ct[ctnn_write, pad_xfer[0], reflect_base, offset, 8], ctx_swap[sig_reflect]
            alu[offset, offset, +, (8 * 4)]
            ctx_arb[sig_reflected]
        .endw
    .endif

#endif //_CAMP_HASH_INIT_EXECUTED

.end
#endm

#macro _camp_hash_undef_LM_HANDLE()
    lm_handle_free(_CAMP_HASH_LM_HANDLE)
    #undef _CAMP_HASH_LM_HANDLE
    #undef _CAMP_HASH_LM_INDEX
#endm

#define _camp_hash_init_INSTRUCTIONS 3
#macro _camp_hash_init()
    local_csr_wr[CRC_REMAINDER, _CAMP_HASH_INIT]
    alu[_CAMP_HASH_STATE[0], _CAMP_HASH_INIT, +, *n$index++]
    alu[_CAMP_HASH_STATE[1], _CAMP_HASH_INIT, XOR, *n$index++]
#endm

#define _camp_hash_step_INSTRUCTIONS 5
#macro _camp_hash_step(IDX)
.begin
    .reg copy
    alu[_CAMP_HASH_STATE[0], _CAMP_HASH_STATE[0], +, _CAMP_HASH_LM_INDEX++]
    alu[_CAMP_HASH_STATE[0], _CAMP_HASH_STATE[0], XOR, *n$index++]
    crc_be[crc_32, copy, _CAMP_HASH_STATE[0]]
    alu[_CAMP_HASH_STATE[1], _CAMP_HASH_STATE[1], XOR, _CAMP_HASH_STATE[0]]
    dbl_shf[_CAMP_HASH_STATE[0], copy, _CAMP_HASH_STATE[0], >>indirect]
.end
#endm


#macro camp_hash(out_hash, in_key_address, in_key_length, MAX_KEY_LENGTH)
.begin
    #define_eval _CAMP_HASH_STATE out_hash
    #define_eval _CAMP_HASH_INIT in_key_length

    .reg crc
    .reg cpy
    .reg rot

    _camp_hash_define_LM_HANDLE()

    local_csr_wr[ACTIVE_LM_ADDR_/**/_CAMP_HASH_LM_HANDLE, in_key_address]
    local_csr_wr[NN_GET, CAMP_HASH_PAD_NN_IDX]

    unroll_for_each(in_key_length, 0, (MAX_KEY_LENGTH - 1), _camp_hash_step, _camp_hash_step, _camp_hash_init)

    _camp_hash_undef_LM_HANDLE()

    alu[cpy, _CAMP_HASH_STATE[0], B, _CAMP_HASH_STATE[1]]
    dbl_shf[rot, cpy, _CAMP_HASH_STATE[1], >>indirect]
    alu[_CAMP_HASH_STATE[0], _CAMP_HASH_STATE[0], XOR, rot]

    local_csr_rd[CRC_REMAINDER]
    immed[crc, 0]
    alu[_CAMP_HASH_STATE[0], _CAMP_HASH_STATE[0], +, crc]

    alu[cpy, _CAMP_HASH_STATE[1], B, _CAMP_HASH_STATE[0]]
    dbl_shf[rot, cpy, _CAMP_HASH_STATE[0], >>indirect]
    alu[_CAMP_HASH_STATE[1], _CAMP_HASH_STATE[1], XOR, rot]

    alu[_CAMP_HASH_STATE[1], _CAMP_HASH_STATE[1], XOR, crc]

.end
#endm


#endif
