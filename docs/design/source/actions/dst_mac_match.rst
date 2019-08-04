.. Copyright (c) 2018-2019 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause

Action - DST_MAC_MATCH
==================

Description
-----------

Interface and Encoding
----------------------
.. rst-class:: action-encoding

    +------+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |Bit / |3|3|3|2|2|2|2|2|2|2|2|2|2|1|1|1|1|1|1|1|1|1|1|0|0|0|0|0|0|0|0|0|
    |Word  |1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
    +======+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    |   0  |            <addr>           |P|            MAC HI             |
    +------+-----------------------------+-+-------------------------------+
    |                                   MAC LO                             |
    +----------------------------------------------------------------------+

:MAC: Drop on mismatch

Reads
.....

- PKT_DATA
- PV_MAC_DST_MC


Implementation
--------------

API Dependencies
................

- __actions_next()
- __actions_read()
- __actions_read_begin()
- __actions_read_end()
- __actions_restore_t_idx()
- pv_seek()
