/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file   lib/npfw/_c/catamaran_utils.c
 * @brief  ME-based interface for configuring Catamaran NPFW
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#include <assert.h>
#include <nfp/cls.h>
#include <nfp/xpb.h>
#include <nfp6000/nfp_cls.h>
#include <nfp6000/nfp_nbi_pc.h>

#include <npfw/catamaran_utils.h>
#include <npfw/nbipc_mem.h>


/* Catamaran configuration helper macros, typedefs and global variables. */

/* Address of the NBI Preclassifier Picoengine Setup register. */
#define NBIPC_PE_SETUP_ADDR(_nbi)                                    \
    (NFP_NBI_PC_XPB_OFF(_nbi) | NFP_NBI_PC_PE | NFP_NBI_PC_PE_SETUP)

/* Address of the Catamaran MAC match lookup scalar. */
#define CTMRN_CFG_MAC_MATCH_HASH_ADDR                                 \
    ((CATAMARAN_CFG_TABLE_BASE0 |                                     \
      CATAMARAN_CFG_LOC_ADDR(CATAMARAN_CFG_MAC_MATCH_HASH_OFF)) << 4)
/* Offset of the Catamaran MAC match lookup scalar. */
// TODO - FIX ME
//#define CTMRN_CFG_MAC_MATCH_HASH_OFF                                 \
//    CATAMARAN_CFG_DATA_ENTRY_8_OFF(CATAMARAN_CFG_MAC_MATCH_HASH_OFF)
#define CTMRN_CFG_MAC_MATCH_HASH_OFF                 \
    ((CATAMARAN_CFG_MAC_MATCH_HASH_OFF & 0xF) ^ 0x8)

/** Structure for storing the Catamaran lookup hash settings. */
struct ctmrn_hash_settings {
    uint8_t mac_match_scalar; /** MAC match hash scalar. */
};

__shared __lmem struct ctmrn_hash_settings ctmrn_hash_cfg;


/* Catamaran channel-to-port table helper macros. */

#define CTMRN_CHAN2PORT_ENTRY_MASK (CATAMARAN_CHAN_ENTRIES_PER_LOC - 1)
#define CTMRN_CHAN2PORT_ENTRY_READ(_data, _off)            \
    ((_data[(_off) >> 2] >> (((_off) & 0x3) << 3)) & 0xFF)
#define CTMRN_CHAN2PORT_ENTRY_WRITE(_data, _off, _val)                \
    do {                                                              \
        _data[(_off) >> 2] &= ~(0xFF << (((_off) & 0x3) << 3));       \
        _data[(_off) >> 2] |= (_val & 0xFF) << (((_off) & 0x3) << 3); \
    } while (0)


/* Catamaran MAC match table helper macros, typedefs and global variables. */

#define CTMRN_MAC_MATCH_ADDR_MASK (CATAMARAN_MAC_TABLE_SIZE - 1)

/** Structure for the Catamaran MAC match table entry. */
struct ctmrn_mac_match_table_entry {
    union {
        struct {
            uint32_t mac_addr1_hi;
            uint16_t mac_addr1_lo;
            unsigned result1:16;
            uint32_t mac_addr0_hi;
            uint16_t mac_addr0_lo;
            unsigned result0:16;
        };
        uint32_t __raw[4];
    };
};

/** Mask for MAC match hash. */
// TODO - FIX ME
//__shared __cls uint64_t ctmrn_mac_match_mask = CATAMARAN_MAC_KEY_MASK;
__shared __cls uint64_t ctmrn_mac_match_mask = 0xFFFFFFFF0000FFFFull;

/** Local copy of the CLS hash settings to use with Catamaran. */
__shared __lmem struct nfp_cls_hash_mult ctmrn_cls_hash_mult;


/* Generic helper macros and global variables for the CLS hash. */

/** Mask for initializing the hash index/residue. */
__shared __cls uint64_t init_cls_hash_mask = 0xFFFFFFFFFFFFFFFFull;

/** Local copy of the CLS hash settings to use when initializing the hash. */
__shared __lmem struct nfp_cls_hash_mult init_cls_hash_mult;


