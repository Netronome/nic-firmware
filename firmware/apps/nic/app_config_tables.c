/*
 * Copyright 2014-2017 Netronome, Inc.
 *
 * @file          app_master_main.c
 * @brief         ME serving as the NFD NIC application master.
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
#include <nfp/macstats.h>
#include <nfp/remote_me.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_mac.h>
#include <nfp6000/nfp_me.h>
#include <nfp/cls.h>

#include <std/synch.h>
#include <std/reg_utils.h>
#include "nfd_user_cfg.h"
#include <vnic/shared/nfd_cfg.h>
#include <vnic/pci_in.h>
#include <vnic/pci_out.h>

#include <shared/nfp_net_ctrl.h>

#include <link_state/link_ctrl.h>
#include <link_state/link_state.h>

#include <npfw/catamaran_app_utils.h>

#include <vnic/nfd_common.h>

#include <infra_basic/infra_basic.h>
#include <nic_basic/nic_basic.h>
#include "app_config_tables.h"


/*
 * Global declarations for configuration change management
 */

/* Islands to configure. */

#ifndef APP_WORKER_ISLAND_LIST
    #error "The list of application Island IDd must be defined"
#else
    __shared __lmem uint32_t app_isl_ids[] = {APP_WORKER_ISLAND_LIST};
#endif


#ifndef APP_MES_LIST
    #error "The list of application MEs IDd must be defined"
#else
    __shared __lmem uint32_t cfg_mes_ids[] = {APP_MES_LIST};
#endif


#define MAX_NN_WRITE    14

#define APP_CONFIG_DEBUG

#define NIC_NBI         0

/* use macros to map input VNIC port to index in table */
#define NIC_PORT_TO_PCIE_INDEX(pcie, vport, queue) \
        ((pcie << 6) | (NFD_BUILD_QID((vport), (queue)) & 0x3f))

#define NIC_PORT_TO_NBI_INDEX(nbi, vport) \
        (NIC_NBI_ENTRY_START + ((nbi << 6) | (vport & 0x3f)))

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
#endif

#ifdef APP_CONFIG_DEBUG
__export __emem __addr40 uint32_t debug_rss_table[100];
#endif

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
 * These instructions are configured in NIC_CFG_INSTR_TBL table.
 * This table contains both instructions for host rx and wire rx.
 * Host rx instructions are configured from index 0..number of PCIE islands *
 * number of PCIe queues. I.e. one PCIe island with 64 PCIe queues.
 * Wire rx instructions are configured from index
 * NUM_PCIE*NUM_PCIE_Q .. NUM_PCIE*NUM_PCIE_Q + #NBI*#NBI channels.
 *
 */

/** Enum for addressing mode.  */
typedef enum CLUSTER_TARGET_ADDRESS_MODE
{
    CT_ADDRESS_MODE_INDEX               = 0x00,     /**< NN register FIFO mode is used. */
    CT_ADDRESS_MODE_ABSOLUTE            = 0x01      /**< NN register number specified is the first to be written to.   */
}  CLUSTER_TARGET_ADDRESS_MODE;



typedef union ct_nn_write_format
{
    struct
    {
        unsigned int reserved_3                         : 2;    /**< Reserved. */
        unsigned int remote_island                      : 6;    /**< Island id of remote master. */
        unsigned int reserved_2                         : 3;    /**< Reserved. */
        unsigned int master                             : 4;    /**< Master within specified island. See NFP-6xxx Pull IDs in 6xxx databook. */
        unsigned int signal_number                      : 7;    /**< If non-zero, signal number to send to the ME on completion. */
        CLUSTER_TARGET_ADDRESS_MODE address_mode        : 1;    /**< Address mode: 0 = NN register FIFO mode, 1 = absolute mode.*/
        unsigned int NN_register_number                 : 7;    /**< Next neighbour register number. */
        unsigned int reserved_1                         : 2;    /**< Reserved. */
    };
    unsigned int value;                                         /**< Accessor to entire lookup detail structure. */
} ct_nn_write_format;


__intrinsic
void ct_nn_write(
    __xwrite void *xfer,
    volatile ct_nn_write_format *address,
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
            ct[ctnn_write, *xfer, address_val, 0, __ct_const_val(count)], sig_done[*sig_ptr], indirect_ref
        }
    } else {
        __asm
        {
            alu[--, --, B, ind.__raw]
            ct[ctnn_write, *xfer, address_val, 0, __ct_const_val(count)], ctx_swap[*sig_ptr], indirect_ref
        }
    }
}


