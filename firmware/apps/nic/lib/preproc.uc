/*
 * Copyright (C) 2009-2014 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        preproc.uc
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _PREPROC_UC_
#define _PREPROC_UC_

/*
    TODO:
    gen mask, width from BF tuples? (Rather put in bitfields.uc)
    - array/list
        - Similar to va_list to read an entry from a comma separated list
        - Must also be able to "write" an entry in the list (a bit awkward without THSDK-173)
        - Must not store state between macro calls so that it can be used in nested code
        - Maybe macros to convert between csv list <-> packed array (like that in pbf.uc)?
    - Build jump targets? (Maybe use callback to construct next label?)
    - hex conversion (maybe also some other building blocks from/for pbf.uc)
    - FFS
    - Popcount
    - #define _dma_mask(width) ((width) > 31 ? 0xffffffff : ((1 << (width)) - 1))
    - #define _dma_dbl_shf(hi, lo, shf) ((((lo) >> (shf)) & _dma_mask((32 - (shf)))) | ((hi) << (32 - (shf))))

    Names of "output" preprocessor variables (TBD with or without OUT in name)
    PREPROC_OUT_LIST
    PREPROC_OUT_LIST_COUNT
    PREPROC_OUT_LIST_ITEM
    PREPROC_OUT_LIST_LEFT
    PREPROC_OUT_LIST_RIGHT
    PREPROC_OUT_TARGETS
*/




/*
*/
#macro preproc_list_len(LIST)

    preproc_list_parse(LIST, 0)

#endm


/*
*/
#macro preproc_list_get(LIST, INDEX)

    preproc_list_parse(LIST, INDEX)

#endm


/*
*/
#macro preproc_list_set(LIST, INDEX, ITEM)

    preproc_list_parse(LIST, INDEX)

    #define_eval PREPROC_LIST 'PREPROC_LIST_LEFT/**/ITEM/**/PREPROC_LIST_RIGHT'

#endm


/*
    Return:
        PREPROC_LIST
        PREPROC_LIST_COUNT = COUNT
*/
#macro preproc_list_create(VAL, COUNT)

    #if (COUNT < 1)
        #error "preproc_list_create: COUNT must be > 0" (COUNT)
    #endif

    #ifdef _PREPROC_LOOP
        #error "preproc_list_create: _PREPROC_LOOP is already defined"
    #endif


    #define_eval PREPROC_LIST 'VAL'

    #define _PREPROC_LOOP 0
    #while (_PREPROC_LOOP < (COUNT - 1))

        #define_eval PREPROC_LIST 'PREPROC_LIST,VAL'

        #define_eval _PREPROC_LOOP (_PREPROC_LOOP + 1)
    #endloop
    #undef _PREPROC_LOOP

    #define_eval PREPROC_LIST_COUNT (COUNT)

#endm


/*
    Return:
        PREPROC_LIST
        PREPROC_LIST_COUNT = COUNT
*/
#macro preproc_csv_list(PREFIX, SUFFIX, COUNT)

    #if (COUNT < 1)
        #error "preproc_csv_list: COUNT must be > 0" (COUNT)
    #endif

    #ifdef _PREPROC_LOOP
        #error "preproc_csv_list: _PREPROC_LOOP is already defined"
    #endif


    #define_eval PREPROC_LIST ''

    #define _PREPROC_LOOP 0
    #while (_PREPROC_LOOP < COUNT)

        // Build up the list
        #define_eval PREPROC_LIST 'PREPROC_LIST,PREFIX/**/_PREPROC_LOOP/**/SUFFIX'

    #define_eval _PREPROC_LOOP (_PREPROC_LOOP+1)
    #endloop
    #undef _PREPROC_LOOP

    // Remove the leading ','
    #define_eval PREPROC_LIST strright('PREPROC_LIST', -1)

    // Remove any leading and trailing spaces
    #define_eval PREPROC_LIST 'PREPROC_LIST'

    #define_eval PREPROC_LIST_COUNT (COUNT)

#endm


