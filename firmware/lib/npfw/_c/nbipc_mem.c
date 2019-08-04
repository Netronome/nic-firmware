/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file  lib/npfw/_c/nbipc_mem.c
 * @brief Read and write NBI Preclassifier memories.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include <assert.h>
#include <nfp.h>
#include <nfp/me.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_nbi_pc.h>

#include <npfw/nbi_cpp.h>
#include <npfw/nbipc_mem.h>


/* Base addresses for NBI Preclassifier memories. */
#define NBIPC_CPP_BASE               0x300000
#define NBIPC_ALL_LMEM_BASE          (NBIPC_CPP_BASE + 0x0)
#define NBIPC_ALL_SMEM_BASE          (NBIPC_CPP_BASE + 0x80000)

/* Sizes of the NBI Preclassifier memories. */
#define NBIPC_LMEM_SIZE              0x4000
#define NBIPC_SMEM_SIZE              0x10000

/* Address of the NBI Preclassifier Table Set register. */
#define NBIPC_TABLE_SET_ADDR(_nbi)                                          \
    (NFP_NBI_PC_XPB_OFF(_nbi) | NFP_NBI_PC_CHAR | NFP_NBI_PC_CHAR_TABLESET)

/* Timeout value for polling for table set changes. */
#define NBIPC_TABLE_SET_POLL_TIMEOUT 100

/* Sleep between each XPB access to reduce the short burst of accesses. */
#ifndef NBIPC_XPB_SLEEP
#define NBIPC_XPB_SLEEP              2000
#endif


/**
 * Write to NBI Preclassifier memory from ME local memory, using the table-set
 * mechanism.
 */
__intrinsic static void
__nbipc_mem_table_copy_from_lmem(unsigned int nbi, uint32_t pri_addr,
                                 uint32_t sec_addr, __lmem void *addr,
                                 size_t size, SIGNAL *sig)
{
    unsigned int i;
    __gpr uint32_t table_set;
    __gpr uint32_t temp_table_set;

    try_ctassert(__is_aligned(pri_addr, NBIPC_MEM_ENTRY_SIZE));
    try_ctassert(__is_aligned(sec_addr, NBIPC_MEM_ENTRY_SIZE));
    try_ctassert(__is_aligned(size, NBIPC_MEM_ENTRY_SIZE));

    /* Check which memory table is the active copy. */
    table_set = xpb_read(NBIPC_TABLE_SET_ADDR(nbi)) &
                NFP_NBI_PC_CHAR_TABLESET_ACTIVE;

    /* Write to the shadow memory first. */
    if (table_set)
        __nbi_cpp_lmem2nbi_copy128(nbi, pri_addr, addr, size, sig);
    else
        __nbi_cpp_lmem2nbi_copy128(nbi, sec_addr, addr, size, sig);

    /* Switch to the updated memory table. */
    xpb_write(NBIPC_TABLE_SET_ADDR(nbi),
              table_set ^ NFP_NBI_PC_CHAR_TABLESET_ACTIVE);

    for (i = 0; i < NBIPC_TABLE_SET_POLL_TIMEOUT; ++i) {
        /* Check if the change took effect. */
        temp_table_set = xpb_read(NBIPC_TABLE_SET_ADDR(nbi)) &
                         (NFP_NBI_PC_CHAR_TABLESET_CHINUSE(table_set) |
                          NFP_NBI_PC_CHAR_TABLESET_PEINUSE(table_set));

        if (!temp_table_set)
            break;

        sleep(NBIPC_XPB_SLEEP);
    }

    if (pri_addr != sec_addr) {
        /* Write to the other memory, even if there be a timeout. */
        if (table_set)
            __nbi_cpp_lmem2nbi_copy128(nbi, sec_addr, addr, size, sig);
        else
            __nbi_cpp_lmem2nbi_copy128(nbi, pri_addr, addr, size, sig);
    }
}


/**
 * Write to NBI Preclassifier memory from a memory location, using the
 * table-set mechanism.
 */
