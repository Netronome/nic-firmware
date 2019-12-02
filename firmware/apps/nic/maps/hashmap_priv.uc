/*
 * Copyright (C) 2012-2017 Netronome Systems, Inc.  All rights reserved.
 *
 * File:        hashmap_priv.uc
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __HASHMAP_PRIV_UC__
#define __HASHMAP_PRIV_UC__

#include <stdmac.uc>
#include <aggregate.uc>
#include <bitfields.uc>
#include <limit.uc>
#include <lm_handle.uc>
#include <passert.uc>
#include <ov.uc>
#include <unroll.uc>
#include <ring_utils.uc>
//#include <ring_utils_ext.uc>

#ifndef PKT_COUNTER_ENABLE
    #define PKT_COUNTER_ENABLE
    #include "pkt_counter.uc"
#endif

#define_eval __HASHMAP_CNTR_SUFFIX PKT_COUNTER_SUFFIX

#macro __hashmap_lm_handles_define()
    #define_eval HASHMAP_LM_HANDLE      3
    #define_eval HASHMAP_LM_INDEX       *l$index3
#endm

#macro __hashmap_lm_handles_undef()
    #undef HASHMAP_LM_HANDLE
    #undef HASHMAP_LM_INDEX
#endm

#macro __hashmap_set($io_txfr)
    #pragma warning(push)
    #pragma warning(disable: 5008)
    aggregate_directive(.set, $io_txfr, HASHMAP_TXFR_COUNT)
    #pragma warning(pop)
#endm

#macro __hashmap_counter_decr(NAME)
.begin
    .reg cntr_addr
    .reg cntr_offset
    move(cntr_addr, ((NAME/**/__HASHMAP_CNTR_SUFFIX >>8) & 0xffffffff))
    move(cntr_offset,(NAME/**/__HASHMAP_CNTR_SUFFIX & 0xff))
    mem[decr64, --, cntr_addr, <<8, cntr_offset]
.end
#endm
#macro __hashmap_counter_add(NAME, value)
.begin
    .reg cntr_addr
    .reg cntr_offset
    .reg iref

    move(cntr_addr, ((NAME/**/__HASHMAP_CNTR_SUFFIX >>8) & 0xffffffff))
    move(cntr_offset,(NAME/**/__HASHMAP_CNTR_SUFFIX & 0xff))
    // override length  = (1 << 7)
    // override dataref = (2 << 3)
    // length[2] = 1 for 64-bit operations = (1 << 10)
    // length[3] = 1 for to pull operand from dataref = (1 << 11)
    move(iref, ( (2 << 3) | (1 << 7) | (1 << 10) | (1 << 11)))
    alu[--, iref, OR, value, <<16]
    mem[add64_imm, --, cntr_addr, <<8, cntr_offset], indirect_ref
.end
#endm

#macro __hashmap_set_opt_field(field, value)
    #if (!streq('field', '--'))
        alu[field, --, b, value]
    #endif
#endm

#macro __hashmap_journal_init()
#ifdef DEBUG_TRACE
    journal_declare(map_debug)
    journal_declare(main_debug)
#endif
#endm

/*
 * debug word 0:
 *      0xd + ctx_num(4) + id(4) + num_lw(4) + tag(16)
 */
#macro __hashmap_dbg_printx(num_lw, tag, ID, $txdbg)
#ifdef DEBUG_TRACE
    .reg dbg_tmp
    .reg dbg_tag
    .reg act_ctx

    local_csr_rd[ACTIVE_CTX_STS]
    immed[act_ctx, 0]
    alu_shf[act_ctx, act_ctx, and, 0x7]
    move(dbg_tag, tag)
    ld_field_w_clr[dbg_tmp, 0011, dbg_tag]
    alu[dbg_tmp, dbg_tmp, or, 0xd, <<28]
    alu[dbg_tmp, dbg_tmp, or, act_ctx, <<24]
    alu[dbg_tmp, dbg_tmp, or, ID, <<20]
    alu[$txdbg[0], dbg_tmp, or, num_lw, <<16]
    #if (ID > 0)
        journal_multi_word($txdbg, num_lw, map_debug)
    #else
        journal_multi_word($txdbg, num_lw, main_debug)
    #endif
#endif
#endm

#macro __hashmap_dbg_print(tag, ID, var1)
#if defined(DEBUG_TRACE) && ((ID <= DEBUG_LEVEL) || (ID == DEBUG_ERR_ID))
.begin
    .reg $dbg[2]
    .xfer_order $dbg
    alu[$dbg[1], --, b, var1]
    __hashmap_dbg_printx(2, tag, ID, $dbg)
