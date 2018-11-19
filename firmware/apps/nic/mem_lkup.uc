/*
 * Copyright (C) 2018-2020 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   mem_lkup.uc
 * @brief  API for the MU LE
 */
#ifndef MEM_LKUP_UC
#define MEM_LKUP_UC


#define HASH_OP_CAMR32_16B 0x0  /**< CAM w/ result, 32b key, 16B bucket. */
#define HASH_OP_CAMR32_64B 0x1  /**< CAM w/ result, 32b key, 64B bucket. */
#define HASH_OP_CAMR48_64B 0x5  /**< CAM w/ result, 48b key, 64B bucket. */
#define HASH_OP_CAMR64_16B 0x8  /**< CAM w/ result, 64b key, 16B bucket. */
#define HASH_OP_CAMR64_64B 0x9  /**< CAM w/ result, 64b key, 64B bucket. */


/** CAM/linear hash base address field size (in bits). */
#define HASH_BASE_ADDR_FIELD_SZ     17

/** Mask for CAM/linear hash base address field. */
#define HASH_BASE_ADDR_FIELD_MASK  ((1 << HASH_BASE_ADDR_FIELD_SZ) - 1)

/** Minimum alignment boundary for CAM/linear hash tables. */
#define HASH_BASE_ADDR_MIN_ALIGN   0x10000

/** Maximum number of buckets for CAM/linear hash tables. */
#define HASH_MAX_NUM_BUCKETS       (1 << 17)

/** Minimum number of buckets for CAM/linear hash tables. */
#define HASH_MIN_NUM_BUCKETS       (1 << 10)

/** Maximum table size (in bytes) for CAM/linear hash tables w/ 16B buckets. */
#define HASH_16B_TABLE_SIZE_MAX    (HASH_MAX_NUM_BUCKETS << 4)

/** Minimum table size (in bytes) for CAM/linear hash tables w/ 16B buckets. */
#define HASH_16B_TABLE_SIZE_MIN    (HASH_MIN_NUM_BUCKETS << 4)

/** Maximum table size (in bytes) for CAM/linear hash tables w/ 64B buckets. */
#define HASH_64B_TABLE_SIZE_MAX    (HASH_MAX_NUM_BUCKETS << 6)

/** Minimum table size (in bytes) for CAM/linear hash tables w/ 64B buckets. */
#define HASH_64B_TABLE_SIZE_MIN    (HASH_MIN_NUM_BUCKETS << 6)

#define HASH_INT_EXT_LU_SHF         31
#define HASH_DIRECT_LOOKUP_SHF      30
#define HASH_LOOKUP_SHF             29
#define HASH_BASE_ADDR_SHF          12
#define HASH_TBL_SZ_SHF             8
#define HASH_OP_CODE_SHF            2
#define HASH_START_POS_SHF          0

#macro mem_lkup_init_hash_tbl(IN_TBL_NAME, IN_MEM, IN_NUM_BUCKETS, IN_BUCKET_SZ)
    #ifdef __TBL_SZ
        #error "__TBL_SZ is already defined"
    #endif

    #if (IN_NUM_BUCKETS < HASH_MIN_NUM_BUCKETS) || (IN_NUM_BUCKETS > HASH_MAX_NUM_BUCKETS)
        #error "IN_BUCKETS must be between (1 << 10) and (1 << 17)"
    #endif

    #if (IN_BUCKET_SZ == 64)
        #define_eval __TBL_SZ (IN_NUM_BUCKETS << 6)
    #elif (IN_BUCKET_SZ  == 16)
        #define_eval __TBL_SZ (IN_NUM_BUCKETS << 4)
    #else
        #error "IN_BUCKET_SZ can only be 16 or 64"
    #endif

    .alloc_mem IN_TBL_NAME IN_MEM global __TBL_SZ HASH_BASE_ADDR_MIN_ALIGN

    #undef __TBL_SZ
#endm

#macro mem_lkup_init_hash_addr(out_addr, in_addr, IN_OPCODE, IN_OFFSET, IN_NUM_BUCKETS, IN_BUCKET_SZ)
.begin
    #if (IN_OPCODE & 1)
        #define __LA 16
    #else
        #define __LA 14
    #endif

    #if (IN_BUCKET_SZ == 64)
        #define_eval __TBL_SZ_ENC ((LOG2(IN_NUM_BUCKETS << 6) - __LA) & 7)
    #elif (IN_BUCKET_SZ  == 16)
        #define_eval __TBL_SZ_ENC ((LOG2(IN_NUM_BUCKETS << 4) - __LA) & 7)
    #else
        #error "IN_BUCKET_SZ can only be 16 or 64"
    #endif

    #undef __LA

    move(out_addr[0], (in_addr >> 8) & 0xFF000000)

    move(out_addr[1], ((in_addr >> 8) & (1 << 31)) |
        (0 << HASH_DIRECT_LOOKUP_SHF) |
        (1 << HASH_LOOKUP_SHF) |
        (((in_addr >> 16) & HASH_BASE_ADDR_FIELD_MASK) << HASH_BASE_ADDR_SHF) |
        (__TBL_SZ_ENC << HASH_TBL_SZ_SHF) |
        (IN_OPCODE << HASH_OP_CODE_SHF) |
        (((IN_OFFSET >> 5) & 0x3) << HASH_START_POS_SHF))

    #undef __TBL_SZ_ENC


.end
#endm

#endif
