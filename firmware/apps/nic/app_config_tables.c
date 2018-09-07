/*
 * Copyright 2017 Netronome Systems, Inc. All rights reserved.
 *
 * @file  app_config_tables.c
 * @brief Control plane management component for datapath action interpreter.
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
#include <vnic/nfd_common.h>
#include <vnic/shared/nfd_vf_cfg_iface.h>
#include <shared/nfp_net_ctrl.h>
#include <nic_basic/nic_basic.h>
#include <nic_basic/nic_stats.h>
#include "app_mac_vlan_config_cmsg.h"
#include "maps/cmsg_map_types.h"
#include "app_config_tables.h"
#include "app_config_instr.h"
#include "ebpf.h"
#include "nic_tables.h"
#include "app_mac_vlan_config_cmsg.h"

/*
    RXB tables (in CTM)

    Per host queue, FL_BUF_SZ from config BAR

    VLAN Member Tables (in CTM)

    58 bit bitmask of (up/enabled) host queue members per VLAN + 6 bit MIN RXB over members
    TX_VLAN strips VLAN


    ** ACTION LISTS **
    No VFs

    Wire -> PF
    RX_WIRE -> MAC_MATCH -> CHECKSUM(C) -> BPF -> RSS -> TX_HOST(PF)

    Wire -> PF (promisc)
    RX_WIRE -> CHECKSUM(C) -> BPF -> RSS -> TX_HOST(PF)

    Host -> Wire
    RX_HOST -> CHECKSUM(I) -> TX_WIRE

    Wire -> Host (SR-IOV)

    Wire->PF
    RX_WIRE -> VEB_LOOKUP -miss-> CHECKSUM(O,I,C) -> BPF -> RSS -> TX_HOST(PF,M=1) -multicast-> PUSH_PKT -> TX_VLAN

    Wire->VF (VLAN=0xfff)
    RX_WIRE -> VEB_LOOKUP -hit-> [CHECKSUM(O,I,C) -> TX_HOST(VF)]

    Wire->VF (VLAN=0x5)
    RX_WIRE -> VEB_LOOKUP -hit-> [CHECKSUM(O,I,C) -> DELETE(12,4) -> TX_HOST(VF)]

    Wire->VF (Promisc/VLAN=0xfff)
    RX_WIRE -> VEB_LOOKUP -hit-> [CHECKSUM(O,I,C) -> TX_HOST(VF,C=1) -> BPF -> RSS -> TX_HOST(PF)]

    Wire->VF (Promisc/VLAN=0x5)
    RX_WIRE -> VEB_LOOKUP -hit-> [CHECKSUM(O,I,C) -> PUSH_PKT -> DELETE(12,4) -> TX_HOST(VF,C=1) -> POP_PKT -> BPF -> RSS -> TX_HOST(PF)]


    Host -> Wire/Host (SR-IOV)

    VF->Wire (VLAN=0xfff)
    RX_HOST -> VEB_LOOKUP -miss-> CHECKSUM(I) -> TX_WIRE(M=1) -multicast-> CHECKSUM(O) -> TX_HOST(PF,C=1) -> PUSH_PKT -> TX_VLAN

    VF->Wire (VLAN=0xfff, Promisc)
    RX_HOST -> VEB_LOOKUP -miss-> CHECKSUM(O,I) -> TX_WIRE(C=1) -> TX_HOST(PF, M=1) -multicast-> PUSH_PKT -> TX_VLAN

    VF->Wire (Vlan=0x5)
    RX_HOST -> INSERT(12,4,0x81000005) -> VEB_LOOKUP -miss-> CHECKSUM(I) -> TX_WIRE(M=1) -multicast-> CHECKSUM(O) -> TX_HOST(PF,C=1) -> PUSH_PKT -> TX_VLAN
,
    VF->Wire (Vlan=0x5, Promisc)
    RX_HOST -> INSERT(12,4,0x81000005) -> VEB_LOOKUP -miss-> CHECKSUM(O,I) -> TX_WIRE(C=1) -> TX_HOST(PF,M=1) -multicast-> PUSH_PKT -> TX_VLAN

    PF->Wire (VLAN=0xfff)
    PF->Wire (VLAN=0x5)
    RX_HOST -> VEB_LOOKUP -miss-> CHECKSUM(I) -> TX_WIRE(M=1) -multicast-> CHECKSUM{O) -> PUSH_PKT -> TX_VLAN

    PF->VF
    RX_HOST -> VEB_LOOKUP -hit-> (same as Wire->VF)

    VF->VF
    RX_HOST -> VEB_LOOKUP -hit-> (same as Wire->VF)

    VF->PF
    RX_HOST -> VEB_LOOKUP -hit-> [CHECKSUM(O,I,C) -> BPF -> RSS -> TX_HOST(PF)]
*/

uint32_t cfg_act_map[] = {
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
};

/*
 * Global declarations for configuration change management
 */

// #define APP_CONFIG_DEBUG


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


#define NIC_NBI 0

  /*
   * Debug
   */
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

__export __emem uint64_t cfg_error_rss_cntr = 0;

/* RSS table length in words */
#define NFP_NET_CFG_RSS_ITBL_SZ_wrd (NFP_NET_CFG_RSS_ITBL_SZ >> 2)

/* VxLAN table length in words */
#define  NFP_NET_CFG_VXLAN_SZ_wrd (NFP_NET_CFG_VXLAN_SZ >> 2)

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

__intrinsic __emem __addr40 uint8_t*
cfg_act_bar_ptr(uint32_t pcie, uint32_t vid)
{

    __emem __addr40 uint8_t* bar_base = 0;

    switch (pcie) {
        case 0: bar_base = NFD_CFG_BAR_ISL(0, vid); break;
        case 1: bar_base = NFD_CFG_BAR_ISL(1, vid); break;
        case 2: bar_base = NFD_CFG_BAR_ISL(2, vid); break;
        case 3: bar_base = NFD_CFG_BAR_ISL(3, vid); break;
    }

    return bar_base;
}

