/*
 * Copyright (C) 2005-2014 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        lm_handle.uc
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _LM_HANDLE_UC_
#define _LM_HANDLE_UC_


/*

    TODO:

    Consider API to select between handles 0+1 and 2+3:
        #macro lm_handle_alloc(HANDLE) // 3, 2, then (0, 1), then err
        #macro lm_handle_alloc_io(HANDLE) //0, 1 or err
        #macro lm_handle_alloc(HANDLE, MASK) //0, 1 or err

*/


#ifdef __NFP6000
    // LM handle 1 is reserved for automatic GPR spilling. This is the only
    // handle that is currently fully supported by the spilling code in nfas.
    #define _LM_HANDLE_SPILLING         1       // Used for automatic GPR spilling
    #define _LM_HANDLE_VALID_MAP        0xd     // Bitmap of valid LM handles on the NFP-6xxx
#else
    #define _LM_HANDLE_VALID_MAP        3       // Bitmap of valid LM handles on the NFP-32xx
#endif


#define _LM_HANDLE_AVAILABLE_MAP        _LM_HANDLE_VALID_MAP    // Bitmap of LM handles available for alloc


/*
    Use:
        #macro define_SOME_LM_HANDLE()

            lm_handle_alloc(SOME_LM_HANDLE)
            #define_eval SOME_LM_HANDLE    _LM_NEXT_HANDLE
            #define_eval SOME_LM_INDEX     _LM_NEXT_INDEX

        #endm
*/
#macro lm_handle_alloc(HANDLE)

    #ifdef _LM_HANDLE_LOOP
        #error "lm_handle_alloc: '_LM_HANDLE_LOOP' is already defined" (_LM_HANDLE_LOOP)
    #endif

    #if (is_ct_const(HANDLE))
        #error "lm_handle_alloc: 'HANDLE' is already defined" (HANDLE)
    #endif

    #if (_LM_HANDLE_AVAILABLE_MAP == 0)
        #error "lm_handle_alloc: No LM handles are available"
    #endif

    #define _LM_HANDLE_LOOP 0
    #while (_LM_HANDLE_LOOP < 4)

        #if (_LM_HANDLE_AVAILABLE_MAP & (1 << _LM_HANDLE_LOOP))

            #define_eval _LM_HANDLE_AVAILABLE_MAP (_LM_HANDLE_AVAILABLE_MAP & ~(1 << _LM_HANDLE_LOOP))

            #define_eval _LM_NEXT_HANDLE    _LM_HANDLE_LOOP
            #define_eval _LM_NEXT_INDEX     '*l$index/**/_LM_HANDLE_LOOP'

            #define_eval _LM_HANDLE_LOOP 4  // Exit the loop

        #endif

        #define_eval _LM_HANDLE_LOOP (_LM_HANDLE_LOOP + 1)
    #endloop
    #undef _LM_HANDLE_LOOP

#endm


/*
    Use:
        #macro undef_SOME_LM_HANDLE()

            lm_handle_free(SOME_LM_HANDLE)
            #undef SOME_LM_HANDLE
            #undef SOME_LM_INDEX

        #endm
*/
#macro lm_handle_free(HANDLE)

    #if (!is_ct_const(HANDLE) || (HANDLE < 0) || (HANDLE > 3) || (~_LM_HANDLE_VALID_MAP & (1 << HANDLE)))
        #error "lm_handle_free: Invalid 'HANDLE'" (HANDLE) (_LM_HANDLE_VALID_MAP)
    #endif

    #if (_LM_HANDLE_AVAILABLE_MAP & (1 << HANDLE))
        #error "lm_handle_free: 'HANDLE' is already freed / not allocated" (HANDLE) (_LM_HANDLE_AVAILABLE_MAP)
    #endif

    #define_eval _LM_HANDLE_AVAILABLE_MAP (_LM_HANDLE_AVAILABLE_MAP | (1 << HANDLE))

#endm


/*
    Sanity check to ensure that all LM handles are freed.
*/
#macro lm_handle_sanity()

    #if (_LM_HANDLE_VALID_MAP != _LM_HANDLE_AVAILABLE_MAP)
        #error "lm_handle_sanity: There are still LM handles in use" (_LM_HANDLE_AVAILABLE_MAP) (_LM_HANDLE_VALID_MAP)
    #endif

#endm


#endif // _LM_HANDLE_UC_
