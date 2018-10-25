/*
 * Copyright 2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file  map_cmsg_rx.c
 * @brief This file receives MAP cmsgs and free's the buffers 
 *
 */

#include <assert.h>
#include <nfp.h>
#include <nfp_chipres.h>

#include <stdint.h>

#include <platform.h>
#include <nfp/me.h>
#include <nfp/mem_bulk.h>
#include <nfp/cls.h>
#include <nfp6000/nfp_me.h>

#include <std/reg_utils.h>
#include "app_mac_vlan_config_cmsg.c"

__asm .init _pkt_buf_ctm_credits 48 32

void map_cmsg_rx(void)
{
    uint32_t q_idx;
    uint32_t isl, pnum;
    uint32_t bls;
    blm_buf_handle_t buf;
    mem_ring_addr_t q_base;
    __xread uint32_t workq_data[CMSG_DESC_LW];

    q_idx = _link_sym(MAP_CMSG_Q_IDX);
    q_base = (_link_sym(MAP_CMSG_Q_BASE) >> 8) & 0xff000000;

    for (;;) {
        mem_workq_add_thread(q_idx, q_base, &workq_data, sizeof(workq_data));

        isl = workq_data[0] >> 26 & 0x3f;
        pnum = workq_data[0] >> 16 & 0x1ff;
        pkt_ctm_free(isl, pnum);

        bls = workq_data[1] >> 29 & 3;
        buf = workq_data[1] & 0x1fffffff;
        blm_buf_free(buf, bls);

        __asm ctx_arb[voluntary]
        pkt_ctm_poll_pe_credit(PKT_BUF_CTM_CREDITS_LINK);
    }
}
