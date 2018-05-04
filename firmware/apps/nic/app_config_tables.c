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
#include <shared/nfp_net_ctrl.h>
#include <nic_basic/nic_basic.h>
#include <nic_basic/nic_stats.h>
#include "app_config_tables.h"
#include "app_config_instr.h"
#include "ebpf.h"

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

/* use macros to map input VNIC port to index in NIC_CFG_INSTR_TBL table */
/* NFD_VNIC_TYPE_PF, NFD_VNIC_TYPE_CTRL, NFD_VNIC_TYPE_VF */
#define NIC_PORT_TO_PCIE_INDEX(pcie, type, vport, queue) \
        ((pcie << 6) | (NFD_BUILD_QID((type),(vport),(queue))&0x3f))

#define NIC_PORT_TO_NBI_INDEX(nbi, vport) \
        ((1 << 8) | (nbi << 7) | (vport & 0x7f))


/* Build output port with this macro */
#define BUILD_PORT(_subsys, _queue) \
    (((_subsys) << 10) | (_queue))

#define BUILD_HOST_PORT(_pcie, _vf, _q) \
  BUILD_PORT(_pcie, NFD_BUILD_QID((_vf), (_q)))


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

// #define GEN_INSTRUCTION
#ifdef GEN_INSTRUCTION
/*
 * By running py script, and generating array: instr_tbl from actions:
 * targets[ins_0#, ins_1#, ins_2#, ins_3#, ins_4#, ins_5#, ins_6#, ins_7#] ;actions_jump
./parse_list.py --label_prefix=ins_ --jump_table_tag=instr_tbl datapath.list

Also, it is expected that it matches:
enum instruction_type {
    INSTR_TX_DROP = 0,
    INSTR_MTU,
    INSTR_MAC,
    INSTR_RSS,
    INSTR_CHECKSUM_COMPLETE,
    INSTR_TX_HOST,
    INSTR_TX_WIRE,
    INSTR_CMSG,
    INSTR_EBPF
};
*/
unsigned int instr_tbl[] = {0, 0x40, 0x50, 0x20, 0x30, 0x80, 0x60, 0x90};
#endif

__export __emem uint64_t cfg_error_rss_cntr = 0;


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

    /* Write multiple entries (one for each host queue) to local CLS.
     * All writes without a signal except last. */
    for (i = 0; i < (num_pcie_q - 1); i++)
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


