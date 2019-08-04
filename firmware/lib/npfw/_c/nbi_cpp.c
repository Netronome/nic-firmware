/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file  lib/npfw/_c/nbi_cpp.c
 * @brief Read and write NBI Preclassifier memories.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include <assert.h>
#include <nfp.h>

#include <npfw/nbi_cpp.h>


__intrinsic void
__nbi_cpp_lmem2nbi_copy128(unsigned int nbi, uint32_t nbi_addr,
                           __lmem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xwrite uint32_t data[4];
    uint32_t end_addr     = nbi_addr + size;
    unsigned int lmem_idx = 0;
    __gpr uint32_t nbi_hi = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 16));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        data[1] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[0] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[3] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[2] = ((__lmem uint32_t *)addr)[lmem_idx++];
        __asm {
            nbi[write, data[0], nbi_hi, <<8, nbi_ptr, 2], ctx_swap[*sig];
        }
    }
}


__intrinsic void
__nbi_cpp_lmem2nbi_copy256(unsigned int nbi, uint32_t nbi_addr,
                           __lmem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xwrite uint32_t data[8];
    uint32_t end_addr     = nbi_addr + size;
    unsigned int lmem_idx = 0;
    __gpr uint32_t nbi_hi = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 32));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        data[1] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[0] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[3] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[2] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[5] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[4] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[7] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[6] = ((__lmem uint32_t *)addr)[lmem_idx++];
        __asm {
            nbi[write, data[0], nbi_hi, <<8, nbi_ptr, 4], ctx_swap[*sig];
        }
    }
}


__intrinsic void
nbi_cpp_lmem2nbi_copy64(unsigned int nbi, uint32_t nbi_addr, __lmem void *addr,
                        size_t size)
{
    SIGNAL sig;

    __nbi_cpp_lmem2nbi_copy64(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
nbi_cpp_lmem2nbi_copy128(unsigned int nbi, uint32_t nbi_addr,
                         __lmem void *addr, size_t size)
{
    SIGNAL sig;

    __nbi_cpp_lmem2nbi_copy128(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
nbi_cpp_lmem2nbi_copy256(unsigned int nbi, uint32_t nbi_addr,
                         __lmem void *addr, size_t size)
{
    SIGNAL sig;

    __nbi_cpp_lmem2nbi_copy256(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
__nbi_cpp_mem2nbi_copy64(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                         size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xrw uint32_t data[2];
    uint32_t end_addr      = nbi_addr + size;
    __gpr uint32_t mem_hi  = ((uint64_t)addr >> 8) & 0xFF000000;
    __gpr uint32_t mem_ptr = (uint64_t)addr & 0xFFFFFFFF;
    __gpr uint32_t nbi_hi  = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 8));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            mem[read, data[0], mem_hi, <<8, mem_ptr, 1], ctx_swap[*sig];
            alu[data[0], --, B, data[1]];
            alu[data[1], --, B, data[0]];
            nbi[write, data[0], nbi_hi, <<8, nbi_ptr, 1], ctx_swap[*sig];
        }

        mem_ptr += sizeof(data);
    }
}


__intrinsic void
__nbi_cpp_mem2nbi_copy128(unsigned int nbi, uint32_t nbi_addr,
                          __mem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xrw uint32_t data[4];
    uint32_t end_addr      = nbi_addr + size;
    __gpr uint32_t mem_hi  = ((uint64_t)addr >> 8) & 0xFF000000;
    __gpr uint32_t mem_ptr = (uint64_t)addr & 0xFFFFFFFF;
    __gpr uint32_t nbi_hi  = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 16));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            mem[read, data[0], mem_hi, <<8, mem_ptr, 2], ctx_swap[*sig];
            alu[data[0], --, B, data[1]];
            alu[data[1], --, B, data[0]];
            alu[data[2], --, B, data[3]];
            alu[data[3], --, B, data[2]];
            nbi[write, data[0], nbi_hi, <<8, nbi_ptr, 2], ctx_swap[*sig];
        }

        mem_ptr += sizeof(data);
    }
}