/* Generic helper functions. */

__intrinsic static uint64_t
swap64(uint64_t x)
{
    uint64_t v = (x >> 32);
    return v | (x << 32);
}


/* Catamaran helper functions. */

__inline static void
catamaran_cls_hash_init(unsigned int nbi)
{
    __gpr struct nfp_nbi_pc_pe_setup pe_setup;
    __xread uint32_t                 cls_hash_mult_xr;

    /* Read the hash configuration from the NBI. */
    pe_setup.__raw = xpb_read(NBIPC_PE_SETUP_ADDR(nbi));

    /* Store the CLS settings needed for the Catamaran hash operations. */
    cls_read(&cls_hash_mult_xr, (__cls void *)NFP_CLS_HASH_MULT,
             sizeof(cls_hash_mult_xr));

    ctmrn_cls_hash_mult.__raw     = cls_hash_mult_xr;
    ctmrn_cls_hash_mult.sboxen    = pe_setup.hashsboxen;
    ctmrn_cls_hash_mult.numsboxes = pe_setup.hashsbox;
    ctmrn_cls_hash_mult.m63       = (pe_setup.hashmult >> 3) & 0x1;
    ctmrn_cls_hash_mult.m53       = (pe_setup.hashmult >> 2) & 0x1;
    ctmrn_cls_hash_mult.m36       = (pe_setup.hashmult >> 1) & 0x1;
    ctmrn_cls_hash_mult.m4        =  pe_setup.hashmult       & 0x1;

    init_cls_hash_mult.__raw      = cls_hash_mult_xr;
    init_cls_hash_mult.sboxen     = 0;
    init_cls_hash_mult.numsboxes  = 0;
    init_cls_hash_mult.m63        = 0;
    init_cls_hash_mult.m53        = 0;
    init_cls_hash_mult.m36        = 0;
    init_cls_hash_mult.m4         = 0;
}


__inline static void
catamaran_config_read(unsigned int nbi)
{
    __lmem uint8_t cfg_entry[NBIPC_MEM_ENTRY_SIZE];

    /* Store the MAC match hash scalar. */
    nbipc_pelm2lmem_copy(nbi, CTMRN_CFG_MAC_MATCH_HASH_ADDR, cfg_entry,
                         sizeof(cfg_entry));

    ctmrn_hash_cfg.mac_match_scalar = cfg_entry[CTMRN_CFG_MAC_MATCH_HASH_OFF];
}


/**
 * Calculate the address of the Catamaran MAC match entry.
 */
__inline static uint32_t
catamaran_mac_match_hash_calc(unsigned int hash_idx, uint64_t mac_addr)
{
    __xread uint64_t  result_xr;
    __xwrite uint32_t temp_mult_xw = init_cls_hash_mult.__raw;
    __xwrite uint64_t temp_hash_xw = swap64(ctmrn_hash_cfg.mac_match_scalar);

    /* Initialize the hash for the MAC match lookup. */
    /*
     * Note: Because the CLS hash index/residue is not directly write-able, it
     *       must be set via a hash operation.  The easiest way to place a
     *       value into the hash index/residue is to disable all sboxes and
     *       multipliers, and then hashing the desired value with the initial
     *       hash index/residue cleared to zero.  This should result in the
     *       desired value being placed into the hash index/residue.
     */
    cls_write(&temp_mult_xw, (__cls void *)NFP_CLS_HASH_MULT,
              sizeof(temp_mult_xw));
    cls_hash_mask_clr(&temp_hash_xw, &init_cls_hash_mask, sizeof(temp_hash_xw),
                      hash_idx);

    /* Use the entire 48-bit MAC address to calculate the entry address. */
    temp_mult_xw = ctmrn_cls_hash_mult.__raw;
    cls_write(&temp_mult_xw, (__cls void *)NFP_CLS_HASH_MULT,
              sizeof(temp_mult_xw));

    temp_hash_xw = swap64(CATAMARAN_MAC_HASH_KEY(mac_addr));
    cls_hash_mask(&temp_hash_xw, &ctmrn_mac_match_mask, sizeof(temp_hash_xw),
                  hash_idx);

    cls_read(&result_xr, (__cls void *)NFP_CLS_HASH_IDX64(hash_idx),
             sizeof(result_xr));

    return (swap64(result_xr) & CTMRN_MAC_MATCH_ADDR_MASK);
}