.end
#endif
#endm
#macro __hashmap_dbg_print(tag, ID, var1,var2)
#if defined(DEBUG_TRACE) && ((ID <= DEBUG_LEVEL) || (ID == DEBUG_ERR_ID))
.begin
    .reg $dbg[3]
    .xfer_order $dbg
    alu[$dbg[1], --, b, var1]
    alu[$dbg[2], --, b, var2]
    __hashmap_dbg_printx(3, tag, ID, $dbg)
.end
#endif
#endm
#macro __hashmap_dbg_print(tag, ID, var1,var2,var3)
#if defined(DEBUG_TRACE) && ((ID <= DEBUG_LEVEL) || (ID == DEBUG_ERR_ID))
.begin
    .reg $dbg[4]
    .xfer_order $dbg
    alu[$dbg[1], --, b, var1]
    alu[$dbg[2], --, b, var2]
    alu[$dbg[3], --, b, var3]
    __hashmap_dbg_printx(4, tag, ID, $dbg)
.end
#endif
#endm
#macro __hashmap_dbg_print(tag,ID, var1,var2,var3,var4)
#if defined(DEBUG_TRACE) && ((ID <= DEBUG_LEVEL) || (ID == DEBUG_ERR_ID))
.begin
    .reg $dbg[5]
    .xfer_order $dbg
    alu[$dbg[1], --, b, var1]
    alu[$dbg[2], --, b, var2]
    alu[$dbg[3], --, b, var3]
    alu[$dbg[4], --, b, var4]
    __hashmap_dbg_printx(5, tag, ID, $dbg)
.end
#endif
#endm
#macro __hashmap_dbg_print(tag,ID,var1,var2,var3,var4,var5)
#if defined(DEBUG_TRACE) && ((ID <= DEBUG_LEVEL) || (ID == DEBUG_ERR_ID))
.begin
    .reg $dbg[6]
    .xfer_order $dbg
    alu[$dbg[1], --, b, var1]
    alu[$dbg[2], --, b, var2]
    alu[$dbg[3], --, b, var3]
    alu[$dbg[4], --, b, var4]
    alu[$dbg[5], --, b, var5]
    __hashmap_dbg_printx(6, tag, ID, $dbg)
.end
#endif
#endm


#macro __hashmap_ctime(ctime, JOURNAL_ID)
.begin
    .reg ts_lo

#define __TS_SHF_NUM__ 1

    local_csr_rd[TIMESTAMP_LOW]
    immed[ts_lo, 0]
    alu[ctime, --, b, ts_lo]
    __hashmap_dbg_print(0x0123, JOURNAL_ID, ctime, ts_lo)
#undef __TS_SHF_NUM__
.end
#endm
#macro __hashmap_elapsed_time(prev_time, e_time, JOURNAL_ID)
.begin
    .reg c_time

    __hashmap_ctime(c_time, JOURNAL_ID)
    alu[e_time, c_time, -, prev_time]
    __hashmap_dbg_print(0x0124, JOURNAL_ID, e_time)
.end
#endm



/*
 * T_INDEX: see DB  5.3.7.3.
 * T_INDEX is in class 1 of indices.  There is a single CSR which is read/written by all contexts
 */

/*
 * $io_txfr     read xfer regs
 * in_addr_hi   addr40
 * in_offset    byte offset to entry
 * in_length    number of bytes to read
 *
 * T_INDEX is set to $io_txfr[0]
 *
 * read as much data as available that can fit into the transfer registers from offset
 *
 * to advance T_INDEX by number of bytes
 *      local_csr_rd[T_INDEX]
 *      immed[temp_advance, 0]
 *      alu[temp_advance, temp_advance, +, bytes_moved]
 *      local_csr_wr[T_INDEX, temp_advance]
 *
 * length:    the number of bytes to read, returns the actual number of bytes read
 *
 */
#macro __hashmap_read_data(o_tindex, in_addr_hi, in_addr_lo, buf_wlen, endian)
.begin

    .reg txfr_size_lw       ; number of words available in $io_txfr
    .sig read_sig
    .reg bytes

    alu[txfr_size_lw, --, b, buf_wlen]
    alu[--, txfr_size_lw, -, HASHMAP_RXFR_COUNT]
    blt[cont#]
    immed[buf_wlen, HASHMAP_RXFR_COUNT]
    alu[txfr_size_lw, --, b, HASHMAP_RXFR_COUNT]

cont#:
    alu[txfr_size_lw, --, b, HASHMAP_RXFR_COUNT]

    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, txfr_size_lw, OVF_SUBTRACT_ONE)    ; length is in 32-bit LWs
    ov_clean
    mem[read32_/**/endian, MAP_RDXR[0], in_addr_hi, <<8, in_addr_lo, max_/**/HASHMAP_RXFR_COUNT], indirect_ref, sig_done[read_sig]

    alu[o_tindex, (&MAP_RDXR[0] << 2), OR, my_act_ctx, <<7]

    ctx_arb[read_sig]