__intrinsic __emem __addr40 uint8_t*
cfg_act_vf_cfg_ptr(uint32_t pcie)
{
    __emem __addr40 uint8_t *vf_cfg_base = 0;

    switch (pcie) {
        case 0: vf_cfg_base = NFD_VF_CFG_BASE_LINK(0); break;
        case 1: vf_cfg_base = NFD_VF_CFG_BASE_LINK(1); break;
        case 2: vf_cfg_base = NFD_VF_CFG_BASE_LINK(2); break;
        case 3: vf_cfg_base = NFD_VF_CFG_BASE_LINK(3); break;
    }

    return vf_cfg_base;
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
/* RSS table uses 0-63 NN registers (max of 2 VNIC ports, 1 RSS tbl per port) */
/* HASH table uses 64-103, EPOCH uses NN 127  */
__intrinsic void
upd_nn_table_instr(__xwrite uint32_t *xwr_instr, uint32_t start_offset,
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
        command.NN_reg_num = start_offset;
        command.remote_isl = cfg_mes_ids[i] >> 4;
        command.master = cfg_mes_ids[i] & 0x0f;
        ct_nn_write(xwr_instr, &command, count/2, sig_done, &sig1);
        wait_for_all(&sig1);

        command.NN_reg_num = start_offset + count/2;
        ct_nn_write(&xwr_instr[count/2], &command, count/2, sig_done, &sig2);
        wait_for_all(&sig2);

#ifdef APP_CONFIG_DEBUG
    mem_write32(xwr_instr, debug_rss_table + start_offset,
                (count/2)<<2);
    mem_write32(xwr_instr, debug_rss_table + start_offset + count/2,
                (count/2)<<2);
#endif

    }
}

