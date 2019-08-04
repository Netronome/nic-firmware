.. Copyright (c) 2018-2019 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause

Action - TX_VLAN 
================

Description
-----------


Interface and Encoding
----------------------
.. rst-class:: action-encoding
    
    +------+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |Bit / |3|3|2|2|2|2|2|2|2|2|2|2|1|1|1|1|1|1|1|1|1|1|0|0|0|0|0|0|0|0|0|0|
    |Word  |1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
    +======+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    |   0  |            <addr>           |P|           Reserved            |
    +------+-----------------------------+-+-------------------------------+

Reads
.....

- nfd_out_atomics
- vf_vlan_cache
- PV_BLS
- PV_CTM_ADDR
- PV_CTM_ACTIVE
- PV_VLAN_ID
- PV_META_TYPES
- PV_MU_ADDR
- PV_NUMBER
- PV_OFFSET
- PV_SPLIT
- PV_QUEUE_IN
- PV_TX_FLAGS

Writes
......

- nfd_out_atomics
- NFD_WQ
- PKT_DATA
- PKT_PREPEND
- PKT_MU_META
- PV_META_LM_PTR
- PV_OFFSET
- PV_LENGTH
- NIC_STATS_QUEUE_RX
- NIC_STATS_QUEUE_TX

Implementation
--------------


API Dependencies
................

- __actions_read()
- bitfield_extract()
- ov_single()
- pkt_io_tx_vlan()
- pv_get_base_addr()
- pv_meta_write
- pv_multicast_resend()
- pv_get_nfd_host_desc()
- pv_update_nfd_desc_queue()
- pv_pop()
- pv_stats_tx_host()