/* Catamaran initialization functions. */

void
catamaran_support_setup(unsigned int nbi)
{
    /* Setup the Catamaran hash scalars for the table lookups. */
    catamaran_config_read(nbi);

    /* Setup the local CLS hash for configuring Catamaran. */
    catamaran_cls_hash_init(nbi);
}


/* Catamaran channel-to-port table functions. */

void
catamaran_chan2port_table_get(unsigned int nbi, unsigned int chan_start,
                              unsigned int chan_end,
                              __lmem struct catamaran_chan2port_entry *entries)
{
    int chan;
    int last_chan;
    uint32_t addr;
    uint32_t block;
    __lmem uint32_t data[4];
    int chan_cnt             = chan_end - chan_start + 1;
    int first_chan           = chan_start & CTMRN_CHAN2PORT_ENTRY_MASK;
    uint32_t block_end       = CATAMARAN_CHAN_LOC_ADDR(chan_end);
    uint32_t block_start     = CATAMARAN_CHAN_LOC_ADDR(chan_start);
    unsigned int entry_cnt   = 0;

    try_ctassert(chan_start < CATAMARAN_CHAN_NUM_CHANS);
    try_ctassert(chan_end < CATAMARAN_CHAN_NUM_CHANS);

    /* Check if any channels are being retrieved. */
    if (chan_cnt <= 0)
        return;

    /* Retrieve the channels one block at a time. */
    for (block = block_start; block <= block_end; ++block) {
        /* Retrieve the block of channels. */
        addr = (CATAMARAN_CHAN_TABLE_BASE0 + block) << 4;

        nbipc_pelm2lmem_copy(nbi, addr, data, sizeof(data));

        /* Extract the info for each channel. */
        last_chan =
            (chan_cnt < (CATAMARAN_CHAN_ENTRIES_PER_LOC - first_chan)) ?
            (first_chan + chan_cnt) : CATAMARAN_CHAN_ENTRIES_PER_LOC;

        for (chan = first_chan; chan < last_chan; ++chan) {
            /* Store the channel-to-port entry info. */
            entries[entry_cnt].port =
                CTMRN_CHAN2PORT_ENTRY_READ(data,
                                           CATAMARAN_CHAN_PORT_OFF(chan));
            entries[entry_cnt].port_mode =
                CTMRN_CHAN2PORT_ENTRY_READ(data,
                                           CATAMARAN_CHAN_MODE_OFF(chan));
            ++entry_cnt;
        }

        /* Prepare for reading the channel info in the next block. */
        first_chan  = 0;
        chan_cnt   -= CATAMARAN_CHAN_ENTRIES_PER_LOC;
    }
}


