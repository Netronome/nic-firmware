/*
 * Copyright (C) 2014-2017,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file       hashmap_cam.uc
 * @brief      basic lookup table implementation.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __HASHMAP_CAM_UC__
#define __HASHMAP_CAM_UC__

#include <nfp_chipres.h>
#include <ring_utils.uc>
#include <ring_ext.uc>

#define __HASHMAP_OV_SIG_BIT__    31

/*
 * 8 cam entries + 8 ctrl = 64-bytes
 */

/*
 *    addr_hi:        addr of hashmap table
 *  addr_lo:        offset to start of entry in hashmap table
 *    ov_cam_offset:     offset to start of ov cam
 *  ov_entry_offset:offset to start of ov entries
 *  ov_offset:        offset to ov entry containing pool offset
 *  pool_offset        offset to freelist pool entry
 */

/*
    struct mem_cam_24bit {
        union {
            struct {
            unsigned int value;  Lower 24 bits valid
        } search;

        struct {
            unsigned int mask:16;    bit field of matched entries, bit 16 = entry#0
            unsigned int data:8;
            unsigned int match:8;
        } result;
    };
};
*/


#define HASHMAP_CAM_EXCL_BIT    7

#define HASHMAP_FREELIST_RING_MEM            emem0
#define HASHMAP_FREELIST_BUF_MEM            emem0

#define HASHMAP_MAX_OV_SZ    (HASHMAP_KEYS_VALU_SZ)
#define HASHMAP_OV_ENTRY_SZ_SHFT (LOG2(HASHMAP_MAX_OV_SZ))


#macro __hashmap_freelist_init(NUM_ENTRIES)

    passert(NUM_ENTRIES, "MULTIPLE_OF", 16)

    // debug counters
    pkt_counter_decl(num_ov_alloc)
    pkt_counter_decl(num_ov_free)

    EMEM0_QUEUE_ALLOC(HASHMAP_FREE_QID, global)
    .alloc_mem HASHMAP_FREE_RBASE emem0 global (NUM_ENTRIES * 4) (NUM_ENTRIES * 4)
    .init_mu_ring HASHMAP_FREE_QID HASHMAP_FREE_RBASE 0

    .alloc_mem HASHMAP_FREEPOOL_BASE emem global (NUM_ENTRIES * HASHMAP_MAX_OV_SZ) 256
    .init HASHMAP_FREEPOOL_BASE 0

#ifdef GLOBAL_INIT
    .if (ctx() == 0)
    .begin
        .sig sig_init_write
        .reg base
        .reg offset
        .reg index
        .reg $data[16]
        .xfer_order $data

        .reg val

        move(index, (NUM_ENTRIES-1))
        alu[val, --, b, 1, <<__HASHMAP_OV_SIG_BIT__]
        .while (index > 0)
            #define_eval __IDX 0
            #while (__IDX < 16)
                alu[$data[__IDX], val, or, index, <<HASHMAP_OV_ENTRY_SZ_SHFT]
                alu[$data[__IDX], val, or, index]
                alu[index, index, -, 1]
                #define_eval __IDX (__IDX + 1)
            #endloop
            ru_emem_ring_op($data, HASHMAP_FREE_QID, sig_init_write, journal, HASHMAP_FREE_RBASE, 16, --)
        .endw
        #undef __IDX
    .end
    .endif

#endif    //GLOBAL_INIT
#endm

/*
 * ring op
 *   get - remove from head
 *     pop - remove from tail
 *   fast_journal - add to tail
 *   put - add to tail
 */

#macro __hashmap_freelist_alloc(out_index, NO_BUFF_LABEL)
.begin
    .sig sig_freelist_pop
    .reg $free_index
    .reg max