__intrinsic static void
__nbipc_mem_table_set_copy_from_mem(unsigned int nbi, uint32_t pri_addr,
                                    uint32_t sec_addr, __mem void *addr,
                                    size_t size, SIGNAL *sig)
{
    unsigned int i;
    __gpr uint32_t table_set;
    __gpr uint32_t temp_table_set;

    try_ctassert(__is_aligned(pri_addr, NBIPC_MEM_ENTRY_SIZE));
    try_ctassert(__is_aligned(sec_addr, NBIPC_MEM_ENTRY_SIZE));
    try_ctassert(__is_aligned(size, NBIPC_MEM_ENTRY_SIZE));

    /* Check which memory table is the active copy. */
    table_set = xpb_read(NBIPC_TABLE_SET_ADDR(nbi)) &
                NFP_NBI_PC_CHAR_TABLESET_ACTIVE;

    /* Write to the shadow memory first. */
    if (table_set)
        __nbi_cpp_mem2nbi_copy128(nbi, pri_addr, addr, size, sig);
    else
        __nbi_cpp_mem2nbi_copy128(nbi, sec_addr, addr, size, sig);

    /* Switch to the updated memory table. */
    xpb_write(NBIPC_TABLE_SET_ADDR(nbi),
              table_set ^ NFP_NBI_PC_CHAR_TABLESET_ACTIVE);

    for (i = 0; i < NBIPC_TABLE_SET_POLL_TIMEOUT; ++i) {
        /* Check if the change took effect. */
        temp_table_set = xpb_read(NBIPC_TABLE_SET_ADDR(nbi)) &
                         (NFP_NBI_PC_CHAR_TABLESET_CHINUSE(table_set) |
                          NFP_NBI_PC_CHAR_TABLESET_PEINUSE(table_set));

        if (!temp_table_set)
            break;

        sleep(NBIPC_XPB_SLEEP);
    }

    if (pri_addr != sec_addr) {
        /* Write to the other memory, even if there be a timeout. */
        if (table_set)
            __nbi_cpp_mem2nbi_copy128(nbi, sec_addr, addr, size, sig);
        else
            __nbi_cpp_mem2nbi_copy128(nbi, pri_addr, addr, size, sig);
    }
}


__intrinsic void
__nbipc_lmem2pelm_copy(unsigned int nbi, uint32_t lmem_pri_addr,
                       uint32_t lmem_sec_addr, __lmem void *addr, size_t size,
                       SIGNAL *sig)
{
    uint32_t pri_addr = NBIPC_ALL_LMEM_BASE + lmem_pri_addr;
    uint32_t sec_addr = NBIPC_ALL_LMEM_BASE + lmem_sec_addr;

    try_ctassert(lmem_pri_addr < NBIPC_LMEM_SIZE);
    try_ctassert(lmem_sec_addr < NBIPC_LMEM_SIZE);

    /* Write to both the active and shadow copies of the table. */
    __nbipc_mem_table_copy_from_lmem(nbi, pri_addr, sec_addr, addr, size, sig);
}


__intrinsic void
nbipc_lmem2pelm_copy(unsigned int nbi, uint32_t lmem_pri_addr,
                     uint32_t lmem_sec_addr, __lmem void *addr, size_t size)
{
    SIGNAL sig;

    __nbipc_lmem2pelm_copy(nbi, lmem_pri_addr, lmem_sec_addr, addr, size,
                           &sig);
}


__intrinsic void
__nbipc_lmem2pesm_copy(unsigned int nbi, uint32_t smem_pri_addr,
                       uint32_t smem_sec_addr, __lmem void *addr, size_t size,
                       SIGNAL *sig)
{
    uint32_t pri_addr = NBIPC_ALL_SMEM_BASE + smem_pri_addr;
    uint32_t sec_addr = NBIPC_ALL_SMEM_BASE + smem_sec_addr;

    try_ctassert(smem_pri_addr < NBIPC_SMEM_SIZE);
    try_ctassert(smem_sec_addr < NBIPC_SMEM_SIZE);

    /* Write to both the active and shadow copies of the table. */
    __nbipc_mem_table_copy_from_lmem(nbi, pri_addr, sec_addr, addr, size, sig);
}


__intrinsic void
nbipc_lmem2pesm_copy(unsigned int nbi, uint32_t smem_pri_addr,
                     uint32_t smem_sec_addr, __lmem void *addr, size_t size)
{
    SIGNAL sig;

    __nbipc_lmem2pesm_copy(nbi, smem_pri_addr, smem_sec_addr, addr, size,
                           &sig);
}


__intrinsic void
__nbipc_mem2pelm_copy(unsigned int nbi, uint32_t lmem_pri_addr,
                      uint32_t lmem_sec_addr, __mem void *addr, size_t size,
                      SIGNAL *sig)
{
    uint32_t pri_addr = NBIPC_ALL_LMEM_BASE + lmem_pri_addr;
    uint32_t sec_addr = NBIPC_ALL_LMEM_BASE + lmem_sec_addr;

    try_ctassert(lmem_pri_addr < NBIPC_LMEM_SIZE);
    try_ctassert(lmem_sec_addr < NBIPC_LMEM_SIZE);

    /* Write to both the active and shadow copies of the table. */
    __nbipc_mem_table_set_copy_from_mem(nbi, pri_addr, sec_addr, addr, size,
                                        sig);
}


__intrinsic void
nbipc_mem2pelm_copy(unsigned int nbi, uint32_t lmem_pri_addr,
                    uint32_t lmem_sec_addr, __mem void *addr, size_t size)
{
    SIGNAL sig;

    __nbipc_mem2pelm_copy(nbi, lmem_pri_addr, lmem_sec_addr, addr, size, &sig);
}


