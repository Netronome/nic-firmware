/*
 * Copyright 2014-2017 Netronome, Inc.
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
 * @file          app_master_main.c
 * @brief         Providing configuration information from PCIe to worker
 *                MEs in a instruction table format.
 *
 * This implementation only handles one PCIe isl.
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
#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>
#include <shared/nfp_net_ctrl.h>
#include <nic_basic/nic_basic.h>

#include "app_config_tables.h"
#include "app_config_instr.h"

/*
 * Global declarations for configuration change management
 */

/* Islands to configure. */

#ifndef APP_WORKER_ISLAND_LIST
    #error "The list of application Island IDs must be defined"
#else
    __shared __lmem uint32_t app_isl_ids[] = {APP_WORKER_ISLAND_LIST};
#endif


#ifndef APP_MES_LIST
    #error "The list of application MEs IDs must be defined"
#else
    __shared __lmem uint32_t cfg_mes_ids[] = {APP_MES_LIST};
#endif

enum {
    INSTR_TX_DROP = 0,
    INSTR_MTU,
    INSTR_MAC,
    INSTR_RSS,
    INSTR_CHECKSUM_COMPLETE,
    INSTR_TX_HOST,
    INSTR_TX_WIRE
};

// #define APP_CONFIG_DEBUG


#define NIC_NBI 0

/* use macros to map input VNIC port to index in NIC_CFG_INSTR_TBL table */
#define NIC_PORT_TO_PCIE_INDEX(pcie, vport, queue) \
        ((pcie << 6) | (NFD_BUILD_QID((vport),(queue))&0x3f))

#define NIC_PORT_TO_NBI_INDEX(nbi, vport) \
        (NIC_NBI_ENTRY_START + ((nbi << 6) | (vport & 0x3f)))


/* Build output port with this macro */
#define BUILD_PORT(_subsys, _queue) \
    (((_subsys) << 10) | (_queue))

#define BUILD_HOST_PORT(_pcie, _vf, _q) \
  BUILD_PORT(_pcie, NFD_BUILD_QID((_vf), (_q)))

#ifdef APP_CONFIG_DEBUG
enum {
    PORT_CFG    = 1,
    PORT_DOWN   = 2,
    MTU         = 3,
    RSS_HI      = 4,
    RSS_LO      = 5
};

union debug_instr_journal {
    struct {
        uint32_t event : 8;
        uint32_t param: 24;
    };
    uint32_t value;
};
MEM_RING_INIT_MU(app_debug_jrn,8192,emem0);

/* RSS table written to NN is also written to emem */
__export __emem __addr40 uint32_t debug_rss_table[100];
#endif


/* RSS table length in words */
#define NFP_NET_CFG_RSS_ITBL_SZ_wrd (NFP_NET_CFG_RSS_ITBL_SZ >> 2)





/* Cluster target NN write defines and structures */
typedef enum CT_ADDR_MODE
{
    CT_ADDR_MODE_INDEX    = 0x00, /* NN reg FIFO mode is used. */
    CT_ADDR_MODE_ABSOLUTE = 0x01  /* Use NN reg num as start (0..127) */
};

typedef union ct_nn_write_format
{
    struct
    {
        unsigned int reserved_3: 2;
        unsigned int remote_isl: 6;     /* Island id of remote master. */
        unsigned int reserved_2: 3;
        unsigned int master: 4;         /* Master within specified island. */
        unsigned int sig_num: 7;        /* If non-zero, sig number to
                                           send to the ME on completion. */
        enum CT_ADDR_MODE addr_mode: 1; /* Address mode:
                                            0 = NN register FIFO mode,
                                            1 = absolute mode.*/
        unsigned int NN_reg_num: 7;     /*NN register number. */
        unsigned int reserved_1: 2;
    };
    unsigned int value;
};

