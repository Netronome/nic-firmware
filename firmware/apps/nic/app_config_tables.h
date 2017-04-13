/*
 * Copyright (C) 2015 Netronome, Inc. All rights reserved.
 *
 * @file          apps/nic/app_config_tables.h
 * @brief         Header file for App Config ME local functions/declarations
 */

#ifndef _APP_CONFIG_TABLES_H_
#define _APP_CONFIG_TABLES_H_

#include <nfp.h>
#include <stdint.h>
#include <nfp_chipres.h>



enum {

    INSTR_MTU = 1,
    INSTR_MAC,
    INSTR_EXTRACT_KEY_WITH_RSS,
    INSTR_RSS_CRC32_HASH_WITH_KEY,
    INSTR_SEL_RSS_QID_WITH_MASK,
    INSTR_RSS_TABLE,
    INSTR_CHECKSUM_COMPLETE,
    INSTR_TX_HOST,
    INSTR_TX_WIRE,
    INSTR_TX_DROP
};


/* if NBI 1 has any ports then two NIB islands */
#if NS_PLATFORM_NUM_PORTS_PER_MAC_1 > 0
#define NUM_NBI 2
#else
#define NUM_NBI 1
#endif

#define NUM_NBI_CHANNELS    64      // channels per NBI
#define NUM_PCIE            1       // number of PCIe islands
#define NUM_PCIE_Q          64      // number of queues configured per PCIe
#define NUM_PCIE_Q_PER_PORT NFD_MAX_PF_QUEUES // nr queues configured per port
#define NIC_MAX_INSTR       32      // 128 bytes, 4B per instruction

#define NIC_HOST_MAX_ENTRIES  (NUM_PCIE*NUM_PCIE_Q)
#define NIC_NBI_ENTRY_START   NIC_HOST_MAX_ENTRIES
#define NIC_WIRE_MAX_ENTRIES  (NUM_NBI*NUM_NBI_CHANNELS)


#define NIC_CFG_INSTR_TBL_ADDR (0x00)
#define NIC_CFG_INSTR_TBL_SIZE (((NIC_HOST_MAX_ENTRIES+NIC_WIRE_MAX_ENTRIES) \
                                * NIC_MAX_INSTR)<<2)

/* For host ports, use 0 to MAX_VFS
 * For wire ports, use MIN_PFS .. MAX_PFS */
__asm
{
    .alloc_mem NIC_CFG_INSTR_TBL cls + NIC_CFG_INSTR_TBL_ADDR \
                island NIC_CFG_INSTR_TBL_SIZE addr40
    .init NIC_CFG_INSTR_TBL 0 0
}



/**
 * Handle port config from PCIe. Configure the config instruction tables
 * for wire and host.
 *
 * @vnic_port   VNIC port
 * @control     First word of the BAR data
 * @update      Second word of the BAR data
 */
void app_config_port(unsigned int vnic_port, unsigned int control,
                        unsigned int update);


/**
 * Handle port down from PCIe. Configure the config instruction tables
 * for wire and host.
 *
 * @vnic_port    VNIC port
 */
void app_config_port_down(unsigned int vnic_port);

#endif /* _APP_CONFIG_TABLES_H_ */
