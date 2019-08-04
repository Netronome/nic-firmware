/*
 * Copyright (C) 2009-2015 Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __RING_UTILS_EXT_UC__
#define __RING_UTILS_EXT_UC__

#ifndef NFP_LIB_ANY_NFAS_VERSION
    #if (!defined(__NFP_TOOL_NFAS) ||                       \
        (__NFP_TOOL_NFAS < NFP_SW_VERSION(5, 0, 0, 0)) ||   \
        (__NFP_TOOL_NFAS > NFP_SW_VERSION(6, 255, 255, 255)))
        #error "This standard library is not supported for the version of the SDK currently in use."
    #endif
#endif

#include <xbuf.uc>
#include <constants.uc>
#include <ov.uc>

/** @file ring_utils.uc Ring Utility Macros
 * @addtogroup ring_utils Ring Utility
 * @{
 *
 * @name Ring Utility Macros
 * @{
 *
 */


#ifndef _CLS_RINGS_CSR_OFFSET_
    #ifdef _CS_RINGS_CSR_OFFSET_
        #define _CLS_RINGS_CSR_OFFSET_ _CS_RINGS_CSR_OFFSET_
    #else
        #define _CLS_RINGS_CSR_OFFSET_   0x10000
    #endif
#endif  /* _CLS_RINGS_CSR_OFFSET_ */

#ifndef K
    #define K   (1024)
#endif  /* K */

#ifndef M
    #define M   (1024 * 1024)
#endif  /* K */

/** Set up a type 2 ring in emem based on parameters passed to the macro
 *  See full version of macro for description
 */
#macro ru_emem_ring_setup(_IN_RING_BASE_ADDR, _in_ring_num, _IN_SIZE_LW, _IN_RING_HEAD, _IN_RING_TAIL, _IN_RING_COUNT)
     ru_emem_ring_setup(--, _IN_RING_BASE_ADDR, --, _in_ring_num, _IN_SIZE_LW, _IN_RING_HEAD, _IN_RING_TAIL, _IN_RING_COUNT)
#endm

/** Set up a type 2 ring in emem based on parameters passed to the macro
 *
 * @param _IN_Q_DESC_ADDR       40-bit address identifying the location of the ring descriptor in emem0, emem1 or emem2 (optional)
 * @param _IN_RING_BASE_ADDR    40-bit address identifying the location of the rings in emem0, emem1 or emem2
 * @param _in_ring_num          Number of emem rings to configure, valid values 0-1023, GPR, compile time or run time constant
 * @param _IN_SIZE_LW           size of ring in long words, must be between 512 and 16M and a power of 2
 * @param _IN_RING_HEAD         Head pointer
 * @param _IN_RING_TAIL         Tail pointer
 * @param _IN_RING_COUNT        Count
 *
 * @b Example 1:
 * Create ring in emem island 24 and supply the descriptor memory
 * @code
 *  #include <nfp_chipres.h>
 *  EMEM0_QUEUE_ALLOC(EMEM_RING_NUM, global)
 *  #define EMEM_RING_SIZE          512
 *
 *  .alloc_mem RING_BASE_ADDR       i24.emem island EMEM_RING_SIZE*4 EMEM_RING_SIZE*4
 *  .alloc_mem Q_DESC_BASE_ADDR     i24.emem island 16
 *
 *  .reg $xdout[2], $xdin[2]
 *  .xfer_order $xdout, $xdin
 *  .sig g1, g2
 *
 *  ru_emem_ring_setup(Q_DESC_BASE_ADDR, RING_BASE_ADDR, EMEM_RING_NUM, EMEM_RING_SIZE, 0, 0, EMEM_RING_SIZE)
 *  ru_emem_ring_put(RING_BASE_ADDR, $xdout[0], EMEM_RING_NUM, 2, g1]
 *  ru_emem_ring_get(RING_BASE_ADDR, $xdin[0], EMEM_RING_NUM, 2, g2]
 * @endcode
 *
 * @b Example 2:
 * Create ring in emem island 24 without supplying the descriptor memory
 * @code
 *  #include <nfp_chipres.h>
 *  EMEM0_QUEUE_ALLOC(EMEM_RING_NUM, global)
 *  #define EMEM_RING_SIZE          512
 *
 *  .alloc_mem RING_BASE_ADDR       i24.emem island EMEM_RING_SIZE*4 EMEM_RING_SIZE*4
 *
 *  .reg $xdout[2], $xdin[2]
 *  .xfer_order $xdout, $xdin
 *  .sig g1, g2
 *
 *  ru_emem_ring_setup(RING_BASE_ADDR, EMEM_RING_NUM, EMEM_RING_SIZE, 0, 0, EMEM_RING_SIZE)
 *  ru_emem_ring_put(RING_BASE_ADDR, $xdout[0], EMEM_RING_NUM, 2, g1]
 *  ru_emem_ring_get(RING_BASE_ADDR, $xdin[0], EMEM_RING_NUM, 2, g2]
 * @endcode
 *
 * Some compile time error checking is done.
 *
 */
#macro ru_emem_ring_setup(_IN_Q_DESC_ADDR, _IN_RING_BASE_ADDR, _IN_Q_LOC, _in_ring_num, _IN_SIZE_LW, _IN_RING_HEAD, _IN_RING_TAIL, _IN_RING_COUNT)
.begin

    #if (!defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
        #error "ru_emem_ring_setup: maccro requires NFP6000 indirect reference format (-indirect_ref_format_nfp6000)."
    #endif

    #if ((_IN_SIZE_LW < 512) || (_IN_SIZE_LW > (16 * M)))
        #error "ru_emem_ring_setup: Invalid ring size specified (Ring #" _IN_SIZE_LW"): Ring size must be in range of [512 16M]."
    #endif

    #if (_IN_RING_TAIL & 0x3)
        #error "_IN_RING_TAIL must be 4 byte aligned"
    #endif

    #if (_IN_RING_HEAD & 0x3)
        #error "_IN_RING_HEAD must be 4 byte aligned"
    #endif

    // The encoding is pretty much log2(_IN_SIZE_LW/512) [512 is the minimum size]
    // So make sure all sizes is a power of 2
    #if (_IN_SIZE_LW & (_IN_SIZE_LW - 1) != 0)
        #error "ru_emem_ring_setup: Invalid ring size specified (Ring #" _in_ring_num"): Ring size must be a power of 2."
    #endif

    .reg qdesc_addr, ring_temp, ring_island
    .sig ring_sig
    .reg read $q_desc[4]
    .xfer_order $q_desc


    //Initialise the queue descriptor memory. If the descriptor memory symbol is not supplied, one will be allocated
    #if (streq('_IN_Q_DESC_ADDR','--'))
        #if ((!is_ct_const(_in_ring_num)) && (!is_rt_const(_in_ring_num)))
            #error "If _IN_Q_DESC_ADDR is not supplied, _in_ring_num must be a compile- or runtime constant"
        #endif
        #define_eval _RU_RING_NUM (_in_ring_num)
        .alloc_mem _RU_Q_DESC_/**/_RU_RING_NUM i24.emem_cache_upper global 16 16
        .init \
            _RU_Q_DESC_/**/_RU_RING_NUM+0 \
            ((log2(_IN_SIZE_LW >> 9) << 28) \
            | (_IN_RING_BASE_ADDR & 0x3fffffc) | (_IN_RING_HEAD))
        .init \
            _RU_Q_DESC_/**/_RU_RING_NUM+4 \
            ((_IN_RING_BASE_ADDR & 0xfffffffc) | (_IN_RING_TAIL) \
            | 2)
        #if(streq('_IN_Q_LOC','--'))
            .init \
                _RU_Q_DESC_/**/_RU_RING_NUM+8 \
                (((_IN_RING_BASE_ADDR >> 8) & 0xC0000000) \
                | _IN_RING_COUNT)
        #else
            .init \
                _RU_Q_DESC_/**/_RU_RING_NUM+8 \
                ((_IN_Q_LOC << 30) \
                | _IN_RING_COUNT)
        #endif
        .init \
            _RU_Q_DESC_/**/_RU_RING_NUM+12 0
        immed40(ring_island, qdesc_addr, _RU_Q_DESC_/**/_RU_RING_NUM)
    #else
        .init \
            _IN_Q_DESC_ADDR+0 \
            ((log2(_IN_SIZE_LW >> 9) << 28) \
            | (_IN_RING_BASE_ADDR & 0x3fffffc) | (_IN_RING_HEAD))
        .init \
            _IN_Q_DESC_ADDR+4 \
            ((_IN_RING_BASE_ADDR & 0xfffffffc) | (_IN_RING_TAIL) \
            | 2)
        #if(streq('_IN_Q_LOC','--'))
            .init \
                _IN_Q_DESC_ADDR+8 \
                (((_IN_RING_BASE_ADDR >> 8) & 0xC0000000) \
                | _IN_RING_COUNT)
        #else
            .init \
                _IN_Q_DESC_ADDR+8 \
                ((_IN_Q_LOC << 30) \
                | _IN_RING_COUNT)
        #endif
        .init \
            _IN_Q_DESC_ADDR+12 0
        immed40(ring_island, qdesc_addr, _IN_Q_DESC_ADDR)
    #endif


    #if (is_ct_const(_in_ring_num) || is_rt_const(_in_ring_num))

        #if (is_ct_const(_in_ring_num))
            #if((_in_ring_num < 0) || (_in_ring_num > 1023))
                #error "ru_emem_ring_setup: _in_ring_num must be between 0 and 1023 (inclusive)"
            #endif
        #elif (is_rt_const(_in_ring_num))
            .assert ((_in_ring_num >= 0) && (_in_ring_num <= 1023))
        #endif

        move(ring_temp, _in_ring_num)
        ov_single(OV_DATA_REF, ring_temp)
        mem[rd_qdesc, --, ring_island, <<8, qdesc_addr], indirect_ref
        //Since rd_qdesc does not have a signal, perform a push_qdesc to xfer regs to ensure the rd_qdesc completed
        mem[push_qdesc, $q_desc[0], ring_island, <<8, ring_temp], ctx_swap[ring_sig]
    #else
        ov_single(OV_DATA_REF, _in_ring_num)
        mem[rd_qdesc, --, ring_island, <<8, qdesc_addr], indirect_ref
         //Since rd_qdesc does not have a signal, perform a push_qdesc to xfer regs to ensure the rd_qdesc completed
        mem[push_qdesc, $q_desc[0], ring_island, <<8, _in_ring_num], ctx_swap[ring_sig]
    #endif

