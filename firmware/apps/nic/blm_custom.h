/**
 * Copyright (C) 2015-2019,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file        nfp_blm_custom.h
 * @brief       A reasonable default buffer configuration file.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __NFP_BLM_CUSTOM_H__
#define __NFP_BLM_CUSTOM_H__

#if defined(__NFP_IS_38XX)
/* Don't override blm library partition calculation, allow flowenv to init */
#define BLM_RESERVE_NUM_CTM_PARTITIONS 0
#endif

#define BLM_NBI_BLQ1_CACHE_SIZE                 64
#define BLM_NBI_BLQ3_CACHE_SIZE                 64

#define NBI8_BLQ_EMU_0_PKTBUF_SIZE              10240
#define NBI8_BLQ_EMU_1_PKTBUF_SIZE              10240
#define NBI8_BLQ_EMU_2_PKTBUF_SIZE              10240
#define NBI8_BLQ_EMU_3_PKTBUF_SIZE              10240
#define NBI9_BLQ_EMU_0_PKTBUF_SIZE              10240
#define NBI9_BLQ_EMU_1_PKTBUF_SIZE              10240
#define NBI9_BLQ_EMU_2_PKTBUF_SIZE              10240
#define NBI9_BLQ_EMU_3_PKTBUF_SIZE              10240

#define BLM_NBI8_BLQ0_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)
#define BLM_NBI8_BLQ1_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)
#define BLM_NBI8_BLQ2_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)
#define BLM_NBI8_BLQ3_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)
#define BLM_NBI9_BLQ0_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)
#define BLM_NBI9_BLQ1_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)
#define BLM_NBI9_BLQ2_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)
#define BLM_NBI9_BLQ3_EMU_Q_LOCALITY            (MU_LOCALITY_HIGH)

#define BLM_NBI8_BLQ0_EMU_Q_ISLAND              24
#define BLM_NBI8_BLQ1_EMU_Q_ISLAND              24
#define BLM_NBI8_BLQ2_EMU_Q_ISLAND              24
#define BLM_NBI8_BLQ3_EMU_Q_ISLAND              24

#define BLM_NBI9_BLQ0_EMU_Q_ISLAND              24
#define BLM_NBI9_BLQ1_EMU_Q_ISLAND              24
#define BLM_NBI9_BLQ2_EMU_Q_ISLAND              24
#define BLM_NBI9_BLQ3_EMU_Q_ISLAND              24

#if defined(__NFP_LANG_ASM)
    #ifndef BLM_BLQ_EMEM_TYPE
        #define BLM_BLQ_EMEM_TYPE               emem
    #endif
#else
    #ifndef BLM_BLQ_EMEM_TYPE
        #define BLM_BLQ_EMEM_TYPE               BLM_MEM_TYPE_EMEM
    #endif
#endif

#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
    #define BLM_NBI8_BLQ0_Q_SIZE                    32768
    #define BLM_NBI8_BLQ1_Q_SIZE                    16384
#else
    #define BLM_NBI8_BLQ0_Q_SIZE                    4096
    #define BLM_NBI8_BLQ1_Q_SIZE                    4096
#endif

#define BLM_NBI8_BLQ2_Q_SIZE                    2048
#define BLM_NBI8_BLQ3_Q_SIZE                    1048576

#define BLM_NBI9_BLQ0_Q_SIZE                    2048
#define BLM_NBI9_BLQ1_Q_SIZE                    2048
#define BLM_NBI9_BLQ2_Q_SIZE                    2048
#define BLM_NBI9_BLQ3_Q_SIZE                    2048

/* EMU Rings buffers configuration */

/* NBI8 BLQs */
#if defined(__NFP_IS_38XX)
    #define BLM_NBI8_BLQ0_LEN                       512
    #define BLM_NBI8_BLQ1_LEN                       512
    #define BLM_NBI8_BLQ2_LEN                       512
    #define BLM_NBI8_BLQ3_LEN                       512

    /* NBI9 BLQs */
    #define BLM_NBI9_BLQ0_LEN                       512
    #define BLM_NBI9_BLQ1_LEN                       512
    #define BLM_NBI9_BLQ2_LEN                       512
    #define BLM_NBI9_BLQ3_LEN                       512
