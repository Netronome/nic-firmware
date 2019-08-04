/**
 * Copyright (C) 2014 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        nbi_pm.h
 * Description: NBI packet modifier constants and utilities.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __NBI_PM_H
#define __NBI_PM_H

#define PM_RWS_STATIC     0
#define PM_RWS_DYNAMIC    1


/* PM registers XPB address offsets */
#define PM_TGT_DEV_ADDR_OPCODE             0x38
#define PM_TGT_DEV_ADDR_RDATA             0x3A


/* RAM table for RW Script storage */

#define MU_RWS_TABLE_MEM    imem0
#define MU_RWS_NUM_ROWS    256
#define MU_RWS_ROW_SIZE     (8*4)
#define MU_RWS_TOTAL_SPACE      (MU_RWS_NUM_ROWS * MU_RWS_ROW_SIZE)

.alloc_mem MU_RWS_TABLE MU_RWS_TABLE_MEM global MU_RWS_TOTAL_SPACE 256
//.init MU_RWS_TABLE (0)

/* PM script operations */
#define PM_MOD_INSTR_OP_DEL             0x0
#define PM_MOD_INSTR_OP_INS             0x1
#define PM_MOD_INSTR_OP_REPLACE         0x2
#define PM_MOD_INSTR_OP_INC             0x3
#define PM_MOD_INSTR_OP_DEC             0x4
#define PM_MOD_INSTR_OP_MASK            0x5
#define PM_MOD_INSTR_OP_PAD             0x6
#define PM_MOD_INSTR_OP_NOOP            0x7


/* Rewrite Script word0 format */
#define PM_RWS_DIRECT_wrd                0
#define PM_RWS_DIRECT_shf               31
#define PM_RWS_DIRECT_bit               31

#define PM_RWS_OFFSET_LEN_shf           24
#define PM_RWS_OFFSET_LEN_msk          0x7

#define PM_RWS_OPCODE_shf               16
#define PM_RWS_OPCODE_msk             0xFF

#define PM_RWS_OFFSET_shf                8
#define PM_RWS_OFFSET_msk             0xFF

#define PM_RWS_RDATA_INDEX_shf           8
#define PM_RWS_RDATA_INDEX_msk        0xFF

#define PM_RWS_RDATA_LOC_shf             6
#define PM_RWS_RDATA_LOC_msk           0x3

#define PM_RWS_RDATA_LEN_shf             0
#define PM_RWS_RDATA_LEN_msk          0x3F


#define PKT_RWS_INDIRECT_OFFSET_SIZE_LW  2
#define PKT_RWS_INDIRECT_RDATA_SIZE_LW   5

#define_eval PKT_RWS_INDIRECT_MAX_SIZE_LW    (PKT_RWS_INDIRECT_OFFSET_SIZE_LW + PKT_RWS_INDIRECT_RDATA_SIZE_LW + 1)


/** OPCODE()
 * Build a rewrite script opcode from parameters
 *
 * @param _instruction      3-bit value defining the modification instruction:
 *                               0x0: delete             0x4: decrement
 *                               0x1: insert             0x5: mask replace for bit level granularity
 *                               0x2: replace            0x6: short packet padding
 *                               0x3: increment          0x7: NoOp (No Modification)
 * @param _bytes            4-bit value defining the bumber of bytes to be modified:
 *                               0x0: modify 1 byte / pad 60 bytes
 *                               0x1: modify 2 bytes / pad 62 bytes
 *                               ...              ....
 *                               0xe: modify 15 bytes / pad 88 bytes
 *                               0xf: modify 16 bytes / reserved
 * @param _rd_loc           1-bit indicating where to get the replacement data from (when 'rdata_loc'=b'10'):
 *                               0x0: from script        0x1: from config ram
*/
#define OPCODE(_instruction, _bytes, _rd_loc)            \
    (_bytes) > 0 ? ( ((_instruction & 0x7) << 5) | (((_bytes-1) & 0xF) << 1) | (_rd_loc & 0x1)) : ( ((_instruction & 0x7) << 5) | (_rd_loc & 0x1))


#define OPCODES_2WORDS(_opcode3, _opcode2, _opcode1, _opcode0)            \
    ( ((_opcode3 & 0xFF) << 24) | ((_opcode2 & 0xFF) << 16) | ((_opcode1 & 0xFF) << 8) | ((_opcode0 & 0xFF)))