do_pop#:
    ru_emem_ring_op($free_index, HASHMAP_FREE_QID, sig_freelist_pop, pop, HASHMAP_FREE_RBASE, 1,NO_BUFF_LABEL)

    br_bclr[$free_index, __HASHMAP_OV_SIG_BIT__, do_pop#], defer[2]
    alu_shf[max, --, b, 1, <<__HASHMAP_OV_SIG_BIT__]
    alu[out_index, $free_index, and~, max]

    // verification/debug code.
#ifdef HASHMAP_UNITTEST_CODE
    #define_eval __VALID_FREELIST_OFFSET__  (HASHMAP_OVERFLOW_ENTRIES)
    move(max, __VALID_FREELIST_OFFSET__)
    alu[--, out_index, -, max]
    bge[do_pop#]
    #undef __VALID_FREELIST_OFFSET__
#endif

ret#:
    pkt_counter_incr(num_ov_alloc)
.end
#endm

#macro __hashmap_freelist_free(in_offset)
.begin
    .sig sig_freelist_put
    .reg $free_index
    .reg free_index

    alu[free_index, --, b, in_offset, >>HASHMAP_OV_ENTRY_SZ_SHFT]
    alu[$free_index, free_index, or, 1, <<__HASHMAP_OV_SIG_BIT__]
    ru_emem_ring_op($free_index, HASHMAP_FREE_QID, sig_freelist_put, put, HASHMAP_FREE_RBASE, 1, --)
    pkt_counter_incr(num_ov_free)
ret#:
.end
#endm

/* debug function */
#macro __hashmap_dbg_qdesc()
.begin
    .reg qdesc_addr, r_addr
    .reg $qdesc[4]
    .xfer_order $qdesc
    .sig dbg_ring_sig
    .reg ring_no

    alu[ring_no, --, b, HASHMAP_FREE_QID]
    immed40(r_addr, qdesc_addr, HASHMAP_FREE_QDESC)
    mem[push_qdesc, $qdesc[0], r_addr, <<8, ring_no], ctx_swap[dbg_ring_sig]
    nop
    nop
    __hashmap_dbg_print(0xd123, DEBUG_ERR_ID, $qdesc[0], $qdesc[1], $qdesc[2], $qdesc[3])
.end
#endm

    /*
     * if hashkey match, return offset
     *
     * in_addr_hi - entry table addr
     * in_offset - offset of entry
     */
#macro __hashmap_cam_lu(in_hashkey, in_addr_hi, in_addr_lo, match_idx, match_bm, NOT_FOUND_LABEL)
.begin
    .reg value
    .reg $lookup
    .reg camtbl_addr_hi
    .sig sig_cam_lu

    /* make sure hash value is not zero */
    ld_field_w_clr[value, 0111, in_hashkey]
    alu[$lookup, value, or, 1]

    mem[cam256_lookup24, $lookup, in_addr_hi, <<8, in_addr_lo], sig_done[sig_cam_lu]
    ctx_arb[sig_cam_lu]
    br=byte[$lookup, 0, 0xff, NOT_FOUND_LABEL],defer[2]
        ld_field_w_clr[match_idx, 0001, $lookup]
        ld_field_w_clr[match_bm, 0011, $lookup, >>16]

.end
#endm

#macro __hashmap_cam_add(in_hashkey, in_addr_hi, in_addr_lo, out_ov_offset, NOTADD_LABEL, FAIL_LABEL)
.begin
    .reg value
    .reg idx
    .reg $lookup
    .sig cam_add_sig
    .reg match_bm
    .reg tmp
    //.reg $cam_addr[8]        ;MAX_RXCAM
    //.xfer_order $cam_addr
    .sig cam_read_sig
    .reg ctx_tindex
    .reg ov_idx


    ld_field_w_clr[value, 0111, in_hashkey]
    alu[$lookup, value, or, 1]
    mem[cam256_lookup24_add, $lookup, in_addr_hi, <<8, in_addr_lo], sig_done[cam_add_sig]
    ctx_arb[cam_add_sig]

    br=byte[$lookup, 0, 0xff, FAIL_LABEL], defer[2]        ; full
        alu[value, 0x1c, and, $lookup, <<2]
        alu[idx, in_addr_lo, +, value]

    br_bset[$lookup, 7, ret#], defer[1]            ; hash added
        alu[out_ov_offset, idx, +, HASHMAP_OV_ENTRY_OFFSET]

    /* hash collision  - find an empty slot */
    mem[read32, MAP_RXCAM, in_addr_hi, <<8, in_addr_lo, 8], sig_done[cam_read_sig]
        immed[ov_idx, 0]
        immed[idx, 0]
        alu[ctx_tindex, (&MAP_RXCAM << 2), or, my_act_ctx, <<7]
    ctx_arb[cam_read_sig]
    local_csr_wr[T_INDEX, ctx_tindex]
next_entry#:
    alu[--, idx, -, 8]
    beq[FAIL_LABEL], defer[1]
        alu[ov_idx, --, b, idx]

    alu[value, --, b, *$index++]
    bne[next_entry#], defer[1]        ;looking for empty entries
        alu[idx, idx, +, 1]

found#:
    .sig cam_write_sig

    ld_field_w_clr[value, 0111, in_hashkey]
    alu[$lookup, value, or, 1]
    alu[idx, --, b, ov_idx, <<2]
    alu[idx, in_addr_lo, +, idx]
    mem[write32, $lookup, in_addr_hi, <<8, idx, 1], sig_done[cam_write_sig]

    alu[out_ov_offset, idx, +, HASHMAP_OV_ENTRY_OFFSET]
    ctx_arb[cam_write_sig]

ret#:
.end
#endm

#macro __hashmap_ov_add(in_hashkey, in_addr_hi, in_idx, in_tid, out_addr_hi, out_addr_lo, ERROR_LABEL)
.begin
    .reg ov_offset
    .reg pool_index
    .reg $ov_addr
    .sig ov_add_sig
    .reg cam_offset
    .reg addr_lo


    __hashmap_freelist_alloc(pool_index, no_free_buf#)
    alu[addr_lo, --, b, in_idx, <<HASHMAP_ENTRY_SZ_SHFT]
    alu[cam_offset, addr_lo, +, HASHMAP_OV_CAM_OFFSET]

    __hashmap_cam_add(in_hashkey, in_addr_hi, cam_offset, ov_offset, not_add#, cam_add_fail#)

    alu[$ov_addr, pool_index, or, in_tid, <<24]
    mem[write32, $ov_addr, in_addr_hi, <<8, ov_offset, 1], sig_done[ov_add_sig]
    move(out_addr_hi, HASHMAP_FREEPOOL_BASE >>8)
    alu[out_addr_lo, --, b, pool_index, <<HASHMAP_OV_ENTRY_SZ_SHFT]
    ctx_arb[ov_add_sig], br[ret#]

no_free_buf#:
    /* TODO: LRU  */
    br[ERROR_LABEL]

not_add#:
cam_add_fail#:
    alu[pool_index, --, b, pool_index, <<HASHMAP_OV_ENTRY_SZ_SHFT]
    __hashmap_freelist_free(pool_index)
    br[ERROR_LABEL]
ret#:
.end
#endm

#macro __hashmap_ov_delete(in_addr_hi, in_idx, in_offset, in_state)
.begin
    .reg ov_offset
    .reg cam_offset
    .reg $cam_wd
    .reg $value
    .sig cam_del_sig
    .sig ov_del_sig
    .reg tmp
    .reg addr_lo

    __hashmap_freelist_free(in_offset)

    alu[addr_lo, --, b, in_idx, <<HASHMAP_ENTRY_SZ_SHFT]

    #define __OV_IDX_SHFT__ (__HASHMAP_DESC_OV_IDX - 2)
    alu[cam_offset, 0x1c, and, in_state, >>__OV_IDX_SHFT__]
    #undef __OV_IDX_SHFT__

    alu[cam_offset, cam_offset, +, addr_lo]
    alu[cam_offset, cam_offset, +, HASHMAP_OV_CAM_OFFSET]
    immed[$cam_wd, 0]
    mem[write32, $cam_wd, in_addr_hi, <<8, cam_offset], sig_done[cam_del_sig]
    alu[ov_offset, cam_offset, +, HASHMAP_OV_ENTRY_OFFSET]
    immed[$value, 0]
    mem[write32, $value, in_addr_hi, <<8, ov_offset], sig_done[ov_del_sig]
    ctx_arb[ov_del_sig, cam_del_sig]

.end
#endm


#macro __hashmap_ov_lookup(in_hashkey, in_tid, in_addr_hi, in_idx, in_key_lmaddr, in_key_lwsz, o_tindex, out_addr_hi, out_addr_lo, out_state, FOUND_LABEL, endian, map_type)
.begin
    .reg ov_offset
    .reg match_bitmap
    .reg match_idx
    .reg $ov_addr
    .sig ov_read_sig
    .reg ov_tid
    .reg freelist_hi
    .reg pool_offset
    .reg cam_offset
    .reg tmp
    .reg addr_lo

    alu[addr_lo, --, b, in_idx, <<HASHMAP_ENTRY_SZ_SHFT]
    alu[cam_offset, addr_lo, +, HASHMAP_OV_CAM_OFFSET]

    __hashmap_cam_lu(in_hashkey, in_addr_hi, cam_offset, match_idx, match_bitmap, ret#)
    move(freelist_hi, HASHMAP_FREEPOOL_BASE >>8)

match#:
    alu[match_idx, --, b, match_idx, <<2]
    alu[ov_offset, addr_lo, +, (HASHMAP_OV_CAM_OFFSET+HASHMAP_OV_ENTRY_OFFSET)]
    alu[ov_offset, ov_offset, +, match_idx]

    mem[read32, $ov_addr, in_addr_hi, <<8, ov_offset, 1], sig_done[ov_read_sig]
    alu[tmp, --, b, match_idx, >>2]
    alu[--, tmp, or, 0]
    alu[match_bitmap, match_bitmap, and~, 1, <<indirect]
    ctx_arb[ov_read_sig]

    ld_field_w_clr[ov_tid, 0001, $ov_addr, >>24]
    alu[--, ov_tid, -, in_tid]        ; match tid
    bne[comp_next_match#]

compare_key#:
    ld_field_w_clr[pool_offset, 0111, $ov_addr]
    alu[pool_offset, --, b, pool_offset, <<HASHMAP_OV_ENTRY_SZ_SHFT]
    __hashmap_compare(o_tindex, in_key_lmaddr, freelist_hi, pool_offset, in_key_lwsz, comp_next_match#, endian, map_type)
    #define __OV_IDX_SHFT__ (__HASHMAP_DESC_OV_IDX - 2)
    alu[out_state, out_state, or, match_idx, <<__OV_IDX_SHFT__]
    alu[out_state, out_state, or, 1, <<__HASHMAP_DESC_OV_BIT]
    br[FOUND_LABEL], defer[2]
        alu[out_addr_hi, --, b, freelist_hi]
        alu[out_addr_lo, --, b, pool_offset]
    #undef __OV_IDX_SHFT__

comp_next_match#:
    ffs[match_idx, match_bitmap]
    bne[match#]

ret#:

.end
#endm

#macro __hashmap_ov_getnext(in_addr_hi, in_idx, in_tid, out_addr_hi, out_addr_lo, io_state, FOUND_LABEL)
.begin
    .reg lm_off
    .reg ov_offset
    .reg $ov_addr[8]
    .xfer_order $ov_addr
    .sig ov_read_sig
    .reg ov_tid
    .reg ov_idx
    .reg idx
    .reg value

    .reg ctx_tindex
    alu[ctx_tindex, (&$ov_addr[0] << 2), or, my_act_ctx, <<7]

    #define __OV_OFFSET__    (HASHMAP_OV_CAM_OFFSET+HASHMAP_OV_ENTRY_OFFSET)
    alu[ov_offset, --, b, in_idx, <<HASHMAP_ENTRY_SZ_SHFT]
    alu[ov_offset, ov_offset, +, __OV_OFFSET__]
    #undef __OV_OFFSET__
    mem[read32, $ov_addr[0], in_addr_hi, <<8, ov_offset, 8], sig_done[ov_read_sig]

    alu[ov_idx, --,b, io_state, >>__HASHMAP_DESC_OV_IDX]
    br_bclr[io_state, __HASHMAP_DESC_OV_BIT, cont#], defer[1]
    alu[ov_idx, ov_idx, and, 7]

    alu[ov_idx, ov_idx, +, 1]

cont#:
    alu[idx, --, b, ov_idx, <<2]
    alu[ctx_tindex, ctx_tindex, +, idx]
    ctx_arb[ov_read_sig]
    local_csr_wr[T_INDEX, ctx_tindex]
    nop
next_entry#:
    alu[--, ov_idx, -, 8]
    beq[ret#], defer[2]
        alu[value, --, b, *$index++]
        ld_field_w_clr[ov_tid, 0001, value, >>24]
    alu[--, ov_tid, -, in_tid]        ;match tid
    bne[next_entry#], defer[2]
        alu[idx, --, b, ov_idx]
        alu[ov_idx, ov_idx, +, 1]

found#:
    move(out_addr_hi, HASHMAP_FREEPOOL_BASE>>8)
    ld_field_w_clr[out_addr_lo, 0111, value]
    alu[out_addr_lo, --, b, out_addr_lo, <<HASHMAP_OV_ENTRY_SZ_SHFT]
    br[FOUND_LABEL], defer[2]
        alu[io_state, io_state, or, 1, <<__HASHMAP_DESC_OV_BIT]
        alu[io_state, io_state, or, idx, <<__HASHMAP_DESC_OV_IDX]
ret#:
.end
#endm

#endif /* __HASHMAP_CAM_UC__ */