__intrinsic void
__nbi_cpp_mem2nbi_copy256(unsigned int nbi, uint32_t nbi_addr,
                          __mem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xrw uint32_t data[8];
    uint32_t end_addr      = nbi_addr + size;
    __gpr uint32_t mem_hi  = ((uint64_t)addr >> 8) & 0xFF000000;
    __gpr uint32_t mem_ptr = (uint64_t)addr & 0xFFFFFFFF;
    __gpr uint32_t nbi_hi  = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 32));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            mem[read, data[0], mem_hi, <<8, mem_ptr, 4], ctx_swap[*sig];
            alu[data[0], --, B, data[1]];
            alu[data[1], --, B, data[0]];
            alu[data[2], --, B, data[3]];
            alu[data[3], --, B, data[2]];
            alu[data[4], --, B, data[5]];
            alu[data[5], --, B, data[4]];
            alu[data[6], --, B, data[7]];
            alu[data[7], --, B, data[6]];
            nbi[write, data[0], nbi_hi, <<8, nbi_ptr, 4], ctx_swap[*sig];
        }

        mem_ptr += sizeof(data);
    }
}


__intrinsic void
nbi_cpp_mem2nbi_copy64(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                       size_t size)
{
    SIGNAL sig;

    __nbi_cpp_mem2nbi_copy64(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
nbi_cpp_mem2nbi_copy128(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                        size_t size)
{
    SIGNAL sig;

    __nbi_cpp_mem2nbi_copy128(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
nbi_cpp_mem2nbi_copy256(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                        size_t size)
{
    SIGNAL sig;

    __nbi_cpp_mem2nbi_copy256(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
__nbi_cpp_lmem2nbi_copy64(unsigned int nbi, uint32_t nbi_addr,
                          __lmem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xwrite uint32_t data[2];
    uint32_t end_addr     = nbi_addr + size;
    unsigned int lmem_idx = 0;
    __gpr uint32_t nbi_hi = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 8));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        data[1] = ((__lmem uint32_t *)addr)[lmem_idx++];
        data[0] = ((__lmem uint32_t *)addr)[lmem_idx++];
        __asm {
            nbi[write, data[0], nbi_hi, <<8, nbi_ptr, 1], ctx_swap[*sig];
        }
    }
}


__intrinsic void
nbi_cpp_nbi2mem_copy256(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                        size_t size)
{
    SIGNAL sig;

    __nbi_cpp_nbi2mem_copy256(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
__nbi_cpp_nbi2lmem_copy64(unsigned int nbi, uint32_t nbi_addr,
                          __lmem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xread uint32_t data[2];
    uint32_t end_addr     = nbi_addr + size;
    unsigned int lmem_idx = 0;
    __gpr uint32_t nbi_hi = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 8));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            nbi[read, data[0], nbi_hi, <<8, nbi_ptr, 1], ctx_swap[*sig];
        }
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[1];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[0];
    }
}


__intrinsic void
__nbi_cpp_nbi2lmem_copy128(unsigned int nbi, uint32_t nbi_addr,
                           __lmem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xread uint32_t data[4];
    uint32_t end_addr     = nbi_addr + size;
    unsigned int lmem_idx = 0;
    __gpr uint32_t nbi_hi = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 16));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            nbi[read, data[0], nbi_hi, <<8, nbi_ptr, 2], ctx_swap[*sig];
        }
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[1];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[0];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[3];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[2];
    }
}


__intrinsic void
__nbi_cpp_nbi2lmem_copy256(unsigned int nbi, uint32_t nbi_addr,
                           __lmem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xread uint32_t data[8];
    uint32_t end_addr     = nbi_addr + size;
    unsigned int lmem_idx = 0;
    __gpr uint32_t nbi_hi = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 32));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
          nbi[read, data[0], nbi_hi, <<8, nbi_ptr, 4], ctx_swap[*sig];
        }
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[1];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[0];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[3];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[2];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[5];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[4];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[7];
        ((__lmem uint32_t *)addr)[lmem_idx++] = data[6];
    }
}


