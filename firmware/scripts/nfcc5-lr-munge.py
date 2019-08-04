#! /usr/bin/env python

# Copyright (c) 2016 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

## Massage the output of the nfcc live range analysis to something
## more sensible.

import sys, os
import textwrap

limit = {'gpr': 32,
         'xrw': 16,
         'xr': 32,
         'xw': 32,
         'nn': 16,
         'sig': 15,
         }

def print_list(d, key):
    ret = ""

    num = len(d[key])
    if key == 'xr' or key == 'xw':
         num += len(d['xrw'])

    ret += "(%2d/%d)" % (num, limit[key])

    for reg in d[key]:
        ret += " %s" % reg

    return ret

def main(argv):
    inf =  open(argv[1], "r")

    while True:
        l = inf.readline()
        if not l:
            break
        if l.startswith("Register Live Range Information Report"):
            break

    if not l:
        return

    res = {}
    cur_addr = 0
    res[cur_addr] = {}
    res[cur_addr]['inst'] = "NONE"
    res[cur_addr]['gpr'] = []
    res[cur_addr]['xr'] = []
    res[cur_addr]['xw'] = []
    res[cur_addr]['xrw'] = []
    res[cur_addr]['nn'] = []
    res[cur_addr]['sig'] = []
    res[cur_addr]['src'] = ""

    curr_live = ''
    while True:
        pl = l
        l = inf.readline()
        if not l:
            break
        l = l.strip()
        addr, _, ins = l.partition(' ')
        if addr.isdigit():
            cur_addr = int(addr)
            if not res.has_key(cur_addr):
                res[cur_addr] = {}
                res[cur_addr]['inst'] = ins.strip()
                res[cur_addr]['gpr'] = []
                res[cur_addr]['xr'] = []
                res[cur_addr]['xw'] = []
                res[cur_addr]['xrw'] = []
                res[cur_addr]['nn'] = []
                res[cur_addr]['sig'] = []
                if pl.startswith("/******/"):
                    _, _, src = pl.partition(' ')
                    lnr, _, src = src.partition(':')
                    lnr = lnr.lstrip('(').lstrip('L').rstrip(')')
                    src = src.strip()
                    res[cur_addr]['src'] = "%s: %s" % (lnr, src)
                else:
                    res[cur_addr]['src'] = ""
        if l.startswith("Live set"):
            curr_live = 'Live set'
            _, _, regs = l.partition(':')
            regs = regs.strip()
            if not regs:
                continue
            regl = regs.split()
            if regl[0].startswith('gr.'):
                res[cur_addr]['gpr'] += regl
            if regl[0].startswith('sig.'):
                res[cur_addr]['sig'] += regl
            if regl[0].startswith('srw_xrw.'):
                res[cur_addr]['xrw'] += regl
            if regl[0].startswith('sr_xr.'):
                res[cur_addr]['xr'] += regl
            if regl[0].startswith('sw_xw.'):
                res[cur_addr]['xw'] += regl
            if regl[0].startswith('nn.'):
                res[cur_addr]['nn'] += regl
        if l.startswith("Live in("):
            curr_live = 'Live in'
        if l.startswith("Live out("):
            curr_live = 'Live out'
        if l.startswith("Live through("):
            curr_live = 'Live through'
        else:
            regl = l.split()
            if not len(regl):
                continue
            if not cur_addr:
                continue
	    # Count only if we are "in" Live set
	    if curr_live == 'Live set':
                if regl[0].startswith('gr.'):
                    res[cur_addr]['gpr'] += regl
                if regl[0].startswith('sig.'):
                    res[cur_addr]['sig'] += regl
                if regl[0].startswith('srw_xrw.'):
                    res[cur_addr]['xrw'] += regl
                if regl[0].startswith('sr_xr.'):
                    res[cur_addr]['xr'] += regl
                if regl[0].startswith('sw_xw.'):
                    res[cur_addr]['xw'] += regl
                if regl[0].startswith('nn.'):
                    res[cur_addr]['nn'] += regl

    _, cols = os.popen("stty size", 'r').read().split()
    cols = int(cols)
    addrs = res.keys()
    addrs.sort()
    for addr in addrs:
        print "[%04d] %s%s" % (addr, res[addr]['inst'],
                               ("; %s" % res[addr]['src']
                                if res[addr]['src'] else ''))
        tw = textwrap.TextWrapper(width=cols,
                                  subsequent_indent="                  ")

        for rt in limit.keys():
            if len(res[addr][rt]) > limit[rt]:
                pref = "XXX"
            elif len(res[addr][rt]) > limit[rt] - 2:
                pref = "~~~"
            else:
                pref = "   "
            print tw.fill("%s %3s:  %s" % (pref, rt, print_list(res[addr], rt)))
        print
      


if __name__ == '__main__':
    sys.exit(main(sys.argv))
