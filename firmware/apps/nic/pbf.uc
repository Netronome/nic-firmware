/*
 * Copyright (C) 2009-2013 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        pbf.uc
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _PBF_UC_
#define _PBF_UC_


/*
    These macros can be used to build up multi-word bit field structures using
    the preprocessor only - no microcode is generated.

    Individual words can be extracted from the structure, or the structure can
    be returned as a comma-separated list.

    All the values returned (word or list) are 8-digit hexadecimal numbers
    with a 0x prefix (0x%08x). This allows the numbers to be used in .init
    directives which do not support the negative numbers returned by
    #define_eval when bit 31 is set.

    The 'array' of numbers are stored in the preprocessor string _PBF_PACKED
    as 8 hex nibbles per word with no delimiters or 0x prefixes.

    The same (WORD_INDEX, MSB, LSB) defined fields are used as in the
    bitfields.uc macros.

    Public preprocessor variables used:
    PBF_NUMBER holds the single word result returned by some macros.
    PBF_LIST holds the comma-separated list result returned by some macros.
    PBF_MASK holds the result returned by pbf_build_mask().
*/


#define PBF_MAX_LW      64  // Maximum number of words in the structure


/*
    Initialize the multi-word structure in _PBF_PACKED with zeros.

    NUM_LW is the number of words in the structure.
*/
#macro pbf_zero(NUM_LW)

    #if ((NUM_LW < 1) || (NUM_LW > PBF_MAX_LW))
        #error "Range" NUM_LW
    #endif

    #define _PBF_LOOP 0
    #define_eval _PBF_PACKED ''
    #while (_PBF_LOOP < NUM_LW)

        #define_eval _PBF_PACKED '_PBF_PACKED/**/00000000'

        #define_eval _PBF_LOOP (_PBF_LOOP + 1)

    #endloop
    #undef _PBF_LOOP

    // Catch potential errors
    #ifdef PBF_LIST
        #undef PBF_LIST
    #endif

#endm


/*
    Insert (set) a word in the multi-word structure (_PBF_PACKED).

    WIDX is the index of the word (constant expression) to write.
    VAL is the value (constant expression) to write.

    Note that PBF_NUMBER is used (changed) by this macro.
*/
#macro pbf_insert(WIDX, VAL)

    #define_eval _PBF_NIDX ((WIDX) * 8)
    #define_eval _PBF_LEN strlen('_PBF_PACKED')
    #if ((_PBF_NIDX < 0) || (_PBF_NIDX >= _PBF_LEN) || (_PBF_LEN % 8))
        #error "Insert" WIDX _PBF_LEN _PBF_PACKED
    #endif

    #define_eval _PBF_LEFT strleft('_PBF_PACKED', _PBF_NIDX)
    #if ((_PBF_LEN - _PBF_NIDX - 8) > 0)
        #define_eval _PBF_RIGHT strright('_PBF_PACKED', (_PBF_LEN - _PBF_NIDX - 8))
    #else
        // strright() does not return an empty string when token2 is 0
        #define_eval _PBF_RIGHT ''
    #endif

    pbf_hex(VAL)
    #define_eval _PBF_MIDDLE strright('PBF_NUMBER', 8)

    #define_eval _PBF_PACKED '_PBF_LEFT/**/_PBF_MIDDLE/**/_PBF_RIGHT'

    #if (strlen('_PBF_PACKED') != _PBF_LEN)
        #error "Insert" WIDX _PBF_LEN _PBF_LEFT _PBF_MIDDLE _PBF_RIGHT _PBF_PACKED
    #endif

#endm


/*
    Insert (set) a bit field in the multi-word structure (_PBF_PACKED).

    The constants (WIDX, MSB, LSB) defines the field to write.
    VAL is the value (constant expression) to write.

    Note that PBF_NUMBER is used (changed) by this macro.

    An error is raised if the field was non-zero, or if VAL is larger than the
    field.
*/
#macro pbf_insert(WIDX, MSB, LSB, VAL)

    #define_eval _PBF_IN (VAL)

    pbf_extract(WIDX)

    pbf_build_mask(MSB, LSB)

    #if ((PBF_NUMBER & (PBF_MASK << (LSB))) != 0)
        #error "Field was already non-zero" WIDX MSB LSB PBF_MASK PBF_NUMBER
    #endif

    #if ((_PBF_IN & ~PBF_MASK))
        #error "Value is bigger than mask" MSB LSB PBF_MASK _PBF_IN VAL
    #endif

    #define_eval PBF_NUMBER (PBF_NUMBER | (_PBF_IN << (LSB)))

    pbf_insert(WIDX, PBF_NUMBER)

#endm


