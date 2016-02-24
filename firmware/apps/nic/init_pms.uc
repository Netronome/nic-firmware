/*
 * Copyright (C) 2014-2015 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        pms.uc
 *
 */

#ifndef _INIT_PMS_UC_
#define _INIT_PMS_UC_

#include <stdmac.uc>
#include <passert.uc>
#include <pbf.uc>
#include <nbi_pm.h>


#define PMS_TYPE_DEL            0
#define PMS_TYPE_VXLAN          1
#define PMS_TYPE_GRE            2

#if ((__REVISION_MIN < __REVISION_B0) && (__REVISION_MAX >= __REVISION_B0))
    #error "The range of chip revisions are not supported in a single build" __REVISION_MIN __REVISION_MAX
#endif

#if (__REVISION_MIN < __REVISION_B0)
    #define PMS_SCRIPT_OFS_MIN      8       // Length field = 0
    #define PMS_SCRIPT_OFS_MAX      56      // Length field = 6
#elif (__REVISION_MIN < __REVISION_C0)
    #define PMS_SCRIPT_OFS_MIN      32      // Length field = 3
    #define PMS_SCRIPT_OFS_MAX      120     // Length field = 14
#else
    #error "Unsupported chip revision" __REVISION_MIN __REVISION_MAX
#endif


#define PMS_DEL_PKT_OFS_MIN     (PMS_SCRIPT_OFS_MIN + 8)
#define PMS_DEL_PKT_OFS_MAX     (PMS_SCRIPT_OFS_MAX + (7 * 16) + 16)
#define PMS_DEL_PKT_OFS_STEP    2

#define PMS_ENTRIES(MIN, MAX, STEP) ((MAX - MIN + STEP) / STEP)

/*
    PMS_STRUCT is used with pbf macros to build up:
    - Indirect script to prepend to packet (3 LW)
    - Validity and where to write script (1 LW)
    - The Opcode Configuration (2 LW)
*/
#define PMS_STRUCT_DIRECT_bf            0, 31, 31
#define PMS_STRUCT_UNUSED_bf            0, 30, 27
#define PMS_STRUCT_OFFSET_LEN_bf        0, 26, 24
#define PMS_STRUCT_OPCODE_IDX_bf        0, 23, 16
#define PMS_STRUCT_RDATA_IDX_bf         0, 15, 8
#define PMS_STRUCT_RDATA_LOC_bf         0, 7, 6
#define PMS_STRUCT_RDATA_LEN_bf         0, 5, 0
#define PMS_STRUCT_OFFSET0_bf           1, 31, 24
#define PMS_STRUCT_OFFSET1_bf           1, 23, 16
#define PMS_STRUCT_OFFSET2_bf           1, 15, 8
#define PMS_STRUCT_OFFSET3_bf           1, 7, 0
#define PMS_STRUCT_OFFSET4_bf           2, 31, 24
#define PMS_STRUCT_OFFSET5_bf           2, 23, 16
#define PMS_STRUCT_OFFSET6_bf           2, 15, 8
#define PMS_STRUCT_OFFSET7_bf           2, 7, 0

#define PMS_STRUCT_VALID_bf             3, 31, 31
#define PMS_STRUCT_PREPEND_LEN0_bf      3, 9, 8     // Zero based ref_cnt
#define PMS_STRUCT_PREPEND_OFS_bf       3, 7, 0     // Max offset for B0 is 120

#define PMS_STRUCT_OP_INSTRUCT3_bf      4, 31, 29   // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES3_bf      4, 28, 25   // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA3_bf      4, 24, 24   // ModRdataOp

#define PMS_STRUCT_OP_INSTRUCT2_bf      4, 23, 21   // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES2_bf      4, 20, 17   // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA2_bf      4, 16, 16   // ModRdataOp

#define PMS_STRUCT_OP_INSTRUCT1_bf      4, 15, 13   // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES1_bf      4, 12, 9    // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA1_bf      4, 8, 8     // ModRdataOp

#define PMS_STRUCT_OP_INSTRUCT0_bf      4, 7, 5     // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES0_bf      4, 4, 1     // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA0_bf      4, 0, 0     // ModRdataOp

#define PMS_STRUCT_OP_INSTRUCT7_bf      5, 31, 29   // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES7_bf      5, 28, 25   // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA7_bf      5, 24, 24   // ModRdataOp

#define PMS_STRUCT_OP_INSTRUCT6_bf      5, 23, 21   // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES6_bf      5, 20, 17   // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA6_bf      5, 16, 16   // ModRdataOp

