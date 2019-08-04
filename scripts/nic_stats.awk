# Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

BEGIN{ QUEUE_COUNT=0; VNIC_COUNT=0}
!/^[ \t]*$/{
    if (length($0) >= 25) {
        print $0 " is too long"
        exit 1
    }

    if (match($0, /_pkts$/)) {
	MASK[QUEUE_COUNT] = 1
	stat = substr($0, 1, length($0) - 5)
        VNIC_COUNT++
    }
    else if (match($0, /_errors$/) || match($0, /_discards$/)) {
	MASK[QUEUE_COUNT] = 5
	stat = $0
        VNIC_COUNT++
    }
    else if (match($0, /_bytes$/)) {
	MASK[QUEUE_COUNT] = 2
	stat = substr($0, 1, length($0) - 6)
        VNIC_COUNT++
    }
    else {
	MASK[QUEUE_COUNT] = 3
        stat = $0
	VNIC_COUNT += 2
    }
    DATA[QUEUE_COUNT++] = stat
}
END{
    x = log(QUEUE_COUNT) / log(2)
    queue_size = 8 * 2 ^ ((x == int(x)) ? x : int(x) + 1)

    x = log(VNIC_COUNT) / log(2)
    vnic_size = 8 * 2 ^ ((x == int(x)) ? x : int(x) + 1)

    print "/* This file is generated during build. Do not edit! */"

    for (i = 0; i < QUEUE_COUNT; ++i)
	printf("#define NIC_STATS_QUEUE_%s_IDX %d\n", toupper(DATA[i]), i)
    for (i = 0; i < QUEUE_COUNT; ++i)
	printf("#define NIC_STATS_QUEUE_%s 0x%x\n", toupper(DATA[i]), i * 8)

    print "#define NIC_STATS_QUEUE_COUNT " QUEUE_COUNT
    print "#define NIC_STATS_QUEUE_SIZE " queue_size

    j = 0
    for (i = 0; i < QUEUE_COUNT; ++i) {
	if (and(MASK[i], 4)) {
	    printf("#define NIC_STATS_VNIC_%s 0x%x\n", toupper(DATA[i]), j)
	    j += 8
	}
	else {
	    if (and(MASK[i], 1)) {
	        printf("#define NIC_STATS_VNIC_%s_PKTS 0x%x\n", toupper(DATA[i]), j)
	        j += 8
	    }
	    if (and(MASK[i], 2)) {
	        printf("#define NIC_STATS_VNIC_%s_BYTES 0x%x\n", toupper(DATA[i]), j)
	        j += 8
	    }
	}

    }

    print "#define NIC_STATS_VNIC_COUNT " VNIC_COUNT
    print "#define NIC_STATS_VNIC_SIZE " vnic_size
    print "#define NIC_STATS_VNIC_MASK_PKTS 1"
    print "#define NIC_STATS_VNIC_MASK_BYTES 2"

    print "#if defined(__NFP_LANG_MICROC)"

    print "typedef struct {"
    print "\tunion {"
    print "\t\tstruct {"
    for (i = 0; i < QUEUE_COUNT; ++i) { print "\t\t\tuint64_t " DATA[i] ";" }
    print "\t\t};"
    print "\t\tuint64_t __raw[" (queue_size / 8) "];"
    print "\t};"
    print "} nic_stats_queue_t;"

    print "typedef struct {"
    print "\tunion {"
    print "\t\tstruct {"
    for (i = 0; i < QUEUE_COUNT; ++i) {
	if (and(MASK[i], 4)) {
	    print "\t\t\tuint64_t " DATA[i] ";"
	}
	else {
	    if (and(MASK[i], 1))
	        print "\t\t\tuint64_t " DATA[i] "_pkts;"
	    if (and(MASK[i], 2))
	        print "\t\t\tuint64_t " DATA[i] "_bytes;"
	}
    }
    print "\t\t};"
    print "\t\tuint64_t __raw[" (vnic_size / 8) "];"
    print "\t};"
    print "} nic_stats_vnic_t;"

    printf "static const char nic_stats_vnic_mask[] = {"
    for (i = 0; i < QUEUE_COUNT; ++i) {
	printf(" %d,", and(MASK[i], 3))
    }
    print " };"

    print "#endif"
}