/*
    Return:
        PREPROC_LIST
        PREPROC_LIST_COUNT = COUNT
*/
#macro preproc_jump_targets(LABEL_BASE, COUNT)
    preproc_csv_list(LABEL_BASE, #, COUNT)
#endm


/*
    Return:
        PREPROC_LIST_ITEM
        PREPROC_LIST_COUNT
        PREPROC_LIST_LEFT
        PREPROC_LIST_RIGHT

    Parse the comma-separated list, count number of items, report errors.
    Set LEFT, MIDDLE and RIGHT?
    Set PREPROC_LIST_COUNT to number of items in the list
    Error if index was not within valid range 0 .. (PREPROC_LIST_COUNT-1)
    Error if list is empty?
*/
#macro preproc_list_parse(LIST, INDEX)

    // Ensure the identifiers that will be "returned" by this macro are undefined
    #ifdef PREPROC_LIST_ITEM
        #undef PREPROC_LIST_ITEM
    #endif

    #ifdef PREPROC_LIST_COUNT
        #undef PREPROC_LIST_COUNT
    #endif

    #ifdef PREPROC_LIST_LEFT
        #undef PREPROC_LIST_LEFT
    #endif

    #ifdef PREPROC_LIST_RIGHT
        #undef PREPROC_LIST_RIGHT
    #endif

    // Ensure internal identifiers are not already defined
    #if (defined(_PREPROC_LIST) + defined(_PREPROC_COMMA_POS) + defined(_PREPROC_BEG) + defined(_PREPROC_END) + defined(_PREPROC_LIST_LEFT) + defined(_PREPROC_LIST_RIGHT) + defined(_PREPROC_LIST_ITEM))
        #error "preproc_list_parse: One of the following is already defined" (_PREPROC_LIST _PREPROC_COMMA_POS _PREPROC_BEG _PREPROC_END _PREPROC_LIST_LEFT _PREPROC_LIST_RIGHT _PREPROC_LIST_ITEM)
    #endif

    // Append a comma to the local copy of the list to simplify the parsing loop
    #define_eval _PREPROC_LIST LIST
    #define_eval _PREPROC_LIST '_PREPROC_LIST,'

    #define_eval _PREPROC_END 0 // This will be the next _PREPROC_BEG
    #define_eval PREPROC_LIST_COUNT 0

    // While there is still a comma in the list...
    #while (strstr('_PREPROC_LIST', ",") > 0)

        // Find the position of the next comma
        #define_eval _PREPROC_COMMA_POS strstr('_PREPROC_LIST', ",")

        // Replace the comma with a colon in the working copy
        #define_eval _PREPROC_LIST_LEFT strleft('_PREPROC_LIST', _PREPROC_COMMA_POS - 1)
        #define_eval _PREPROC_LIST_RIGHT strright('_PREPROC_LIST', -_PREPROC_COMMA_POS)
        #define_eval _PREPROC_LIST '_PREPROC_LIST_LEFT:_PREPROC_LIST_RIGHT'

        #undef _PREPROC_LIST_LEFT
        #undef _PREPROC_LIST_RIGHT

        // The position of this item
        #define_eval _PREPROC_BEG _PREPROC_END
        #define_eval _PREPROC_END _PREPROC_COMMA_POS

        // Validate all items in the list
        #define_eval _PREPROC_LIST_ITEM strright(strleft('_PREPROC_LIST', _PREPROC_END - 1), -_PREPROC_BEG)
        #define_eval _PREPROC_LIST_ITEM '_PREPROC_LIST_ITEM'

        #if (strlen('_PREPROC_LIST_ITEM') < 1)
            // Get pristine copy of the list
            #define_eval _PREPROC_LIST LIST
            #error "preproc_list_parse: Not a valid argument" _PREPROC_LIST_ITEM "LIST:" _PREPROC_LIST
        #endif

        // Is this item at the index specified?
        #if (INDEX == PREPROC_LIST_COUNT)

            #define_eval PREPROC_LIST_ITEM '_PREPROC_LIST_ITEM'

            // Start with pristine copies of the list for left and right
            #define_eval PREPROC_LIST_LEFT LIST
            #define_eval PREPROC_LIST_RIGHT LIST

            #define_eval PREPROC_LIST_LEFT strleft('PREPROC_LIST_LEFT', _PREPROC_BEG)
            #define_eval PREPROC_LIST_RIGHT strright('PREPROC_LIST_RIGHT', -(_PREPROC_END - 1))

        #endif

        #undef _PREPROC_LIST_ITEM

        // Count number of items found
        #define_eval PREPROC_LIST_COUNT (PREPROC_LIST_COUNT + 1)

    #endloop

    // Ensure INDEX was in a valid range
    #if ((INDEX < 0) || (INDEX >= PREPROC_LIST_COUNT))
        #error "preproc_list_parse: INDEX is out of bounds" INDEX PREPROC_LIST_COUNT
    #endif

    // Clean up name space
    #undef _PREPROC_LIST
    #undef _PREPROC_COMMA_POS
    #undef _PREPROC_BEG
    #undef _PREPROC_END

#endm


/*
    The "Build|Verbose Output" flag must be on in PS to see the output of the #info directive.
*/
#macro preproc_list_display(LIST)

    #ifdef _PREPROC_LOOP
        #error "preproc_list_display: _PREPROC_LOOP is already defined"
    #endif

    // Get PREPROC_LIST_COUNT = len(LIST)
    preproc_list_len(LIST)

    #info "Contents of" LIST "("PREPROC_LIST_COUNT "items):"

    #define _PREPROC_LOOP 0
    #while (_PREPROC_LOOP < PREPROC_LIST_COUNT)

        preproc_list_get(LIST, _PREPROC_LOOP)

        #info "["_PREPROC_LOOP"] =" PREPROC_LIST_ITEM

        #define_eval _PREPROC_LOOP (_PREPROC_LOOP + 1)
    #endloop
    #undef _PREPROC_LOOP

#endm


/*
*/
#macro preproc_list_callback(callback_macro, LIST)

    #ifdef _PREPROC_CALLBACK_BUSY
        #error "preproc_list_callback: The callback macro may not call preproc_list_callback again"
    #endif

    #define _PREPROC_CALLBACK_BUSY 1

    #if (defined(_PREPROC_CALLBACK_LOOP) + defined(_PREPROC_CALLBACK_COUNT) + defined(_PREPROC_CALLBACK_ITEM))
        #error "preproc_list_callback: One of the following is already defined" _PREPROC_CALLBACK_LOOP _PREPROC_CALLBACK_COUNT _PREPROC_CALLBACK_ITEM
    #endif

    // Get PREPROC_LIST_COUNT = len(LIST)
    preproc_list_len(LIST)

    // Store local copy of count
    #define_eval _PREPROC_CALLBACK_COUNT PREPROC_LIST_COUNT

    #define _PREPROC_CALLBACK_LOOP 0
    #while (_PREPROC_CALLBACK_LOOP < _PREPROC_CALLBACK_COUNT)

        preproc_list_get(LIST, _PREPROC_CALLBACK_LOOP)

        // Store local copy of item
        #define_eval _PREPROC_CALLBACK_ITEM PREPROC_LIST_ITEM

        callback_macro(_PREPROC_CALLBACK_ITEM, _PREPROC_CALLBACK_LOOP, _PREPROC_CALLBACK_COUNT)

        #undef _PREPROC_CALLBACK_ITEM

        #define_eval _PREPROC_CALLBACK_LOOP (_PREPROC_CALLBACK_LOOP + 1)
    #endloop
    #undef _PREPROC_CALLBACK_LOOP
    #undef _PREPROC_CALLBACK_COUNT
    #undef _PREPROC_CALLBACK_BUSY

#endm


/*
    Convert the input VAL (constant expression) to a hexadecimal number of
    the form 0x%08x. The result is stored in PREPROC_NUMBER.

    PREPROC_NUMBER may safely be used as input (VAL).
*/
#macro preproc_hex(VAL)

    #if (defined(_PREPROC_HEX_IN) + defined(_PREPROC_HEX_OUT) + defined(_PREPROC_HEX_LOOP) + defined(_PREPROC_HEX_NIBBLE))
        #error "preproc_hex: One of the following is already defined" _PREPROC_HEX_IN _PREPROC_HEX_OUT _PREPROC_HEX_LOOP _PREPROC_HEX_NIBBLE
    #endif

    #if (!is_ct_const(VAL))
        #error "preproc_hex: The input VAL must be a compile time constant" (VAL)
    #endif

    #define_eval _PREPROC_HEX_IN (VAL)

    preproc_assert_32bit_const(_PREPROC_HEX_IN)

    #define_eval _PREPROC_HEX_OUT ''

    #define _PREPROC_HEX_LOOP 7 // TODO: support different widths?
    #while (_PREPROC_HEX_LOOP >= 0)

        #define_eval _PREPROC_HEX_NIBBLE ((_PREPROC_HEX_IN >> (_PREPROC_HEX_LOOP * 4)) & 0xf)
        #define_eval _PREPROC_HEX_NIBBLE strleft(strright("0123456789abcdef", 16 - _PREPROC_HEX_NIBBLE), 1)
        #define_eval _PREPROC_HEX_OUT '_PREPROC_HEX_OUT/**/_PREPROC_HEX_NIBBLE'

        #define_eval _PREPROC_HEX_LOOP (_PREPROC_HEX_LOOP - 1)

    #endloop
    #undef _PREPROC_HEX_LOOP

    #define_eval PREPROC_NUMBER '0x/**/_PREPROC_HEX_OUT'

    // Clean up name space
    #undef _PREPROC_HEX_IN
    #undef _PREPROC_HEX_OUT
    #undef _PREPROC_HEX_NIBBLE

#endm


/*
*/
#macro preproc_ffs(VAL)

    #if (defined(_PREPROC_FFS_IN) + defined(_PREPROC_FFS_OUT) + defined(_PREPROC_FFS_LOOP))
        #error "preproc_hex: One of the following is already defined" _PREPROC_FFS_IN _PREPROC_FFS_OUT _PREPROC_FFS_LOOP
    #endif

    #if (!is_ct_const(VAL))
        #error "preproc_ffs: The input VAL must be a compile time constant" (VAL)
    #endif

    #define_eval _PREPROC_FFS_IN (VAL)

    preproc_assert_32bit_const(_PREPROC_FFS_IN)


    #define_eval _PREPROC_FFS_OUT -1

    #define _PREPROC_FFS_LOOP 0
    #while (_PREPROC_FFS_LOOP < 32)

        #if (_PREPROC_FFS_IN & (1 << _PREPROC_FFS_LOOP)) // TODO will this work for both __PREPROC32 and __PREPROC64?
            #define_eval _PREPROC_FFS_OUT _PREPROC_FFS_LOOP
            #define_eval _PREPROC_FFS_LOOP 32
        #endif

        #define_eval _PREPROC_FFS_LOOP (_PREPROC_FFS_LOOP + 1)

    #endloop
    #undef _PREPROC_FFS_LOOP

    #define_eval PREPROC_NUMBER _PREPROC_FFS_LOOP

    // Clean up name space
    #undef _PREPROC_FFS_IN
    #undef _PREPROC_FFS_OUT

#endm


/*
*/
#macro preproc_assert_32bit_const(VAL)

    #ifdef _PREPROC_VAL
        #error "preproc_assert_32bit_const: _PREPROC_VAL is already defined" (_PREPROC_VAL)
    #endif

    #if (!is_ct_const(VAL))
        #error "preproc_assert_32bit_const: The input VAL must be a compile time constant" (VAL)
    #endif

    #define_eval _PREPROC_VAL (VAL)

    #if (defined(__PREPROC64))
        // Verify that the 64-bit number can be represented as a 32-bit number as used in immed32()
        #if ((_PREPROC_VAL > 0xFFFFFFFF) || (_PREPROC_VAL < -4294967295))
            #error "preproc_assert_32bit_const: Invalid 32-bit constant:" VAL "==" _PREPROC_VAL
        #endif
    #endif

    #undef _PREPROC_VAL

#endm


#endif // _PREPROC_UC_