__intrinsic void
nbi_cpp_nbi2lmem_copy64(unsigned int nbi, uint32_t nbi_addr, __lmem void *addr,
                        size_t size)
{
    SIGNAL sig;

    __nbi_cpp_nbi2lmem_copy64(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
nbi_cpp_nbi2lmem_copy128(unsigned int nbi, uint32_t nbi_addr,
                         __lmem void *addr, size_t size)
{
    SIGNAL sig;

    __nbi_cpp_nbi2lmem_copy128(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
nbi_cpp_nbi2lmem_copy256(unsigned int nbi, uint32_t nbi_addr,
                         __lmem void *addr, size_t size)
{
    SIGNAL sig;

    __nbi_cpp_nbi2lmem_copy256(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
__nbi_cpp_nbi2mem_copy64(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                         size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xrw uint32_t data[2];
    uint32_t end_addr      = nbi_addr + size;
    __gpr uint32_t mem_hi  = ((uint64_t)addr >> 8) & 0xFF000000;
    __gpr uint32_t mem_ptr = (uint64_t)addr & 0xFFFFFFFF;
    __gpr uint32_t nbi_hi  = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 8));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            nbi[read, data[0], nbi_hi, <<8, nbi_ptr, 1], ctx_swap[*sig];
            alu[data[0], --, B, data[1]];
            alu[data[1], --, B, data[0]];
            mem[write, data[0], mem_hi, <<8, mem_ptr, 1], ctx_swap[*sig];
        }

        mem_ptr += sizeof(data);
    }
}


__intrinsic void
__nbi_cpp_nbi2mem_copy128(unsigned int nbi, uint32_t nbi_addr,
                          __mem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xrw uint32_t data[4];
    uint32_t end_addr      = nbi_addr + size;
    __gpr uint32_t mem_hi  = ((uint64_t)addr >> 8) & 0xFF000000;
    __gpr uint32_t mem_ptr = (uint64_t)addr & 0xFFFFFFFF;
    __gpr uint32_t nbi_hi  = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 16));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            nbi[read, data[0], nbi_hi, <<8, nbi_ptr, 2], ctx_swap[*sig];
            alu[data[0], --, B, data[1]];
            alu[data[1], --, B, data[0]];
            alu[data[2], --, B, data[3]];
            alu[data[3], --, B, data[2]];
            mem[write, data[0], mem_hi, <<8, mem_ptr, 2], ctx_swap[*sig];
        }

        mem_ptr += sizeof(data);
    }
}


__intrinsic void
__nbi_cpp_nbi2mem_copy256(unsigned int nbi, uint32_t nbi_addr,
                          __mem void *addr, size_t size, SIGNAL *sig)
{
    __gpr uint32_t nbi_ptr;
    __xrw uint32_t data[8];
    uint32_t end_addr      = nbi_addr + size;
    __gpr uint32_t mem_hi  = ((uint64_t)addr >> 8) & 0xFF000000;
    __gpr uint32_t mem_ptr = (uint64_t)addr & 0xFFFFFFFF;
    __gpr uint32_t nbi_hi  = nbi << 30;

    try_ctassert(nbi < 2);
    try_ctassert(__is_aligned(nbi_addr, 8));
    try_ctassert(__is_aligned(size, 32));

    for (nbi_ptr = nbi_addr; nbi_ptr < end_addr; nbi_ptr += sizeof(data)) {
        __asm {
            nbi[read, data[0], nbi_hi, <<8, nbi_ptr, 4], ctx_swap[*sig];
            alu[data[0], --, B, data[1]];
            alu[data[1], --, B, data[0]];
            alu[data[2], --, B, data[3]];
            alu[data[3], --, B, data[2]];
            alu[data[4], --, B, data[5]];
            alu[data[5], --, B, data[4]];
            alu[data[6], --, B, data[7]];
            alu[data[7], --, B, data[6]];
            mem[write, data[0], mem_hi, <<8, mem_ptr, 4], ctx_swap[*sig];
        }

        mem_ptr += sizeof(data);
    }
}


__intrinsic void
nbi_cpp_nbi2mem_copy64(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                       size_t size)
{
    SIGNAL sig;

    __nbi_cpp_nbi2mem_copy64(nbi, nbi_addr, addr, size, &sig);
}


__intrinsic void
nbi_cpp_nbi2mem_copy128(unsigned int nbi, uint32_t nbi_addr, __mem void *addr,
                        size_t size)
{
    SIGNAL sig;

    __nbi_cpp_nbi2mem_copy128(nbi, nbi_addr, addr, size, &sig);
}
