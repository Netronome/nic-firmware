/*
 * Copyright (C) 2017-2019 Netronome Systems, Inc.  All rights reserved.
 *
 * @file   ebpf.h
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#include <nfp_chipres.h>
#include <nfp/mem_ring.h>
#include "slicc_hash.h"

/*
 * EBPF support
 */
#define EBPF_WQ_NUM      17

#define BPF_NUM_MES	 2
#define BPF_NUM_THREADS	 4

#define EBPF_WQ_E_N	7

#define EBPF_INSTR_PER_ME	4096
#define EBPF_FW_GLUE_SIZE	31
#define EBPF_TGT_OUT		11
#define EBPF_TGT_ABORT		10

#ifndef _link_sym
#define _link_sym(x) __link_sym(#x)
#endif

#define M_CREATE_WQS()                                      \
    M_CREATE_WQ(m_ebpf_wq0);                                \
    M_CREATE_WQ(m_ebpf_wq1);                                \
    __shared __gpr unsigned int dbg_m_ebpf_wq_rnum;         \
    __shared __gpr mem_ring_addr_t dbg_m_ebpf_wq_mem;


#define M_CREATE_WQ(name)                                               \
    EMEM0_QUEUE_ALLOC(name##_rnum, global);                             \
    _NFP_CHIPRES_ASM(.alloc_mem name##_mem emem global SZ_1M SZ_1M);    \
    _NFP_CHIPRES_ASM(.init_mu_ring name##_rnum name##_mem);

#define M_INIT_WQ(name, lname)                                          \
    do {                                                                \
        dbg_##lname##_rnum = _link_sym(name##_rnum);                    \
        dbg_##lname##_mem =                                             \
            mem_ring_get_addr((__emem void *)_link_sym(name##_mem));    \
    } while(0)

/* in lib/nic_basic/_c/nic_internal.c */
__intrinsic void nic_local_bpf_reconfig(__gpr uint32_t *ctx_mode, uint32_t vid, uint32_t vnic);
__intrinsic void upd_slicc_hash_table(void);
