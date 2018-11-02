/*
 * Copyright 2014-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file          app_private.c
 * @brief         Declarations of private app master primitives and
 *                interfaces to said primitives
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef APP_PRIVATE_C
#define APP_PRIVATE_C

/* Mutex for accessing MAC registers. */
__shared __gpr volatile int mac_reg_lock = 0;

/* Macros for local mutexes. */
#define LOCAL_MUTEX_LOCK(_mutex) \
    do {                         \
        while (_mutex)           \
            ctx_swap();          \
        _mutex = 1;              \
    } while (0)
#define LOCAL_MUTEX_UNLOCK(_mutex) \
    do {                           \
        _mutex = 0;                \
    } while (0)

/* Current value of NFP_NET_CFG_CTRL (shared between all contexts) */
__shared __lmem volatile uint32_t nic_control_word[NFD_MAX_ISL][NVNICS];

/* Current state of the link state and the pending interrupts. */
#define LS_ARRAY_LEN           ((NVNICS + 31) >> 5)
#define LS_IDX(_vnic)          ((_vnic) >> 5)
#define LS_SHF(_vnic)          ((_vnic) & 0x1f)
#define LS_MASK(_vnic)         (0x1 << LS_SHF(_vnic))
#define LS_READ(_state, _vnic) ((_state[LS_IDX(_vnic)] >> LS_SHF(_vnic)) & 0x1)

#define LS_CLEAR(_state, _vnic)                   \
    do {                                          \
        _state[LS_IDX(_vnic)] &= ~LS_MASK(_vnic); \
    } while (0)
#define LS_SET(_state, _vnic)                    \
    do {                                         \
        _state[LS_IDX(_vnic)] |= LS_MASK(_vnic); \
    } while (0)

__shared __lmem uint32_t vs_current[NFD_MAX_ISL][LS_ARRAY_LEN];
__shared __lmem uint32_t ls_current[NFD_MAX_ISL][LS_ARRAY_LEN];
__shared __lmem uint32_t pending[NFD_MAX_ISL][LS_ARRAY_LEN];
__shared __lmem uint32_t vf_lsc_list[NS_PLATFORM_NUM_PORTS][NFD_MAX_ISL][LS_ARRAY_LEN];

/*Interface to nic_control_word*/
uint32_t
get_nic_control_word(const int pcie, uint32_t vid)
{
    return nic_control_word[pcie][vid];
}

void
set_nic_control_word(const int pcie, uint32_t vid, uint32_t control)
{
    nic_control_word[pcie][vid] = control;
}

/*Interface to vs_current*/
uint32_t
get_vs_current(const int pcie, uint32_t vid)
{
    return LS_READ(vs_current[pcie], vid);
}

void
set_vs_current(const int pcie, uint32_t vid, uint32_t ls)
{
    LS_CLEAR(vs_current[pcie], vid);
    vs_current[pcie][LS_IDX(vid)] |= (ls << LS_SHF(vid));
}

/*Interface to ls_current*/
uint32_t
get_ls_current(const int pcie, uint32_t vid)
{
    return LS_READ(ls_current[pcie], vid);
}

void
set_ls_current(const int pcie, uint32_t vid, uint32_t ls)
{
    LS_CLEAR(ls_current[pcie], vid);
    ls_current[pcie][LS_IDX(vid)] |= (ls << LS_SHF(vid));
}

/*Interface to vf_lsc_list*/
uint32_t
get_vf_lsc(uint32_t port, const int pcie,  uint32_t vid)
{
    return LS_READ(vf_lsc_list[port][pcie], vid);
}

void
set_vf_lsc(uint32_t port, const int pcie, uint32_t vid, uint32_t ls)
{
    LS_CLEAR(vf_lsc_list[port][pcie], vid);
    vf_lsc_list[port][pcie][LS_IDX(vid)] |= (ls << LS_SHF(vid));
}

#endif