.end
#endm   // ru_emem_ring_setup



/** Add entries to the tail of the circular buffer in emem based on parameters passed to the macro
 *
 * @param IN_RING_BASE_ADDR    40-bit address identifying the location of the rings in emem0, emem1 or emem2
 * @param in_entry          Entries to add to the circular buffer
 * @param in_ring_num          Select the ring number to add to, between 0-1023
 * @param in_sig_name          Signal to use for ring operation
 *
 * See ru_emem_ring_op() macro for implementation details
 * Some compile time error checking is done.
 *
 */
#macro ru_emem_ring_fast_journal(in_entry, in_ring_num, in_sig_name, IN_RING_BASE_ADDR)
    ru_emem_ring_op(in_entry, in_ring_num, in_sig_name, fast_journal, IN_RING_BASE_ADDR, --, --)
#endm


/** Remove entires from the tail of the circular buffer in emem based on parameters passed to the macro
 *
 * @param IN_RING_BASE_ADDR    40-bit address identifying the location of the rings in emem0, emem1 or emem2
 * @param in_xfer_reg          Entries to add to the circular buffer
 * @param in_ring_num          Select the ring number to add to, between 0-1023
 * @param IN_REF_CNT           Number of 32-bit words to add to the circular buffer, must be between 1-16
 * @param in_sig_name          Signal to use for ring operation
 *
 * See ru_emem_ring_op() macro for implementation details
 * Some compile time error checking is done.
 *
 */
#macro ru_emem_ring_pop(out_xfer_reg, in_ring_num, in_sig_name, IN_RING_BASE_ADDR, IN_REF_CNT)
    ru_emem_ring_op(out_xfer_reg, in_ring_num, in_sig_name, pop, IN_RING_BASE_ADDR,  IN_REF_CNT, --)
#endm

/** Add entries to the tail of the circular buffer in emem based on parameters passed to the macro
 *
 * @param IN_RING_BASE_ADDR    40-bit address identifying the location of the rings in emem0, emem1 or emem2
 * @param in_xfer_reg          Entries to add to the circular buffer
 * @param in_ring_num          Select the ring number to add to, between 0-1023
 * @param IN_REF_CNT           Number of 32-bit words to add to the circular buffer, must be between 1-16
 * @param in_sig_name          Signal to use for ring operation
 *
 * See ru_emem_ring_op() macro for implementation details
 * Some compile time error checking is done.
 *
 */
#macro ru_emem_ring_put(in_xfer_reg, in_ring_num, in_sig_name, IN_RING_BASE_ADDR, IN_REF_CNT)
    ru_emem_ring_op(in_xfer_reg, in_ring_num, in_sig_name, put, IN_RING_BASE_ADDR,  IN_REF_CNT, --)
#endm


/** Remove entries from the head of the circular buffer in emem based on parameters passed to the macro
 *
 * @param IN_RING_BASE_ADDR    40-bit address identifying the location of the rings in emem0, emem1 or emem2
 * @param out_xfer_reg         Entries to remove from the circular buffer
 * @param in_ring_num          Select the ring number to remove from, between 0-1023
 * @param IN_REF_CNT           Number of 32-bit words to remove from the circular buffer must between 1-16
 * @param in_sig_name          Signal to use for ring operation
 *
 * See ru_emem_ring_op() macro for implementation details
 * Some compile time error checking is done.
 *
 */
#macro ru_emem_ring_get(out_xfer_reg, in_ring_num, in_sig_name, IN_RING_BASE_ADDR, IN_REF_CNT, IN_ERROR_LABEL)
    ru_emem_ring_op(out_xfer_reg, in_ring_num, in_sig_name, get, IN_RING_BASE_ADDR,  IN_REF_CNT, IN_ERROR_LABEL)
#endm


/** Perform an operation on the ring.
 *
 * @param _io_entries           Entries to add (or xfer registers to write) to the circular buffer
 * @param _in_ring_num          Select the ring number to add to, between 0-1023
 * @param _in_sig_name          Signal to use for ring operation
 * @param _IN_CMD               Command to be performed on the ring. supported commands are: get, get_eop, get_safe, get_freely
 *                              pop, pop_eop, pop_safe, pop_freely, put, journal and fast_journal
 * @param _IN_RING_BASE_ADDR    40-bit address identifying the location of the rings in emem0, emem1 or emem2
 * @param _IN_REF_CNT           Number of 32-bit words to add/remove to/from the circular buffer, must be between 1-16, or '--' for fast_journal
 * @param _IN_ERROR_LABEL       Error label to branch to if buffer does not have sufficient words or space. Use '--' for get_freely,
 *                              get_safe, put, pop_freely, pop_safe
 *
 */
