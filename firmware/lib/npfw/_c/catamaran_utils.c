/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
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
 * @file   lib/npfw/_c/catamaran_utils.c
 * @brief  ME-based interface for configuring Catamaran NPFW
 */


#include <assert.h>
#include <npfw/catamaran_utils.h>
#include <npfw/nbipc_mem.h>


/* Catamaran channel-to-port table helper macros. */
#define CTMRN_CHAN2PORT_ENTRY_MASK (CATAMARAN_CHAN_ENTRIES_PER_LOC - 1)
#define CTMRN_CHAN2PORT_ENTRY_READ(_data, _off)            \
    ((_data[(_off) >> 2] >> (((_off) & 0x3) << 3)) & 0xFF)
#define CTMRN_CHAN2PORT_ENTRY_WRITE(_data, _off, _val)                \
    do {                                                              \
        _data[(_off) >> 2] &= ~(0xFF << (((_off) & 0x3) << 3));       \
        _data[(_off) >> 2] |= (_val & 0xFF) << (((_off) & 0x3) << 3); \
    } while (0)


__intrinsic void
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


__intrinsic void
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
