.. Copyright (c) 2018-2019 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause

Action - RX_HOST
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
    |   0  |            <addr>           |P|           MTU             |C|c|
    +------+-----------------------------+-+---------------------------+-+-+

:C: Enable outer L3 checksum processing
:c: Enable outer L4 checksum processing

.. |_| unicode:: 0xA0
    :trim:

Reads
.....

- PKT_DATA

Writes
......

- PKT_DATA
- PV_BLS
- PV_CBS
- PV_CTM_ISL
- PV_CTM_ADDR
- PV_CTM_ACTIVE
- PV_CSUM_OFFLOAD
- PV_HEADER_STACK
- PV_LENGTH
- PV_MAC_DST_TYPE
- PV_META_TYPES
- PV_MU_ADDR
- PV_NUMBER
- PV_OFFSET
- PV_PROTO
- PV_SPLIT
- PV_SEQ_CTX
- PV_SEQ_NO
- PV_SEEK_BASE
- PV_VLAN_ID
- PV_QUEUE_IN
- NIC_STATS_QUEUE_ERROR_PCI
- NIC_STATS_QUEUE_ERROR_MTU

Implementation
--------------


API Dependencies
................

- __actions_next()
- __actions_read()
- __actions_restore_t_idx()
- bitfield_extract()
- bits_set()
- pkt_buf_copy_mu_head_to_ctm()
- pkt_io_rx_host()
- __pv_get_mac_dst_type()
- __pv_lso_fixup()
- __pv_mtu_check()
- pv_hdr_parse()
- pv_init_nfd()
- pv_seek()
- pv_stats_update()