#define PMS_STRUCT_OP_INSTRUCT5_bf      5, 15, 13   // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES5_bf      5, 12, 9    // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA5_bf      5, 8, 8     // ModRdataOp

#define PMS_STRUCT_OP_INSTRUCT4_bf      5, 7, 5     // ModInstructOp
#define PMS_STRUCT_OP_NUMBYTES4_bf      5, 4, 1     // NumBytesOp
#define PMS_STRUCT_OP_MODRDATA4_bf      5, 0, 0     // ModRdataOp

#define PMS_STRUCT_SIZE_LW              4
#define PMS_STRUCT_SIZE                 (PMS_STRUCT_SIZE_LW << 2)

#define PM_OPCODE_CFG_0                 4
#define PM_OPCODE_CFG_1                 5

#define PM_PBF_SIZE_LW                  6
#define PM_PBF_SIZE                     (PM_PBF_SIZE_LW << 2)



/*
    Select the opcode / rdata configuration indices at compile time.

    Params:
        SCRIPT_TYPE:    Only PMS_TYPE_DEL currently supported
        DELTA_OFFSET:   The offset from start of script to start of packet

    PM_OPCODE_CFG_IDX is defined with the Opcode Configuration Index. (-1 if not available)
    PM_RDATA_CFG_IDX is defined with the Rdata Configuration Index. (-1 if not available)
*/
#macro _pms_configuration_indices(SCRIPT_TYPE, DELTA_OFFSET)

    #if (SCRIPT_TYPE != PMS_TYPE_DEL)
        #error "Only PMS_TYPE_DEL is currently supported"
    #endif

    passert(DELTA_OFFSET, "MULTIPLE_OF", PMS_DEL_PKT_OFS_STEP)

    // For now, just use opcode indices starting from 0
    #define_eval PM_OPCODE_CFG_IDX  (DELTA_OFFSET / PMS_DEL_PKT_OFS_STEP) // TODO step may differ for other types

    // Replacement data configuration is currently unused
    #define_eval PM_RDATA_CFG_IDX   0

#endm


#macro pms_init()

    _pms_init_del(PMS_DEL_PKT_OFS_MIN, PMS_DEL_PKT_OFS_MAX, PMS_DEL_PKT_OFS_STEP)
    //_pms_init_vxlan()
    //_pms_init_gre()

#endm


#macro _pms_init_del(PKT_OFS_MIN, PKT_OFS_MAX, PKT_OFS_STEP)

    _pms_passert(PKT_OFS_MIN, PKT_OFS_MAX, PKT_OFS_STEP)

    _pms_alloc(_PM_DEL_SCRIPTS, PKT_OFS_MIN, PKT_OFS_MAX, PKT_OFS_STEP)

/*
TODO test for and clean up namespace:
_PMS_PKT_OFS
_PMS_SCRIPT_OFS
_PMS_DELTA
_PMS_SCRIPT_LEN
...
*/
    #define_eval _PMS_PKT_OFS PKT_OFS_MIN
    // Loop through the supported packet offsets to build the lookup table
    #while (_PMS_PKT_OFS <= PKT_OFS_MAX)

        // Find the biggest offset where the script can start
        #if (__REVISION_MIN < __REVISION_B0)

            // A0 legal script offsets: 0=8, 1=16, 2=24, 3=32, 4=40, 5=48, 6=56
            #if (_PMS_PKT_OFS >= (56 + 8))
                #define_eval _PMS_SCRIPT_OFS 56
            #elif (_PMS_PKT_OFS >= (8 + 8))
                #define_eval _PMS_SCRIPT_OFS ((_PMS_PKT_OFS & ~7) - 8)
            #else
                #error "Unsupported packet offset (A0)" _PMS_PKT_OFS
            #endif

        #elif (__REVISION_MIN < __REVISION_C0)

            // B0 legal script offsets: 3=32, 4=40, 5=48, 6=56, 11=96, 12=104, 13=112, 14=120
            #if (_PMS_PKT_OFS >= (120 + 8))
                #define_eval _PMS_SCRIPT_OFS 120
            #elif (_PMS_PKT_OFS >= (96 + 8))
                #define_eval _PMS_SCRIPT_OFS ((_PMS_PKT_OFS & ~7) - 8)
            #elif (_PMS_PKT_OFS >= (56 + 8))
                #define_eval _PMS_SCRIPT_OFS 56
            #elif (_PMS_PKT_OFS >= (32 + 8))
                #define_eval _PMS_SCRIPT_OFS ((_PMS_PKT_OFS & ~7) - 8)
            #else
                #error "Unsupported packet offset (B0)" _PMS_PKT_OFS
            #endif

        #else
            #error "Unsupported chip revision" __REVISION_MIN __REVISION_MAX
        #endif

        passert(_PMS_SCRIPT_OFS, "GE", PMS_SCRIPT_OFS_MIN)
        passert(_PMS_SCRIPT_OFS, "LE", PMS_SCRIPT_OFS_MAX)


        // Delta between start of script and start of packet
        #define_eval _PMS_DELTA (_PMS_PKT_OFS - _PMS_SCRIPT_OFS)

        // Calculate script length
        #define_eval MAX_DEL_4_OFFSETS  (4 - 1) // There will also be a padding instruction
        #if ((_PMS_DELTA - 8) <= (MAX_DEL_4_OFFSETS * 16))
            // No more than 4 offsets will be required
            #define_eval _PMS_SCRIPT_LEN 8
            #define_eval DEL_8s 0
        #elif ((_PMS_DELTA - 16) <= (MAX_DEL_4_OFFSETS * 16))
            // Corner case: need longer script but must ensure that 4 deletes are still used
            #define_eval _PMS_SCRIPT_LEN 16
            #define_eval DEL_8s 2 // Delete the first 16B with 2x 8B delete opcodes
        #else
            // More than 4 offsets will be required
            #define_eval _PMS_SCRIPT_LEN 16
            #define_eval DEL_8s 0
        #endif

        #define_eval TO_DELETE (_PMS_DELTA - _PMS_SCRIPT_LEN)