#else
    #define BLM_NBI8_BLQ0_LEN                       1024
    #define BLM_NBI8_BLQ1_LEN                       1024
    #define BLM_NBI8_BLQ2_LEN                       1024
    #define BLM_NBI8_BLQ3_LEN                       1024

    /* NBI9 BLQs */
    #define BLM_NBI9_BLQ0_LEN                       1024
    #define BLM_NBI9_BLQ1_LEN                       1024
    #define BLM_NBI9_BLQ2_LEN                       1024
    #define BLM_NBI9_BLQ3_LEN                       1024
#endif

/* EMU Ring 0 NBI8 */
#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
    #define BLM_NBI8_BLQ0_EMU_EMEM0_NUM_BUFS        7168
    #define BLM_NBI8_BLQ0_BDSRAM_EMEM0_NUM_BUFS     1024
    #define BLM_NBI8_BLQ0_EMU_EMEM0_DENSITY         1
#else
    #define BLM_NBI8_BLQ0_EMU_EMEM0_NUM_BUFS        1000
    #if defined(__NFP_IS_38XX)
        #define BLM_NBI8_BLQ0_BDSRAM_EMEM0_NUM_BUFS     500
    #else
        #define BLM_NBI8_BLQ0_BDSRAM_EMEM0_NUM_BUFS     1000
    #endif
    #define BLM_NBI8_BLQ0_EMU_EMEM0_DENSITY         1
#endif

#define BLM_NBI8_BLQ0_EMU_IMEM0_NUM_BUFS        0
#define BLM_NBI8_BLQ0_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI8_BLQ0_EMU_IMEM0_DENSITY         0
#define BLM_NBI8_BLQ0_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ0_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ0_EMU_EMEM1_DENSITY         0
#define BLM_NBI8_BLQ0_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ0_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ0_EMU_IMEM1_DENSITY         0
#define BLM_NBI8_BLQ0_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI8_BLQ0_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI8_BLQ0_EMU_EMEM2_DENSITY         0

/* EMU Ring 0 NBI9 */
#define BLM_NBI9_BLQ0_EMU_IMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ0_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ0_EMU_IMEM0_DENSITY         0
#define BLM_NBI9_BLQ0_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ0_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ0_EMU_IMEM1_DENSITY         0
#define BLM_NBI9_BLQ0_EMU_EMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ0_BDSRAM_EMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ0_EMU_EMEM0_DENSITY         0
#define BLM_NBI9_BLQ0_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ0_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ0_EMU_EMEM1_DENSITY         0
#define BLM_NBI9_BLQ0_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI9_BLQ0_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI9_BLQ0_EMU_EMEM2_DENSITY         0

/* EMU Ring 1 NBI8 */
#if (NS_PLATFORM_TYPE == NS_PLATFORM_CADMIUM_DDR_1x50)
    #define BLM_NBI8_BLQ1_EMU_EMEM0_NUM_BUFS        4096
    #define BLM_NBI8_BLQ1_EMU_EMEM0_DENSITY         1
    #define BLM_NBI8_BLQ1_EMU_IMEM0_NUM_BUFS        0
    #define BLM_NBI8_BLQ1_EMU_IMEM0_DENSITY         0
#else
    #if defined(__NFP_IS_38XX)
        #define BLM_NBI8_BLQ1_EMU_IMEM0_NUM_BUFS        0
        #define BLM_NBI8_BLQ1_EMU_IMEM0_DENSITY         0
        #define BLM_NBI8_BLQ1_EMU_EMEM0_NUM_BUFS        1000
        #define BLM_NBI8_BLQ1_EMU_EMEM0_DENSITY         1
    #elif defined(__NFP_IS_6XXX)
        #define BLM_NBI8_BLQ1_EMU_IMEM0_NUM_BUFS        350
        #define BLM_NBI8_BLQ1_EMU_IMEM0_DENSITY         1
        #define BLM_NBI8_BLQ1_EMU_EMEM0_NUM_BUFS        650
        #define BLM_NBI8_BLQ1_EMU_EMEM0_DENSITY         2
    #else
        #error "Please select valid chip target."
    #endif
#endif

#define BLM_NBI8_BLQ1_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI8_BLQ1_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ1_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ1_EMU_IMEM1_DENSITY         0
#define BLM_NBI8_BLQ1_BDSRAM_EMEM0_NUM_BUFS     0
#define BLM_NBI8_BLQ1_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ1_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ1_EMU_EMEM1_DENSITY         0
#define BLM_NBI8_BLQ1_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI8_BLQ1_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI8_BLQ1_EMU_EMEM2_DENSITY         0

