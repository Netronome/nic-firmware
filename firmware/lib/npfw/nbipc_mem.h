/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file   lib/npfw/nbipc_mem.h
 * @brief  NFP NBI Preclassifier memory interface.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#ifndef _NPFW__NBIPC_MEM_H_
#define _NPFW__NBIPC_MEM_H_

#include <nfp.h>
#include <stdint.h>


/* NBI Preclassifier helper macros. */
#define NBIPC_MEM_ENTRY_SIZE 16


/**
 * Copy 16B to the NBI Preclassifier local memory from ME local memory.
 *
 * @param nbi            NBI island to write to (0/1)
 * @param lmem_pri_addr  NBI Preclassifier local memory primary address to
 *                       write to, must be a multiple of 16.
 * @param lmem_sec_addr  NBI Preclassifier local memory secondary address to
 *                       write to, must be a multiple of 16, can be same as
 *                       primary address if no secondary address.
 * @param addr           Pointer to the ME local memory start address
 * @param size           Size of the read, must be a multiple of 16
 * @param sig            Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_lmem2pelm_copy(unsigned int nbi,
                                        uint32_t lmem_pri_addr,
                                        uint32_t lmem_sec_addr,
                                        __lmem void *addr, size_t size,
                                        SIGNAL *sig);

__intrinsic void nbipc_lmem2pelm_copy(unsigned int nbi, uint32_t lmem_pri_addr,
                                      uint32_t lmem_sec_addr,
                                      __lmem void *addr, size_t size);


/**
 * Copy 16B to the NBI Preclassifier shared memory from ME local memory.
 *
 * @param nbi            NBI island to write to (0/1)
 * @param smem_pri_addr  NBI Preclassifier shared memory primary address to
 *                       write to, must be a multiple of 16.
 * @param smem_sec_addr  NBI Preclassifier shared memory secondary address to
 *                       write to, must be a multiple of 16, can be same as
 *                       primary address if no secondary address.
 * @param addr           Pointer to the ME local memory start address
 * @param size           Size of the read, must be a multiple of 16
 * @param sig            Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_lmem2pesm_copy(unsigned int nbi,
                                        uint32_t smem_pri_addr,
                                        uint32_t smem_sec_addr,
                                        __lmem void *addr, size_t size,
                                        SIGNAL *sig);

__intrinsic void nbipc_lmem2pesm_copy(unsigned int nbi, uint32_t smem_pri_addr,
                                      uint32_t smem_sec_addr,
                                      __lmem void *addr, size_t size);


/**
 * Copy 16B to the NBI Preclassifier local memory from a memory location.
 *
 * @param nbi            NBI island to write to (0/1)
 * @param lmem_pri_addr  NBI Preclassifier local memory primary address to
 *                       write to, must be a multiple of 16.
 * @param lmem_sec_addr  NBI Preclassifier local memory secondary address to
 *                       write to, must be a multiple of 16, can be same as
 *                       primary address if no secondary address.
 * @param addr           40-bit pointer to the memory start address
 * @param size           Size of the read, must be a multiple of 16
 * @param sig            Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_mem2pelm_copy(unsigned int nbi,
                                       uint32_t lmem_pri_addr,
                                       uint32_t lmem_sec_addr,
                                       __mem void *addr, size_t size,
                                       SIGNAL *sig);

__intrinsic void nbipc_mem2pelm_copy(unsigned int nbi, uint32_t lmem_pri_addr,
                                     uint32_t lmem_sec_addr, __mem void *addr,
                                     size_t size);


/**
 * Copy 16B to the NBI Preclassifier shared memory from a memory location.
 *
 * @param nbi            NBI island to write to (0/1)
 * @param smem_pri_addr  NBI Preclassifier shared memory primary address to
 *                       write to, must be a multiple of 16.
 * @param smem_sec_addr  NBI Preclassifier shared memory secondary address to
 *                       write to, must be a multiple of 16, can be same as
 *                       primary address if no secondary address.
 * @param addr           40-bit pointer to the memory start address
 * @param size           Size of the read, must be a multiple of 16
 * @param sig            Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_mem2pesm_copy(unsigned int nbi,
                                       uint32_t smem_pri_addr,
                                       uint32_t smem_sec_addr,
                                       __mem void *addr, size_t size,
                                       SIGNAL *sig);

__intrinsic void nbipc_mem2pesm_copy(unsigned int nbi, uint32_t smem_pri_addr,
                                     uint32_t smem_sec_addr, __mem void *addr,
                                     size_t size);


/**
 * Copy 16B from the NBI Preclassifier local memory into ME local memory.
 *
 * @param nbi        NBI island to read from (0/1)
 * @param lmem_addr  NBI Preclassifier local memory address to read from, must
 *                   be a multiple of 16.
 * @param addr       Pointer to the ME local memory start address
 * @param size       Size of the read, must be a multiple of 16
 * @param sig        Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_pelm2lmem_copy(unsigned int nbi, uint32_t lmem_addr,
                                        __lmem void *addr, size_t size,
                                        SIGNAL *sig);

__intrinsic void nbipc_pelm2lmem_copy(unsigned int nbi, uint32_t lmem_addr,
                                      __lmem void *addr, size_t size);


/**
 * Copy 16B from the NBI Preclassifier local memory into a memory location.
 *
 * @param nbi        NBI island to read from (0/1)
 * @param lmem_addr  NBI Preclassifier local memory address to read from, must
 *                   be a multiple of 16.
 * @param addr       40-bit pointer to the memory start address
 * @param size       Size of the read, must be a multiple of 16
 * @param sig        Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_pelm2mem_copy(unsigned int nbi, uint32_t lmem_addr,
                                       __mem void *addr, size_t size,
                                       SIGNAL *sig);

__intrinsic void nbipc_pelm2mem_copy(unsigned int nbi, uint32_t lmem_addr,
                                     __mem void *addr, size_t size);


/**
 * Copy 16B from the NBI Preclassifier shared memory into ME local memory.
 *
 * @param nbi        NBI island to read from (0/1)
 * @param smem_addr  NBI Preclassifier shared memory address to read from, must
 *                   be a multiple of 16.
 * @param addr       Pointer to the ME local memory start address
 * @param size       Size of the read, must be a multiple of 16
 * @param sig        Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_pesm2lmem_copy(unsigned int nbi, uint32_t smem_addr,
                                        __lmem void *addr, size_t size,
                                        SIGNAL *sig);

__intrinsic void nbipc_pesm2lmem_copy(unsigned int nbi, uint32_t smem_addr,
                                      __lmem void *addr, size_t size);


/**
 * Copy 16B from the NBI Preclassifier shared memory into a memory location.
 *
 * @param nbi        NBI island to read from (0/1)
 * @param smem_addr  NBI Preclassifier shared memory address to read from, must
 *                   be a multiple of 16.
 * @param addr       40-bit pointer to the memory start address
 * @param size       Size of the read, must be a multiple of 16
 * @param sig        Signal to use
 *
 * @note One or more ctx_swap's will be invoked with this function
 */
__intrinsic void __nbipc_pesm2mem_copy(unsigned int nbi, uint32_t smem_addr,
                                       __mem void *addr, size_t size,
                                       SIGNAL *sig);

__intrinsic void nbipc_pesm2mem_copy(unsigned int nbi, uint32_t smem_addr,
                                     __mem void *addr, size_t size);


#endif /* !_NPFW__NBIPC_MEM_H_ */
