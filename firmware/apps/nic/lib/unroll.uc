/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   unroll.uc
 * @brief  Microcode library for explicit loop unrolling.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _UNROLL_
#define _UNROLL_

#include <passert.uc>
#include <preproc.uc>
#include <pkt_counter.uc>

pkt_counter_decl(unroll_overflow_err, 0)


#macro unroll_for_each(count, MIN_IDX, MAX_IDX, FIRST_OPS, OTHER_OPS, DEFER_OPS)
#ifdef _UNROLL_LOOP
    #warning "_UNROLL_LOOP is being redefined"
#endif

#if is_ct_const(count)
    #if (! streq('DEFER_OPS', '--'))
        DEFER_OPS()
        nop // for compatibility, a local_csr_write[] in first DEFER_OPS() slot would be permitted in the jump when count is not a ct_const
    #endif
    #define_eval _UNROLL_LOOP 0
    #if (count == (MAX_IDX - MIN_IDX + 1))
        FIRST_OPS(0)
        #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
    #endif
    #while (_UNROLL_LOOP < count)
        OTHER_OPS(_UNROLL_LOOP)
        #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
    #endloop
#else
.begin
    .reg unroll_jump

    alu[unroll_jump, (MAX_IDX - MIN_IDX + 1), -, count]
    blo[overflow#]
    #if (OTHER_OPS/**/_INSTRUCTIONS > 1)
        #if ( ( (OTHER_OPS/**/_INSTRUCTIONS) & ((OTHER_OPS/**/_INSTRUCTIONS) - 1) ) == 0 )
            alu[unroll_jump, --, B, unroll_jump, <<(log2(OTHER_OPS/**/_INSTRUCTIONS))]
        #else
            passert(OTHER_OPS/**/_INSTRUCTIONS, "LE", 255)
            mul_step[unroll_jump, OTHER_OPS/**/_INSTRUCTIONS], 24x8_start
            mul_step[unroll_jump, OTHER_OPS/**/_INSTRUCTIONS], 24x8_step1
            mul_step[unroll_jump, --], 24x8_last
        #endif
    #endif

    preproc_jump_targets(landing_strip, (MAX_IDX - MIN_IDX + 1))

    #if (streq('DEFER_OPS', '--'))
        jump[unroll_jump, landing_strip0#], targets[PREPROC_LIST]
overflow#:
    #else
        passert(DEFER_OPS/**/_INSTRUCTIONS, "LE", 3)
        jump[unroll_jump, landing_strip0#], targets[PREPROC_LIST], defer[DEFER_OPS/**/_INSTRUCTIONS]
overflow#:
        DEFER_OPS()
    #endif

    pkt_counter_incr(unroll_overflow_err)

    #if (FIRST_OPS/**/_INSTRUCTIONS > OTHER_OPS/**/_INSTRUCTIONS)
        br[landing_strip/**/MIN_IDX#]

        first_ops#:
        #if (FIRST_OPS/**/_INSTRUCTIONS < 3)
            br[other_ops#], defer[FIRST_OPS/**/_INSTRUCTIONS]
            FIRST_OPS(MIN_IDX)
        #else
            FIRST_OPS(MIN_IDX)
            br[other_ops#]
        #endif
    #elif (! defined(PACKET_COUNTER_ENABLED))
        nop_volatile // needed to match extra cycle of jump branch penalty for equivalent handling of DEFER_OPS() when packet counters are disabled
    #endif

    landing_strip/**/MIN_IDX#:
    #if (FIRST_OPS/**/_INSTRUCTIONS > OTHER_OPS/**/_INSTRUCTIONS)
        br[first_ops#]
        #define_eval _UNROLL_LOOP 1
        #while (_UNROLL_LOOP < OTHER_OPS/**/_INSTRUCTIONS)
            nop_volatile
            #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
        #endloop
    #else
        FIRST_OPS(MIN_IDX)
        #define_eval _UNROLL_LOOP FIRST_OPS/**/_INSTRUCTIONS
        #while (_UNROLL_LOOP < OTHER_OPS/**/_INSTRUCTIONS)
            nop_volatile
            #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
        #endloop
    #endif

    other_ops#:
    #define_eval _UNROLL_LOOP (MIN_IDX + 1)
    #while (_UNROLL_LOOP <= (MAX_IDX))
    landing_strip/**/_UNROLL_LOOP#:
        OTHER_OPS(_UNROLL_LOOP)
        #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
    #endloop
.end
#endif
#undef _UNROLL_LOOP
#endm


#macro unroll_for_each(count, MIN_IDX, MAX_IDX, FIRST_OPS, OTHER_OPS)
    unroll_for_each(count, MIN_IDX, MAX_IDX, FIRST_OPS, OTHER_OPS, --)
#endm


#macro unroll_for_each(count, MIN_IDX, MAX_IDX, OPS)
    unroll_for_each(count, MIN_IDX, MAX_IDX, OPS, OPS, --)
#endm


#macro _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, MAX_COUNT)
    #ifdef _UNROLL_DST
        #warning "_UNROLL_DST is being redefined"
    #endif

    #ifdef _UNROLL_DST_IDX
        #warning "_UNROLL_DST_IDX is being redefined"
    #endif

    #ifdef _UNROLL_SRC
        #warning "_UNROLL_SRC is being redefined"
    #endif

    #ifdef _UNROLL_SRC_IDX
        #warning "_UNROLL_SRC_IDX is being redefined"
    #endif

    #if (streq('++', 'DST_IDX'))
        #define _UNROLL_DST_IDX ++
    #elif (streq('--', 'DST_IDX'))
        #define _UNROLL_DST_IDX --
    #else
        #define_eval _UNROLL_DST_IDX (DST_IDX + MAX_COUNT - 1)
    #endif

    #if (streq('++', 'SRC_IDX'))
        #define _UNROLL_SRC_IDX ++
    #elif (streq('--', 'SRC_IDX'))
        #define _UNROLL_SRC_IDX --
    #else
        #define_eval _UNROLL_SRC_IDX (SRC_IDX + MAX_COUNT - 1)
    #endif

    #define_eval _UNROLL_DST dst
    #define_eval _UNROLL_SRC src
#endm


#macro _unroll_undef_indices()
    #undef _UNROLL_DST
    #undef _UNROLL_DST_IDX
    #undef _UNROLL_SRC
    #undef _UNROLL_SRC_IDX
#endm

#define _UNROLL_COPY_INSTRUCTIONS 1
#macro _UNROLL_COPY(IDX)
    #if (!strstr('|++|--|', '|_UNROLL_DST_IDX|') && !strstr('|++|--|', '|_UNROLL_SRC_IDX|'))
        alu[_UNROLL_DST[(_UNROLL_DST_IDX - IDX)], --, B, _UNROLL_SRC[(_UNROLL_SRC_IDX - IDX)]]
    #elif (!strstr('|++|--|', '|_UNROLL_DST_IDX|') && strstr('|++|--|', '|_UNROLL_SRC_IDX|'))
        alu[_UNROLL_DST[(_UNROLL_DST_IDX - IDX)], --, B, _UNROLL_SRC/**/_UNROLL_SRC_IDX]
    #elif (strstr('|++|--|', '|_UNROLL_DST_IDX|') && !strstr('|++|--|', '|_UNROLL_SRC_IDX|'))
        alu[_UNROLL_DST/**/_UNROLL_DST_IDX, --, B, _UNROLL_SRC[(_UNROLL_SRC_IDX - IDX)]]
    #else
        alu[_UNROLL_DST/**/_UNROLL_DST_IDX, --, B, _UNROLL_SRC/**/_UNROLL_SRC_IDX]
    #endif
#endm


/**
 * Efficiently copy a given number of elements (where the count is a runtime value up to MAX_COUNT)
 * from source to destination aggregates using the given indices. Note that when a post-increment
 * index register is used for either the source or destination (not both) then the order of elements
 * is reversed during the copy operation. This is a natural side effect of the internal mechanism,
 * which copies elements in reverse order by means of a jump landing strip that copies the balance
 * of the aggregate. The reversal of elements is of little consequence if both read and write
 * transactions are mediated via unroll_*() calls, however, it is nevertheless a quirk of the
 * implementation which users should be aware of. If an in order copy is desired then the index
 * should be initialized to the tail end of the appropriate aggregate and a post-decrement index
 * should be used instead.
 *
 * @param dst       Destination aggregate
 * @param DST_IDX   Index of the 1st register of dst
 * @param src       Source aggregate
 * @param SRC_IDX   Index of the 1st register of src
 * @param count     The number of elements to be copied from src to dst (known at runtime)
 * @param MAX_COUNT The maximum value (a compile time value) that count may be at runtime
 * @param DEFER_OPS A macro refence containing up to 3 instructions that will be placed in the defer
 *                  shadow of the internally used jump instruction (ie. immediately before the unrolled
 *                  copy loop is executed). It is acceptable to set an LM pointer used within the loop
 *                  as the first of these instructions, as the jump instruction incurs a 4 cycle branch
 *                  latency that covers the 3 cycle local_csr_wr latency. The number of instructions
 *                  provided by DEFER_OPS must be given by the preprocessor defined [DEFER_OPS]_INSTRUCTIONS.
 */
#macro unroll_copy(dst, DST_IDX, src, SRC_IDX, count, MAX_COUNT, DEFER_OPS)
    #if (is_ct_const(count))
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, count)
    #else
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, MAX_COUNT)
    #endif

    #if (!strstr('|++|--|', '|_UNROLL_DST_IDX|'))
        #ifdef _UNROLL_LOOP
            #warning "_UNROLL_LOOP is being redefined"
        #endif
        #define _UNROLL_LOOP 0
        #while (_UNROLL_LOOP < MAX_COUNT)
            .set _UNROLL_DST[(_UNROLL_DST_IDX - _UNROLL_LOOP)]
            #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
        #endloop
        #undef _UNROLL_LOOP
    #endif

    unroll_for_each(count, 0, (MAX_COUNT - 1), _UNROLL_COPY, _UNROLL_COPY, DEFER_OPS)

    _unroll_undef_indices()
#endm


#macro unroll_copy(dst, DST_IDX, src, SRC_IDX, count, MAX_COUNT)
    unroll_copy(dst, DST_IDX, src, SRC_IDX, count, MAX_COUNT, --)
#endm


#macro unroll_copy(dst, DST_IDX, src, SRC_IDX, count, MAX_COUNT, FIRST_OPS, DEFER_OPS)
    #if (is_ct_const(count))
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, count)
    #else
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, MAX_COUNT)
    #endif

    #if (!strstr('|++|--|', '|_UNROLL_DST_IDX|'))
        #ifdef _UNROLL_LOOP
            #warning "_UNROLL_LOOP is being redefined"
        #endif
        #define _UNROLL_LOOP 1
        #if (is_ct_const(count))
            #while (_UNROLL_LOOP < count)
                .set _UNROLL_DST[(_UNROLL_DST_IDX - _UNROLL_LOOP)]
                #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
            #endloop
        #else
            #while (_UNROLL_LOOP < MAX_COUNT)
                .set _UNROLL_DST[(_UNROLL_DST_IDX - _UNROLL_LOOP)]
                #define_eval _UNROLL_LOOP (_UNROLL_LOOP + 1)
            #endloop
        #endif
        #undef _UNROLL_LOOP
    #endif

    unroll_for_each(count, 0, (MAX_COUNT - 1), FIRST_OPS, _UNROLL_COPY, DEFER_OPS)

    _unroll_undef_indices()
#endm


#define _UNROLL_COMPARE_INSTRUCTIONS 2
#macro _UNROLL_COMPARE(IDX)
    #if (!strstr('|++|--|', '|_UNROLL_DST_IDX|') && !strstr('|++|--|', '|_UNROLL_SRC_IDX|'))
        alu[--, _UNROLL_DST[(_UNROLL_DST_IDX - IDX)], -, _UNROLL_SRC[(_UNROLL_SRC_IDX - IDX)]]
    #elif (!strstr('|++|--|', '|_UNROLL_DST_IDX|') && strstr('|++|--|', '|_UNROLL_SRC_IDX|'))
        alu[--, _UNROLL_DST[(_UNROLL_DST_IDX - IDX)], -, _UNROLL_SRC/**/_UNROLL_SRC_IDX]
    #elif (strstr('|++|--|', '|_UNROLL_DST_IDX|') && !strstr('|++|--|', '|_UNROLL_SRC_IDX|'))
        alu[--, _UNROLL_DST/**/_UNROLL_DST_IDX, -, _UNROLL_SRC[(_UNROLL_SRC_IDX - IDX)]]
    #else
        alu[--, _UNROLL_DST/**/_UNROLL_DST_IDX, -, _UNROLL_SRC/**/_UNROLL_SRC_IDX]
    #endif
    bne[_UNROLL_COMPARE_DIFFERS_LABEL]
#endm


#macro unroll_compare(dst, DST_IDX, src, SRC_IDX, DIFFERS_LABEL, count, MAX_COUNT, DEFER_OPS)
    #if (is_ct_const(count))
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, count)
    #else
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, MAX_COUNT)
    #endif

    #define_eval _UNROLL_COMPARE_DIFFERS_LABEL DIFFERS_LABEL

    unroll_for_each(count, 0, (MAX_COUNT - 1), _UNROLL_COMPARE, _UNROLL_COMPARE, DEFER_OPS)

    #undef _UNROLL_COMPARE_DIFFERS_LABEL

    _unroll_undef_indices()
#endm


#macro unroll_compare(dst, DST_IDX, src, SRC_IDX, DIFFERS_LABEL, count, MAX_COUNT, FIRST_OPS, DEFER_OPS)
    #if (is_ct_const(count))
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, count)
    #else
        _unroll_define_indices(dst, DST_IDX, src, SRC_IDX, MAX_COUNT)
    #endif

    #define_eval _UNROLL_COMPARE_DIFFERS_LABEL DIFFERS_LABEL

    unroll_for_each(count, 0, (MAX_COUNT - 1), FIRST_OPS, _UNROLL_COMPARE, DEFER_OPS)

    #undef _UNROLL_COMPARE_DIFFERS_LABEL

    _unroll_undef_indices()
#endm


#macro unroll_compare(dst, DST_IDX, src, SRC_IDX, DIFFERS_LABEL, count, MAX_COUNT)
    unroll_compare(dst, DST_IDX, src, SRC_IDX, DIFFERS_LABEL, count, MAX_COUNT, --)
#endm


#endif