#define INDIRECT_PREPEND_WORD(_offset_len, _opcode_index, _rdata_index, _rdata_loc, _rdata_len)            \
                ((0 << TM_RWS_DIRECT_shf) | \
                ((_offset_len & PM_RWS_OFFSET_LEN_msk) << PM_RWS_OFFSET_LEN_shf) | \
                ((_opcode_index & PM_RWS_OPCODE_msk) << PM_RWS_OPCODE_shf) | \
                ((_rdata_index & PM_RWS_RDATA_INDEX_msk) << PM_RWS_RDATA_INDEX_shf) | \
                ((_rdata_loc & PM_RWS_RDATA_LOC_msk) << PM_RWS_RDATA_LOC_shf) | \
                ((_rdata_len & PM_RWS_RDATA_LEN_msk) << PM_RWS_RDATA_LEN_shf))

#define RWS_GET_BYTE_FROM_WORD(_byte_num, _word)            \
                ((_word >> (8 * _byte_num)) & 0xFF)

#define RWS_GET_BYTE_FROM_WORDS(_byte_num, _word_4, _word_3, _word_2, _word_1, _word_0)            \
                (_byte_num > 3) ? ((_byte_num > 7) ? ((_byte_num > 11) ? ((_byte_num > 15) ? ((_byte_num > 19) ? 0x00 : (RWS_GET_BYTE_FROM_WORD((_byte_num - 16),_word_4))) : (RWS_GET_BYTE_FROM_WORD((_byte_num - 12),_word_3))) : (RWS_GET_BYTE_FROM_WORD((_byte_num - 8),_word_2))) : (RWS_GET_BYTE_FROM_WORD((_byte_num - 4),_word_1))) : (RWS_GET_BYTE_FROM_WORD((_byte_num - 0),_word_0))


#define OFFSETS_2WORDS(_offset3, _offset2, _offset1, _offset0)            \
                ( ((_offset3 & 0xFF) << 24) | ((_offset2 & 0xFF) << 16) | ((_offset1 & 0xFF) << 8) | ((_offset0 & 0xFF)))

#define OFFSETS_2STREAM(_offset7, _offset6, _offset5, _offset4,_offset3, _offset2, _offset1, _offset0)            \
                (OFFSETS_2WORDS(_offset7, _offset6, _offset5, _offset4)  | OFFSETS_2WORDS(_offset3, _offset2, _offset1, _offset0))


#define REVERSE_BYTES(_data, _this_byte, _total_bytes)            \
                (((_data >> (8 *_this_byte - 1)) & 0xFF) << (8 * (_total_bytes - _this_byte)))

 #define RWS_PACK_WORD(_len, _data)            \
                ((_len == 1) ? (REVERSE_BYTES(_data,1,4)) : ((_len == 2) ? (REVERSE_BYTES(_data,1,4) | REVERSE_BYTES(_data,2,4)) : ((_len == 3) ? (REVERSE_BYTES(_data,1,4) | REVERSE_BYTES(_data,2,4) | REVERSE_BYTES(_data,3,4)) : ((_len == 4) ? (REVERSE_BYTES(_data,1,4) | REVERSE_BYTES(_data,2,4) | REVERSE_BYTES(_data,3,4) | REVERSE_BYTES(_data,4,4)) : (0x0)))))

#define RWS_WORD_0(_len, _data) (_data<<1)

#define RWS_TOKEN_WORD(_script_index, _word_index) IND_RWS##_script_index##_W##_word_index
#define RWS_TOKEN_LEN(_script_index) IND_RWS##_script_index##_LEN

#define RDATA_2WORDS(_rdata)            \
                ((_rdata >> 64) & 0xFFFFFFFF) , ((_rdata >> 48) & 0xFFFFFFFF) , ((_rdata >> 32) & 0xFFFFFFFF), ((_rdata >> 16) & 0xFFFFFFFF) , ((_rdata >> 0) & 0xFFFFFFFF)

#define RWS_LENGTH(_rdata_len,_offset_len)            \
                (((4 + (_offset_len) + (_rdata_len) - 1) & (~0x7)) + 8 )


#endif /* __NBI_PM_H */
