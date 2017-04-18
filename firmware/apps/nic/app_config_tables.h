/*
 * Copyright (C) 2015 Netronome, Inc. All rights reserved.
 *
 * @file          apps/nic/app_config_tables.h
 * @brief         Header file for App Config ME local functions/declarations
 */

#ifndef _APP_CONFIG_TABLES_H_
#define _APP_CONFIG_TABLES_H_



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