__intrinsic
void ct_nn_write(
    __xwrite void *xfer,
    volatile union ct_nn_write_format *address,
    unsigned int count,
    sync_t sync,
    SIGNAL *sig_ptr
)
{
    __gpr unsigned int address_val =  address->value;
    struct nfp_mecsr_prev_alu ind;

    /* Setup length in PrevAlu for the indirect */
    ind.__raw = 0;
    ind.ov_len = 1;
    ind.length = count - 1;
    if (sync == sig_done) {
        __asm
        {
            alu[--, --, B, ind.__raw]
            ct[ctnn_write, *xfer, address_val, 0, __ct_const_val(count)], \
                sig_done[*sig_ptr], indirect_ref
        }
    } else {
        __asm
        {
            alu[--, --, B, ind.__raw]
            ct[ctnn_write, *xfer, address_val, 0, __ct_const_val(count)], \
                ctx_swap[*sig_ptr], indirect_ref
        }
    }
}

/*
 * Config change management.
 *
 * If port is up, write the instruction list for rx from host datapath and
 * rx from wire datapath. Anything received on the wire port is mapped to
 * the host port, and vice versa.
 * For instance NBI port 0 maps to VNIC port 0 and
 * NBI port 1 maps to VNIC port 1.
 * Each VNIC port has a number of queues (NFD_MAX_PF_QUEUES) which is
 * configured depending on the number of host ports configured.
 *
 * Worker instructions are configured in NIC_CFG_INSTR_TBL table.
 * This table contains both instructions for host rx and wire rx.
 * Host rx instructions are configured from index 0..num PCIE islands *
 * num PCIe queues (NUM_PCIE*NUM_PCIE_Q).
 * Wire rx instructions are configured from index
 * NUM_PCIE*NUM_PCIE_Q .. NUM_PCIE*NUM_PCIE_Q + #NBI*#NBI channels.
 */


/* Write the RSS table to NN registers for all MEs */
__intrinsic void
upd_rss_table_instr(__xwrite uint32_t *xwr_instr, uint32_t start_offset,
                    uint32_t count)
{
    SIGNAL sig1, sig2;
    uint32_t i;
    union ct_nn_write_format command;

    ctassert(count <= 32);

    command.value = 0;
    command.sig_num = 0x0;
    command.addr_mode = CT_ADDR_MODE_ABSOLUTE;
    command.NN_reg_num = start_offset;

    /* ct_nn_write only writes max of 16 words, hence we split it */
    for(i = 0; i < sizeof(cfg_mes_ids)/sizeof(uint32_t); i++) {
        command.remote_isl = cfg_mes_ids[i] >> 4;
        command.master = cfg_mes_ids[i] & 0x0f;
        ct_nn_write(xwr_instr, &command, count/2, sig_done, &sig1);

        command.NN_reg_num = start_offset + count/2;
        ct_nn_write(&xwr_instr[count/2], &command, count/2, sig_done, &sig2);

        wait_for_all(&sig1, &sig2);
    }
}


/* Update RX wire instr -> one table entry per NBI queue/port */
__intrinsic void
upd_rx_wire_instr(__xwrite uint32_t *xwr_instr,
                   uint32_t start_offset, uint32_t count)
{
    __cls __addr32 void *nic_cfg_instr_tbl = (__cls __addr32 void*)
                                        __link_sym("NIC_CFG_INSTR_TBL");
    SIGNAL sig;
    uint32_t addr_hi;
    uint32_t addr_lo;
    uint32_t isl;
    struct nfp_mecsr_prev_alu ind;

    /* write to local CLS table */
    ind.__raw = 0;
    ind.ov_len = 1;
    ind.length = count - 1;
    __asm {
        alu[--, --, B, ind.__raw]
        cls[write, *xwr_instr, nic_cfg_instr_tbl, start_offset, \
                __ct_const_val(count)], ctx_swap[sig], indirect_ref
    }

    /* Propagate to all worker CLS islands */
    for (isl= 0; isl< sizeof(app_isl_ids)/sizeof(uint32_t); isl++) {
        addr_lo = (uint32_t)nic_cfg_instr_tbl + start_offset;
        addr_hi = app_isl_ids[isl] >> 4; /* only use island, mask out ME */
        addr_hi = (addr_hi << (34 - 8)); /* address shifted by 8 in instr */

        ind.__raw = 0;
        ind.ov_len = 1;
        ind.length = count - 1;
        __asm {
            alu[--, --, B, ind.__raw]
            cls[write, *xwr_instr, addr_hi, <<8, addr_lo, \
                    __ct_const_val(count)], ctx_swap[sig], indirect_ref
        }
    }
    return;
}

