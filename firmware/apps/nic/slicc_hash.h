/*
 * Copyright 2017-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file   slicc_hash.h
 * @brief  Stereoscopic Locomotive Interleaved Cryptographic CRC Hash
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _SLICC_HASH_H
#define _SLICC_HASH_H

#define SLICC_HASH_PAD_NN_IDX           64
#define SLICC_HASH_PAD_SIZE_LW          40

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
    #define SLICC_HASH_MEM imem1
#else
    #define SLICC_HASH_MEM imem
#endif

#if defined(__NFP_LANG_ASM)
    // crytographic pad (should be initialized using secure random generator at boot)
    .alloc_mem SLICC_HASH_PAD_DATA SLICC_HASH_MEM global (SLICC_HASH_PAD_SIZE_LW * 4) 256

    // TODO: SLICC_HASH_PAD_DATA is initialized by host

    passert (SLICC_HASH_PAD_SIZE_LW, "EQ", 40)
    .init SLICC_HASH_PAD_DATA   0x65694ffa 0x43c6e6ae 0x363febf1 0x13bd5b2d \
                                0x94c52ed3 0xb87f801a 0x1cdf5125 0xe5268fc8 \
                                0xf2deff60 0x0ba40fa1 0x7e94d556 0xf23a4d9a \
                                0xf98e8783 0x2a5503e7 0x13d49e5b 0xc624e34f \
                                0xb15b73a9 0xe5e3723a 0x632e3ee3 0xa23b25c6 \
                                0xd080a55d 0x6fe12427 0x0966f217 0x6d5c6402 \
                                0x0a1f1588 0x6a88be4b 0xf6e1a460 0x7cb27130 \
                                0x5f5c36d3 0x1f083364 0xcb92793c 0xf3dc4e8f \
                                0xfd3caa85 0xbf9cda4b 0x0f06c66f 0x144776fa \
                                0x61dc0013 0x255dee97 0xd4586ee4 0xbae3d338

#elif defined(__NFP_LANG_MICROC)
    __asm {
        .alloc_mem SLICC_HASH_PAD_DATA SLICC_HASH_MEM global (SLICC_HASH_PAD_SIZE_LW * 4) 256
    }
#endif



#endif  /* _SLICC_HASH_H */