/* Write the RSS table to NN registers for all MEs */
__intrinsic void
upd_rss_table_instr(__xwrite uint32_t *xwr_instr, uint32_t start_offset, uint32_t count)
{
    SIGNAL sig;
    uint32_t i;
    ct_nn_write_format    command;

    command.value = 0;
    command.signal_number = 0x0;
    command.address_mode = CT_ADDRESS_MODE_ABSOLUTE;
    command.NN_register_number = start_offset;

    for(i = 0; i < sizeof(cfg_mes_ids)/sizeof(uint32_t); i++) {
        command.remote_island = cfg_mes_ids[i] >> 4;
        command.master = cfg_mes_ids[i] & 0x0f;
        ct_nn_write(xwr_instr, &command, count, ctx_swap, &sig);
    }
}


/* Update RX wire instruction */
__intrinsic void
upd_rx_wire_instr(__xwrite uint32_t *xwr_instr,
                   uint32_t start_offset, uint32_t count)
{
    __cls __addr32 void *nic_cfg_instr_tbl = (__cls __addr32 void*)
                                        __link_sym("NIC_CFG_INSTR_TBL");
    SIGNAL last_sig;
    uint32_t addr_hi;
    uint32_t addr_lo;
    uint32_t isl;
    struct nfp_mecsr_prev_alu ind;

    ind.__raw = 0;
    ind.ov_len = 1;
    ind.length = count - 1;
    __asm {
        alu[--, --, B, ind.__raw]
        cls[write, *xwr_instr, nic_cfg_instr_tbl, start_offset, \
                __ct_const_val(count)], sig_done[last_sig], indirect_ref
    }
    wait_for_all(&last_sig);

    for (isl= 0; isl< sizeof(app_isl_ids)/sizeof(uint32_t); isl++) {
        addr_lo = (uint32_t)nic_cfg_instr_tbl + start_offset;
        addr_hi = app_isl_ids[isl] >> 4; // only use island, mask out ME
        addr_hi = (addr_hi << (40 - 8 - 6));

        /* last write */
        ind.__raw = 0;
        ind.ov_len = 1;
        ind.length = count - 1;
        __asm {
            alu[--, --, B, ind.__raw]
            cls[write, *xwr_instr, addr_hi, <<8, addr_lo, \
                    __ct_const_val(count)], sig_done[last_sig], indirect_ref
        }
        wait_for_all(&last_sig);

    }
    return;
}

/* Update RX wire instruction */
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

    for (i = 0; i < NUM_PCIE_Q_PER_PORT - 1; i++)
    {
        /* write to CLS without a signal. We will wait for signal on the last
         * write */
        __asm cls[write, *xwr_instr, nic_cfg_instr_tbl, byte_off, \
                    __ct_const_val(count)]
        byte_off += (NIC_MAX_INSTR<<2);
    }

    /* last write */
    __asm cls[write, *xwr_instr, nic_cfg_instr_tbl, byte_off, \
                __ct_const_val(count)], sig_done[last_sig]

    wait_for_all(&last_sig);

    /* Propagate to all worker isls */

    for (isl= 0; isl< sizeof(app_isl_ids)/sizeof(uint32_t); isl++) {
        addr_lo = (uint32_t)nic_cfg_instr_tbl + start_offset;
        addr_hi = app_isl_ids[isl] >> 4; // only use island, mask out ME
        addr_hi = (addr_hi << (40 - 8 - 6));


        for (i = 0; i < NUM_PCIE_Q_PER_PORT - 1; i++)
        {
            /* write to CLS without a signal. We will wait for signal on the last
            * write */
            __asm cls[write, *xwr_instr, addr_hi, <<8, addr_lo, \
                        __ct_const_val(count)]
            addr_lo += (NIC_MAX_INSTR<<2);
        }

        /* last write */
        __asm cls[write, *xwr_instr, addr_hi, <<8, addr_lo, \
                    __ct_const_val(count)], sig_done[last_sig]
        wait_for_all(&last_sig);
    }
    return;
}