;            passert(TO_DELETE, "IS_IN_RANGE", DEL_MIN, DEL_MAX)
;            passert(TO_DELETE, "MULTIPLE_OF", OFFSET_STEP)


        // TODO passert

        pbf_zero(PM_PBF_SIZE_LW)

        pbf_insert(PMS_STRUCT_DIRECT_bf, 0) // Always use indirect script


        #define_eval DEL_OFFSET 0

        #define_eval OP_IDX 0
        #while (TO_DELETE > 0)

            #define_eval THIS_DEL_LEN (TO_DELETE > 16 ? 16 : TO_DELETE)

            #if (DEL_8s)
                // Handle the corner case - ensure that there will be enough opcodes to maintain the script length
                #define_eval THIS_DEL_LEN 8
                #define_eval DEL_8s (DEL_8s - 1)
            #endif

            // Insert delete instruction
            pbf_insert(PMS_STRUCT_OP_INSTRUCT/**/OP_IDX/**/_bf, PM_MOD_INSTR_OP_DEL)
            pbf_insert(PMS_STRUCT_OP_NUMBYTES/**/OP_IDX/**/_bf, (THIS_DEL_LEN - 1))
            pbf_insert(PMS_STRUCT_OP_MODRDATA/**/OP_IDX/**/_bf, 1) // SP // TODO

            pbf_insert(PMS_STRUCT_OFFSET/**/OP_IDX/**/_bf, DEL_OFFSET)

            #define_eval DEL_OFFSET (DEL_OFFSET + THIS_DEL_LEN)
            #define_eval TO_DELETE (TO_DELETE - THIS_DEL_LEN)

            #define_eval OP_IDX (OP_IDX + 1)
        #endloop

        passert(OP_IDX, "LT", 8)


        // Insert short packet padding instruction
        pbf_insert(PMS_STRUCT_OP_INSTRUCT/**/OP_IDX/**/_bf, PM_MOD_INSTR_OP_PAD)
        pbf_insert(PMS_STRUCT_OP_NUMBYTES/**/OP_IDX/**/_bf, 0) // 0 -> pad to 60 bytes
        pbf_insert(PMS_STRUCT_OP_MODRDATA/**/OP_IDX/**/_bf, 1) // SP

        pbf_insert(PMS_STRUCT_OFFSET/**/OP_IDX/**/_bf, DEL_OFFSET)

        #define_eval OP_IDX (OP_IDX + 1)

        pbf_insert(PMS_STRUCT_OFFSET_LEN_bf, (OP_IDX > 0 ? (OP_IDX - 1) : 0))

        // Pad unused opcodes with NOPs
        #while (OP_IDX < 8)

            pbf_insert(PMS_STRUCT_OP_INSTRUCT/**/OP_IDX/**/_bf, PM_MOD_INSTR_OP_NOOP)
            pbf_insert(PMS_STRUCT_OP_NUMBYTES/**/OP_IDX/**/_bf, 0)
            pbf_insert(PMS_STRUCT_OP_MODRDATA/**/OP_IDX/**/_bf, 1) // SP

            #define_eval OP_IDX (OP_IDX + 1)
        #endloop


        // Determine the opcode configuration index (will be defined as PM_OPCODE_CFG_IDX)
        _pms_configuration_indices(PMS_TYPE_DEL, _PMS_DELTA)
        pbf_insert(PMS_STRUCT_OPCODE_IDX_bf, PM_OPCODE_CFG_IDX)

        pbf_insert(PMS_STRUCT_RDATA_IDX_bf, 0)
        pbf_insert(PMS_STRUCT_RDATA_LOC_bf, 1) // SP
        pbf_insert(PMS_STRUCT_RDATA_LEN_bf, 0)

        pbf_insert(PMS_STRUCT_VALID_bf, 1)
        pbf_insert(PMS_STRUCT_PREPEND_LEN0_bf, ((_PMS_SCRIPT_LEN / 4) - 1)) // Ready for zero-based length override
        pbf_insert(PMS_STRUCT_PREPEND_OFS_bf, _PMS_SCRIPT_OFS)


        #ifdef PMS_INIT_MEM
            pbf_create_list(0, PMS_STRUCT_SIZE_LW)
            pbf_init_mem_list(_PM_DEL_SCRIPTS, (PMS_STRUCT_SIZE * (_PMS_PKT_OFS - PKT_OFS_MIN) / PKT_OFS_STEP))
        #endif /* PMS_INIT_MEM */

        #ifdef PMS_INIT_TM
            pbf_extract(PM_OPCODE_CFG_0)
            .init_csr xpb:Nbi0IsldXpbMap.NbiTopXpbMap.PktModifier.NbiPmOpcodeRamCnfg.NbiPmOpcode32Cnfg0_/**/PM_OPCODE_CFG_IDX PBF_NUMBER
            #if (__nfp_has_island(9))
                .init_csr xpb:Nbi1IsldXpbMap.NbiTopXpbMap.PktModifier.NbiPmOpcodeRamCnfg.NbiPmOpcode32Cnfg0_/**/PM_OPCODE_CFG_IDX PBF_NUMBER
            #endif
            pbf_extract(PM_OPCODE_CFG_1)
            .init_csr xpb:Nbi0IsldXpbMap.NbiTopXpbMap.PktModifier.NbiPmOpcodeRamCnfg.NbiPmOpcode32Cnfg1_/**/PM_OPCODE_CFG_IDX PBF_NUMBER
            #if (__nfp_has_island(9))
                .init_csr xpb:Nbi1IsldXpbMap.NbiTopXpbMap.PktModifier.NbiPmOpcodeRamCnfg.NbiPmOpcode32Cnfg1_/**/PM_OPCODE_CFG_IDX PBF_NUMBER
            #endif
        #endif /* PMS_INIT_TM */

        #define_eval _PMS_PKT_OFS (_PMS_PKT_OFS + PKT_OFS_STEP)
    #endloop
    #undef _PMS_PKT_OFS

#endm


#macro _pms_passert(PKT_OFS_MIN, PKT_OFS_MAX, PKT_OFS_STEP)

    passert(PKT_OFS_STEP, "POWER_OF_2")
    passert(PKT_OFS_STEP, "GE", 1)
    passert(PKT_OFS_MIN, "MULTIPLE_OF", PKT_OFS_STEP)
    passert(PKT_OFS_MAX, "MULTIPLE_OF", PKT_OFS_STEP)
    passert(PKT_OFS_MAX, "GE", PKT_OFS_MIN)
    #if (PKT_OFS_MIN == PKT_OFS_MAX)
        passert(PKT_OFS_STEP, "EQ", 1)
    #endif

#endm


#macro _pms_alloc(SYMBOL, PKT_OFS_MIN, PKT_OFS_MAX, PKT_OFS_STEP)

    #ifdef PMS_INIT_MEM
        .alloc_mem SYMBOL cls island (PMS_ENTRIES(PKT_OFS_MIN, PKT_OFS_MAX, PKT_OFS_STEP) * PMS_STRUCT_SIZE) PMS_STRUCT_SIZE addr32
    #endif /* PMS_INIT_MEM */

#endm



//
// MAIN
//
    pms_init()


#endif // _INIT_PMS_UC_