#macro ru_emem_ring_op(_io_entries, _in_ring_num, _in_sig_name, _IN_CMD, _IN_RING_BASE_ADDR,  _IN_REF_CNT, _IN_ERROR_LABEL)
    #if (!defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
        #error "ru_emem_ring_setup: macro requires NFP6000 indirect reference format (-indirect_ref_format_nfp6000)."
    #endif

    #if (streq('_IN_CMD','get'))
    #elif (streq('_IN_CMD','get_eop'))
    #elif (streq('_IN_CMD','get_safe'))
    #elif (streq('_IN_CMD','get_freely'))
    #elif (streq('_IN_CMD','pop'))
    #elif (streq('_IN_CMD','pop_eop'))
    #elif (streq('_IN_CMD','pop_safe'))
    #elif (streq('_IN_CMD','pop_freely'))
    #elif (streq('_IN_CMD','put'))
    #elif (streq('_IN_CMD','journal'))
    #elif (streq('_IN_CMD','fast_journal'))
    #else
        #error "Command not supported"
        #error _IN_CMD
    #endif

    #if(!streq('_IN_REF_CNT', '--'))
        #if (!is_ct_const(_IN_REF_CNT))
            #error "ru_emem_ring_op: _IN_REF_CNT must be constant."
        #endif

        #if (_IN_REF_CNT > 16)
            #error "ru_emem_ring_op: _IN_REF_CNT cannot exceed 16."
        #endif
    #endif
    .begin
    .reg src_op1, src_op2
    immed[src_op1, ((_IN_RING_BASE_ADDR >>24) & 0xFFFF), <<16]
    #if (streq('_IN_CMD','fast_journal')) //fast_journal is a little different
        #if (!streq('_IN_REF_CNT','--'))
            #error "ru_emem_ring_op: fast_journal commands do not take a ref count."
        #endif
            .reg _tmp
            move(_tmp, _in_ring_num)
            move(src_op2, _io_entries)
            ov_single(OV_DATA_REF, _tmp)
            mem[_IN_CMD, --, src_op1, <<8, src_op2], indirect_ref
    #else
        #if (!strstr(_io_entries, $))
            #error "ru_emem_ring_op: _io_entries must be xfer register"
        #endif

        #if (is_rt_const(_in_ring_num))
            .assert ((_in_ring_num >= 0) && (_in_ring_num <= 1023))


            immed[src_op2, _in_ring_num]
            #if (_IN_REF_CNT > 8)
                .reg cnt

                immed[cnt, (_IN_REF_CNT - 1)]   // override zero indexed
                alu[--, 0x80, OR, cnt, <<8]
                #if(_IN_REF_CNT > 1)
                    mem[_IN_CMD, _io_entries[0], src_op1, <<8, src_op2, max_/**/_IN_REF_CNT], indirect_ref, sig_done[_in_sig_name]
                #else
                    mem[_IN_CMD, _io_entries, src_op1, <<8, src_op2, max_/**/_IN_REF_CNT], indirect_ref, sig_done[_in_sig_name]
                #endif
            #else
            #if(_IN_REF_CNT > 1)
                mem[_IN_CMD, _io_entries[0], src_op1, <<8, src_op2, _IN_REF_CNT], sig_done[_in_sig_name]
            #else
                mem[_IN_CMD, _io_entries, src_op1, <<8, src_op2, _IN_REF_CNT], sig_done[_in_sig_name]
            #endif
            #endif
            #if ((streq('_IN_CMD','get') \
                || streq('_IN_CMD','get_eop') \
                || streq('_IN_CMD','pop') \
                || streq('_IN_CMD','pop_eop')))
                ctx_arb[_in_sig_name[0]]
                #if (!streq('_IN_ERROR_LABEL','--'))
                    br_signal[_in_sig_name[1], _IN_ERROR_LABEL]
                #endif
            #else
                ctx_arb[_in_sig_name]
            #endif
        #else


            immed[src_op2, 0x3FF]   // ring numbers limited to 1023
            alu[src_op2, _in_ring_num, and, src_op2]
            #if (_IN_REF_CNT > 8)
                .reg cnt

                immed[cnt, (_IN_REF_CNT - 1)]   // override zero indexed
                alu[--, 0x80, OR, cnt, <<8]
                mem[_IN_CMD, _io_entries, src_op1, <<8, src_op2, max_/**/_IN_REF_CNT], indirect_ref, sig_done[_in_sig_name]
            #else
                mem[_IN_CMD, _io_entries, src_op1, <<8, src_op2, _IN_REF_CNT], sig_done[_in_sig_name]
            #endif
            #if ((streq('_IN_CMD','get') \
                || streq('_IN_CMD','get_eop') \
                || streq('_IN_CMD','pop') \
                || streq('_IN_CMD','pop_eop')))
                ctx_arb[_in_sig_name[0]]
                #if (!streq('_IN_ERROR_LABEL','--'))
                    br_signal[_in_sig_name[1], _IN_ERROR_LABEL]
                #endif
            #else
                ctx_arb[_in_sig_name]
            #endif
        #endif
    #endif
    .end
#endm
/**
 * Next-neighbor ring initialization
 *
 * @param NN_EMPTY_THRESHOLD  Threshold when NN_Empty asserts.
 *                            Valid values are 0-3.
 *
 */
#macro ru_nn_ring_init(NN_EMPTY_THRESHOLD)
.begin

    .reg ctx_enable
    local_csr_rd[ctx_enables]
    immed[ctx_enable, 0]
    alu_shf[ctx_enable, ctx_enable, AND~, 3, <<18]
    alu_shf[ctx_enable, ctx_enable, OR, NN_EMPTY_THRESHOLD, <<18]
    local_csr_wr[ctx_enables, ctx_enable]
    local_csr_wr[nn_put, 0]
    local_csr_wr[nn_get, 0]
    alu[--, --, b, 0]
    alu[--, --, b, 0]
    alu[--, --, b, 0]

.end
#endm // _nn_ring_init




/** Set up a type 2 DRAM ring based on parameters passed to the macro.
 *
 * Some compile time error checking is done.
 *
 * @param _IN_RING_NUM_    Number of DRAM ring to configure
 * @param _IN_BASE_ADDR_   DRAM address where ring starts
 * @param _IN_SIZE_LW_     LW size of ring, must be between 512 and 16M and a power of 2
 * @param _IN_Q_LOC_       Queue locality mode: @n
 *                         @arg @c MU_LOCALITY_HIGH
 *                         @arg @c MU_LOCALITY_LOW
 *                         @arg @c MU_LOCALITY_DIRECT_ACCESS
 *                         @arg @c MU_LOCALITY_DISCARD_AFTER_READ
 * @param _IN_Q_PAGE_      Top two bits of the queue entry addresses.
 *
 */
