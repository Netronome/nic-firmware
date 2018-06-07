/*
 * Copyright 2016-2017 Netronome, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * @file          apps/nic/app_mac_vlan_config_cmsg.c
 * @brief         NIC application MAC+VLAN lookup table config request
 *                via cmsg_map ME
 */


#include <assert.h>
#include <nfp.h>
#include <nfp_chipres.h>

#include <stdint.h>

#include <platform.h>

#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp/mem_ring.h>
#include <nfp/mem_atomic.h>
#include <nfp/cls.h>

#include <nfp6000/nfp_me.h>

#include <std/reg_utils.h>

#include <pkt/pkt.h>
#include <blm/blm.h>

#include "app_mac_vlan_config_cmsg.h"
#include "maps/cmsg_map_types.h"

#include <vnic/pci_in.h>
#include <vnic/pci_out.h>

//#include <infra_basic/infra_basic.h>
#include <shared/nfd_common.h>

#ifndef _link_sym
#define _link_sym(x) __link_sym(#x)
#endif

#define CMSG_MAP_VERSION    1
#define CMSG_DESC_LW    3

/* CTM allocation credits */
__import __shared __cls struct ctm_pkt_credits pkt_buf_ctm_credits;

#ifndef CTM_ALLOC_ERR
#define CTM_ALLOC_ERR   0xffffffff
#endif

/* The smallest CTM buffer size that can be allocated is 256B */
#define MIN_CTM_TYPE        PKT_CTM_SIZE_256
#define MIN_CTM_SIZE        (256 << MIN_CTM_TYPE)

EMEM0_QUEUE_ALLOC(MAP_CMSG_Q_IDX, global);
__asm .alloc_mem MAP_CMSG_Q_BASE emem0 global MAP_CMSG_IN_WQ_SZ MAP_CMSG_IN_WQ_SZ;
__asm .init_mu_ring MAP_CMSG_Q_IDX MAP_CMSG_Q_BASE;

DBG_JOURNAL_DECLARE(sriov_journal_cmsg);
#define SRIOV_CMSG_IDBG(_x) JDBG(sriov_journal_cmsg, _x)
#define SRIOV_CMSG_IDBG_TYPE(_type, _x) JDBG_TYPE(sriov_journal_cmsg, _type, _x)

int32_t
nic_mac_vlan_entry_op_cmsg(__lmem struct nic_mac_vlan_key *key,
                            __lmem uint32_t *action_list, const int operation)
{
    __gpr uint32_t proc_res;
    uint32_t ctm_pnum;
    __xread blm_buf_handle_t emem_buf_h;
    __addr40 uint8_t *emem_dst;
    __xwrite struct nic_mac_vlan_cmsg cmsg_data;
    __xwrite uint32_t action_data[(NIC_MAC_VLAN_RESULT_SIZE_LW)];
    __xwrite uint32_t workq_data[CMSG_DESC_LW];

    unsigned int q_idx;
    mem_ring_addr_t q_base;

    q_idx = _link_sym(MAP_CMSG_Q_IDX);
    q_base = (_link_sym(MAP_CMSG_Q_BASE) >> 8) & 0xff000000;

    /* Allocate CTM buffer */
    /* Buffer not used but will be freed by cmsgmap ME */
    pkt_ctm_get_credits(&pkt_buf_ctm_credits, 1, 1, 1);
    ctm_pnum = pkt_ctm_alloc(&pkt_buf_ctm_credits, __ISLAND, MIN_CTM_TYPE, 0, 0);
    if (ctm_pnum == CTM_ALLOC_ERR) {
        proc_res = CMESG_DISPATCH_FAIL;
	goto skip;
    }

   /* Allocate emem buffer */
retry:;
    if (blm_buf_alloc(&emem_buf_h, NFD_IN_BLM_REG_BLS) == -1) {
       sleep(100);
       goto retry;
    }

    emem_dst = ((__mem uint8_t *)blm_buf_handle2ptr(emem_buf_h) + NFD_IN_DATA_OFFSET);

    /* write cmsg data to buffer */
    cmsg_data.word0=((operation)|(CMSG_MAP_VERSION<<8));
    cmsg_data.tid=((SRIOV_TID<<24));
    cmsg_data.count=0;
    cmsg_data.flags=0; /* 0 if any (add if not existed), 1 is update only */
    reg_cp(cmsg_data.key.__raw, key->__raw, sizeof(cmsg_data.key));
    mem_write32_swap(&cmsg_data, emem_dst, ((NIC_MAC_VLAN_CMSG_SIZE_LW)*4));

    reg_cp(action_data, action_list, (NIC_MAC_VLAN_RESULT_SIZE_LW*4));
    emem_dst = (emem_dst + 80);
    mem_write32(&action_data, emem_dst, ((NIC_MAC_VLAN_RESULT_SIZE_LW)*4));
    emem_dst = (emem_dst - (NFD_IN_DATA_OFFSET+80));
    /* build queue descriptor */
    reg_zero(&workq_data, sizeof(workq_data));

    workq_data[0] =((__ISLAND<<26) | (ctm_pnum<<16));
    workq_data[1] = (uint32_t)(((uint64_t) emem_dst)>>11);
    workq_data[2] = (SRIOV_QUEUE<<16);
    /* place message on nfd work queue. */
    mem_workq_add_work(q_idx, q_base,
                 workq_data, sizeof(workq_data));

    proc_res = CMESG_DISPATCH_OK;

skip:;
    return proc_res;
}
