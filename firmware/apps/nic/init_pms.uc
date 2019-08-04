/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file  init_pms.uc
 * @brief Initialization of packet modifier indirect scripts.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _INIT_PMS_UC_
#define _INIT_PMS_UC_

#macro hex_format(VALUE)
    #define_eval _HEX_IN (VALUE)
    #define_eval _HEX_OUT ''

    #define _HEX_LOOP 28
    #while (_HEX_LOOP >= 0)
        #define_eval _HEX_TMP ((_HEX_IN >> _HEX_LOOP) & 0xf)
        #define_eval _HEX_TMP strleft(strright("0123456789abcdef", 16 - _HEX_TMP), 1)
        #define_eval _HEX_OUT '_HEX_OUT/**/_HEX_TMP'
        #define_eval _HEX_LOOP (_HEX_LOOP - 4)
        #undef _HEX_TMP
    #endloop
    #undef _HEX_LOOP

    #define_eval HEX_OUT '0x/**/_HEX_OUT'
#endm

#define PM_SCRIPT 0
#while (PM_SCRIPT <= 112)

    // rdata = 1
    #define_eval OPCODES 0x0101010101010101

    // render delete opcodes
    #define_eval PMS_DEL_BYTES (PM_SCRIPT)
    #define_eval PMS_DEL_SHIFT 1
    #while (PMS_DEL_BYTES != 0)
        #if (PMS_DEL_BYTES <= 16)
            #define_eval OPCODES (OPCODES | ((PMS_DEL_BYTES - 1) << PMS_DEL_SHIFT))
            #define_eval PMS_DEL_BYTES (0)
        #else
            #define_eval OPCODES (OPCODES | (15 << PMS_DEL_SHIFT))
            #define_eval PMS_DEL_BYTES (PMS_DEL_BYTES - 16)
        #endif
        #define_eval PMS_DEL_SHIFT (PMS_DEL_SHIFT + 8)
    #endloop

    // make last opcode pad packet to length
    #define_eval OPCODES (OPCODES | (0xc0 << (((PM_SCRIPT + 15) / 16) * 8)))

    // fill remaining opcodes with NOPs
    #define_eval NOP_COUNT 1
    #while ((OPCODES & 0x8000000000000000) == 0)
        #define_eval OPCODES (OPCODES | (0xe0 << ((NOP_COUNT + ((PM_SCRIPT + 15) / 16)) * 8)))
        #define_eval NOP_COUNT (NOP_COUNT + 1)
    #endloop

    hex_format(OPCODES)
    .init_csr xpb:Nbi0IsldXpbMap.NbiTopXpbMap.PktModifier.NbiPmOpcodeRamCnfg.NbiPmOpcode32Cnfg0_/**/PM_SCRIPT HEX_OUT

    hex_format(OPCODES >> 32)
    .init_csr xpb:Nbi0IsldXpbMap.NbiTopXpbMap.PktModifier.NbiPmOpcodeRamCnfg.NbiPmOpcode32Cnfg1_/**/PM_SCRIPT HEX_OUT

#define_eval PM_SCRIPT (PM_SCRIPT + 1)
#endloop

#endif // _INIT_PMS_UC_
