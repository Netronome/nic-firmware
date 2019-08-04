# Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

BEGIN{ COUNT = 0 }
!/^[ \t]*$/{
    if (length($0) >= 25) {
        print $0 " is too long"
        exit 1
    }
    if (match($0, /_pkts$/) || match($0, /_bytes$/) || match($0, /_discards$/) || match($0, /_errors$/)) {
	DATA[COUNT++] = $0
    }
    else {
        DATA[COUNT++] = $0 "_pkts"
	DATA[COUNT++] = $0 "_bytes"
    }
    for (i = 0; i < 256; ++i)
	ascii[sprintf("%c", i)] = i
}
function print_et_string(str) {
    for (j = 1; j <= 32; j += 4)
	printf(" 0x%02x%02x%02x%02x",
	       (j + 3 <= length(str)) ? ascii[substr(str, j + 3, 1)] : 0,
	       (j + 2 <= length(str)) ? ascii[substr(str, j + 2, 1)] : 0,
	       (j + 1 <= length(str)) ? ascii[substr(str, j + 1, 1)] : 0,
	       (j <= length(str)) ? ascii[substr(str, j, 1)] : 0)
}
END{
    print "/* This file is generated during build. Do not edit! */"

    len = 4 + COUNT * (1 + 32 + 8)
    if (COUNT % 4)
	len += 4 - COUNT % 4

    printf("nfd_tlv_init(_PCI, _VID, NFP_NET_CFG_TLV_TYPE_EXT_STATS, %d,", len)

    printf(" 0x%08x", COUNT)

    for (i = 0; i < COUNT; ++i) {
        if (substr(DATA[i], 1, 3) == "rx_") {
            DATA[i] = substr(DATA[i], 4)
            dir[i % 4] = 2
        }
	else if (substr(DATA[i], 1, 3) == "tx_") {
            DATA[i] = substr(DATA[i], 4)
            dir[i % 4] = 3
        }
	else dir[i % 4] = 1

	if (i % 4 == 3)
	    printf(" 0x%02x%02x%02x%02x", dir[3], dir[2], dir[1], dir[0])
    }

    switch (i % 4) {
        case 0: break;
        case 1: printf(" 0x000000%02x", dir[0]); break;
        case 2: printf(" 0x0000%02x%02x", dir[1], dir[0]); break
        case 3: printf(" 0x00%02x%02x%02x", dir[2], dir[1], dir[0]) ; break
    }

    for (i = 0; i < COUNT; ++i) {
	print_et_string(DATA[i])
    }

    printf(")\n")
}