#define NFP_NET_CFG_RSS_ITBL_SZ_wrd (NFP_NET_CFG_RSS_ITBL_SZ >> 2)
__intrinsic void
upd_rss_table(uint32_t start_offset, __emem __addr40 uint8_t *bar_base)
{
    __xread uint32_t xrd_rss_tbl[(NFP_NET_CFG_RSS_ITBL_SZ_wrd / 2)];
    __xwrite uint32_t xwr_nn_info[(NFP_NET_CFG_RSS_ITBL_SZ_wrd / 2)];
    uint32_t count = NFP_NET_CFG_RSS_ITBL_SZ_wrd/2;

    /*Update RSS table to NN registers of MEs */

    /* Read/write first half (16 words) */
    mem_read32_swap(xrd_rss_tbl,
                    bar_base + NFP_NET_CFG_RSS_ITBL,
                    sizeof(xrd_rss_tbl));
    reg_cp(xwr_nn_info, xrd_rss_tbl, sizeof(xrd_rss_tbl));

    /* We can only write 16 words with NN write.
     * If vnic_port 0, write at NN register offset 0,
     * if vnic_port 1, write at NN register offset 1*RSS_table size (32)
     */
    upd_rss_table_instr(xwr_nn_info, start_offset, count);

#ifdef APP_CONFIG_DEBUG
    mem_write32(xwr_nn_info, debug_rss_table + start_offset, count<<2);
#endif

    /* Read/write second half */
    start_offset += count;
    mem_read32_swap(xrd_rss_tbl,
                    bar_base + NFP_NET_CFG_RSS_ITBL + sizeof(xrd_rss_tbl),
                    sizeof(xrd_rss_tbl));

    reg_cp(xwr_nn_info, xrd_rss_tbl, sizeof(xrd_rss_tbl));
    upd_rss_table_instr(xwr_nn_info,  start_offset, count);
#ifdef APP_CONFIG_DEBUG
    mem_write32(xwr_nn_info, debug_rss_table + start_offset, count<<2);
#endif

    return;
}

/* Set RSS flags but matching what is used in the workers */
__intrinsic uint32_t
extract_rss_flags(uint32_t rss_ctrl)
{
    uint32_t rss_flags = (rss_ctrl &
                        (NFP_NET_CFG_RSS_IPV4 | NFP_NET_CFG_RSS_IPV6));

    if (rss_ctrl & NFP_NET_CFG_RSS_IPV4_TCP)
        rss_flags |= (NIC_RSS_IP4 | NIC_RSS_TCP);
    if (rss_ctrl & NFP_NET_CFG_RSS_IPV4_UDP)
        rss_flags |= (NIC_RSS_IP4 | NIC_RSS_UDP);
    if (rss_ctrl & NFP_NET_CFG_RSS_IPV6_TCP)
        rss_flags |= (NIC_RSS_IP6 | NIC_RSS_TCP);
    if (rss_ctrl & NFP_NET_CFG_RSS_IPV6_UDP)
        rss_flags |= (NIC_RSS_IP6 | NIC_RSS_UDP);

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
    __xwrite uint32_t xwr_instr[16];
    __gpr uint32_t instr[16];
    uint32_t rss_flags;
    uint32_t byte_off;
    uint32_t mask;
    uint32_t count;

    __cls __addr32 void *nic_cfg_instr_tbl = (__cls __addr32 void*)
                                        __link_sym("NIC_CFG_INSTR_TBL");

#ifdef APP_CONFIG_DEBUG
    {
        union debug_instr_journal data;
        data.value = 0x00;
        data.event = PORT_CFG;
        data.param = vnic_port;

        /* Log the data to the ring */
        JDBG(app_debug_jrn, data.value);
    }
#endif

    count = 2;
    /* mtu */
    mem_read32(&mtu, (__mem void*)(bar_base + NFP_NET_CFG_MTU),
                   sizeof(mtu));
    instr[0] = (INSTR_MTU << 16) | mtu;
    instr[1] = (INSTR_TX_WIRE << 16) | PKT_WIRE_PORT(NIC_NBI, vnic_port);
    reg_cp(xwr_instr, (void *)instr, count<<2);

    byte_off = NIC_PORT_TO_PCIE_INDEX(NIC_PCI, vnic_port, 0)
            * NIC_MAX_INSTR * NUM_PCIE_Q_PER_PORT;

     /* write TX instr to local table and to other islands too */
    upd_rx_host_instr (xwr_instr, byte_off<<2, count);

#ifdef APP_CONFIG_DEBUG
    {
        union debug_instr_journal data;
        data.value = 0x00;
        data.event = MTU;
        data.param = mtu;

        /* Log the data to the ring */
        JDBG(app_debug_jrn, data.value);
    }
#endif

    /* mtu already setup for update rx host */
    count = 1;

    /* MAC address */
    mem_read64(nic_mac, (__mem void*)(bar_base + NFP_NET_CFG_MACADDR),
                sizeof(nic_mac));
    instr[count++] = (INSTR_MAC << 16) | (nic_mac[0] >> 16);
    instr[count++] = (nic_mac[0] << 16) | (nic_mac[1] >> 16);

    if (control & NFP_NET_CFG_CTRL_RSS) {

        /* First update the RSS NN table but only if RSS has changed */
        if (update & NFP_NET_CFG_UPDATE_RSS) {
            upd_rss_table(vnic_port*NFP_NET_CFG_RSS_ITBL_SZ_wrd, bar_base);
        }

        /* read rss_ctrl but only first word is used */
        mem_read64(rss_ctrl, bar_base + NFP_NET_CFG_RSS_CTRL,
                sizeof(rss_ctrl));
        rss_flags = extract_rss_flags(rss_ctrl[0]);
        instr[count++] = (INSTR_EXTRACT_KEY_WITH_RSS << 16)
                        | (rss_flags >> 16);
        instr[count++] = (rss_flags << 16);
        mask = rss_ctrl[0];

        /* provide rss key with hash */
        mem_read64(rss_key, bar_base + NFP_NET_CFG_RSS_KEY,
                NFP_NET_CFG_RSS_KEY_SZ);
        instr[count++] = (INSTR_RSS_CRC32_HASH_WITH_KEY << 16)
                        | (rss_key[0] >> 16);
        instr[count++] = (rss_key[0] << 16) | (rss_key[1] >> 16);
        instr[count++] = (rss_key[1] << 16);

        /* RSS table with NN register index as start offset */
        instr[count++] = (INSTR_RSS_TABLE << 16) | (vnic_port*NFP_NET_CFG_RSS_ITBL_SZ_wrd);

        /* mask fits into 16 bits as rss_ctrl is masked with 0x7f) */
        mask = NFP_NET_CFG_RSS_MASK_of(mask);
        instr[count++] = (INSTR_SEL_RSS_QID_WITH_MASK << 16) | (mask);

        instr[count++] = (INSTR_CHECKSUM_COMPLETE << 16);
        instr[count++] = (INSTR_TX_HOST<<16) | PKT_HOST_PORT(NIC_PCI, vnic_port, 0);
        reg_cp(xwr_instr, instr, count << 2);

#ifdef APP_CONFIG_DEBUG
        {
            union debug_instr_journal data;
            data.value = 0x00;
            data.event = RSS_HI;
            data.param = rss_ctrl[0] >> 16;

            /* Log the data to the ring */
            JDBG(app_debug_jrn, data.value);

            data.event = RSS_LO;
            data.param = rss_ctrl[0];

            /* Log the data to the ring */
            JDBG(app_debug_jrn, data.value);
        }
#endif

    } else {
        instr[count++] = (INSTR_TX_HOST<<16) | PKT_HOST_PORT(NIC_PCI, vnic_port, 0);
        reg_cp(xwr_instr, (void *)instr, count<<2);
    }

    byte_off = NIC_PORT_TO_NBI_INDEX(NIC_NBI, vnic_port) * NIC_MAX_INSTR;

    /* write TX instr to local table and to other islands too */
    upd_rx_wire_instr(xwr_instr, byte_off<<2, count);

    return;
}