ret#:
.end
#endm

#macro __hashmap_read_more(io_tindex, in_addr_hi, in_addr_lo, buf_wlen, endian)
.begin
    .reg start_tindex
    .reg consumed
    .reg avail

    alu[--, io_tindex, -, 0]
    beq[do_read#]

    alu[start_tindex, (&MAP_RDXR[0] << 2), OR, my_act_ctx, <<7]
    alu[consumed, io_tindex, -, start_tindex]
    alu[consumed, --, b, consumed, >>2]
    alu[avail, HASHMAP_RXFR_COUNT, -, consumed]
    alu[--, avail, -, buf_wlen]
    bge[ret#]

do_read#:
    __hashmap_read_data(io_tindex, in_addr_hi, in_addr_lo, buf_wlen, endian)

.end
ret#:
#endm

#macro __hashmap_compare(io_tindex, lm_addr, in_addr_hi, in_addr_lo, in_wlen, MISS_LABEL, endian, map_type)
.begin

    .reg comp_lw
    .reg lw_read, bytes_read
    .reg off
    .reg lm_off

    __hashmap_lm_handles_define()
    alu[lm_off, --, b, lm_addr]

    alu[lw_read, --, b, in_wlen]
    alu[off, --, b, in_addr_lo]
    immed[comp_lw, 0]

do_read#:
    local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, lm_off]

    __hashmap_read_data(io_tindex, in_addr_hi, off, lw_read, endian)

read_done#:
    local_csr_wr[T_INDEX, io_tindex]    ; global csr 3 cycles
        alu[bytes_read, --, b, lw_read, <<2]
        nop
        nop

    unroll_compare(*$index, ++, HASHMAP_LM_INDEX, ++, MISS_LABEL, lw_read, HASHMAP_RXFR_COUNT, --)

compare_match#:
    alu[comp_lw, comp_lw, +, lw_read]
    alu[lw_read, comp_lw, B-A, in_wlen] ; comp_bytes < bytes_read
    bgt[do_read#], defer[2]
        alu[lm_off, lm_off, +, bytes_read]
        alu[off, off, +, bytes_read]

ret#:
    __hashmap_lm_handles_undef()
    local_csr_rd[T_INDEX]
    immed[io_tindex, 0]
.end
#endm


#macro __hashmap_read_field(io_tindex, lm_field_addr, in_addr_hi, in_addr_lo, in_wlen, RTN_OPT, out_addr, out_tindex, endian)
.begin
    .reg read_lw, bytes
    .reg copy_lw
    .reg off
    .reg lm_off

    #if (RTN_OPT == HASHMAP_RTN_ADDR)
        alu[out_addr[0], --, b, in_addr_hi]
        alu[out_addr[1], --, b, in_addr_lo]
    #elif (RTN_OPT == HASHMAP_RTN_TINDEX)
        __hashmap_read_more(io_tindex, in_addr_hi, in_addr_lo, in_wlen, endian)
        alu[out_tindex, --, b, io_tindex]
        alu[out_addr[0], --, b, in_addr_hi]
        alu[out_addr[1], --, b, in_addr_lo]
    #else

        __hashmap_lm_handles_define()
        alu[lm_off, --, b, lm_field_addr]

        alu[read_lw, --, b, in_wlen]
        immed[copy_lw, 0]
        alu[off, --, b, in_addr_lo]

do_read#:
        local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, lm_off]
        __hashmap_read_more(io_tindex, in_addr_hi, off, read_lw, endian)

        local_csr_wr[T_INDEX, io_tindex]    ; global csr 3 cycles
        alu[bytes, --, b, read_lw, <<2]
        unroll_copy(HASHMAP_LM_INDEX, ++, *$index, ++, read_lw, HASHMAP_RXFR_COUNT, --)
        alu[off, off, +, bytes]
        alu[copy_lw, copy_lw, +, read_lw]
        alu[read_lw, copy_lw, B-A, in_wlen]
        bgt[do_read#], defer[2]
            alu[off, off, +, bytes]
            alu[lm_off, lm_off, +, bytes]

        __hashmap_lm_handles_undef()
        local_csr_rd[T_INDEX]
           immed[io_tindex, 0]
    #endif  //RTN_OPT

.end
#endm

#macro __hashmap_write_field(lm_field_addr, field_mask, in_addr_hi, in_addr_lo, in_wlen, endian)
.begin
    .reg wbytes, write_lw
    .reg copied_lw
    .reg off
    .sig write_sig
    .reg tmp
    .reg lm_off
    .reg wr_tindex


    __hashmap_lm_handles_define()

    alu[lm_off, --, b, lm_field_addr]
    alu[tmp, --, b, in_wlen, <<2]
    alu[off, lm_off, +, tmp]
    alu[off, off, -, 4]
    local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, off]

    alu[wr_tindex, (&MAP_TXFR[0] << 2), OR, my_act_ctx, <<7]
    alu[write_lw, --, b, in_wlen]
    immed[copied_lw, 0]
    alu[off, --, b, in_addr_lo]

    alu[HASHMAP_LM_INDEX, field_mask, and, HASHMAP_LM_INDEX]
do_write#:
    local_csr_wr[T_INDEX, wr_tindex]
    local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, lm_off]
    alu[--, write_lw, -, HASHMAP_TXFR_COUNT]
    blt[write_cont#]

    alu[write_lw, --, b, HASHMAP_TXFR_COUNT]

write_cont#:
    unroll_copy(*$index, ++, HASHMAP_LM_INDEX, ++, write_lw, HASHMAP_TXFR_COUNT, --)

    ov_start(OV_LENGTH)
    ov_set_use(OV_LENGTH, write_lw, OVF_SUBTRACT_ONE)   ; length is in 32-bit LWs
    ov_clean
    mem[write32_/**/endian, MAP_TXFR[0], in_addr_hi, <<8, off, max_/**/HASHMAP_TXFR_COUNT], indirect_ref, ctx_swap[write_sig]

    alu[wbytes, --, b, write_lw, <<2]
    alu[copied_lw, copied_lw, +, write_lw]
    alu[write_lw, copied_lw, B-A, in_wlen]
    bgt[do_write#], defer[2]
        alu[off, off, +, wbytes]
        alu[lm_off, lm_off, +, wbytes]

    __hashmap_lm_handles_undef()

.end
#endm

#macro __hashmap_write_tid(in_fd, in_idx)
.begin
    .reg $tid_value
    .sig write_tid_sig
    .reg lk_addr_hi
    .reg lk_addr_lo

    alu[$tid_value, --, b, in_fd]
    move(lk_addr_hi, __HASHMAP_LOCK_TBL >>8)
    alu[lk_addr_lo, --, b, in_idx, <<HASHMAP_LOCK_SZ_SHFT]
    alu[lk_addr_lo, 4, +, lk_addr_lo]
    mem[atomic_write, $tid_value, lk_addr_hi, <<8, lk_addr_lo, 1], sig_done[write_tid_sig]
    ctx_arb[write_tid_sig]
.end
#endm

#macro __hashmap_dump_lm(lm_off)
.begin
    .reg dbg_isl
    .reg dbg_meid
    .reg dbg_stack_addr
    .reg dbg_ctx
    .reg dbg_act

    local_csr_rd[ACTIVE_CTX_STS]
    immed[dbg_act, 0]
    alu_shf[dbg_ctx, dbg_act, and, 0x7]

    __hashmap_lm_handles_define()
    local_csr_wr[ACTIVE_LM_ADDR_/**/HASHMAP_LM_HANDLE, lm_off]
    alu_shf[dbg_meid, 0xB, and, dbg_act, >>3]
    alu_shf[dbg_isl, 0x3f, and, dbg_act, >>25]

    __hashmap_dbg_print(0x1001, 0, dbg_isl, dbg_meid, lm_off)

    __hashmap_dbg_print(0x1002, DEBUG_ERR_ID, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++)
    __hashmap_dbg_print(0x1003, DEBUG_ERR_ID, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++)
    __hashmap_dbg_print(0x1004, DEBUG_ERR_ID, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++)
    __hashmap_dbg_print(0x1005, DEBUG_ERR_ID, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++)
    __hashmap_dbg_print(0x1006, DEBUG_ERR_ID, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++, HASHMAP_LM_INDEX++)

.end
    __hashmap_lm_handles_undef()
#endm



#endif /* _HASHMAP_PRIV_UC_*/