void
catamaran_chan2port_table_set(unsigned int nbi, unsigned int chan_start,
                              unsigned int chan_end,
                              __lmem struct catamaran_chan2port_entry *entries)
{
    int chan;
    int last_chan;
    uint32_t addr_pri;
    uint32_t addr_sec;
    uint32_t block;
    __lmem uint32_t data[4];
    int chan_cnt           = chan_end - chan_start + 1;
    int first_chan         = chan_start & CTMRN_CHAN2PORT_ENTRY_MASK;
    uint32_t block_end     = CATAMARAN_CHAN_LOC_ADDR(chan_end);
    uint32_t block_start   = CATAMARAN_CHAN_LOC_ADDR(chan_start);
    unsigned int entry_cnt = 0;

    try_ctassert(chan_start < CATAMARAN_CHAN_NUM_CHANS);
    try_ctassert(chan_end < CATAMARAN_CHAN_NUM_CHANS);

    /* Check if any channels are being configured. */
    if (chan_cnt <= 0)
        return;

    /* Configure the channels one block at a time. */
    for (block = block_start; block <= block_end; ++block) {
        /* Retrieve the block of channels. */
        addr_pri = (CATAMARAN_CHAN_TABLE_BASE0 + block) << 4;
        addr_sec = (CATAMARAN_CHAN_TABLE_BASE1 + block) << 4;

        nbipc_pelm2lmem_copy(nbi, addr_pri, data, sizeof(data));

        /* Set the info for each channel. */
        last_chan =
            (chan_cnt < (CATAMARAN_CHAN_ENTRIES_PER_LOC - first_chan)) ?
            (first_chan + chan_cnt) : CATAMARAN_CHAN_ENTRIES_PER_LOC;

        for (chan = first_chan; chan < last_chan; ++chan) {
            /* Set the channel-to-port entry info. */
            CTMRN_CHAN2PORT_ENTRY_WRITE(data, CATAMARAN_CHAN_PORT_OFF(chan),
                                        entries[entry_cnt].port);
            CTMRN_CHAN2PORT_ENTRY_WRITE(data, CATAMARAN_CHAN_MODE_OFF(chan),
                                        entries[entry_cnt].port_mode);
            ++entry_cnt;
        }

        /* Commit the changes to the table. */
        nbipc_lmem2pelm_copy(nbi, addr_pri, addr_sec, data, sizeof(data));

        /* Prepare for writing the channel info in the next block. */
        first_chan  = 0;
        chan_cnt   -= CATAMARAN_CHAN_ENTRIES_PER_LOC;
    }
}


/* Catamaran MAC match table functions. */

int
catamaran_mac_match_table_add(unsigned int nbi, uint64_t mac_addr,
                              uint16_t result, unsigned int cls_hash_idx)
{
    __lmem struct ctmrn_mac_match_table_entry table_entry;
    int available        = -1;
    uint32_t addr_offset = catamaran_mac_match_hash_calc(cls_hash_idx,
                                                         mac_addr);
    uint32_t addr0       = (CATAMARAN_MAC_TABLE_BASE0 + addr_offset) << 4;
    uint32_t addr1       = (CATAMARAN_MAC_TABLE_BASE1 + addr_offset) << 4;
    uint32_t mac_addr_hi = (mac_addr >> 16) & 0xFFFFFFFF;
    uint16_t mac_addr_lo =  mac_addr        & 0xFFFF;

    try_ctassert(mac_addr <= 0xFFFFFFFFFFFFull);
    try_ctassert(result != 0);

    /* Retrieve the MAC match entry. */
    nbipc_pesm2lmem_copy(nbi, addr0, table_entry.__raw, sizeof(table_entry));

    /* Check if the entry already exists, and if any entries are available. */
    if ((mac_addr_hi == table_entry.mac_addr0_hi) &&
        (mac_addr_lo == table_entry.mac_addr0_lo) &&
        (table_entry.result0 != 0)) {
        /* Replace the result for the entry. */
        table_entry.result0 = result;
        nbipc_lmem2pesm_copy(nbi, addr0, addr1, table_entry.__raw,
                             sizeof(table_entry));

        available = 0; /* Entry already exists. */
    } else if ((mac_addr_hi == table_entry.mac_addr1_hi) &&
               (mac_addr_lo == table_entry.mac_addr1_lo) &&
               (table_entry.result1 != 0)) {
        /* Replace the result for the entry. */
        table_entry.result1 = result;
        nbipc_lmem2pesm_copy(nbi, addr0, addr1, table_entry.__raw,
                             sizeof(table_entry));

        available = 0; /* Entry already exists. */
    } else if ((table_entry.mac_addr0_hi == 0) &&
               (table_entry.mac_addr0_lo == 0) && (table_entry.result0 == 0)) {
        /* Add the entry to the table. */
        table_entry.mac_addr0_hi = mac_addr_hi;
        table_entry.mac_addr0_lo = mac_addr_lo;
        table_entry.result0      = result;
        nbipc_lmem2pesm_copy(nbi, addr0, addr1, table_entry.__raw,
                             sizeof(table_entry));

        available = 0; /* Entry available. */
    } else if ((table_entry.mac_addr1_hi == 0) &&
               (table_entry.mac_addr1_lo == 0) && (table_entry.result1 == 0)) {
        /* Add the entry to the table. */
        table_entry.mac_addr1_hi = mac_addr_hi;
        table_entry.mac_addr1_lo = mac_addr_lo;
        table_entry.result1      = result;
        nbipc_lmem2pesm_copy(nbi, addr0, addr1, table_entry.__raw,
                             sizeof(table_entry));

        available = 0; /* Entry available. */
    }

    return available;
}


