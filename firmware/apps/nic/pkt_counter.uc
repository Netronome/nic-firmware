/*
 * Copyright (C) 2015 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        pkt_counter.uc
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _PKT_COUNTER_UC_
#define _PKT_COUNTER_UC_

#include <nfp_chipres.h>
#include <stdmac.uc>
#include <passert.uc>

#define PKT_COUNTER_MAX     112
#define PKT_COUNTER_WIDTH   8 //8 bytes = 64 bit

#define PKT_COUNTER_SUFFIX  __cntr__ //used to avoid the possibility of someone else using the word "counter" which will be picked up by a future script that searches the rtsym table

#macro pkt_counter_init()
#ifdef PKT_COUNTER_ENABLE
    passert(PKT_COUNTER_MAX, "MULTIPLE_OF", (128 / PKT_COUNTER_WIDTH))
    #define PKT_COUNTER_ALLOC_LOOP 0
    #define PKT_COUNTER_IMEM 0
    #while (PKT_COUNTER_ALLOC_LOOP < (PKT_COUNTER_MAX / (128 / PKT_COUNTER_WIDTH)))
        .alloc_mem pkt_counters_base/**/PKT_COUNTER_ALLOC_LOOP imem/**/PKT_COUNTER_IMEM global 128 256
        .declare_resource pkt_counters/**/PKT_COUNTER_ALLOC_LOOP global 128 pkt_counters_base/**/PKT_COUNTER_ALLOC_LOOP
        #define_eval PKT_COUNTER_ALLOC_LOOP (PKT_COUNTER_ALLOC_LOOP + 1)
        #if (__nfp_has_island("imem1"))
            #define_eval PKT_COUNTER_IMEM ((PKT_COUNTER_IMEM + 1) % 2)
        #endif
    #endloop
    #undef PKT_COUNTER_ALLOC_LOOP
    #undef PKT_COUNTER_IMEM
    #define PKT_COUNTER_POOL 0
#endif
#endm

/** pkt_counter_decl
 *
 * Declare a 64 bit counter
 *
 * @param IN_NAME   Name of the counter.
 */
#macro pkt_counter_decl(IN_NAME)
#ifdef PKT_COUNTER_ENABLE
    .alloc_resource IN_NAME/**/PKT_COUNTER_SUFFIX pkt_counters/**/PKT_COUNTER_POOL global (PKT_COUNTER_WIDTH) (PKT_COUNTER_WIDTH)
    #define_eval PKT_COUNTER_POOL ((PKT_COUNTER_POOL + 1) % (PKT_COUNTER_MAX / (128 / PKT_COUNTER_WIDTH)))
#endif
#endm


/** pkt_counter_decl
 *
 * Declare a 64 bit counter within a specific pool
 *
 * @param IN_NAME   Name of the counter.
 * @param IN_POOL   Pool from which to allocate
 */
#macro pkt_counter_decl(IN_NAME, IN_POOL)
#ifdef PKT_COUNTER_ENABLE
    .alloc_resource IN_NAME/**/PKT_COUNTER_SUFFIX pkt_counters/**/IN_POOL global (PKT_COUNTER_WIDTH) (PKT_COUNTER_WIDTH)
    #define_eval PKT_COUNTER_POOL ((IN_POOL + 1) % (PKT_COUNTER_MAX / (128 / PKT_COUNTER_WIDTH)))
#endif
#endm


/** pkt_counter_incr
 *
 * Increments a 64 bit counter by one
 *
 * @param IN_NAME   Name of the counter.
 */
#macro pkt_counter_incr(IN_NAME)
#ifdef PKT_COUNTER_ENABLE
.begin
    .reg addr
    move(addr, ((IN_NAME/**/PKT_COUNTER_SUFFIX >> 8) & 0xFFFFFFFF))
    passert(PKT_COUNTER_WIDTH, "EQ", 8)
    mem[incr64, --, addr, <<8, (IN_NAME/**/PKT_COUNTER_SUFFIX & 0xFF)] // offset should be <= 0x7F, mask is deliberately 0xFF to catch alloc mistakes
.end
#endif
#endm


#endif // _PKT_COUNTER_UC_