__intrinsic void
app_config_port_down(uint32_t vnic_port)
{

    __xwrite uint32_t xwr_instr[2];
    __gpr uint32_t instr;
    uint32_t i;
    uint32_t byte_off;
    SIGNAL last_sig;
    __cls __addr32 void *nic_cfg_instr_tbl = (__cls __addr32 void*)
                                        __link_sym("NIC_CFG_INSTR_HOST_TBL");
    __cls __addr32 void *nic_cfg_instr_wire_tbl = (__cls __addr32 void*)
                                        __link_sym("NIC_CFG_INSTR_WIRE_TBL");

    /* TX drop instr for host port lookup */
    /* MTU */
    instr = (INSTR_TX_DROP << 16) | PKT_DROP_WIRE;
    xwr_instr[0] = instr;
    xwr_instr[1] = 0x00;

    byte_off = NIC_PORT_TO_PCIE_INDEX(NIC_PCI, vnic_port, 0)*NIC_MAX_INSTR*NUM_PCIE_Q_PER_PORT;

    /* write drop instr to local host table */
    upd_rx_host_instr (&xwr_instr[0], byte_off << 2, 2);

    /* write drop instr to local wire table */
    instr = (INSTR_TX_DROP << 16) | PKT_DROP_HOST;
    xwr_instr[0] = instr;
    byte_off = NIC_PORT_TO_NBI_INDEX(NIC_NBI, vnic_port) * NIC_MAX_INSTR;

    upd_rx_wire_instr(&xwr_instr[0], byte_off << 2, 2);

#ifdef APP_CONFIG_DEBUG
    {
        union debug_instr_journal data;
        data.value = 0x00;
        data.event = PORT_DOWN;
        data.param = vnic_port;

        /* Log the data to the ring */
        JDBG(app_debug_jrn, data.value);
    }
#endif

    return;
}