__intrinsic void
init_nn_tables()
{
    SIGNAL sig;
    uint32_t i, j;
    union ct_nn_write_format command;
    __xwrite uint32_t xwr_nn_info[16] = { 0 };

    command.value = 0;
    command.sig_num = 0x0;
    command.addr_mode = CT_ADDR_MODE_ABSOLUTE;

    for (i = 0; i < 128; i += 16) {
        command.NN_reg_num = i;
        for (j = 0; j < sizeof(cfg_mes_ids)/sizeof(uint32_t); j++) {
            command.remote_isl = cfg_mes_ids[j] >> 4;
            command.master = cfg_mes_ids[j] & 0x0f;
            ct_nn_write(xwr_nn_info, &command, 16, ctx_swap, &sig);
        }
    }
    return;
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
                   uint32_t start_offset, uint32_t count, uint32_t num_pcie_q)
{
    __cls __addr32 void *nic_cfg_instr_tbl = (__cls __addr32 void*)
                                        __link_sym("NIC_CFG_INSTR_TBL");
    SIGNAL last_sig;
    uint32_t addr_hi;
    uint32_t addr_lo;
    uint32_t byte_off = start_offset;
    uint32_t isl;
    uint32_t i;

    for (isl = 0; isl < sizeof(app_isl_ids) / sizeof(uint32_t); isl++) {
        addr_lo = (uint32_t) nic_cfg_instr_tbl + start_offset;
        addr_hi = app_isl_ids[isl] >> 4; /* only use island, mask out ME */
        addr_hi = (addr_hi << (34 - 8)); /* address shifted by 8 in instr */

        for (i = 0; i < (num_pcie_q - 1); i++)
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

/* Copy VLAN members table to all CTMs */
__intrinsic void
upd_ctm_vlan_members()
{
    __ctm __addr40 void *vlan_vnic_members_tbl = (__ctm __addr40 void*)
                                        __link_sym("_vf_vlan_cache");

    SIGNAL sig_read;
    SIGNAL sig_write;
    uint32_t addr_hi;
    uint32_t addr_lo;
    uint32_t start_offset;
    uint32_t isl;
    struct nfp_mecsr_prev_alu ind;
    __xwrite uint32_t wr_data[16];
    __xread uint32_t rd_data[16];

    ind.__raw = 0;
    ind.ov_len = 1;
    ind.length = 15;

    /* Propagate to all worker CTM islands */
    for(start_offset = 0; start_offset < (4096*64)/8; start_offset+=64){
        mem_read32(&rd_data, &nic_vlan_to_vnics_map_tbl[(start_offset/8)], (16*4));
        reg_cp(wr_data, rd_data, sizeof(rd_data));
        for (isl= 32; isl< 37; isl++) {
            addr_lo = (uint32_t)vlan_vnic_members_tbl + start_offset;
            addr_hi = ((isl) << (32 - 8));
            addr_hi = (addr_hi | (1<<(39-8)));
            __asm {
                alu[--, --, B, ind.__raw]
                mem[write32, wr_data, addr_hi, << 8, addr_lo, \
                       max_16], ctx_swap[sig_write], indirect_ref
            }
        }
    }
    return;
}


//for each port there must be call to this.
//for each port size of table must be known and configured accordingly
__intrinsic void upd_rss_table(uint32_t start_offset, __emem __addr40 uint8_t *bar_base, uint32_t vnic_port)
{
    __xread uint32_t rss_rd[NFP_NET_CFG_RSS_ITBL_SZ_wrd];
    __xwrite uint32_t rss_wr[32];
    uint32_t i, j, tmp, data, shf, rows, cols;
    uint32_t rss_tmp[32];

    if (((start_offset + (RSS_TBL_SIZE_LW / NS_PLATFORM_NUM_PORTS)) > SLICC_HASH_PAD_NN_IDX) || (vnic_port > NS_PLATFORM_NUM_PORTS)) {
	cfg_error_rss_cntr++;
	return;
    }

    mem_read32(rss_rd, bar_base + NFP_NET_CFG_RSS_ITBL, sizeof(rss_rd));

    #if (NFD_MAX_PF_QUEUES <= 4)
        #define ACTION_RSS_ROW_MASK  0x7
        #define ACTION_RSS_COL_SHIFT 0x1
        #define ACTION_RSS_ROW_SHIFT 0x4
        #define ACTION_RSS_Q_MASK    0x3
        rows = 8;
        cols = 16;
    #elif (NFD_MAX_PF_QUEUES <= 16)
        #define ACTION_RSS_ROW_MASK  0xf
        #define ACTION_RSS_COL_SHIFT 0x2
        #define ACTION_RSS_ROW_SHIFT 0x3
        #define ACTION_RSS_Q_MASK    0xf
	rows = 16;
	cols = 8;
    #else
        #define ACTION_RSS_ROW_MASK  0x1f
        #define ACTION_RSS_COL_SHIFT 0x3
        #define ACTION_RSS_ROW_SHIFT 0x2
        #define ACTION_RSS_Q_MASK    0xff
	rows = 32;
	cols = 4;
    #endif

    shf = 32 / cols;
    for (i = 0; i < rows; ++i) {
	rss_tmp[i] = 0;
        for (j = 0; j < cols; ++j) {
	    uint32_t idx = i * cols + j;
	    __gpr uint32_t tmp = rss_rd[idx / 4]; // coerce rss_rd[idx / 4] into GPR, see THSDK-4039
	    tmp = (tmp >> ((idx % 4) * 8)) & ((1 << shf) - 1);
	    if (tmp >= NFD_MAX_PF_QUEUES)
	       continue;
	    rss_tmp[i] |= (tmp << (j * shf));
        }
    }

    // separate loop for rss_wr[i] to avoid T_INDEX bug, see THSDK-4040
    for (i = 0; i < rows; ++i) {
        rss_wr[i] = rss_tmp[i];
    }

    upd_nn_table_instr(rss_wr, start_offset, rows);
}

__intrinsic void
upd_slicc_hash_table(void)
{
    __xwrite uint32_t xwr_nn_info[SLICC_HASH_PAD_SIZE_LW/4];
    __xread uint32_t xrd_data[SLICC_HASH_PAD_SIZE_LW/4];
    uint32_t i;
	uint32_t t;
	uint32_t start_offset = SLICC_HASH_PAD_NN_IDX;
	__imem uint32_t *slicc_hash_data =
		(__imem uint32_t *) __link_sym("SLICC_HASH_PAD_DATA");

	for (t=0; t<SLICC_HASH_PAD_SIZE_LW; t+=(sizeof(xrd_data)/4)) {
		mem_read32(xrd_data, slicc_hash_data, sizeof(xrd_data));

		for (i = 0; i < (sizeof(xrd_data)/4); i++) {
			xwr_nn_info[i] = xrd_data[i];
		}

	    /* Write at NN register start_offset for all worker MEs */
		upd_nn_table_instr(xwr_nn_info,  start_offset, (sizeof(xrd_data)/4));

		start_offset += sizeof(xrd_data)/4;
		slicc_hash_data += sizeof(xrd_data)/4;
	}
    return;
}

#define VXLAN_PORTS_NN_IDX (SLICC_HASH_PAD_NN_IDX + SLICC_HASH_PAD_SIZE_LW)

__intrinsic uint32_t
cfg_act_upd_vxlan_table(uint32_t pcie, uint32_t vid)
{
    __xread uint32_t xrd_vxlan_data[NFP_NET_CFG_VXLAN_SZ_wrd];
    __xwrite uint32_t xwr_nn_info[NFP_NET_CFG_VXLAN_SZ_wrd];
    uint32_t vxlan_data[NFP_NET_CFG_VXLAN_SZ_wrd];
    uint32_t i;
    uint32_t n_vxlan = 0;

    mem_read32(xrd_vxlan_data, cfg_act_bar_ptr(pcie, vid) +
	       NFP_NET_CFG_VXLAN_PORT, sizeof(xrd_vxlan_data));
    for (i = 0; i < NFP_NET_CFG_VXLAN_SZ_wrd; i++) {
        xwr_nn_info[i] = xrd_vxlan_data[i];
	if ((xrd_vxlan_data[i] & 0xffff) != 0)
	    n_vxlan++;
    }

    /* Write at NN register start_offset for all worker MEs */
    upd_nn_table_instr(xwr_nn_info, VXLAN_PORTS_NN_IDX, NFP_NET_CFG_VXLAN_SZ_wrd);
    return n_vxlan;
}


__intrinsic void
cfg_act_init(action_list_t *acts)
{
    reg_zero(acts->instr, NIC_MAX_INSTR);
    acts->count = 0;
    acts->prev = 0;
}


__intrinsic void
cfg_act_write_queue(uint32_t qid, action_list_t *acts)
{
    SIGNAL sig;
    uint32_t addr_hi;
    uint32_t addr_lo;
    uint32_t isl;
    uint32_t count;
    struct nfp_mecsr_prev_alu ind;
    __xwrite uint32_t xwr_instr[NIC_MAX_INSTR];
    __cls __addr32 void *nic_cfg_instr_tbl = (__cls __addr32 void*)
                                              __link_sym("NIC_CFG_INSTR_TBL");

    reg_cp(xwr_instr, (void *) acts->instr, NIC_MAX_INSTR << 2);
    count = acts->count;

    for (isl = 0; isl < sizeof(app_isl_ids) / sizeof(uint32_t); isl++) {
	addr_lo = (uint32_t) nic_cfg_instr_tbl + qid * NIC_MAX_INSTR * 4;
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
}


__intrinsic void
cfg_act_write_host(uint32_t pcie, uint32_t vid, action_list_t *acts)
{
    uint32_t i;

    for (i = 0; i < NFD_VID_MAXQS(vid); ++i)
        cfg_act_write_queue((pcie << 6) | NFD_VID2QID(vid, i), acts);
}


__intrinsic void
cfg_act_write_wire(uint32_t port, action_list_t *acts)
{
    cfg_act_write_queue((1 << 8) | port, acts);
}


__intrinsic void
cfg_act_append(action_list_t *acts, uint16_t op, uint16_t args)
{
    uint32_t precursor_act = 2 * cfg_act_map[op] - cfg_act_map[op + 1];

    acts->instr[acts->count].pipeline =
        (acts->count && acts->prev == precursor_act) ? 1 : 0;

    acts->instr[acts->count].op = cfg_act_map[op];
    acts->prev = cfg_act_map[op];

    acts->instr[acts->count++].args = args;
}

__intrinsic void
cfg_act_append_drop(action_list_t *acts)
{
    cfg_act_append(acts, INSTR_DROP, 0);
}


__intrinsic void
cfg_act_append_rx_host(action_list_t *acts, uint32_t pcie, uint32_t vid, uint32_t outer_csum)
{
    instr_rx_host_t instr_rx_host;
    __xread uint32_t mtu;

    instr_rx_host.__raw[0] = 0;

    mem_read32(&mtu, (__mem void*) (cfg_act_bar_ptr(pcie, vid) +
				    NFP_NET_CFG_MTU), sizeof(mtu));

    instr_rx_host.mtu = mtu + NET_ETH_LEN + 1;
    instr_rx_host.csum_outer_l3 = outer_csum;
    instr_rx_host.csum_outer_l4 = outer_csum;

    cfg_act_append(acts, INSTR_RX_HOST, instr_rx_host.__raw[0]);
}

__intrinsic void
cfg_act_append_veb_lookup(action_list_t *acts, uint32_t pcie, uint32_t vid,
			  uint32_t promisc, uint32_t mac_match)
{
    __xread uint32_t bar_mac[2];
    uint32_t mac[2];

    if (promisc) {
        cfg_act_append(acts, INSTR_VEB_LOOKUP, 0);
        acts->instr[acts->count++].value = 0;
    } else {
        if (mac_match) {
            mem_read64(bar_mac, (__mem void*) (cfg_act_bar_ptr(pcie, vid) +
				NFP_NET_CFG_MACADDR), sizeof(mac));
            mac[0] = bar_mac[0];
            mac[1] = bar_mac[1];
        } else {
            mac[0] = 0;
            mac[1] = 0;
        }
	cfg_act_append(acts, INSTR_VEB_LOOKUP, mac[0] >> 16);
	acts->instr[acts->count++].value = (mac[0] << 16) | (mac[1] >> 16);
    }
}

__intrinsic void
cfg_act_append_mac_match(action_list_t *acts, uint32_t pcie, uint32_t vid)
{
    __xread uint32_t mac[2];

    mem_read64(mac, (__mem void*) (cfg_act_bar_ptr(pcie, vid) +
				   NFP_NET_CFG_MACADDR), sizeof(mac));
    cfg_act_append(acts, INSTR_MAC_MATCH, mac[0] >> 16);
    acts->instr[acts->count++].value = (mac[0] << 16) | (mac[1] >> 16);
}

#define ACTION_RSS_IPV6_TCP_BIT 0
#define ACTION_RSS_IPV6_UDP_BIT 1
#define ACTION_RSS_IPV4_TCP_BIT 2
#define ACTION_RSS_IPV4_UDP_BIT 3

__intrinsic void
cfg_act_append_rss(action_list_t *acts, uint32_t pcie, uint32_t vid, int update_map, int v1_meta)
{
    __emem __addr40 uint8_t *bar_base;
    SIGNAL sig1, sig2, sig3;
    __xread uint32_t rss_ctrl;
    __xread uint32_t rx_rings[2];
    __xread uint32_t rss_key[NFP_NET_CFG_RSS_KEY_SZ / sizeof(uint32_t)];
    uint32_t rss_tbl_nnidx;
    uint32_t type, vnic;
    instr_rss_t instr_rss;

    bar_base = cfg_act_bar_ptr(pcie, vid);

    /* RSS remapping table with NN register index as start offset */
    NFD_VID2VNIC(type, vnic, vid);
    rss_tbl_nnidx = vnic * (RSS_TBL_SIZE_LW / NS_PLATFORM_NUM_PORTS);
    if (update_map)
        upd_rss_table(rss_tbl_nnidx, bar_base, vnic);

    /* Read RSS configuration from BAR */
    __mem_read32(&rss_ctrl, (__mem void*) (bar_base + NFP_NET_CFG_RSS_CTRL),
                 sizeof(rss_ctrl), sizeof(rss_ctrl), sig_done, &sig1);
    __mem_read64(&rss_key, (__mem void*) (bar_base + NFP_NET_CFG_RSS_KEY),
                NFP_NET_CFG_RSS_KEY_SZ, NFP_NET_CFG_RSS_KEY_SZ, sig_done, &sig2);
    __mem_read64(&rx_rings, (__mem void*) (bar_base + NFP_NET_CFG_RXRS_ENABLE),
                 sizeof(uint64_t), sizeof(uint64_t), sig_done, &sig3);
    wait_for_all(&sig1, &sig2, &sig3);
    instr_rss.key = rss_key[0];

    // Driver does L3 unconditionally, so we only care about L4 combinations
    instr_rss.cfg_proto = 0;
    if (rss_ctrl & NFP_NET_CFG_RSS_IPV4_TCP)
        instr_rss.cfg_proto |= (1 << ACTION_RSS_IPV4_TCP_BIT);
    if (rss_ctrl & NFP_NET_CFG_RSS_IPV4_UDP)
        instr_rss.cfg_proto |= (1 << ACTION_RSS_IPV4_UDP_BIT);
    if (rss_ctrl & NFP_NET_CFG_RSS_IPV6_TCP)
        instr_rss.cfg_proto |= (1 << ACTION_RSS_IPV6_TCP_BIT);
    if (rss_ctrl & NFP_NET_CFG_RSS_IPV6_UDP)
        instr_rss.cfg_proto |= (1 << ACTION_RSS_IPV6_UDP_BIT);

    instr_rss.max_queue = ((~rx_rings[0]) ? ffs(~rx_rings[0]) : 32 + ffs(~rx_rings[1]) - 1);

    instr_rss.v1_meta = v1_meta;
    instr_rss.col_shf = ACTION_RSS_COL_SHIFT;
    instr_rss.queue_mask = ACTION_RSS_Q_MASK;
    instr_rss.row_mask = ACTION_RSS_ROW_MASK;
    instr_rss.table_addr = rss_tbl_nnidx;
    instr_rss.row_shf = ACTION_RSS_ROW_SHIFT;

    cfg_act_append(acts, INSTR_RSS, instr_rss.__raw[0]);
    acts->instr[acts->count++].value = instr_rss.__raw[1];
    acts->instr[acts->count++].value = instr_rss.__raw[2];
}


__intrinsic void
cfg_act_append_push_pkt(action_list_t *acts)
{
    cfg_act_append(acts, INSTR_PUSH_PKT, 0);
}


__intrinsic void
cfg_act_append_pop_pkt(action_list_t *acts)
{
    cfg_act_append(acts, INSTR_POP_PKT, 0);
}


__intrinsic void
cfg_act_append_checksum(action_list_t *acts,
			int outer, int inner, int complete)
{
    instr_checksum_t instr_csum;

    instr_csum.__raw[0] = 0;
    instr_csum.outer_l3 = outer;
    instr_csum.outer_l4 = outer;
    instr_csum.inner_l3 = inner;
    instr_csum.inner_l4 = inner;
    instr_csum.complete_meta = complete;

    cfg_act_append(acts, INSTR_CHECKSUM, instr_csum.__raw[0]);
}


__intrinsic void
cfg_act_append_rx_wire(action_list_t *acts, uint32_t pcie, uint32_t vid,
		       uint32_t vxlan, uint32_t nvgre, uint32_t rxcsum)
{
    instr_rx_wire_t instr_rx_wire;

    instr_rx_wire.__raw[0] = 0;

    if (vxlan) {
        instr_rx_wire.parse_vxlans = cfg_act_upd_vxlan_table(pcie, vid);
        instr_rx_wire.vxlan_nn_idx = VXLAN_PORTS_NN_IDX;
    }

    instr_rx_wire.parse_nvgre = nvgre;
    instr_rx_wire.host_encap_prop_csum = rxcsum;

    cfg_act_append(acts, INSTR_RX_WIRE, instr_rx_wire.__raw[0]);
}

__intrinsic void
cfg_act_remove_strip_vlan(action_list_t *acts)
{
    uint32_t i, found = 0;

    for (i = 0; i < acts->count - 1; ++i) {
	if (found) {
	    acts->instr[i] = acts->instr[i + 1];
	}
	else if (acts->instr[i].op == INSTR_POP_VLAN) {
	    found = 1;
	    acts->instr[i] = acts->instr[i + 1];
	    acts->instr[i].pipeline = 0;
	}
    }
    acts->count -= found;
}

__intrinsic void
cfg_act_append_strip_vlan(action_list_t *acts)
{
    cfg_act_append(acts, INSTR_POP_VLAN, 0);
}

__intrinsic void
cfg_act_append_push_vlan(action_list_t *acts, uint32_t vlan_tag)
{
    cfg_act_append(acts, INSTR_PUSH_VLAN, vlan_tag);
}

__intrinsic void
cfg_act_append_tx_wire(action_list_t *acts, uint32_t tmq,
                       uint32_t cont, uint32_t multicast)
{

    instr_tx_wire_t instr_tx_wire;
    uint32_t type, vnic;

    instr_tx_wire.tm_queue = tmq;
    instr_tx_wire.cont = cont;
    instr_tx_wire.multicast = multicast;

    cfg_act_append(acts, INSTR_TX_WIRE, instr_tx_wire.__raw[0]);
}

__intrinsic void
cfg_act_append_tx_host(action_list_t *acts, uint32_t pcie, uint32_t vid,
                       uint32_t cont, uint32_t multicast)
{

    __imem uint32_t *fl_buf_sz_cache = (__imem uint32_t *)
                                        __link_sym("_fl_buf_sz_cache");
    uint32_t min_rxb = 0;
    instr_tx_host_t instr_tx_host;
    __xread uint64_t members;
    __xread uint32_t flbuf_sz;

    instr_tx_host.pcie = pcie;
    instr_tx_host.queue = NFD_VID2QID(vid, 0); //to PF!
    instr_tx_host.cont = cont;
    instr_tx_host.multicast = multicast;

    mem_read32(&flbuf_sz, &fl_buf_sz_cache[pcie * 64 + vid], sizeof(flbuf_sz));
    min_rxb = flbuf_sz >> 8;
    instr_tx_host.min_rxb = (min_rxb > 63) ? 63 : min_rxb;

    cfg_act_append(acts, INSTR_TX_HOST, instr_tx_host.__raw[0]);
}

__intrinsic void
cfg_act_append_tx_vlan(action_list_t *acts)
{
    cfg_act_append(acts, INSTR_TX_VLAN, 0);
}

__intrinsic void
cfg_act_append_bpf(action_list_t *acts, uint32_t vnic)
{

    uint32_t bpf_offset;

    bpf_offset = NFD_BPF_START_OFF + vnic * NFD_BPF_MAX_LEN;
    cfg_act_append(acts, INSTR_EBPF, bpf_offset);
}


__intrinsic void
cfg_act_append_cmsg(action_list_t *acts)
{
    cfg_act_append(acts, INSTR_CMSG, 0);
}


__intrinsic void
cfg_act_build_ctrl(action_list_t *acts, uint32_t pcie, uint32_t vid)
{
    uint32_t type, vnic;

    cfg_act_init(acts);

    NFD_VID2VNIC(type, vnic, vid);

    if (type != NFD_VNIC_TYPE_CTRL)
        return;

    cfg_act_append_rx_host(acts, pcie, vid, 0);
    cfg_act_append_cmsg(acts);
}


__intrinsic void
cfg_act_build_pf(action_list_t *acts, uint32_t pcie, uint32_t vid,
		 uint32_t veb_up, uint32_t control, uint32_t update)
{
    uint32_t type, vnic;
    uint32_t csum_i, csum_o;
    uint32_t tmq;

    cfg_act_init(acts);

    NFD_VID2VNIC(type, vnic, vid);

    if (type != NFD_VNIC_TYPE_PF)
        return;

    csum_o = (control & NFP_NET_CFG_CTRL_TXCSUM) ? 1 : 0;
    csum_i = (csum_o && (control & NFP_NET_CFG_CTRL_VXLAN)) ? 1 : 0;
    tmq = NS_PLATFORM_NBI_TM_QID_LO(vnic);

    cfg_act_append_rx_host(acts, pcie, vid, veb_up);

    if (! veb_up)
        cfg_act_append_tx_wire(acts, tmq, 0, 0);
    else {
	cfg_act_append_veb_lookup(acts, pcie, vid, 0, 0);

        if (csum_i)
	    cfg_act_append_checksum(acts, 0, 1, 0); // I

        cfg_act_append_tx_wire(acts, tmq, 0, 1); // M

        if (csum_o)
	    cfg_act_append_checksum(acts, 1, 0, 0); // O

        cfg_act_append_push_pkt(acts);
        cfg_act_append_tx_vlan(acts);
    }
}

__intrinsic void
cfg_act_build_vf(action_list_t *acts, uint32_t pcie, uint32_t vid,
		 uint32_t pf_control, uint32_t vf_control)
{
    __xread struct sriov_cfg sriov_cfg_data;
    __emem __addr40 uint8_t *vf_cfg_base;
    uint32_t type, vnic;
    uint32_t csum_i, csum_o;
    uint32_t promisc;

    cfg_act_init(acts);

    NFD_VID2VNIC(type, vnic, vid);
    if (type != NFD_VNIC_TYPE_VF)
        return;

    csum_o = (vf_control & NFP_NET_CFG_CTRL_TXCSUM) ? 1 : 0;
    csum_i = (csum_o && (vf_control & NFP_NET_CFG_CTRL_VXLAN)) ? 1 : 0;
    promisc = (pf_control & NFP_NET_CFG_CTRL_PROMISC) ? 1 : 0;

    cfg_act_append_rx_host(acts, pcie, vid, 1);

    vf_cfg_base = cfg_act_vf_cfg_ptr(pcie);
    mem_read32(&sriov_cfg_data,
	       NFD_VF_CFG_ADDR(vf_cfg_base, NFD_VID2VF(vid)),
	       sizeof(struct sriov_cfg));
    if (sriov_cfg_data.vlan_tag != 0)
        cfg_act_append_push_vlan(acts, sriov_cfg_data.vlan_tag);

    cfg_act_append_veb_lookup(acts, pcie, vid, 0, 0);

    if (csum_i)
        cfg_act_append_checksum(acts, 0, 1, 0); // I

    cfg_act_append_tx_wire(acts, NS_PLATFORM_NBI_TM_QID_LO(0) /* vnic 0 */,
			   promisc, 1);

    if (csum_o)
	 cfg_act_append_checksum(acts, 1, 0, 0); // O

    cfg_act_append_tx_host(acts, pcie, NFD_PF2VID(0), 0, 1); // M

    cfg_act_append_push_pkt(acts);
    cfg_act_append_tx_vlan(acts);
}

__intrinsic void
cfg_act_build_pcie_down(action_list_t *acts, uint32_t pcie, uint32_t vid)
{
    cfg_act_init(acts);
    cfg_act_append_rx_host(acts, pcie, vid, 0);
    cfg_act_append_drop(acts);
}

__intrinsic void
cfg_act_build_nbi(action_list_t *acts, uint32_t pcie, uint32_t vid,
		  uint32_t veb_up, uint32_t control, uint32_t update)
{
    uint32_t type, vnic;
    uint32_t vxlan = (control & NFP_NET_CFG_CTRL_VXLAN) ? 1 : 0;
    uint32_t nvgre = (control & NFP_NET_CFG_CTRL_NVGRE) ? 1 : 0;
    uint32_t promisc = (control & NFP_NET_CFG_CTRL_PROMISC) ? 1 : 0;
    uint32_t csum_compl = (control & NFP_NET_CFG_CTRL_CSUM_COMPLETE) ? 1 : 0;
    uint32_t rx_csum = (control & NFP_NET_CFG_CTRL_RXCSUM) ? 1 : 0;
    uint32_t update_rss = (update & NFP_NET_CFG_UPDATE_RSS ||
			   update & NFP_NET_CFG_CTRL_BPF);
    uint32_t rss_v1 = (NFD_CFG_MAJOR_PF < 4 &&
                       !(control & NFP_NET_CFG_CTRL_CHAIN_META));

    cfg_act_init(acts);

    NFD_VID2VNIC(type, vnic, vid);
    if (type != NFD_VNIC_TYPE_PF)
        return;

    cfg_act_append_rx_wire(acts, pcie, vid, vxlan, nvgre,
			   rx_csum && !csum_compl);

    if (veb_up)
        cfg_act_append_veb_lookup(acts, pcie, vid, promisc, 1);
    else if (! promisc)
        cfg_act_append_mac_match(acts, pcie, vid);

    if (veb_up || csum_compl)
        cfg_act_append_checksum(acts, veb_up, veb_up, csum_compl); // O, I, C

    if (control & NFP_NET_CFG_CTRL_BPF)
        cfg_act_append_bpf(acts, vnic);

    if (control & NFP_NET_CFG_CTRL_RSS_ANY || control & NFP_NET_CFG_CTRL_BPF)
	cfg_act_append_rss(acts, pcie, vid, update_rss, rss_v1);

    cfg_act_append_tx_host(acts, pcie, vid, 0, veb_up);

    if (veb_up) {
        cfg_act_append_push_pkt(acts);
        cfg_act_append_tx_vlan(acts);
    }

}


__intrinsic void
cfg_act_build_nbi_down(action_list_t *acts, uint32_t pcie, uint32_t vid)
{
    cfg_act_init(acts);
    cfg_act_append_rx_wire(acts, pcie, vid, 0, 0, 0);
    cfg_act_append_drop(acts);
}


__intrinsic void
cfg_act_build_veb_pf(action_list_t *acts, uint32_t pcie, uint32_t vid,
		     uint32_t control, uint32_t update)
{
    uint32_t type, vnic;
    uint32_t update_rss = (update & NFP_NET_CFG_UPDATE_RSS ||
			   update & NFP_NET_CFG_CTRL_BPF);
    uint32_t rss_v1 = (NFD_CFG_MAJOR_PF < 4 &&
                       !(control & NFP_NET_CFG_CTRL_CHAIN_META));
    uint32_t csum_c = (control & NFP_NET_CFG_CTRL_CSUM_COMPLETE) ? 1 : 0;

    cfg_act_init(acts);

    NFD_VID2VNIC(type, vnic, vid);
    if (type != NFD_VNIC_TYPE_PF)
        return;

    cfg_act_append_checksum(acts, 1, 1, csum_c); // O, I, C?

    if (control & NFP_NET_CFG_CTRL_BPF)
        cfg_act_append_bpf(acts, vnic);

    if (control & NFP_NET_CFG_CTRL_RSS_ANY || control & NFP_NET_CFG_CTRL_BPF)
	cfg_act_append_rss(acts, pcie, vid, update_rss, rss_v1);

    cfg_act_append_tx_host(acts, pcie, vid, 0, 0);
}


__intrinsic void
cfg_act_build_veb_vf(action_list_t *acts, uint32_t pcie, uint32_t vid,
                     uint32_t pf_control, uint32_t vf_control, uint32_t update)
{
    __xread struct sriov_cfg sriov_cfg_data;
    __emem __addr40 uint8_t *vf_cfg_base;
    uint32_t type, vnic;
    uint32_t rss_v1;
    uint32_t csum_c = (vf_control & NFP_NET_CFG_CTRL_CSUM_COMPLETE) ? 1 : 0;
    uint32_t promisc = (pf_control & NFP_NET_CFG_CTRL_PROMISC) ? 1 : 0;

    cfg_act_init(acts);

    NFD_VID2VNIC(type, vnic, vid);
    if (type != NFD_VNIC_TYPE_VF)
        return;

    if (promisc) {
        cfg_act_append_push_pkt(acts);
    }

    vf_cfg_base = cfg_act_vf_cfg_ptr(pcie);
    mem_read32(&sriov_cfg_data,
	       NFD_VF_CFG_ADDR(vf_cfg_base, NFD_VID2VF(vid)),
	       sizeof(struct sriov_cfg));
    if (sriov_cfg_data.vlan_tag != 0)
        cfg_act_append_strip_vlan(acts);

    cfg_act_append_checksum(acts, 1, 1, csum_c); // O, I, C?

    cfg_act_append_tx_host(acts, pcie, vid, promisc, 0);

    if (promisc) {
        cfg_act_append_pop_pkt(acts);

	if (pf_control & NFP_NET_CFG_CTRL_CSUM_COMPLETE)
	    cfg_act_append_checksum(acts, 0, 0, 1); // C

	if (pf_control & NFP_NET_CFG_CTRL_BPF)
	    cfg_act_append_bpf(acts, vnic);

        if (pf_control & NFP_NET_CFG_CTRL_RSS_ANY || pf_control & NFP_NET_CFG_CTRL_BPF) {
            rss_v1 = (NFD_CFG_MAJOR_PF < 4 && !(pf_control & NFP_NET_CFG_CTRL_CHAIN_META));
	    cfg_act_append_rss(acts, pcie, NFD_PF2VID(0), 0, rss_v1);
	}

        cfg_act_append_tx_host(acts, pcie, NFD_PF2VID(0), 0, 0);
    }
}


__intrinsic void
cfg_act_cache_fl_buf_sz(uint32_t pcie, uint32_t vid)
{
    int i;
    __xread uint32_t rxb_r;
    __xwrite uint32_t rxb_w;
    __imem uint32_t *fl_buf_sz_cache = (__imem uint32_t *)
                                        __link_sym("_fl_buf_sz_cache");

    mem_read32(&rxb_r, (__mem void*) (cfg_act_bar_ptr(pcie, vid) + NFP_NET_CFG_FLBUFSZ), sizeof(rxb_r));
    rxb_w = rxb_r;
    for (i = 0; i < NFD_VID_MAXQS(vid); ++i)
        mem_write32(&rxb_w, &fl_buf_sz_cache[pcie * 64 + NFD_VID2NATQ(vid, i)], sizeof(rxb_w));
}


__shared __mem struct nic_mac_vlan_key veb_stored_keys[NVNICS];

enum cfg_msg_err
cfg_act_write_veb(uint32_t vid, __lmem struct nic_mac_vlan_key *veb_key,
		  action_list_t *acts)
{
    __xread struct nic_mac_vlan_key stored_key_rd;
    __xwrite struct nic_mac_vlan_key stored_key_wr;
    __lmem struct nic_mac_vlan_key del_key;
    uint32_t new_vlan_id, vlan_id;
    uint64_t new_mac_addr = MAC64_FROM_VEB_KEY(*veb_key);
    enum cfg_msg_err err_code = NO_ERROR;

    if (acts != 0) {
        /* Fail if mac is 0 or multicast */
        if (new_mac_addr == 0 || ((new_mac_addr >> 40) & 0x01))
            return MAC_VLAN_ADD_FAIL;

        new_vlan_id = veb_key->vlan_id;
        /* Add or overwrite VEB table entries */
        for (vlan_id = 0; vlan_id <= NIC_NO_VLAN_ID; vlan_id++) {
            if (new_vlan_id == NIC_NO_VLAN_ID || vlan_id == new_vlan_id ||
		(new_vlan_id == 0 && vlan_id == NIC_NO_VLAN_ID)) {
		if (vlan_id == NIC_NO_VLAN_ID)
                    cfg_act_remove_strip_vlan(acts);
      	        veb_key->vlan_id = vlan_id;
                if (nic_mac_vlan_entry_op_cmsg(veb_key,
		        (__lmem uint32_t *) acts->instr,
                        CMSG_TYPE_MAP_ADD) == CMESG_DISPATCH_FAIL)
                    return MAC_VLAN_ADD_FAIL;
            }
        }
    }

    mem_read32(&stored_key_rd, &veb_stored_keys[vid], sizeof(struct nic_mac_vlan_key)),

    reg_cp(&stored_key_wr, veb_key, sizeof(struct nic_mac_vlan_key));
    mem_write32(&stored_key_wr, &veb_stored_keys[vid], sizeof(struct nic_mac_vlan_key));

    /* Delete previously existing entries if the lookup key differs */
    for (vlan_id = 0; vlan_id <= NIC_NO_VLAN_ID; vlan_id++) {
	if (veb_key->mac_addr_hi != stored_key_rd.mac_addr_hi ||
	    veb_key->mac_addr_lo != stored_key_rd.mac_addr_lo ||
	    (new_vlan_id != NIC_NO_VLAN_ID && vlan_id != new_vlan_id)) {
	    reg_cp(&del_key, &stored_key_rd, sizeof(struct nic_mac_vlan_key));
            del_key.vlan_id = vlan_id;
            if (nic_mac_vlan_entry_op_cmsg(&del_key, 0,
                    CMSG_TYPE_MAP_DELETE) == CMESG_DISPATCH_FAIL)
                err_code = MAC_VLAN_DELETE_WARN;
	}
    }

    return err_code;
}


int
cfg_act_vf_up(uint32_t pcie, uint32_t vid,
	      uint32_t pf_control, uint32_t vf_control, uint32_t update)
{
    __xread struct sriov_cfg sriov_cfg_data;
    __emem __addr40 uint8_t *vf_cfg_base;
    __shared __lmem struct nic_mac_vlan_key veb_key;
    uint64_t mac_addr;
    uint16_t vlan_id;
    action_list_t acts;

    cfg_act_build_veb_vf(&acts, pcie, vid, pf_control, vf_control, update);

    vf_cfg_base = cfg_act_vf_cfg_ptr(pcie);
    mem_read32(&sriov_cfg_data,
	       NFD_VF_CFG_ADDR(vf_cfg_base, NFD_VID2VF(vid)),
	       sizeof(struct sriov_cfg));
    vlan_id = sriov_cfg_data.vlan_tag ? sriov_cfg_data.vlan_id : NIC_NO_VLAN_ID;

    mac_addr = MAC64_FROM_SRIOV_CFG(sriov_cfg_data);
    VEB_KEY_FROM_MAC64(veb_key, mac_addr);
    veb_key.vlan_id = vlan_id;

    if (cfg_act_write_veb(vid, &veb_key, &acts) != NO_ERROR)
        return 1;

    cfg_act_cache_fl_buf_sz(pcie, vid);
    add_vlan_member(vlan_id, vid);
    upd_ctm_vlan_members();

    cfg_act_build_vf(&acts, pcie, vid, pf_control, vf_control);
    cfg_act_write_host(pcie, vid, &acts);

    cfg_act_build_nbi(&acts, pcie, NFD_PF2VID(0), 1, pf_control, 0);
    cfg_act_write_wire(0, &acts);
    cfg_act_build_pf(&acts, pcie, NFD_PF2VID(0), 1, pf_control, 0);
    cfg_act_write_host(pcie, NFD_PF2VID(0), &acts);

    return 0;
}

int
cfg_act_vf_down(uint32_t pcie, uint32_t vid)
{
    __shared __lmem struct nic_mac_vlan_key veb_key;
    action_list_t acts;

    cfg_act_build_pcie_down(&acts, pcie, vid);
    cfg_act_write_host(pcie, vid, &acts);

    VEB_KEY_FROM_MAC64(veb_key, 0ull)

    if (cfg_act_write_veb(vid, &veb_key, 0) != NO_ERROR)
	return 1;

    remove_vlan_member(vid);
    upd_ctm_vlan_members();

    return 0;
}


int
cfg_act_pf_up(uint32_t pcie, uint32_t vid, uint32_t veb_up,
	      uint32_t control, uint32_t update)
{
    __xread uint32_t mac[2];
    uint32_t type, vnic;
    __shared __lmem struct nic_mac_vlan_key veb_key;
    action_list_t acts;

    cfg_act_cache_fl_buf_sz(pcie, vid);

    cfg_act_build_nbi(&acts, pcie, vid, veb_up, control, update);
    NFD_VID2VNIC(type, vnic, vid);
    cfg_act_write_wire(vnic, &acts);

    cfg_act_build_pf(&acts, pcie, vid, veb_up, control, update);
    cfg_act_write_host(pcie, vid, &acts);

    if (vnic == 0) { // VFs are only associated with the first PF VNIC (for now)
        cfg_act_build_veb_pf(&acts, pcie, vid, control, update);

        mem_read64(mac, (__mem void*) (cfg_act_bar_ptr(pcie, vid) +
				       NFP_NET_CFG_MACADDR), sizeof(mac));
        veb_key.__raw[0] = 0;
        veb_key.mac_addr_hi = (mac[0] >> 16);
        veb_key.mac_addr_lo = (mac[0] << 16) | (mac[1] >> 16);
	veb_key.vlan_id = NIC_NO_VLAN_ID;

	if (cfg_act_write_veb(vid, &veb_key, &acts) != NO_ERROR)
	    return 1;
    }

    return 0;
}

int cfg_act_pf_down(uint32_t pcie, uint32_t vid)
{
    __emem __addr40 uint8_t *bar_base = NFD_CFG_BAR_ISL(pcie, vid);
    __xread uint32_t mac[2];
    uint32_t type, vnic;
    __shared __lmem struct nic_mac_vlan_key veb_key;
    action_list_t acts;

    NFD_VID2VNIC(type, vnic, vid);
    if (type != NFD_VNIC_TYPE_PF)
	return 1;

    cfg_act_build_nbi_down(&acts, pcie, vid);
    cfg_act_write_wire(vnic, &acts);
    cfg_act_build_pcie_down(&acts, pcie, vid);
    cfg_act_write_host(pcie, vid, &acts);

    if (vnic == 0) {
	mem_read64(mac, (__mem void*) (cfg_act_bar_ptr(pcie, vid) +
	    		               NFP_NET_CFG_MACADDR), sizeof(mac));
        veb_key.__raw[0] = 0;
        veb_key.mac_addr_hi = (mac[0] >> 16);
        veb_key.mac_addr_lo = (mac[0] << 16) | (mac[1] >> 16);

	if (cfg_act_write_veb(vid, &veb_key, 0) != NO_ERROR)
	    return 1;
    }

    return 0;
}