__intrinsic void
upd_rss_table(uint32_t start_offset, __emem __addr40 uint8_t *bar_base,
              uint32_t vnic_port)
{
    __xread uint32_t xrd_rss_tbl[NFP_NET_CFG_RSS_ITBL_SZ_wrd];
    __xwrite uint32_t xwr_nn_info[NFP_NET_CFG_RSS_ITBL_SZ_wrd];
    uint32_t i;

	if ( (start_offset + NFP_NET_CFG_RSS_ITBL_SZ_wrd) > SLICC_HASH_PAD_NN_IDX) {
		cfg_error_rss_cntr++;
		return;
	}
    /* Read all 32 words of RSS table */
    mem_read32_swap(xrd_rss_tbl,
                    bar_base + NFP_NET_CFG_RSS_ITBL,
                    sizeof(xrd_rss_tbl));

    for (i = 0; i < NFP_NET_CFG_RSS_ITBL_SZ_wrd; i++) {
        if ((xrd_rss_tbl[i] & 0xff) >= NFD_MAX_PF_QUEUES) continue;
        if (((xrd_rss_tbl[i] >> 8) & 0xff) >= NFD_MAX_PF_QUEUES) continue;
        if (((xrd_rss_tbl[i] >> 16) & 0xff) >= NFD_MAX_PF_QUEUES) continue;
        if (((xrd_rss_tbl[i] >> 24) & 0xff) >= NFD_MAX_PF_QUEUES) continue;
        xwr_nn_info[i] = xrd_rss_tbl[i];
    }

    /* Write at NN register start_offset for all worker MEs */
    upd_nn_table_instr(xwr_nn_info,  start_offset,
                        NFP_NET_CFG_RSS_ITBL_SZ_wrd);

    return;
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

#define ACTION_RSS_IPV6_TCP_BIT 0
#define ACTION_RSS_IPV6_UDP_BIT 1
#define ACTION_RSS_IPV4_TCP_BIT 2
#define ACTION_RSS_IPV4_UDP_BIT 3

/* Set RSS flags by matching what is used in the workers */
__intrinsic uint32_t
extract_rss_flags(uint32_t rss_ctrl)
{
    uint32_t rss_flags = 0;

    // Driver does L3 unconditionally, so we only care about L4 combinations

    if (rss_ctrl & NFP_NET_CFG_RSS_IPV4_TCP)
        rss_flags |= (1 << ACTION_RSS_IPV4_TCP_BIT);

    if (rss_ctrl & NFP_NET_CFG_RSS_IPV4_UDP)
        rss_flags |= (1 << ACTION_RSS_IPV4_UDP_BIT);

    if (rss_ctrl & NFP_NET_CFG_RSS_IPV6_TCP)
        rss_flags |= (1 << ACTION_RSS_IPV6_TCP_BIT);

    if (rss_ctrl & NFP_NET_CFG_RSS_IPV6_UDP)
        rss_flags |= (1 << ACTION_RSS_IPV6_UDP_BIT);

    return rss_flags;
}


#define SET_PIPELINE_BIT(prev, current) \
    ((current) - (prev) == 1) ? 1 : 0;

/*vnic_port == vid */
__intrinsic void
app_config_port(uint32_t vid, uint32_t control, uint32_t update)
{
    __emem __addr40 uint8_t *bar_base = NFD_CFG_BAR_ISL(NIC_PCI, vid);
    __xread uint32_t rss_ctrl[2];
    __xread uint32_t mtu;
    __xread uint32_t nic_mac[2];
    __xread uint32_t rss_key[NFP_NET_CFG_RSS_KEY_SZ / sizeof(uint32_t)];
    __xwrite uint32_t xwr_instr[NIC_MAX_INSTR];
    __xread uint32_t rx_rings[2];
    __lmem union instruction_format instr[NIC_MAX_INSTR];
    SIGNAL sig1, sig2;
    uint32_t rss_flags, rss_rings;
    uint32_t rss_tbl_nnidx;
    uint32_t byte_off;
    uint32_t count;
    uint32_t type, vnic;
    uint32_t prev_instr = 0;
    __xwrite uint32_t dbg;
    __imem struct nic_port_stats_extra *nic_stats_extra =
        (__imem struct nic_port_stats_extra *) __link_sym("_nic_stats_extra");

    reg_zero(instr, sizeof(instr));
    count = 0;

    NFD_VID2VNIC(type, vnic, vid);
    if (type == NFD_VNIC_TYPE_CTRL) {
		/* CTRL vnic instruction */
#ifdef GEN_INSTRUCTION
        instr[0].instr = instr_tbl[INSTR_CMSG];
#else
        instr[0].instr = INSTR_CMSG;
#endif
        reg_cp(xwr_instr, (void *)instr, 4);
        byte_off = NIC_PORT_TO_PCIE_INDEX(NIC_PCI, type, vnic, 0) * NIC_MAX_INSTR;
        upd_rx_host_instr(xwr_instr, byte_off<<2, 1, 1);
        return;
    }

    /*
     * RX HOST --> TX WIRE
     */

    /* mtu */
    mem_read32(&mtu, (__mem void*)(bar_base + NFP_NET_CFG_MTU), sizeof(mtu));
#ifdef GEN_INSTRUCTION
    instr[count].instr = instr_tbl[INSTR_MTU];
#else
    instr[count].instr = INSTR_MTU;
#endif
    // add eth hdrlen, plus one to cause borrow on subtract of MTU from pktlen
    instr[count].param = mtu + NET_ETH_LEN + 1;
    instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_MTU);
    prev_instr = INSTR_MTU;

    /* tx wire */
#ifdef GEN_INSTRUCTION
    instr[count].instr = instr_tbl[INSTR_TX_WIRE];
#else
    instr[count].instr = INSTR_TX_WIRE;
#endif
    instr[count].param = NS_PLATFORM_NBI_TM_QID_LO(vnic);
    instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_TX_WIRE);
    prev_instr = INSTR_TX_WIRE;

    reg_cp(xwr_instr, (void *)instr, NIC_MAX_INSTR<<2);

    /* write TX instr to local table and to other islands too */
    byte_off = NIC_PORT_TO_PCIE_INDEX(NIC_PCI, type, vnic, 0) * NIC_MAX_INSTR;
    upd_rx_host_instr(xwr_instr, byte_off<<2, count, NUM_PCIE_Q_PER_PORT);

    /*
     * RX WIRE --> TX HOST
     */
    count = 0;
    prev_instr = 0;
    reg_zero(instr, sizeof(instr));