/* EMU Ring 1 NBI9 */
#define BLM_NBI9_BLQ1_EMU_IMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ1_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ1_EMU_IMEM0_DENSITY         0
#define BLM_NBI9_BLQ1_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ1_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ1_EMU_IMEM1_DENSITY         0
#define BLM_NBI9_BLQ1_EMU_EMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ1_BDSRAM_EMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ1_EMU_EMEM0_DENSITY         0
#define BLM_NBI9_BLQ1_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ1_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ1_EMU_EMEM1_DENSITY         0
#define BLM_NBI9_BLQ1_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI9_BLQ1_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI9_BLQ1_EMU_EMEM2_DENSITY         0

/* EMU Ring 2 NBI8 */
#define BLM_NBI8_BLQ2_EMU_IMEM0_NUM_BUFS        0
#define BLM_NBI8_BLQ2_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI8_BLQ2_EMU_IMEM0_DENSITY         0
#define BLM_NBI8_BLQ2_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ2_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ2_EMU_IMEM1_DENSITY         0
#define BLM_NBI8_BLQ2_EMU_EMEM0_NUM_BUFS        0
#define BLM_NBI8_BLQ2_BDSRAM_EMEM0_NUM_BUFS     0
#define BLM_NBI8_BLQ2_EMU_EMEM0_DENSITY         0
#define BLM_NBI8_BLQ2_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ2_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ2_EMU_EMEM1_DENSITY         0
#define BLM_NBI8_BLQ2_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI8_BLQ2_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI8_BLQ2_EMU_EMEM2_DENSITY         0
/* EMU Ring 2 NBI9 */
#define BLM_NBI9_BLQ2_EMU_IMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ2_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ2_EMU_IMEM0_DENSITY         0
#define BLM_NBI9_BLQ2_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ2_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ2_EMU_IMEM1_DENSITY         0
#define BLM_NBI9_BLQ2_EMU_EMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ2_BDSRAM_EMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ2_EMU_EMEM0_DENSITY         0
#define BLM_NBI9_BLQ2_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ2_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ2_EMU_EMEM1_DENSITY         0
#define BLM_NBI9_BLQ2_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI9_BLQ2_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI9_BLQ2_EMU_EMEM2_DENSITY         0

/* EMU Ring 3 NBI8 */
#define BLM_NBI8_BLQ3_EMU_EMEM0_NUM_BUFS        64
#define BLM_NBI8_BLQ3_EMU_EMEM0_DENSITY         1
#define BLM_NBI8_BLQ3_EMU_IMEM0_NUM_BUFS        0
#define BLM_NBI8_BLQ3_EMU_IMEM0_DENSITY         0
#define BLM_NBI8_BLQ3_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI8_BLQ3_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ3_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ3_EMU_IMEM1_DENSITY         0
#define BLM_NBI8_BLQ3_BDSRAM_EMEM0_NUM_BUFS     0
#define BLM_NBI8_BLQ3_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI8_BLQ3_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI8_BLQ3_EMU_EMEM1_DENSITY         0
#define BLM_NBI8_BLQ3_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI8_BLQ3_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI8_BLQ3_EMU_EMEM2_DENSITY         0
/* EMU Ring 3 NBI9 */
#define BLM_NBI9_BLQ3_EMU_IMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ3_BDSRAM_IMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ3_EMU_IMEM0_DENSITY         0
#define BLM_NBI9_BLQ3_EMU_IMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ3_BDSRAM_IMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ3_EMU_IMEM1_DENSITY         0
#define BLM_NBI9_BLQ3_EMU_EMEM0_NUM_BUFS        0
#define BLM_NBI9_BLQ3_BDSRAM_EMEM0_NUM_BUFS     0
#define BLM_NBI9_BLQ3_EMU_EMEM0_DENSITY         0
#define BLM_NBI9_BLQ3_EMU_EMEM1_NUM_BUFS        0
#define BLM_NBI9_BLQ3_BDSRAM_EMEM1_NUM_BUFS     0
#define BLM_NBI9_BLQ3_EMU_EMEM1_DENSITY         0
#define BLM_NBI9_BLQ3_EMU_EMEM2_NUM_BUFS        0
#define BLM_NBI9_BLQ3_BDSRAM_EMEM2_NUM_BUFS     0
#define BLM_NBI9_BLQ3_EMU_EMEM2_DENSITY         0

#endif // __NFP_BLM_CONFIG_H__