#macro ru_dram_ring_setup(_IN_RING_NUM_, _IN_BASE_ADDR_, _IN_SIZE_LW_, _IN_Q_LOC_, _IN_Q_PAGE_)
    #if (!defined(__NFP_INDIRECT_REF_FORMAT_NFP3200) && !defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
        #error "This macro is only available in NFP indirect reference format mode."
    #endif

    .begin
        // First perform some error checking
        #if ((_IN_SIZE_LW_ < 512) | (_IN_SIZE_LW_ > (16 * M)))
            #error "ru_dram_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be in range of [512 16M]."
        #endif

        #if (_IN_Q_PAGE_ > 3)
            #error "ru_dram_ring_setup: Invalid q_page value, must be a 2-bit value."
        #endif

        #if (_IN_Q_LOC_ > 3)
            #error "ru_dram_ring_setup: Invalid q_loc value, must be a 2-bit value."
        #endif

        // The encoding is pretty much log2(_IN_SIZE_LW_/512) [512 is the minimum size]
        // So make sure all sizes is a power of 2
        #if (_IN_SIZE_LW_ & (_IN_SIZE_LW_ - 1) != 0)
            #error "ru_dram_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be a power of 2."
        #endif  /* _IN_SIZE_LW_ */

        #define_eval    _RING_SIZE_ENC_     log2(_IN_SIZE_LW_ >>9)

        // The ring must be aligned to the ring size
        #if (is_ct_const(_IN_BASE_ADDR_))
            #if (_IN_BASE_ADDR_ & ((_IN_SIZE_LW_ <<2) -  1))
                #error "ru_dram_ring_setup: Ring base address must be aligned based on the ring size  (Ring #" _IN_RING_NUM_")"
            #endif  /* _IN_BASE_ADDR_ */
        #elif (is_rt_const(_IN_BASE_ADDR_))
            .assert ((_IN_BASE_ADDR_ % (_IN_SIZE_LW_ <<2)) == 0) "ru_dram_ring_setup: Ring base address must be aligned based on the ring size"
        #endif

        // make sure the ring number is valid
        #if ((_IN_RING_NUM_ < 0) | (_IN_RING_NUM_ > 1023))
            #error "ru_dram_ring_setup: DRAM ring numbers must be between 0 and 1023 (inclusive)"
        #endif  /* _IN_RING_NUM_ */

        .reg    ring_addr
        .reg    ring_temp

        .reg    ring_setup[4]

        xbuf_alloc($ring_desc, 4, read_write)

        .sig    ring_sig

        move(ring_addr, _IN_BASE_ADDR_)

        move(ring_temp, _IN_BASE_ADDR_)
        alu[ring_setup[0], ring_temp, and~, 0x3F, <<26]              // clear top 4 bits and 2 reserved bits of addr for this word
        alu[ring_setup[0], ring_setup[0], or, _RING_SIZE_ENC_, <<28]// set the encoded ring size in those bits
        alu[ring_setup[1], ring_temp, or, 2]                        // 2 low order bits are the ring type

        immed[ring_setup[2], ((_IN_Q_LOC_ << 14) | (_IN_Q_PAGE_ << 8)), <<16] // count is zero

        alu[ring_setup[3], --, b, 0]

        alu[$ring_desc0, --, b, ring_setup[0]]
        alu[$ring_desc1, --, b, ring_setup[1]]
        alu[$ring_desc2, --, b, ring_setup[2]]
        alu[$ring_desc3, --, b, ring_setup[3]]

        mem[write, $ring_desc0, ring_addr, 0, 2], sig_done[ring_sig]
        ctx_arb[ring_sig]

        // read the data back so we can be sure it is in memory
        mem[read, $ring_desc0, ring_addr, 0, 2], sig_done[ring_sig]
        ctx_arb[ring_sig]

        // now we load the descriptor into the queue hardware
        #if (defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
            #if is_ct_const(_IN_RING_NUM_)
                move(ring_temp, _IN_RING_NUM_)
                alu[ring_temp, --, b, ring_temp, <<16]
            #else
                alu[ring_temp, --, b, _IN_RING_NUM_, <<16]
            #endif  /* is_ct_const(_IN_RING_NUM_) */
        #else
            // use mode 0 for the indirect format
            ; NB: It is important to note that we are assuming the enhanced indirect format
            #if is_ct_const(_IN_RING_NUM_)
                move(ring_temp, _IN_RING_NUM_)
                alu[ring_temp, --, b, ring_temp, <<5]
            #else
                alu[ring_temp, --, b, _IN_RING_NUM_, <<5]
            #endif  /* is_ct_const(_IN_RING_NUM_) */
        #endif
        mem[rd_qdesc, --, ring_addr, 0], indirect_ref
        br[ru_dram_ring_setup_end#]


    ru_dram_ring_setup_end#:
        // clean up namespace
        xbuf_free($ring_desc)
        #undef  _RING_SIZE_ENC_

    .end
#endm // ru_dram_ring_setup


/** Set up a type 2 DRAM ring based on parameters passed to the macro.
 *
 * This is an overloaded macro which uses @c MU_LOCALITY_HIGH for
 * @c _IN_Q_LOC_ and @c 0 for @c _IN_Q_PAGE_.
 *
 * @param _IN_RING_NUM_    Number of DRAM ring to configure
 * @param _IN_BASE_ADDR_   DRAM address where ring starts
 * @param _IN_SIZE_LW_     LW size of ring, must be between 512 and 16M and a power of 2
 *
 */
#macro ru_dram_ring_setup(_IN_RING_NUM_, _IN_BASE_ADDR_, _IN_SIZE_LW_)
    ru_dram_ring_setup(_IN_RING_NUM_, _IN_BASE_ADDR_, _IN_SIZE_LW_, MU_LOCALITY_HIGH, 0)
#endm // ru_dram_ring_setup


/** Set up a SRAM ring Based on parameters passed into the macro.
 *
 * Some compile time error checking is done.
 *
 * @param _IN_RING_NUM_    Number of SRAM ring to configure
 * @param _IN_BASE_ADDR_   SRAM address where ring starts (channel value will be extracted)
 * @param _IN_SIZE_LW_     LW size of ring, must be between 512 and 64K and a power of 2
 *
 */
#macro ru_sram_ring_setup(_IN_RING_NUM_, _IN_BASE_ADDR_, _IN_SIZE_LW_)
.begin

    // First perform some error checking
    #if ((_IN_SIZE_LW_ < 512) | (_IN_SIZE_LW_ > (64 * K)))
        #error "ru_sram_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be in range of [512 64K]."
    #endif

    // The encoding is pretty much log2(_IN_SIZE_LW_/512) [512 is the minimum size]
    // So make sure all sizes is a power of 2
    #if (_IN_SIZE_LW_ & (_IN_SIZE_LW_ - 1) != 0)
        #error "ru_sram_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be a power of 2."
    #endif  /* _IN_SIZE_LW_ */

    #define_eval    _RING_SIZE_ENC_     log2(_IN_SIZE_LW_ >>9)

    // Extract the channel number and remove it from the base address
    #define_eval    _RING_CHAN_NUM_ ((_IN_BASE_ADDR_ >>30) & 3)
    #define_eval    _RING_BASE_ADDR_    (_IN_BASE_ADDR_ & ~(3<<30))

    // The ring must be aligned to the ring size
    #if (_RING_BASE_ADDR_ & ((_IN_SIZE_LW_ <<2) -  1))
        #error "ru_sram_ring_setup: Ring base address must be aligned based on the ring size  (Ring #" _IN_RING_NUM_")"
    #endif  /* _RING_BASE_ADDR_ */

    // make sure the ring number is valid
    #if ((_IN_RING_NUM_ < 0) | (_IN_RING_NUM_ > 63))
        #error "ru_sram_ring_setup: SRAM ring numbers must be between 0 and 63 (inclusive)"
    #endif  /* _IN_RING_NUM_ */

    .reg    ring_addr
    .reg    ring_temp

    .reg    ring_setup[4]

    xbuf_alloc($ring_desc, 4, read_write)

    .sig    ring_sig

    move(ring_addr, _IN_BASE_ADDR_)
    move(ring_temp, ( (1<<23)-1 ) )
    alu[ring_temp, ring_temp, and, ring_addr]
    alu[ring_temp, --, b, ring_temp, >>2]   // word address


    alu[ring_setup[0], ring_temp, or, _RING_SIZE_ENC_, <<29]    // head with ring size encoding
    alu[ring_setup[1], --, b, ring_temp]                        // tail
    alu[ring_setup[2], --, b, 0]                                // count is zero
    alu[ring_setup[3], --, b, 0]

    alu[$ring_desc0, --, b, ring_setup[0]]
    alu[$ring_desc1, --, b, ring_setup[1]]
    alu[$ring_desc2, --, b, ring_setup[2]]
    alu[$ring_desc3, --, b, ring_setup[3]]

    sram[write, $ring_desc0, ring_addr, 0, 4], sig_done[ring_sig]
    ctx_arb[ring_sig]

    // read the data back so we can be sure it is in memory
    sram[read, $ring_desc0, ring_addr, 0, 4], sig_done[ring_sig]
    ctx_arb[ring_sig]

    // now we load the descriptor into the queue hardware
    alu[ring_temp, --, b, _RING_CHAN_NUM_, <<30]
    alu[ring_temp, ring_temp, or, _IN_RING_NUM_, <<24]
    alu[ring_addr, ring_addr, and~, 3, <<30]            // take out channel info (it's already being added back in)
    alu[ring_addr, ring_temp, or, ring_addr, >>2]       // address must be word address
    sram[rd_qdesc_head, $ring_desc0, ring_addr, 0, 2], ctx_swap[ring_sig]
    sram[rd_qdesc_other, --, ring_addr, 0]
    br[ru_sram_ring_setup_end#]


ru_sram_ring_setup_end#:
    // clean up namespace
    xbuf_free($ring_desc)
    #undef  _RING_SIZE_ENC_
    #undef  _RING_CHAN_NUM_
    #undef  _RING_BASE_ADDR_

.end
#endm // ru_sram_ring_setup


/** Set up a single CLS ring based on parameters passed into the macro.
 *
 * Some compile time error checking is done.
 *
 * @param _IN_RING_NUM_    Number of CLS ring to configure
 * @param _IN_BASE_ADDR_   CLS address where ring starts
 * @param _IN_SIZE_LW_     LW size of ring, must be between 32 and 1024 and a power of 2
 *
 *
 */
#macro ru_cls_ring_setup(_IN_RING_NUM_, _IN_BASE_ADDR_, _IN_SIZE_LW_)
    #if (IS_IXPTYPE(__IXP28XX))
        #error "This macro is not available for IXP code."
    #endif

    .begin

        .reg    ring_setup

        .reg    ring_csr_addr
        .reg    $ring_base
        .reg    $ring_ptrs

        .sig    ring_base_sig
        .sig    ring_ptrs_sig
        // First perform some error checking
        // Verify that a valid ring size has been given
        #if ((_IN_SIZE_LW_ < 32) | (_IN_SIZE_LW_ > (1 * K)))
            #error "ru_cls_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be in range of [32 1K]."
        #endif

        // The encoding is pretty much log2(_IN_SIZE_LW_/32) [32 is the minimum size]
        // So make sure all sizes is a power of 2
        #if (_IN_SIZE_LW_ & (_IN_SIZE_LW_ - 1) != 0)
            #error "ru_cls_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be a power of 2."
        #endif  /* _IN_SIZE_LW_ */

        #define_eval    _RING_SIZE_ENC_     log2(_IN_SIZE_LW_ >>5)

        // The lower 7 bits of the base address is ignored, so make sure these are 0
        // for alignment purposes
        // However, since the next test covers this implicitly, we only need to perform
        // that
        // The ring must be aligned to the ring size

        #if (is_ct_const(_IN_BASE_ADDR_))
            #if (_IN_BASE_ADDR_ % (_IN_SIZE_LW_ <<2))
                #error "ru_cls_ring_setup: Ring base address must be aligned based on the ring size  (Ring #:" _IN_RING_NUM_")"
            #endif  /* _IN_BASE_ADDR_ */
        #elif (is_rt_const(_IN_BASE_ADDR_))
            .assert ((_IN_BASE_ADDR_ % (_IN_SIZE_LW_ <<2)) == 0) "ru_cls_ring_setup: Ring base address must be aligned based on the ring size"
        #endif
        // Specify which events we would like to report
        // Assuming ring fullness can be tested for, we don't want to report on that
        // For now, don't request any events
        #define_eval    _RING_REPORT_ENC_   0

        immed[ring_setup, (_IN_BASE_ADDR_ >> 7)]
        alu[ring_setup, ring_setup, or, _RING_SIZE_ENC_, <<16]
        alu[$ring_base, ring_setup, or, _RING_REPORT_ENC_, <<24]
        // all other fields in ring_base is set to 0 as specified in the DB
        immed[$ring_ptrs, 0] // always set to 0

        // setup the ring CSR address for the ring base info
        move(ring_csr_addr, _CLS_RINGS_CSR_OFFSET_)
        alu[ring_csr_addr, ring_csr_addr, or, _IN_RING_NUM_, <<3]
        cls[write, $ring_base, 0, ring_csr_addr, 1], sig_done[ring_base_sig]

        // setup the ring CSR address for the ring ptrs info
        move(ring_csr_addr, (_CLS_RINGS_CSR_OFFSET_ + 0x80))
        alu[ring_csr_addr, ring_csr_addr, or, _IN_RING_NUM_, <<3]
        cls[write, $ring_ptrs, 0, ring_csr_addr, 1], sig_done[ring_ptrs_sig]

        ctx_arb[ring_base_sig, ring_ptrs_sig]


    ru_cls_ring_setup_end#:
        // clean up namespace
        #undef  _RING_SIZE_ENC_
        #undef  _RING_REPORT_ENC_

    .end
#endm // ru_cls_ring_setup


/** Set up a single CTM ring based on parameters passed into the macro.
 *
 * Some compile time error checking is done.
 *
 * @param _IN_RING_NUM_    CONST, Number of CTM ring to configure, must be between 0 and 14
 * @param _IN_BASE_ADDR_   CONST, CTM address where ring starts, must be aligned to ring size
 * @param _IN_SIZE_LW_     CONST, LW size of ring, must be between  128 and 16*1024 and a power of 2
 * @param _IN_STATUS_      CONST, status generation control, either "FULL" or "EMPTY"
 *
 */
#macro ru_ctm_ring_setup(_IN_RING_NUM_, _IN_BASE_ADDR_, _IN_SIZE_LW_, _IN_STATUS_)
    #if (!IS_IXPTYPE(__NFP6000))
        #error "This macro is only available on NFP6000."
    #endif

    .begin

        .sig    _s
        .reg    ring_setup
        .reg    ring_ctm_addr
        .reg    $xd[3]
        .xfer_order $xd

        // First perform some error checking

        // Verify that a valid ring number has been given
        #if ( _IN_RING_NUM_ > 14 )
            #error "ru_ctm_ring_setup: max ctm ring number is 14."
        #endif

        // Verify that a valid ring size has been given
        #if ((_IN_SIZE_LW_ < 128) | (_IN_SIZE_LW_ > (16 * K)))
            #error "ru_cls_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be in range of [128 16K]."
        #endif

        // The encoding is pretty much log2(_IN_SIZE_LW_/128) [128 is the minimum size]
        // So make sure all sizes is a power of 2
        #if (_IN_SIZE_LW_ & (_IN_SIZE_LW_ - 1) != 0)
            #error "ru_ctm_ring_setup: Invalid ring size specified (Ring #" _IN_RING_NUM_"): Ring size must be a power of 2."
        #endif  /* _IN_SIZE_LW_ */

        #define_eval    _RING_SIZE_ENC_     log2(_IN_SIZE_LW_ >>7)

        // The lower 9 bits of the base address is ignored, so make sure these are 0
        // for alignment purposes
        // However, since the next test covers this implicitly, we only need to perform
        // that
        // The ring must be aligned to the ring size

        #if (is_ct_const(_IN_BASE_ADDR_))
            #if (_IN_BASE_ADDR_ % (_IN_SIZE_LW_ <<2))
                #error "ru_ctm_ring_setup: Ring base address must be aligned based on the ring size  (Ring #:" _IN_RING_NUM_")"
            #endif  /* _IN_BASE_ADDR_ */
        #elif (is_rt_const(_IN_BASE_ADDR_))
            .assert ((_IN_BASE_ADDR_ % (_IN_SIZE_LW_ <<2)) == 0) "ru_cls_ring_setup: Ring base address must be aligned based on the ring size"
        #endif

        // Specify which status we want
        #if streq(_IN_STATUS_, 'FULL' )
            #define_eval _RING_STATUS_ENC_   1
        #else
            #define_eval _RING_STATUS_ENC_   0
        #endif

        #if (is_ct_const(_IN_BASE_ADDR_))
            #define_eval _IBA ((_IN_BASE_ADDR_ & 0x3FE00) >> 8)
            immed[ring_setup, _IBA, <<8]
            #undef _IBA
        #else
            immed[ring_setup, 0x3FE, <<8]
            alu[ring_setup, ring_setup, AND, _IN_BASE_ADDR_]
        #endif
        alu[ring_setup, ring_setup, or, _RING_SIZE_ENC_, <<29]
        alu[$xd[0], ring_setup, or, _RING_STATUS_ENC_, <<28]
        // all other fields in ring_base is set to 0 as specified in the DB
        immed[$xd[1], 0]
        immed[$xd[2], 0]

        // setup the ring CSR address
        move(ring_ctm_addr, 0x00080100) // local xpb, xpb dev id 8, start reg = ring_0 base
        alu[ring_ctm_addr, ring_ctm_addr, OR, _IN_RING_NUM_, <<4] // offset to selected ring

        // write the regs
        ct[xpb_write, $xd[0], ring_ctm_addr, 0, 3], ctx_swap[_s]

        ru_ctm_ring_setup_end#:
        // clean up namespace
        #undef  _RING_SIZE_ENC_
        #undef  _RING_STATUS_ENC_

    .end
#endm // ru_ctm_ring_setup


/** Wrapper for CLS/GS/CTM ring commands.
 *
 * This macro is used to hide some of the internal details such as encoding the ring address.
 *
 * @param __MEM_TYPE__   One of CLS,GS, or CTM. GS not supported for NFP6000. CTM only supported for NFP6000
 * @param _IN_CMD_       Ring command to perform (put/get for CLS,GS or ring_put/get for CTM)
 * @param in_xfer_reg    Xfer register name to use in command
 * @param _IN_RING_NUM_  Ring number where data is to be placed, must be between 0-15
 * @param _IN_REF_CNT_   Reference count, must be between 1-16
 * @param in_sig         Signal to use for ring operation
 *
 * @note No swapping on the signal is done, the calling code needs to do this.
 *
 */
#macro ru_ring_op(__MEM_TYPE__, _IN_CMD_, in_xfer_reg, _IN_RING_NUM_, _IN_REF_CNT_, in_sig)
    #if ( IS_NFPTYPE(__NFP6000) && streq('__MEM_TYPE__', 'GS'))
        #error "ring_op: Mem Type GS (Global Scratch) not supported on NFP6000"
    #endif

    #if ( !IS_NFPTYPE(__NFP6000) && streq('__MEM_TYPE__', 'CTM'))
        #error "ru_ring_op: Mem Type CTM (Cluster Target Memory) is only supported on NFP6000"
    #endif

    #if is_ct_const(_IN_RING_NUM_)
        #if ((_IN_RING_NUM_ < 0) | (_IN_RING_NUM_ > 15))
            #error "ru_ring_op: Ring number must be between 0 and 15"
        #endif
    #endif

    .begin
    .reg    addr_reg
    alu[addr_reg, --, b, _IN_RING_NUM_, <<2]    // 2: ring number is bits [5:2]

    #if (streq('__MEM_TYPE__', 'CS') || streq('__MEM_TYPE__', 'CLS'))
        #if (_IN_REF_CNT_ > 8)
            .reg _tmpc

            // Set override length in PREV_ALU according assembler option -indirect_ref_format_nfp6000/3200
            #if (defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
                immed[_tmpc, ((_IN_REF_CNT_) - 1)]          // note: length override field zero indexed
                alu[--, 0x80, or, _tmpc, <<8]               // 0x80: override length field flag
            #else                                           // __NFP_INDIRECT_REF_FORMAT_NFP3200
                alu[_tmpc, --, b, 0x02, <<28]               // 0x02: override length field flags
                alu[--, _tmpc, or, ((_IN_REF_CNT_) - 1)]    // note: length override field zero indexed
            #endif
            cls[_IN_CMD_, in_xfer_reg, 0, addr_reg, max_/**/_IN_REF_CNT_], indirect_ref, sig_done[in_sig]
        #else
            cls[_IN_CMD_, in_xfer_reg, 0, addr_reg, _IN_REF_CNT_], sig_done[in_sig]
        #endif

    #elif (streq('__MEM_TYPE__', 'GS'))

        scratch[_IN_CMD_, in_xfer_reg, 0, addr_reg, _IN_REF_CNT_], sig_done[in_sig]

    #elif (streq('__MEM_TYPE__', 'CTM'))
        #if (_IN_REF_CNT_ > 8)
            .reg _tmp

            // Set override length in PREV_ALU according assembler option -indirect_ref_format_nfp6000/3200
            #if (defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
                immed[_tmp, ((_IN_REF_CNT_) - 1)]       // note: length override field zero indexed
                alu[--, 0x80, or, _tmp, <<8]            // 0x80: override length field flag
            #else                                       // __NFP_INDIRECT_REF_FORMAT_NFP3200
                alu[_tmp, --, b, 0x02, <<28]            // 0x02: override length field flags
                alu[--, _tmp, or, ((_IN_REF_CNT_) - 1)] // note: length override field zero indexed
            #endif

            ct[_IN_CMD_, in_xfer_reg, 0, addr_reg, max_/**/_IN_REF_CNT_], indirect_ref, sig_done[in_sig]
        #else
            ct[_IN_CMD_, in_xfer_reg, 0, addr_reg, _IN_REF_CNT_], sig_done[in_sig]
        #endif
    #else
        #error "Ring Memory type not valid."
    #endif
    .end
#endm


/// @cond INTERNAL_MACROS
/** Wrapper for QDR ring commands.
 *
 * @param _IN_CMD_                Ring command to perform (get / put / journal)
 * @param in_xfer_reg             Xfer register name to use in command
 * @param in_src_op1/in_src_op2   Restricted operands are added (src_op1 + src_op2) to define the following:
 *                                @arg [31:30]: SRAM channel.
 *                                @arg [29:8]: Ignored.
 *                                @arg [7:2]: Ring number.
 *                                @arg [1:0]: Ignored.
 * @param _IN_REF_CNT_            Reference count in increments of 4 byte words. Valid values are 1 to 8.
 * @param in_sig_name             Signal to use for ring operation
 * @param sig_action              SIG_NONE or SIG_WAIT
 *
 * @note @arg If there are no sufficient words in the ring for get and put commands, two signals will be pushed where
 *            sig_name[1] signals error.
 */
#macro _ru_sram_ring_op(_IN_CMD_, in_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    #if (!is_ct_const(_IN_REF_CNT_))
        #error "_ru_sram_ring_op: reference count must be constant."
    #endif

    #if (_RING_CHAN_NUM_ > 3 || _RING_CHAN_NUM_ < 0)
        #error "Ring channel must be in the range 0-3"
    #endif

    .reg q_id tmp
    alu_shf[tmp, --, B, _RING_CHAN_NUM_, <<30]
    move(q_id, in_src_op1)
    alu_shf[q_id, tmp, OR, q_id, <<2]
    sram[_IN_CMD_, in_xfer_reg, q_id, in_src_op2, _IN_REF_CNT_], sig_done[in_sig_name]

    #if (streq('sig_action', 'SIG_WAIT'))
        ctx_arb[in_sig_name]
    #endif
.end
#endm
/// @endcond

/** Put @p _IN_REF_CNT_ words on sram ring
 * @param in_xfer_reg             Xfer register name to use in command
 * @param in_src_op1              Restricted operands are added (src_op1 + src_op2) to define the following:
 *                                @arg [31:30]: SRAM channel.
 *                                @arg [29:8]: Ignored.
 *                                @arg [7:2]: Ring number.
 *                                @arg [1:0]: Ignored.
 * @param in_src_op2              As per above
 * @param _RING_CHAN_NUM_         SRAM channel/bank to use
 * @param _IN_REF_CNT_            Reference count in increments of 4 byte words. Valid values are 1 to 8.
 * @param in_sig_name             Signal to use for ring operation
 * @param sig_action              SIG_NONE or SIG_WAIT
 *
 * @note @arg If there are no sufficient words in the ring for get and put commands, two signals will be pushed where
 *            sig_name[1] signals error.
 */
#macro ru_sram_ring_put(in_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_sram_ring_op(put, in_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_sram_ring_put

/** Refer to description for ru_sram_ring_put macro.
 */
#macro ru_sram_ring_get(out_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, IN_REF_CNT_, in_sig_name)
    _ru_sram_ring_op(get, out_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, _IN_REF_CNT_, in_sig_name, SIG_NONE)
#endm // ru_sram_ring_get

/** Refer to description for ru_sram_ring_put macro.
 */
#macro ru_sram_ring_get(out_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_,  _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_sram_ring_op(get, out_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_sram_ring_get

/** Refer to description for ru_sram_ring_put macro.
 */
#macro ru_sram_ring_journal(in_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_sram_ring_op(journal, in_xfer_reg, in_src_op1, in_src_op2, _RING_CHAN_NUM_, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_sram_ring_journal

/// @cond INTERNAL_MACROS
/** Wrapper for DDR ring commands.
 *
 * @param _IN_CMD_                Ring command to perform (get / get_safe / get_eop / get_tag_safe /
 *                                pop / pop_safe / pop_eop / pop_tag_safe /
 *                                put / put_tag / journal / journal_tag)
 * @param in_xfer_reg             Xfer register name to use in command
 * @param in_src_op1/in_src_op2   Restricted operands are added (src_op1 + src_op2) to define the following:
 *                                @arg [23:16]: Memory tag number for XX_tag_XX commands.
 *                                @arg [9:0]: Queue array entry number.
 * @param _IN_REF_CNT_            Reference count in increments of 4 byte words. Valid values are 1 to 16
 *
 * @param in_sig_name             Signal to use for ring operation
 * @param sig_action              SIG_NONE or SIG_WAIT
 *
 * @note @arg If there are not sufficient words in the ring for get, pop, and put commands, two signals will be pushed where
 *            sig_name[1] signals error.
 *       @arg If the EOP bit is set for get_eop and pop_eop commands, two signals will be pushed, where sig_name[1] signals error.
 *       @arg If the tag is not matched for get_safe_tag, pop_tag_safe, and journal_tag, two signals will be pushed, where
 *            sig_name[1] signals error.
 *
 */
#macro _ru_dram_ring_op(_IN_CMD_, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    #if (!is_ct_const(_IN_REF_CNT_))
        #error "_ru_dram_ring_op: _IN_REF_CNT must be constant."
    #endif

    #if (_IN_REF_CNT_ > 16)
        #error "_ru_dram_ring_op: _IN_REF_CNT cannot exceed 16."
    #endif

    #if (IS_NFPTYPE(__NFP6000) && ( strstr(_IN_CMD_, 'tag') != 0 ))
        #error "ru_dram_ring_op: tag cmds not supported on NFP6000"
    #endif

    .begin
    #if (is_ct_const(in_src_op1))
        .reg q_id

        immed[q_id, in_src_op1]
        #if ((_IN_REF_CNT_) > 8)
            .reg cnt

            // Set override length in PREV_ALU according assembler option -indirect_ref_format_nfp6000/3200
            #if (defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
                immed[cnt, ((_IN_REF_CNT_) - 1)]        // note: length override field zero indexed
                alu[--, 0x80, or, cnt, <<8]             // 0x80: indicate override length field
            #else                                       // __NFP_INDIRECT_REF_FORMAT_NFP3200
                alu[cnt, --, b, 0x02, <<28]             // 0x02: indicate override length field
                alu[--, cnt, or, ((_IN_REF_CNT_) - 1)]  // note: length override field zero indexed
            #endif
            mem[_IN_CMD_, in_xfer_reg, q_id, in_src_op2, max_/**/_IN_REF_CNT_], indirect_ref, sig_done[in_sig_name]
        #else
            mem[_IN_CMD_, in_xfer_reg, q_id, in_src_op2, _IN_REF_CNT_], sig_done[in_sig_name]
        #endif
    #else
        #if (_IN_REF_CNT_ > 8)
            .reg cnt

            // Set override length in PREV_ALU according assembler option -indirect_ref_format_nfp6000/3200
            #if (defined(__NFP_INDIRECT_REF_FORMAT_NFP6000))
                immed[cnt, ((_IN_REF_CNT_) - 1)]        // note: length override field zero indexed
                alu[--, 0x80, or, cnt, <<8]             // 0x80: indicate override length field
            #else                                       // __NFP_INDIRECT_REF_FORMAT_NFP3200
                alu[cnt, --, b, 0x02, <<28]             // 0x02: indicate override length field
                alu[--, cnt, or, ((_IN_REF_CNT_) - 1)]  // note: length override field zero indexed
            #endif
            mem[_IN_CMD_, in_xfer_reg, in_src_op1, in_src_op2, max_/**/_IN_REF_CNT_], indirect_ref, sig_done[in_sig_name]
        #else
            mem[_IN_CMD_, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_], sig_done[in_sig_name]
        #endif
    #endif  // is_ct_const(in_src_op1)
    .end

    #if ((streq('_IN_CMD_','get')     + \
          streq('_IN_CMD_','get_eop') + \
          streq('_IN_CMD_','pop')     + \
          streq('_IN_CMD_','pop_eop')) == 1)

        #if (streq('sig_action', 'SIG_WAIT'))
            ctx_arb[in_sig_name[0]]
        #endif
    #else
        #if (streq('sig_action', 'SIG_WAIT'))
            ctx_arb[in_sig_name]
        #endif
    #endif