int
catamaran_mac_match_table_get(unsigned int nbi, uint64_t mac_addr,
                              unsigned int cls_hash_idx)
{
    __lmem struct ctmrn_mac_match_table_entry table_entry;
    int match            = -1;
    uint32_t addr_offset = catamaran_mac_match_hash_calc(cls_hash_idx,
                                                         mac_addr);
    uint32_t addr        = (CATAMARAN_MAC_TABLE_BASE0 + addr_offset) << 4;
    uint32_t mac_addr_hi = (mac_addr >> 16) & 0xFFFFFFFF;
    uint16_t mac_addr_lo =  mac_addr        & 0xFFFF;

    try_ctassert(mac_addr <= 0xFFFFFFFFFFFFull);

    /* Retrieve the MAC match entry. */
    nbipc_pesm2lmem_copy(nbi, addr, table_entry.__raw, sizeof(table_entry));

    /* Check if any entries match the MAC address. */
    if ((mac_addr_hi == table_entry.mac_addr0_hi) &&
        (mac_addr_lo == table_entry.mac_addr0_lo) &&
        (table_entry.result0 != 0)) {
        /* Copy the result. */
        match = table_entry.result0; /* Match found. */
    } else if ((mac_addr_hi == table_entry.mac_addr1_hi) &&
               (mac_addr_lo == table_entry.mac_addr1_lo) &&
               (table_entry.result1 != 0)) {
        /* Copy the result. */
        match = table_entry.result1; /* Match found. */
    }

    return match;
}


int
catamaran_mac_match_table_remove(unsigned int nbi, uint64_t mac_addr,
                                 unsigned int cls_hash_idx)
{
    __lmem struct ctmrn_mac_match_table_entry table_entry;
    int match            = -1;
    uint32_t addr_offset = catamaran_mac_match_hash_calc(cls_hash_idx,
                                                         mac_addr);
    uint32_t addr0       = (CATAMARAN_MAC_TABLE_BASE0 + addr_offset) << 4;
    uint32_t addr1       = (CATAMARAN_MAC_TABLE_BASE1 + addr_offset) << 4;
    uint32_t mac_addr_hi = (mac_addr >> 16) & 0xFFFFFFFF;
    uint16_t mac_addr_lo =  mac_addr        & 0xFFFF;

    try_ctassert(mac_addr <= 0xFFFFFFFFFFFFull);

    /* Retrieve the MAC match entry. */
    nbipc_pesm2lmem_copy(nbi, addr0, table_entry.__raw, sizeof(table_entry));

    /* Check if any entries match the MAC address. */
    if ((mac_addr_hi == table_entry.mac_addr0_hi) &&
        (mac_addr_lo == table_entry.mac_addr0_lo) &&
        (table_entry.result0 != 0)) {
        /* Remove the entry from the table. */
        table_entry.mac_addr0_hi = 0;
        table_entry.mac_addr0_lo = 0;
        table_entry.result0      = 0;
        nbipc_lmem2pesm_copy(nbi, addr0, addr1, table_entry.__raw,
                             sizeof(table_entry));

        match = 0; /* Match found. */
    } else if ((mac_addr_hi == table_entry.mac_addr1_hi) &&
               (mac_addr_lo == table_entry.mac_addr1_lo) &&
               (table_entry.result1 != 0)) {
        /* Remove the entry from the table. */
        table_entry.mac_addr1_hi = 0;
        table_entry.mac_addr1_lo = 0;
        table_entry.result1      = 0;
        nbipc_lmem2pesm_copy(nbi, addr0, addr1, table_entry.__raw,
                             sizeof(table_entry));

        match = 0; /* Match found. */
    }

    return match;
}
