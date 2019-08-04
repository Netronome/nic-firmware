/*
 * Copyright (C) 2009-2011 Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __TIMESTAMP_UC__
#define __TIMESTAMP_UC__

#ifndef NFP_LIB_ANY_NFAS_VERSION
    #if (!defined(__NFP_TOOL_NFAS) ||                       \
        (__NFP_TOOL_NFAS < NFP_SW_VERSION(5, 0, 0, 0)) ||   \
        (__NFP_TOOL_NFAS > NFP_SW_VERSION(5, 255, 255, 255)))
        #error "This standard library is not supported for the version of the SDK currently in use."
    #endif
#endif

#include <stdmac.uc>


/** @file timestamp.uc Timestamp Macros
 * @addtogroup timestamp Timestamp
 * @{
 *
 * @name Timestamp Macros
 * @{
 *
 */


/** Enable global time stamp in CAP MISC_CONTROL CSR and set TIMESTAMP_LOW and
 *  TIMESTAMP_HIGH CSRs to zero.
 *
 * @note Call this only from a single thread.
 */
#macro timestamp_enable()
.begin

    #if (IS_NFPTYPE(__NFP6000))

        #define OVL_MISC_XPB_DEVICE_ID 4
        #define OVL_TIMER_PA_CFG_OFFSET 0x5000
        #define TIMER_ENABLE  ((4<<2) | 1)
        #define TIMER_RESTART ((4<<2) | (1<<1) | 1)

       .sig s
       .reg cl_num, addr, offset, $xd

        local_csr_wr[TIMESTAMP_LOW, 0]
        local_csr_wr[TIMESTAMP_HIGH, 0]

        local_csr_rd[ACTIVE_CTX_STS]
        immed[cl_num,0]
        alu_shf[cl_num, 0x3F, AND, cl_num, >>25]
        alu_shf[addr, --, B, cl_num,<<24] // Bit[29:24]=Island number
        alu_shf[addr, addr, OR, OVL_MISC_XPB_DEVICE_ID, <<16]
        alu_shf[addr, addr, OR, 1, <<30] // Set global bit
        immed[offset, OVL_TIMER_PA_CFG_OFFSET]

        immed[$xd,TIMER_RESTART]
        ct[xpb_write, $xd, addr, offset, 1], ctx_swap[s]

        immed[$xd,TIMER_ENABLE]
        ct[xpb_write, $xd, addr, offset, 1], ctx_swap[s]

        #undef OVL_MISC_XPB_DEVICE_ID
        #undef OVL_TIMER_PA_CFG_OFFSET
        #undef TIMER_ENABLE
        #undef TIMER_RESTART

    #else

    .reg read $control
    .sig cap_sig

    cap[read, $control, MISC_CONTROL], sig_done[cap_sig]
    .repeat
    .until (signal(cap_sig))

    .if ( !($control & 0x80) )

        local_csr_wr[TIMESTAMP_LOW, 0]
        local_csr_wr[TIMESTAMP_HIGH, 0]

        alu[--, $control, OR, 0x80]
        cap[fast_wr, ALU, MISC_CONTROL]

    .endif

    #endif /* NFP6000 */

.end
#endm


/** Sleep current context for specified number of hardware ticks.
 *
 * @param in_ticks  Number of hardware ticks to sleep
 */
#macro timestamp_sleep(in_ticks)
.begin

    .reg next

    .sig future_sig
    .set_sig future_sig

    local_csr_wr[ACTIVE_FUTURE_COUNT_SIGNAL, &future_sig]

    local_csr_rd[TIMESTAMP_LOW]
    immed[next, 0]

    alu_op(next, next, +, in_ticks)

    local_csr_wr[ACTIVE_CTX_FUTURE_COUNT, next]

    ctx_arb[future_sig]

.end
#endm


/** Sleep current context for specified number of hardware ticks and efficiently branch to the supplied label.
 *
 * @param in_ticks  Number of hardware ticks to sleep
 * @param LABEL     Label to branch to after sleep
 */
#macro timestamp_sleep_br(in_ticks, LABEL)
.begin

    .reg next

    .sig future_sig
    .set_sig future_sig

    local_csr_wr[ACTIVE_FUTURE_COUNT_SIGNAL, &future_sig]

    local_csr_rd[TIMESTAMP_LOW]
    immed[next, 0]

    alu_op(next, next, +, in_ticks)

    local_csr_wr[ACTIVE_CTX_FUTURE_COUNT, next]

    ctx_arb[future_sig], br[LABEL]

.end
#endm


/** Sleep current context for specified number of microseconds.
 *
 * @param in_us  Number of microseconds to sleep
 *
 * @note This macro assumes 1.4 GHz system clock.
 */
#macro timestamp_sleep_us(in_us)
.begin

    #ifdef _TIMESTAMP_TMP
        #warning "_TIMESTAMP_TMP is being redefined"
    #endif

    // XXX: Assumes 1.4 GHz clock.  We probably want to set this
    // according to the chip we're compiling for.
    #define_eval _TIMESTAMP_TMP (in_us*1400/16)

    timestamp_sleep(_TIMESTAMP_TMP)

    #undef _TIMESTAMP_TMP

.end
#endm


/** Spin current context for specified number of hardware ticks.
 *
 * @param in_ticks  Number of hardware ticks to sleep
 */
#macro timestamp_spin(in_ticks)
.begin

    .reg next

    .sig future_sig
    .set_sig future_sig

    local_csr_wr[ACTIVE_FUTURE_COUNT_SIGNAL, &future_sig]

    local_csr_rd[TIMESTAMP_LOW]
    immed[next, 0]

    alu_op(next, next, +, in_ticks)

    local_csr_wr[ACTIVE_CTX_FUTURE_COUNT, next]

    // Wait for the signal
    .repeat
    .until (signal(future_sig))

.end
#endm


/** @}
 * @}
 */

#endif /* __TIMESTAMP_UC__ */