/* Update RX host instr -> multiple table entries (mult queues) per port */
__intrinsic void
upd_rx_host_instr (__xwrite uint32_t *xwr_instr,
                   uint32_t start_offset, uint32_t count)
{
    __cls __addr32 void *nic_cfg_instr_tbl = (__cls __addr32 void*)
                                        __link_sym("NIC_CFG_INSTR_TBL");
    SIGNAL last_sig;
    uint32_t addr_hi;
    uint32_t addr_lo;
    uint32_t byte_off = start_offset;
    uint32_t isl;
    uint32_t i;

    /* Write multiple entries (one for each host queue) to local CLS.
     * All writes without a signal except last. */
    for (i = 0; i < NUM_PCIE_Q_PER_PORT - 1; i++)
    {
        __asm cls[write, *xwr_instr, nic_cfg_instr_tbl, byte_off, \
                    __ct_const_val(count)]
        byte_off += (NIC_MAX_INSTR<<2);
    }

    /* last write to local CLS */
    __asm cls[write, *xwr_instr, nic_cfg_instr_tbl, byte_off, \
                __ct_const_val(count)], sig_done[last_sig]

    wait_for_all(&last_sig);

    /* Propagate to all worker (remote) CLS islands */
    for (isl= 0; isl< sizeof(app_isl_ids)/sizeof(uint32_t); isl++) {
        addr_lo = (uint32_t)nic_cfg_instr_tbl + start_offset;
        addr_hi = app_isl_ids[isl] >> 4; /* only use island, mask out ME */
        addr_hi = (addr_hi << (34 - 8)); /* address shifted by 8 in instr */

        for (i = 0; i < NUM_PCIE_Q_PER_PORT - 1; i++)
        {
            __asm cls[write, *xwr_instr, addr_hi, <<8, addr_lo, \
                        __ct_const_val(count)]
            addr_lo += (NIC_MAX_INSTR<<2);
        }

        /* last write to remote CLS */
        __asm cls[write, *xwr_instr, addr_hi, <<8, addr_lo, \
                    __ct_const_val(count)], sig_done[last_sig]
        wait_for_all(&last_sig);
    }
    return;
}


__intrinsic void
upd_rss_table(uint32_t start_offset, __emem __addr40 uint8_t *bar_base)
{
    __xread uint32_t xrd_rss_tbl[NFP_NET_CFG_RSS_ITBL_SZ_wrd];
    __xwrite uint32_t xwr_nn_info[NFP_NET_CFG_RSS_ITBL_SZ_wrd];

    /* Read all 32 words of RSS table */
    mem_read32_swap(xrd_rss_tbl,
                    bar_base + NFP_NET_CFG_RSS_ITBL,
                    sizeof(xrd_rss_tbl));

    reg_cp(xwr_nn_info, xrd_rss_tbl, sizeof(xrd_rss_tbl)/2);
    reg_cp((void *)(&xwr_nn_info[16]), (void *)(&xrd_rss_tbl[16]),
           sizeof(xrd_rss_tbl)/2);

    /* Write at NN register start_offset for all worker MEs */
    upd_rss_table_instr(xwr_nn_info,  start_offset,
                        NFP_NET_CFG_RSS_ITBL_SZ_wrd);

#ifdef APP_CONFIG_DEBUG
    mem_write32(xwr_nn_info, debug_rss_table + start_offset,
                sizeof(xwr_nn_info));
#endif

    return;
}

