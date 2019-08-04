#! /usr/bin/env python

# Copyright (c) 2016 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

import fileinput

NIC_SRCS = ['apps/nic', 'lib/nic']

inst = -1
lineno = -1
filen = None

res = []


for line in fileinput.input():
    elems = line.split()

    # skip empty line
    if not len(elems):
        continue

    if elems[0].startswith('.'):
        if elems[0] == ".%line":
            lineno = int(elems[1])
            filen = elems[2][1:-1]
        else:
            try:
                inst = int(elems[0][1:])
            except:
                inst = -1
            lineno = -1
            filen = None

    if not inst == -1 and not lineno == -1:
        # print "%4d: %s:%d" % (inst, filen, lineno)
        res.append([inst, filen, lineno])
        inst = -1
        lineno = -1

# we now have a list of instructions and the filename and filenumber
# they are attributed with in the .list file

# go through the list an count instructions per line of NIC source code
cur_inst = res[0][0]
cur_filen = res[0][1]
cur_lineno = res[0][2]
inst_cnt = 0

for inst, filen, lineno in res:
    inst_cnt += 1

    for src in NIC_SRCS:
        if src in filen:
            if cur_filen:
                print "%4d -> %4d: %s:%d" % \
                      (inst_cnt, cur_inst, cur_filen, cur_lineno)
            cur_inst = inst
            cur_filen = filen
            cur_lineno = lineno
            inst_cnt = 0

print "%4d -> %4d: %s:%d" % \
      (inst_cnt, cur_inst, cur_filen, cur_lineno)