#ifdef GEN_INSTRUCTION
    instr[count].instr = instr_tbl[INSTR_MTU];
#else
    instr[count].instr = INSTR_MTU;
#endif
    // add eth hdrlen, plus one to cause borrow on subtract of MTU from pktlen
    instr[count].param = mtu + NET_ETH_LEN + 1;
    instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_MTU);
    prev_instr = INSTR_MTU;

    if (!(control & NFP_NET_CFG_CTRL_PROMISC)) {
        /* MAC address */
        mem_read64(nic_mac, (__mem void*)(bar_base + NFP_NET_CFG_MACADDR),
                    sizeof(nic_mac));
#ifdef GEN_INSTRUCTION
        instr[count].instr = instr_tbl[INSTR_MAC];
#else
        instr[count].instr = INSTR_MAC;
#endif
        instr[count].param = (nic_mac[0] >> 16);
        instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_MAC);
        prev_instr = INSTR_MAC;
        instr[count++].value = (nic_mac[0] << 16) | (nic_mac[1] >> 16);
    }

    if (control & NFP_NET_CFG_CTRL_BPF) {
        instr[count].param = NFD_BPF_START_OFF + vnic * NFD_BPF_MAX_LEN;
#ifdef GEN_INSTRUCTION
        instr[count++].instr = instr_tbl[INSTR_EBPF];
#else
        instr[count++].instr = INSTR_EBPF;
#endif
        prev_instr = INSTR_EBPF;
    }

    /* RSS */
    if (control & NFP_NET_CFG_CTRL_RSS_ANY) {

        /* RSS remapping table with NN register index as start offset */
        rss_tbl_nnidx = vnic * NFP_NET_CFG_RSS_ITBL_SZ_wrd;

        /* Udate the RSS NN table but only if RSS has changed
        * If vnic_port x write at x*32 NN register */
        if (update & NFP_NET_CFG_UPDATE_RSS) {
            upd_rss_table(rss_tbl_nnidx, bar_base, vnic);
        }

        /* RSS flags: read rss_ctrl but only first word is used */
        __mem_read64(rss_ctrl, bar_base + NFP_NET_CFG_RSS_CTRL,
                sizeof(rss_ctrl), sizeof(rss_ctrl), sig_done, &sig1);
        __mem_read64(rss_key, bar_base + NFP_NET_CFG_RSS_KEY,
                NFP_NET_CFG_RSS_KEY_SZ, NFP_NET_CFG_RSS_KEY_SZ,
                sig_done, &sig2);
        wait_for_all(&sig1, &sig2);

        mem_read64(rx_rings, (__mem void*)(bar_base + NFP_NET_CFG_RXRS_ENABLE), sizeof(uint64_t));
        rss_rings = (~rx_rings[0]) ? ffs(~rx_rings[0]) : 32 + ffs(~rx_rings[1]);
        rss_flags = extract_rss_flags(rss_ctrl[0]);

#ifdef GEN_INSTRUCTION
        instr[count].instr = instr_tbl[INSTR_RSS];
#else
        instr[count].instr = INSTR_RSS;
#endif
        instr[count].param = (rss_tbl_nnidx << 8) | (rss_flags & 0x0f);
		if ((NFD_CFG_MAJOR_PF < 4) && !(control & NFP_NET_CFG_CTRL_CHAIN_META)) {
            instr[count].param |= (1 << INSTR_RSS_V1_META_BIT);
        }
        instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_RSS);
        prev_instr = INSTR_RSS;

        /* RSS key: provide rss key with hash. Use only first 26 bits */
        instr[count++].value = (rss_key[0] & ~0x3fu) | (rss_rings - 1);
    }

    if (control & NFP_NET_CFG_CTRL_CSUM_COMPLETE) {
        /* calculate checksum and drop if mismatch */
#ifdef GEN_INSTRUCTION
        instr[count].instr = instr_tbl[INSTR_CHECKSUM_COMPLETE];
#else
        instr[count].instr = INSTR_CHECKSUM_COMPLETE;
#endif
        instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_CHECKSUM_COMPLETE);
        prev_instr = INSTR_CHECKSUM_COMPLETE;
    }
    else if (control & NFP_NET_CFG_CTRL_RXCSUM) {
#ifdef GEN_INSTRUCTION
        instr[count].instr = instr_tbl[INSTR_RXCSUM];
#else
        instr[count].instr = INSTR_RXCSUM;
#endif
        instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_RXCSUM);
        prev_instr = INSTR_RXCSUM;
    }

