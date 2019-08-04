/*
 * Copyright (C) 2013 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        journal.uc
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _JOURNAL_UC_
#define _JOURNAL_UC_

#include <ring_utils.uc>
#include <ring_ext.uc>
//#include <ring_utils_ext.uc>

#ifndef JOURNAL_SIZE_LW
    #ifdef NO_DRAM
        #define JOURNAL_SIZE_LW 8192
    #else
        #define JOURNAL_SIZE_LW (1024*1024*8)
    #endif
#endif

#define JOURNAL_DELIMIT     0x2D2D2d00

#macro journal_declare(NAME, SIZE)
#ifdef JOURNAL_ENABLE

    .alloc_mem NAME/**/_journal emem0 global SIZE SIZE
    .alloc_resource NAME/**/_journal_ring emem0_queues global 1
    .load_mu_qdesc \
            emem0 NAME/**/_journal_ring \
            ((log2(SIZE >> 11) << 28) | (NAME/**/_journal & 0x3fffffc)) \
            ((NAME/**/_journal & 0xfffffffc) | 2) \
            ((NAME/**/_journal >> 8) & 0x3000000) \
            0

    #ifndef JOURNAL_DECLARED
    #define JOURNAL_DECLARED
    #endif

#endif
#endm


#macro journal_declare(NAME)
    journal_declare(NAME, (JOURNAL_SIZE_LW * 4))
#endm

#macro journal(NAME, WORD)
#ifdef JOURNAL_DECLARED
.begin
    .reg __addr_hi
    .reg __ringno

    #if (isnum(WORD))
        .reg __jdata
        move(__jdata, WORD)
        #define_eval __JDATA__ '__jdata'
    #else
        #define_eval __JDATA__ 'WORD'
    #endif

    alu[__addr_hi, --, B, (NAME/**/_journal >> 32), <<24]
    immed[__ringno, NAME/**/_journal_ring]
    alu[--, (1 << 3), OR, __ringno, <<16]
    mem[fast_journal, --, __addr_hi, <<8, __JDATA__], indirect_ref

    #undef __JDATA__

.end
#endif
#endm

#macro journal_multi_word(in_xfer, IN_COUNT, IN_NAME)
#ifdef JOURNAL_DECLARED
.begin
    .sig journal_sig
    ru_emem_ring_op(in_xfer, IN_NAME/**/_journal_ring, journal_sig, journal, IN_NAME/**/_journal, IN_COUNT, --)
.end
#endif
#endm


#macro journal_delim_xfer_decl(IN_LEN, IN_NAME)
#ifdef JOURNAL_ENABLE
    .reg write $journal_xfer_/**/IN_NAME[(IN_LEN + 1)]
    .xfer_order $journal_xfer_/**/IN_NAME
#endif
#endm

#macro journal_delim_xfer_add_word(in_data, IN_WORD, IN_NAME)
#ifdef JOURNAL_ENABLE
    #define_eval __WORD (IN_WORD + 1)
    move($journal_xfer_/**/IN_NAME[__WORD], in_data)
    #undef __WORD
#endif
#endm

#macro journal_delim_xfer_add_aggregate(in_src, IN_DST_IDX, IN_SRC_IDX, IN_COUNT, IN_NAME)
#ifdef JOURNAL_ENABLE
    aggregate_copy($journal_xfer_/**/IN_NAME, (1 + IN_DST_IDX), in_src, IN_SRC_IDX, IN_COUNT)
#endif
#endm

#macro journal_delim_multi_word(IN_JOURNAL_DELIMIT, IN_COUNT, IN_NAME)
#ifdef JOURNAL_DECLARED
.begin
    .sig journal_sig
    move($journal_xfer_/**/IN_NAME[0], (IN_JOURNAL_DELIMIT | IN_COUNT))
    #ifdef _JOURNAL_COUNT
        #error "_JOURNAL_COUNT is already defined"
    #endif
    #define_eval _JOURNAL_COUNT (IN_COUNT + 1)
    ru_emem_ring_op($journal_xfer_/**/IN_NAME, IN_NAME/**/_journal_ring, journal_sig, journal, IN_NAME/**/_journal, _JOURNAL_COUNT, --)
    #undef _JOURNAL_COUNT
.end
#endif
#endm

#endif // _JOURNAL_UC_
