/*
 * Copyright (C) 2009-2015 Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __RING_EXT_UC__
#define __RING_EXT_UC__


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


#endif	/* __RING_EXT_UC */