/*
    Extract a word from the multi-word structure (_PBF_PACKED).

    WIDX is the index of the word (constant expression) to read.

    The extracted word is stored in PBF_NUMBER and is of the form
    0x%08x.
*/
#macro pbf_extract(WIDX)

    #define_eval _PBF_NIDX ((WIDX) * 8)
    #define_eval _PBF_LEN strlen('_PBF_PACKED')
    #if ((_PBF_NIDX < 0) || (_PBF_NIDX >= _PBF_LEN) || (_PBF_LEN % 8))
        #error "Extract" WIDX _PBF_LEN _PBF_PACKED
    #endif

    #define_eval _PBF_TMP strleft(strright('_PBF_PACKED', (_PBF_LEN - _PBF_NIDX)), 8)

    #define_eval PBF_NUMBER '0x/**/_PBF_TMP'

    #if (strlen('PBF_NUMBER') != 10)
        #error "Extract" WIDX PBF_NUMBER _PBF_PACKED
    #endif

#endm


/*
    Extract a bit field from the multi-word structure (_PBF_PACKED).

    The constants (WIDX, MSB, LSB) defines the field to read.

    The extracted field is stored in PBF_NUMBER and is of the form
    0x%08x.
*/
#macro pbf_extract(WIDX, MSB, LSB)

    pbf_extract(WIDX)

    pbf_build_mask(MSB, LSB)

    #define_eval PBF_NUMBER ((PBF_NUMBER >> (LSB)) & PBF_MASK)

    pbf_hex(PBF_NUMBER)

#endm


/*
    Convert the input VAL (constant expression) to a hexadecimal number of
    the form 0x%08x. The result is stored in PBF_NUMBER.

    PBF_NUMBER may safely be used as input (VAL).
*/
#macro pbf_hex(VAL)

    #define_eval _PBF_HEX_IN (VAL)

    #define_eval _PBF_HEX_OUT ''

    #define _PBF_HEX_LOOP 28
    #while (_PBF_HEX_LOOP >= 0)

        #define_eval _PBF_TMP ((_PBF_HEX_IN >> _PBF_HEX_LOOP) & 0xf)
        #define_eval _PBF_TMP strleft(strright("0123456789abcdef", 16 - _PBF_TMP), 1)
        #define_eval _PBF_HEX_OUT '_PBF_HEX_OUT/**/_PBF_TMP'

        #define_eval _PBF_HEX_LOOP (_PBF_HEX_LOOP - 4)

    #endloop
    #undef _PBF_HEX_LOOP

    #define_eval PBF_NUMBER '0x/**/_PBF_HEX_OUT'

#endm


/*
    Build a mask of width (MSB - LSB + 1). The result is stored in PBF_MASK.

    An error is raised if the field or mask does not fit in a word.
*/
#macro pbf_build_mask(MSB, LSB)

    #if ((LSB < 0) || (LSB > 31) || (MSB < 0) || (MSB > 31) || (LSB > MSB))
        #error "Mask" MSB LSB
    #endif

    #define_eval PBF_MASK ((MSB) - (LSB) + 1)

    // ((1 << 32) - 1) is not evaluated correctly
    #define_eval PBF_MASK ((PBF_MASK < 32) ? ((1 << PBF_MASK) - 1) : 0xffffffff)

#endm


/*
    Store the packed words from the multi-word structure (_PBF_PACKED) as a
    comma-separated list in PBF_LIST. All the words in the list will be of the
    form 0x%08x.
*/
#macro pbf_create_list()

    #define_eval _PBF_STOP (strlen('_PBF_PACKED') / 8)

    pbf_create_list(0, _PBF_STOP)

#endm


/*
    Do the same as pbf_create_list() except that only words from START to
    (STOP - 1) are stored in PBF_LIST.

    _PBF_PACKED is not modified, so this macro can be called multiple times.
*/
#macro pbf_create_list(START, STOP)

    #define_eval _PBF_NSTART ((START) * 8)
    #define_eval _PBF_NSTOP ((STOP) * 8)
    #define_eval _PBF_LEN strlen('_PBF_PACKED')

    #if ((_PBF_NSTART < 0) || (_PBF_NSTART >= _PBF_NSTOP) || (_PBF_NSTOP > _PBF_LEN) || (_PBF_LEN % 8))
        #error "List" _PBF_NSTART _PBF_NSTOP _PBF_LEN _PBF_PACKED
    #endif

    #define _PBF_LOOP _PBF_NSTART
    #define_eval PBF_LIST ''
    #while (_PBF_LOOP < _PBF_NSTOP)

        #define_eval _PBF_TMP strleft(strright('_PBF_PACKED', (_PBF_LEN - _PBF_LOOP)), 8)

        #define_eval PBF_LIST 'PBF_LIST,0x/**/_PBF_TMP'

        #define_eval _PBF_LOOP (_PBF_LOOP + 8)

    #endloop
    #undef _PBF_LOOP

    // Strip leading comma
    #define_eval PBF_LIST strright('PBF_LIST', -1)

#endm


/*
    Initialize a memory block with the list PBF_LIST.

    OFFSET (constant expression) is the byte offset from the memory block
    named 'name' where the initialization must start.

    Call pbf_create_list() first to create PBF_LIST.
*/
#macro pbf_init_mem_list(name, OFFSET)

    #define_eval _PBF_TMP (OFFSET)

    .init name+_PBF_TMP PBF_LIST

#endm


#macro pbf_init_aggregate_list(name, offset)

    #error "Not implemented"

#endm


#endif // _PBF_UC_