#ifdef GEN_INSTRUCTION
    instr[count].instr = instr_tbl[INSTR_TX_HOST];
#else
    instr[count].instr = INSTR_TX_HOST;
#endif
    instr[count].param = NFD_VID2QID(vid, 0);
    instr[count++].pipeline = SET_PIPELINE_BIT(prev_instr, INSTR_TX_HOST);
    prev_instr = INSTR_TX_HOST;

    reg_cp(xwr_instr, (void *)instr, NIC_MAX_INSTR<<2);

    /* map vnic_port to NBI index in the instruction table */
    byte_off = NIC_PORT_TO_NBI_INDEX(NIC_NBI, vnic) * NIC_MAX_INSTR;

    /* write TX instr to local table and to other islands too */
    upd_rx_wire_instr(xwr_instr, byte_off<<2, count);

#ifdef APP_CONFIG_DEBUG
    {
        union debug_instr_journal data;
        data.value = 0x00;
        data.event = PORT_CFG;
        data.param = vid;
        JDBG(app_debug_jrn, data.value);
    }
#endif

    return;
}


__intrinsic void
app_config_port_down(uint32_t vid)
{
    __xwrite union instruction_format xwr_instr;
    uint32_t i;
    uint32_t byte_off;
    uint32_t type, vnic;

    /* TX drop instr
     * Probably should use the instr field in union but cannot do that with
     * xfer, must first do it in GPR and then copy to xfer which is an overkill
     */
#ifdef GEN_INSTRUCTION
    xwr_instr.value = (instr_tbl[INSTR_TX_DROP] << INSTR_OPCODE_LSB);
#else
    xwr_instr.value = (INSTR_TX_DROP << INSTR_OPCODE_LSB);
#endif

    /* write drop instr to local host table */
	/* do nothing for CTRL vNIC */
    NFD_VID2VNIC(type, vnic, vid);
    if (type == NFD_VNIC_TYPE_PF) {
    	byte_off = NIC_PORT_TO_PCIE_INDEX(NIC_PCI, type, vnic, 0) * NIC_MAX_INSTR;
    	upd_rx_host_instr(&xwr_instr.value, byte_off << 2, 1, NUM_PCIE_Q_PER_PORT);

    	/* write drop instr to local wire table */
    	byte_off = NIC_PORT_TO_NBI_INDEX(NIC_NBI, vnic) * NIC_MAX_INSTR;
    	upd_rx_wire_instr(&xwr_instr.value, byte_off << 2, 1);

#ifdef APP_CONFIG_DEBUG
    	{
        	union debug_instr_journal data;
        	data.value = 0x00;
        	data.event = PORT_DOWN;
        	data.param = vnic_port;
        	JDBG(app_debug_jrn, data.value);
    	}
#endif
    }

    return;
}