#endm
/// @endcond

/** Put @p _IN_REF_CNT_ words on dram ring
 * @param in_xfer_reg             Xfer register name to use in command
 * @param in_src_op1              Restricted operands are added (src_op1 + src_op2) to define the following:
 *                                @arg [23:16]: Memory tag number for XX_tag_XX commands.
 *                                @arg [9:0]: Queue array entry number.
 * @param in_src_op2              As per above
 * @param _IN_REF_CNT_            Reference count in increments of 4 byte words. Valid values are 1 to 16 for NFP6000
 *                                or 1 to 8 otherwise. Specified as actual count - 1.
 * @param in_sig_name             Signal to use for ring operation
 * @param sig_action              SIG_NONE or SIG_WAIT
 *
 * @note @arg If there are not sufficient words in the ring for get, pop, and put commands, two signals will be pushed where
 *            sig_name[1] signals error.
 *       @arg If the EOP bit is set for get_eop and pop_eop commands, two signals will be pushed, where sig_name[1] signals error.
 *       @arg If the tag is not matched for get_safe_tag, pop_tag_safe, and journal_tag, two signals will be pushed, where
 *            sig_name[1] signals error.
 *
 */
#macro ru_dram_ring_put(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(put, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_put


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_put_tag(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(put_tag, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_put_tag


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_qadd_work(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(qadd_work, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_put


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_qadd_thread(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(qadd_thread, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_put


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_get(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name)
    _ru_dram_ring_op(get, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, SIG_NONE)
#endm // ru_dram_ring_get

/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_get(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(get, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_get


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_get_eop(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(get_eop, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_get_eop


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_get_safe(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(get_safe, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_get_safe


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_get_tag_safe(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(get_tag_safe, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_get_tag_safe


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_pop(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name)
    _ru_dram_ring_op(pop, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, SIG_NONE)
#endm // ru_dram_ring_pop

/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_pop(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    #if (streq('sig_action', 'SIG_WAIT'))
        #error "SIG_WAIT may cause indefinite wait in ctx_arb[] due to double signal. Use SIG_NONE instead and handle signal external to macro."
    #endif
    #if (streq('sig_action', 'SIG_NONE'))
        #warning "This macro is deprecated. Please use the macro without sig_action parameter."
    #endif
    _ru_dram_ring_op(pop, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_pop


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_pop_eop(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(pop_eop, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_pop_eop


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_pop_safe(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(pop_safe, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_pop_safe


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_pop_tag_safe(out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(pop_tag_safe, out_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_pop_tag_safe


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_journal(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(journal, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_journal


/** Refer to description for ru_dram_ring_put macro.
 */
#macro ru_dram_ring_journal_tag(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
    _ru_dram_ring_op(journal_tag, in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
#endm // ru_dram_ring_journal_tag

/**
 * Generic ring dequeue operation
 *
 * @param out_req  Register aggregate
 * @param RING_TYPE Ring type, One of NN_RING,CLS_RING,GS_RING,DDR_RING,QDR_RING
 * @param ref_cnt Number of operations to perform
 * @param ring_num Ring number
 * @param sig Signal to generate
 * @param sig_action If SIG_WAIT, waits for operation to complete
 * @param __NULL_LABEL__ label to branch to on NN_RING empty, or -- to wait for not empty
 *
 */
#macro ru_deq_from_ring(out_req, RING_TYPE, ref_cnt, ring_num, sig, sig_action, __NULL_LABEL__)
    ru_deq_from_ring(out_req, RING_TYPE, ref_cnt, ring_num, --, sig, sig_action, __NULL_LABEL__)
#endm

/**
 * Generic ring dequeue operation
 *
 * @param out_req  Register aggregate
 * @param RING_TYPE Ring type, One of NN_RING,CLS_RING,GS_RING,DDR_RING,QDR_RING
 * @param ref_cnt Number of operations to perform
 * @param ring_num Ring number
 * @param ring_chan Ring channel, only applicable to the QDR_RING
 * @param sig Signal to generate
 * @param sig_action If SIG_WAIT, waits for operation to complete
 * @param __NULL_LABEL__ label to branch to on NN_RING empty, or -- to wait for not empty
 *
 */
#macro ru_deq_from_ring(out_req, RING_TYPE, ref_cnt, ring_num, ring_chan, sig, sig_action, __NULL_LABEL__)
.begin

    #if ( ( streq('RING_TYPE', 'NN_RING')   + \
            streq('RING_TYPE', 'CLS_RING')  + \
            streq('RING_TYPE', 'GS_RING')   + \
            streq('RING_TYPE', 'DDR_RING')  + \
            streq('RING_TYPE', 'DDR_WQ_RING')  + \
            streq('RING_TYPE', 'QDR_RING')    \
        ) != 1 )
        #error "ru_deq_from_ring: Either Input interface not defined or multiple interface types defined."
    #endif

    #if (IS_NFPTYPE(__NFP6000))
        #if ( streq('RING_TYPE', 'GS_RING'))
            #error "ru_deq_from_ring: GS_RING (Global Scratch Ring) not supported on NFP6000."
        #endif
    #endif

    #if (streq('__NULL_LABEL__', '--'))
        #define_eval __LOOP_LABEL__ ("dq_ring_empty#")
    #else
        #define_eval __LOOP_LABEL__ ('__NULL_LABEL__')
    #endif

    #if ( streq('RING_TYPE', 'NN_RING') )

        dq_ring_empty#:
        br_inp_state[nn_empty, __LOOP_LABEL__]

        #define_eval __LOOP__ 0

        #while(__LOOP__ < ref_cnt)

            alu[out_req[__LOOP__], --, b, *n$index++]

            #define_eval __LOOP__ (__LOOP__ + 1)

        #endloop

        #undef __LOOP__

        #if( streq('sig_action', 'SIG_WAIT') )
            ctx_arb[sig]
        #endif

    #elif ( streq('RING_TYPE', 'CLS_RING') )

        ru_ring_op(CLS, get, out_req[0], ring_num, ref_cnt, sig)

        #if( streq('sig_action', 'SIG_WAIT') )
            ctx_arb[sig]
        #endif

    #elif ( streq('RING_TYPE', 'GS_RING') )

        ru_ring_op(GS, get, out_req[0], ring_num, ref_cnt, sig)

        #if( streq('sig_action', 'SIG_WAIT') )
            ctx_arb[sig]
        #endif

    #elif ( streq('RING_TYPE', 'DDR_RING') )

        ru_dram_ring_get(out_req[0], ring_num, 0, ref_cnt, sig, sig_action)

    #elif( streq('RING_TYPE', 'DDR_WQ_RING') )

        ru_dram_ring_qadd_thread(out_req[0], ring_num, 0, ref_cnt, sig, sig_action)

    #elif ( streq('RING_TYPE', 'QDR_RING') )

        #if (streq('ring_chan', '--'))
            #define_eval RING_CHAN 0
            #warning "Ring channel was not specified for a QDR ring, assuming channel zero! Use ru_enq_to_ring with 8 parameters to explicitly set the channel"
        #else
            #define_eval RING_CHAN ring_chan
        #endif
        ru_sram_ring_get(out_req[0], ring_num, 0, RING_CHAN, ref_cnt, sig, sig_action)

    #else

        #error "Invalid input interface type defined:" RING_TYPE

    #endif //QDR_RING

    #undef __LOOP_LABEL__

.end
#endm // ru_deq_from_ring


/** Add n 32-bit words to the tail of the ring.
 *
 * @param in_xfer_reg   xfer registers
 * @param in_src_op1    Ring number (contant/GPR)
 * @param in_src_op2    Not used and ignored. Can be "--".
 * @param _IN_REF_CNT_  Number of 32-bit words to put on to ring
 * @param in_sig_name   Signal to wait on
 * @param sig_action    SIG_WAIT or SIG_NONE
 */
#macro ru_cls_ring_put(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    ru_ring_op(CLS, put, in_xfer_reg, in_src_op1, _IN_REF_CNT_, in_sig_name)
    #if( streq('sig_action', 'SIG_WAIT') )
        ctx_arb[in_sig_name]
    #endif

.end
#endm // ru_cls_ring_put


/** Pop n 32-bit words from tail of the ring (LIFO).
 */
#macro ru_cls_ring_pop(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    ru_ring_op(CLS, pop, in_xfer_reg, in_src_op1, _IN_REF_CNT_, in_sig_name)
    #if( streq('sig_action', 'SIG_WAIT') )
        ctx_arb[in_sig_name]
    #endif

.end
#endm // ru_cls_ring_pop


/** Pop n 32-bit words from tail of the ring (LIFO).
 *
 * If less than n in the ring, return zero for extra words.
 */
#macro ru_cls_ring_pop_safe(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    ru_ring_op(CLS, pop_safe, in_xfer_reg, in_src_op1, _IN_REF_CNT_, in_sig_name)
    #if( streq('sig_action', 'SIG_WAIT') )
        ctx_arb[in_sig_name]
    #endif

.end
#endm // ru_cls_ring_pop_safe


/** Get n 32-bit words from head of the ring (FIFO).
 *
 * If less than n in the ring, return zero for extra words.
 */
#macro ru_cls_ring_get_safe(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    ru_ring_op(CLS, get_safe, in_xfer_reg, in_src_op1, _IN_REF_CNT_, in_sig_name)
    #if( streq('sig_action', 'SIG_WAIT') )
        ctx_arb[in_sig_name]
    #endif

.end
#endm // ru_cls_ring_get_safe

/** Get n 32-bit words from head of the ring (FIFO).
 *
 */
#macro ru_cls_ring_get(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    ru_ring_op(CLS, get, in_xfer_reg, in_src_op1, _IN_REF_CNT_, in_sig_name)
    #if( streq('sig_action', 'SIG_WAIT') )
        ctx_arb[in_sig_name]
    #endif

.end
#endm // ru_cls_ring_get


/** Add n 32-bit words to the tail of the ring.
 *
 * @param in_xfer_reg   xfer registers
 * @param in_src_op1    Ring number (contant/GPR)
 * @param in_src_op2    Not used and ignored. Can be "--".
 * @param _IN_REF_CNT_  Number of 32-bit words to put on to ring
 * @param in_sig_name   Signal to wait on
 * @param sig_action    SIG_WAIT or SIG_NONE
 */
#macro ru_ctm_ring_put(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    ru_ring_op(CTM, ring_put, in_xfer_reg, in_src_op1, _IN_REF_CNT_, in_sig_name)
    #if( streq('sig_action', 'SIG_WAIT') )
        ctx_arb[in_sig_name]
    #endif

.end
#endm // ru_ctm_ring_put


/** Get n 32-bit words from head of the ring.
 *
 * @param in_xfer_reg   xfer registers
 * @param in_src_op1    Ring number (contant/GPR)
 * @param in_src_op2    Not used and ignored. Can be "--".
 * @param _IN_REF_CNT_  Number of 32-bit words to get from ring
 * @param in_sig_name   Signal to wait on
 * @param sig_action    SIG_WAIT or SIG_NONE
 */
#macro ru_ctm_ring_get(in_xfer_reg, in_src_op1, in_src_op2, _IN_REF_CNT_, in_sig_name, sig_action)
.begin

    ru_ring_op(CTM, ring_get, in_xfer_reg, in_src_op1, _IN_REF_CNT_, in_sig_name)
    #if( streq('sig_action', 'SIG_WAIT') )
        ctx_arb[in_sig_name]
    #endif

.end
#endm // ru_ctm_ring_get


/**
 * Generic ring enqueue operation, with optional ring channel
 *
 * @param in_req  Register aggregate
 * @param RING_TYPE Ring type, One of NN_RING,CLS_RING,GS_RING(not supported for NFP6000),DDR_RING,QDR_RING
 * @param ref_cnt Number of operations to perform
 * @param ring_num Ring number
 * @param sig Signal to generate
 * @param sig_action If SIG_WAIT, waits for operation to complete
 * @param __FULL_LABEL__ label to branch to on NN_RING full, or -- to wait for not full
 */
#macro ru_enq_to_ring(in_req, RING_TYPE, ref_cnt, ring_num, sig, sig_action, __FULL_LABEL__)
    ru_enq_to_ring(in_req, RING_TYPE, ref_cnt, ring_num, --, sig, sig_action, __FULL_LABEL__)
#endm

/**
 * Generic ring enqueue operation, with optional ring channel
 *
 * @param in_req  Register aggregate
 * @param RING_TYPE Ring type, One of NN_RING,CLS_RING,GS_RING,DDR_RING,QDR_RING
 * @param ref_cnt Number of operations to perform
 * @param ring_num Ring number
 * @param ring_chan Ring channel, only applicable to the QDR_RING
 * @param sig Signal to generate
 * @param sig_action If SIG_WAIT, waits for operation to complete
 * @param __FULL_LABEL__ label to branch to on NN_RING full, or -- to wait for not full
 */
#macro ru_enq_to_ring(in_req, RING_TYPE, ref_cnt, ring_num, ring_chan, sig, sig_action, __FULL_LABEL__)
.begin

    #if ( ( streq('RING_TYPE', 'NN_RING')   + \
            streq('RING_TYPE', 'CLS_RING')  + \
            streq('RING_TYPE', 'GS_RING')   + \
            streq('RING_TYPE', 'DDR_RING')  + \
            streq('RING_TYPE', 'DDR_WQ_RING')  + \
            streq('RING_TYPE', 'QDR_RING')    \
        ) != 1 )
        #error "ru_enq_to_ring: Either Output interface not defined or multiple interface types defined."
    #endif

    #if (IS_NFPTYPE(__NFP6000))
        #if ( streq('RING_TYPE', 'GS_RING'))
            #error "ru_enq_to_ring: GS_RING (Global Scratch Ring) not supported on NFP6000."
        #endif
    #endif


    #if (streq('__FULL_LABEL__', '--'))
        #define_eval __LOOP_LABEL__ ("enq_ring_full#")
    #else
        #define_eval __LOOP_LABEL__ ('__FULL_LABEL__')
    #endif

    #if( streq('RING_TYPE', 'NN_RING') )

    enq_ring_full#:
        br_inp_state[nn_full, __LOOP_LABEL__]

        #define_eval __LOOP__ 0

        #while(__LOOP__ < ref_cnt)

            alu[*n$index++, --, b, in_req[__LOOP__]]

            #define_eval __LOOP__ (__LOOP__ + 1)

        #endloop

        #undef __LOOP__

        #if( streq('sig_action', 'SIG_WAIT') )
            ctx_arb[sig]
        #endif

    #elif( streq('RING_TYPE', 'CLS_RING') )

        #if (!streq('__FULL_LABEL__', 'PUT_BLIND'))
        #if (!is_ct_const(ring_num))
            #error "Ring number must be constant."
        #endif

    enq_ring_full#:
        br_!inp_lstate[cls_ring/**/ring_num/**/_status, put_req#]

        br[__LOOP_LABEL__]
        #endif

    put_req#:
        ru_ring_op(CLS, put, in_req[0], ring_num, ref_cnt, sig)

        #if( streq('sig_action', 'SIG_WAIT') )
            ctx_arb[sig]
        #endif

    #elif( streq('RING_TYPE', 'GS_RING') )

        #if (!streq('__FULL_LABEL__', 'PUT_BLIND'))
        #if (!is_ct_const(ring_num))
            #error "Ring number must be constant."
        #endif

    enq_ring_full#:
        br_!inp_state[scr_ring/**/ring_num/**/_status, put_req#]

        br[__LOOP_LABEL__]
        #endif

    put_req#:
        ru_ring_op(GS, put, in_req[0], ring_num, ref_cnt, sig)

        #if( streq('sig_action', 'SIG_WAIT') )
            ctx_arb[sig]
        #endif

    #elif( streq('RING_TYPE', 'DDR_RING') )

        #if (!is_ct_const(ring_num))
            #error "Ring number must be constant."
        #endif

        ru_dram_ring_put(in_req[0], ring_num, 0, ref_cnt, sig, sig_action)

    #elif( streq('RING_TYPE', 'DDR_WQ_RING') )

        #if (!is_ct_const(ring_num))
            #error "Ring number must be constant."
        #endif

        ru_dram_ring_qadd_work(in_req[0], ring_num, 0, ref_cnt, sig, sig_action)

    #elif( streq('RING_TYPE', 'QDR_RING') )

        #if (streq('ring_chan', '--'))
            #define_eval RING_CHAN 0
            #warning "Ring channel was not specified for a QDR ring, assuming channel zero! Use ru_enq_to_ring with 8 parameters to explicitly set the channel"
        #else
            #define_eval RING_CHAN ring_chan
        #endif
        ru_sram_ring_put(in_req[0], ring_num, 0, RING_CHAN, ref_cnt, sig, sig_action)
    #else

        #error "Invalid output interface type defined:" RING_TYPE

    #endif

    #undef __LOOP_LABEL__

.end
#endm // ru_enq_to_ring

/*The following are deprecated, but we keep the old names for backward compatability*/
#define ru_cs_ring_setup ru_cls_ring_setup /**< Deprecated alias @deprecated This alias should not be used in new code. @see ru_cls_ring_setup */
#define ru_cs_ring_put ru_cls_ring_put /**< Deprecated alias @deprecated This alias should not be used in new code. @see ru_cls_ring_put */
#define ru_cs_ring_pop ru_cls_ring_pop /**< Deprecated alias @deprecated This alias should not be used in new code. @see ru_cls_ring_pop */
#define ru_cs_ring_pop_safe ru_cls_ring_pop_safe /**< Deprecated alias @deprecated This alias should not be used in new code. @see ru_cls_ring_pop_safe*/
#define ru_cs_ring_get_safe ru_cls_ring_get_safe /**< Deprecated alias @deprecated This alias should not be used in new code. @see ru_cls_ring_get_safe */


/** @}
 * @}
 */

#endif /* __RING_UTILS_UC__ */