#define ACTION_RSS_L3_BIT 0
#define ACTION_RSS_L4_BIT 1

/* Set RSS flags by matching what is used in the workers */
__intrinsic uint32_t
extract_rss_flags(uint32_t rss_ctrl)
{
    uint32_t rss_flags = 0;

    if ((rss_ctrl & NFP_NET_CFG_RSS_IPV4) | (rss_ctrl & NFP_NET_CFG_RSS_IPV6))
        rss_flags |= (1 << ACTION_RSS_L3_BIT);

    if ((rss_ctrl & NFP_NET_CFG_RSS_IPV4_TCP) | (rss_ctrl & NFP_NET_CFG_RSS_IPV4_UDP) |
        (rss_ctrl & NFP_NET_CFG_RSS_IPV6_TCP) | (rss_ctrl & NFP_NET_CFG_RSS_IPV6_UDP))
        rss_flags |= (1 << ACTION_RSS_L3_BIT) | (1 << ACTION_RSS_L4_BIT);

    return rss_flags;
}


__intrinsic void
app_config_port(uint32_t vnic_port, uint32_t control, uint32_t update)
{
    __emem __addr40 uint8_t *bar_base = NFD_CFG_BAR_ISL(NIC_PCI, vnic_port);
    __xread uint32_t rss_ctrl[2];
    __xread uint32_t mtu;
    __xread uint32_t nic_mac[2];
    __xread uint32_t rss_key[NFP_NET_CFG_RSS_KEY_SZ / sizeof(uint32_t)];
    __xwrite uint32_t xwr_instr[32];
    __gpr uint32_t instr[32];
    SIGNAL sig1, sig2;
    uint32_t rss_flags;
    uint32_t rss_tbl_nnidx;
    uint32_t byte_off;
    uint32_t mask;
    uint32_t count;

#ifdef APP_CONFIG_DEBUG
    {
        union debug_instr_journal data;
        data.value = 0x00;
        data.event = PORT_CFG;
        data.param = vnic_port;
        JDBG(app_debug_jrn, data.value);
    }
#endif

    count = 2;
    /* mtu */
    mem_read32(&mtu, (__mem void*)(bar_base + NFP_NET_CFG_MTU),
                   sizeof(mtu));
    instr[0] = (INSTR_MTU << INSTR_OPCODE_LSB) | (mtu & 0xffff);
    instr[1] = (INSTR_TX_WIRE << INSTR_OPCODE_LSB);
      // | BUILD_PORT(NIC_NBI, NS_PLATFORM_NBI_TM_QID_LO(vnic_port));

    reg_cp(xwr_instr, (void *)instr, count<<2);

    /* write TX instr to local table and to other islands too */
    byte_off = NIC_PORT_TO_PCIE_INDEX(NIC_PCI, vnic_port, 0) * NIC_MAX_INSTR;
    upd_rx_host_instr (xwr_instr, byte_off<<2, count);

#ifdef APP_CONFIG_DEBUG
    {
        union debug_instr_journal data;
        data.value = 0x00;
        data.event = MTU;
        data.param = mtu;
        JDBG(app_debug_jrn, data.value);
    }
#endif

    /* mtu already setup for update rx host */
    count = 1;

    /* MAC address */
    mem_read64(nic_mac, (__mem void*)(bar_base + NFP_NET_CFG_MACADDR),
                sizeof(nic_mac));
    instr[count++] = (INSTR_MAC << INSTR_OPCODE_LSB) | (1 << INSTR_PIPELINE_BIT) | (nic_mac[1] >> 16);
    instr[count++] = (nic_mac[0]);

    if (control & NFP_NET_CFG_CTRL_RSS) {

        /* Udate the RSS NN table but only if RSS has changed
         * If vnic_port x write at x*32 NN register */
        if (update & NFP_NET_CFG_UPDATE_RSS) {
            upd_rss_table(vnic_port*NFP_NET_CFG_RSS_ITBL_SZ_wrd, bar_base);
        }

        /* RSS flags: read rss_ctrl but only first word is used */
        __mem_read64(rss_ctrl, bar_base + NFP_NET_CFG_RSS_CTRL,
                sizeof(rss_ctrl), sizeof(rss_ctrl), sig_done, &sig1);
        __mem_read64(rss_key, bar_base + NFP_NET_CFG_RSS_KEY,
                NFP_NET_CFG_RSS_KEY_SZ, NFP_NET_CFG_RSS_KEY_SZ,
                sig_done, &sig2);
        wait_for_all(&sig1, &sig2);

        rss_flags = extract_rss_flags(rss_ctrl[0]);

        /* RSS remapping table with NN register index as start offset */
        rss_tbl_nnidx = vnic_port*NFP_NET_CFG_RSS_ITBL_SZ_wrd;

        instr[count++] = (INSTR_RSS << INSTR_OPCODE_LSB) | (1 << INSTR_PIPELINE_BIT) | (rss_tbl_nnidx << 8) | (rss_flags);
        mask = rss_ctrl[0];

        /* RSS key: provide rss key with hash. Use only first word */

        instr[count++] = rss_key[0];

        /* mask fits into 16 bits as rss_ctrl is masked with 0x7f) */
        //mask = NFP_NET_CFG_RSS_MASK_of(mask);
        //instr[count++] = (INSTR_SEL_RSS_QID_WITH_MASK << 16) | (mask & 0xffff);

        /* calculate checksum and drop if mismatch (drop port is included) */
        instr[count++] = (INSTR_CHECKSUM_COMPLETE << INSTR_OPCODE_LSB) | (1 << INSTR_PIPELINE_BIT);
        instr[count++] = (INSTR_TX_HOST << INSTR_OPCODE_LSB) | (1 << INSTR_PIPELINE_BIT);
        reg_cp(xwr_instr, instr, count << 2);

#ifdef APP_CONFIG_DEBUG
        {
            union debug_instr_journal data;
            data.value = 0x00;
            data.event = RSS_HI;
            data.param = rss_ctrl[0] >> 16;
            JDBG(app_debug_jrn, data.value);

            data.event = RSS_LO;
            data.param = rss_ctrl[0];
            JDBG(app_debug_jrn, data.value);
        }
#endif

    } else {
        instr[count++] = (INSTR_TX_HOST << INSTR_OPCODE_LSB);
        reg_cp(xwr_instr, (void *)instr, count<<2);
    }

    /* map vnic_port to NBI index in the instruction table */
    byte_off = NIC_PORT_TO_NBI_INDEX(NIC_NBI, vnic_port) * NIC_MAX_INSTR;

    /* write TX instr to local table and to other islands too */
    upd_rx_wire_instr(xwr_instr, byte_off<<2, count);

    return;
}


__intrinsic void
app_config_port_down(uint32_t vnic_port)
{

    __xwrite uint32_t xwr_instr;
    __gpr uint32_t instr[2];
    uint32_t i;
    uint32_t byte_off;

    /* TX drop instr for host port lookup */
    xwr_instr = (INSTR_TX_DROP << INSTR_OPCODE_LSB);

    /* write drop instr to local host table */
    byte_off = NIC_PORT_TO_PCIE_INDEX(NIC_PCI, vnic_port, 0) * NIC_MAX_INSTR;
    upd_rx_host_instr (&xwr_instr, byte_off << 2, 1);

    /* write drop instr to local wire table */
    byte_off = NIC_PORT_TO_NBI_INDEX(NIC_NBI, vnic_port) * NIC_MAX_INSTR;
    upd_rx_wire_instr(&xwr_instr, byte_off << 2, 1);

#ifdef APP_CONFIG_DEBUG
    {
        union debug_instr_journal data;
        data.value = 0x00;
        data.event = PORT_DOWN;
        data.param = vnic_port;
        JDBG(app_debug_jrn, data.value);
    }
#endif

    return;
}


