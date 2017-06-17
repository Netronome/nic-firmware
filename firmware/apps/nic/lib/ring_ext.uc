
/*
 * Copyright (C) 2009-2015 Netronome Systems, Inc.  All rights reserved.
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

#endif	/* __RING_EXT_UC */
