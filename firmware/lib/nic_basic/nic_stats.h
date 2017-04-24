/*
 * Copyright 2015 Netronome, Inc.
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
 * @file          lib/nic/_c/nic_stats.c
 * @brief         Implementation for additional stats
 */

#ifndef _LIBNIC_NIC_STATS_H_
#define _LIBNIC_NIC_STATS_H_

/*
 * Additional counters for the NIC application
 *
 * Most of the statistics for the NIC are directly based on stats
 * maintained by the MAC.  However, some required stats are either
 * derived counts or software based counts.  This structure defines
 * these additional stats.
 *
 * DO NOT CHANGE THE ORDER!
 */
struct nic_port_stats_extra {
    unsigned long long rx_discards;
    unsigned long long rx_errors;
    unsigned long long rx_uc_octets;
    unsigned long long rx_mc_octets;
    unsigned long long rx_bc_octets;
    unsigned long long rx_uc_pkts;
    unsigned long long rx_mc_pkts;
    unsigned long long rx_bc_pkts;

    unsigned long long tx_discards;
    unsigned long long tx_errors;
    unsigned long long tx_uc_octets;
    unsigned long long tx_mc_octets;
    unsigned long long tx_bc_octets;
    unsigned long long tx_uc_pkts;
    unsigned long long tx_mc_pkts;
    unsigned long long tx_bc_pkts;
};

#endif