// Stereoscopic Locomotive Interleaved Cryptographic CRC Hash
#ifndef _SLICC_HASH_H
#define _SLICC_HASH_H

#define SLICC_HASH_PAD_NN_IDX           64
#define SLICC_HASH_PAD_SIZE_LW          64

#if defined(__NFP_LANG_ASM)
    // crytographic pad (should be initialized using secure random generator at boot)
    .alloc_mem SLICC_HASH_PAD_DATA imem global (SLICC_HASH_PAD_SIZE_LW * 4) 256

    // TODO: SLICC_HASH_PAD_DATA is initialized by host

    passert (SLICC_HASH_PAD_SIZE_LW, "EQ", 64)
    .init SLICC_HASH_PAD_DATA   0x65694ffa 0x43c6e6ae 0x363febf1 0x13bd5b2d \
                                0x94c52ed3 0xb87f801a 0x1cdf5125 0xe5268fc8 \
                                0xf2deff60 0x0ba40fa1 0x7e94d556 0xf23a4d9a \
                                0xf98e8783 0x2a5503e7 0x13d49e5b 0xc624e34f \
                                0xb15b73a9 0xe5e3723a 0x632e3ee3 0xa23b25c6 \
                                0xd080a55d 0x6fe12427 0x0966f217 0x6d5c6402 \
                                0x0a1f1588 0x6a88be4b 0xf6e1a460 0x7cb27130 \
                                0x5f5c36d3 0x1f083364 0xcb92793c 0xf3dc4e8f \
                                0xfd3caa85 0xbf9cda4b 0x0f06c66f 0x144776fa \
                                0x61dc0013 0x255dee97 0xd4586ee4 0xbae3d338 \
                                0x2a4c8a8a 0x91c11957 0x22794666 0x642cc1c4 \
                                0x208a5013 0x8ee3a18b 0x0444e73c 0xbb827d6d \
                                0x129697a1 0x694255f1 0x0d0f091d 0xa4b8c6c2 \
                                0xcbc226af 0x885d3a4b 0x06033188 0x194af9e0 \
                                0x23aef7c7 0x0549d794 0xaf29adaf 0x6e8a569e \
                                0xe7c96807 0xb9f2540f 0x84a63436 0xec9107ec

#elif defined(__NFP_LANG_MICROC)
	__asm {
    	.alloc_mem SLICC_HASH_PAD_DATA imem global (SLICC_HASH_PAD_SIZE_LW * 4) 256
	}

#endif



#endif	/* _SLICC_HASH_H */