__intrinsic void
__nbipc_mem2pesm_copy(unsigned int nbi, uint32_t smem_pri_addr,
                      uint32_t smem_sec_addr, __mem void *addr, size_t size,
                      SIGNAL *sig)
{
    uint32_t pri_addr = NBIPC_ALL_SMEM_BASE + smem_pri_addr;
    uint32_t sec_addr = NBIPC_ALL_SMEM_BASE + smem_sec_addr;

    try_ctassert(smem_pri_addr < NBIPC_SMEM_SIZE);
    try_ctassert(smem_sec_addr < NBIPC_SMEM_SIZE);

    /* Write to both the active and shadow copies of the table. */
    __nbipc_mem_table_set_copy_from_mem(nbi, pri_addr, sec_addr, addr, size,
                                        sig);
}


__intrinsic void
nbipc_mem2pesm_copy(unsigned int nbi, uint32_t smem_pri_addr,
                    uint32_t smem_sec_addr, __mem void *addr, size_t size)
{
    SIGNAL sig;

    __nbipc_mem2pesm_copy(nbi, smem_pri_addr, smem_sec_addr, addr, size, &sig);
}


__intrinsic void
__nbipc_pelm2lmem_copy(unsigned int nbi, uint32_t lmem_addr, __lmem void *addr,
                       size_t size, SIGNAL *sig)
{
    try_ctassert(lmem_addr < NBIPC_LMEM_SIZE);
    try_ctassert(__is_aligned(lmem_addr, NBIPC_MEM_ENTRY_SIZE));

    __nbi_cpp_nbi2lmem_copy128(nbi, NBIPC_ALL_LMEM_BASE + lmem_addr, addr,
                               size, sig);
}


__intrinsic void
nbipc_pelm2lmem_copy(unsigned int nbi, uint32_t lmem_addr, __lmem void *addr,
                     size_t size)
{
    try_ctassert(lmem_addr < NBIPC_LMEM_SIZE);
    try_ctassert(__is_aligned(lmem_addr, NBIPC_MEM_ENTRY_SIZE));

    nbi_cpp_nbi2lmem_copy128(nbi, NBIPC_ALL_LMEM_BASE + lmem_addr, addr, size);
}


__intrinsic void
__nbipc_pelm2mem_copy(unsigned int nbi, uint32_t lmem_addr, __mem void *addr,
                      size_t size, SIGNAL *sig)
{
    try_ctassert(lmem_addr < NBIPC_LMEM_SIZE);
    try_ctassert(__is_aligned(lmem_addr, NBIPC_MEM_ENTRY_SIZE));

    __nbi_cpp_nbi2mem_copy128(nbi, NBIPC_ALL_LMEM_BASE + lmem_addr, addr, size,
                              sig);
}


__intrinsic void
nbipc_pelm2mem_copy(unsigned int nbi, uint32_t lmem_addr, __mem void *addr,
                    size_t size)
{
    try_ctassert(lmem_addr < NBIPC_LMEM_SIZE);
    try_ctassert(__is_aligned(lmem_addr, NBIPC_MEM_ENTRY_SIZE));

    nbi_cpp_nbi2mem_copy128(nbi, NBIPC_ALL_LMEM_BASE + lmem_addr, addr, size);
}


__intrinsic void
__nbipc_pesm2lmem_copy(unsigned int nbi, uint32_t smem_addr, __lmem void *addr,
                       size_t size, SIGNAL *sig)
{
    try_ctassert(smem_addr < NBIPC_SMEM_SIZE);
    try_ctassert(__is_aligned(smem_addr, NBIPC_MEM_ENTRY_SIZE));

    __nbi_cpp_nbi2lmem_copy128(nbi, NBIPC_ALL_SMEM_BASE + smem_addr, addr,
                               size, sig);
}


__intrinsic void
nbipc_pesm2lmem_copy(unsigned int nbi, uint32_t smem_addr, __lmem void *addr,
                     size_t size)
{
    try_ctassert(smem_addr < NBIPC_SMEM_SIZE);
    try_ctassert(__is_aligned(smem_addr, NBIPC_MEM_ENTRY_SIZE));

    nbi_cpp_nbi2lmem_copy128(nbi, NBIPC_ALL_SMEM_BASE + smem_addr, addr, size);
}


__intrinsic void
__nbipc_pesm2mem_copy(unsigned int nbi, uint32_t smem_addr, __mem void *addr,
                      size_t size, SIGNAL *sig)
{
    try_ctassert(smem_addr < NBIPC_SMEM_SIZE);
    try_ctassert(__is_aligned(smem_addr, NBIPC_MEM_ENTRY_SIZE));

    __nbi_cpp_nbi2mem_copy128(nbi, NBIPC_ALL_SMEM_BASE + smem_addr, addr, size,
                              sig);
}


__intrinsic void
nbipc_pesm2mem_copy(unsigned int nbi, uint32_t smem_addr, __mem void *addr,
                    size_t size)
{
    try_ctassert(smem_addr < NBIPC_SMEM_SIZE);
    try_ctassert(__is_aligned(smem_addr, NBIPC_MEM_ENTRY_SIZE));

    nbi_cpp_nbi2mem_copy128(nbi, NBIPC_ALL_SMEM_BASE + smem_addr, addr, size);
}
