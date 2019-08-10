.. Copyright (c) 2018-2019 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause

Action - EBPF
=============

Description
-----------


Interface and Encoding
----------------------
.. rst-class:: action-encoding

    +------+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |Bit / |3|3|2|2|2|2|2|2|2|2|2|2|1|1|1|1|1|1|1|1|1|1|0|0|0|0|0|0|0|0|0|0|
    |Word  |1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
    +======+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    |   0  |            <addr>           |P|            UC Addr            |
    +------+-----------------------------+-+-------------------------------+

:UC Addr: Code store address at which to begin execution of eBPF

.. |_| unicode:: 0xA0
    :trim:

Reads
.....

Program defined.

Writes
......

Program defined.

Implementation
--------------


API Dependencies
................

- __actions_read()
- ebpf_call()
- pv_save_lm_ptr()
