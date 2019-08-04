#! /usr/bin/env python

# Copyright (c) 2016 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

## 1) Counting the code store per function in the list file
## 2) Massage the output of the nfcc live range analysis to something
## more sensible, reporting register usage per function
## 3) Also reporting register usage per instruction
## Usage:
## ./nic_reg_usage.py LIVEINFO_FILE LIST_FILE --gpr
## The last argument is the reg usage used in sorting (optional)
## as default value is --gpr, and it can be --gpr/--xrw/--xr/--xw/--nn/--sig

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

def reg_check_in_func(start_inst, inst_cnt, cur_filen, cur_lineno, reg_res,
                      reg_func):
    max_cnt = {}
    last_cnt = {}
    for rt in limit.keys():
        max_cnt[rt] = 0
    for i in range(0, inst_cnt):
        cur_addr = start_inst + i
        for rt in limit.keys():
            if len(reg_res[cur_addr][rt]) > max_cnt[rt]:
                max_cnt[rt] = len(reg_res[cur_addr][rt])
    for rt in limit.keys():
        last_cnt[rt] = len(reg_res[start_inst + inst_cnt - 1][rt])
    reg_func.append([max_cnt, last_cnt, start_inst,
                     (start_inst + inst_cnt - 1), cur_filen, cur_lineno])

def main(argv):

    NIC_SRCS = ['firmware/apps', 'firmware/lib']

    # Analyzing the list file for code store
    inst = -1
    lineno = -1
    filen = None

    int_res = []

    listf =  open(argv[2], "r")

    list_lines = listf.readlines()

    for line in list_lines:
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
            int_res.append([inst, filen, lineno])
            inst = -1
            lineno = -1

    # we now have a list of instructions and the filename and filenumber
    # they are attributed with in the .list file

    # go through the list an count instructions per line of NIC source code
    cur_inst = int_res[0][0]
    cur_filen = int_res[0][1]
    cur_lineno = int_res[0][2]
    inst_cnt = 0
    inst_func = []

    print('Analyzing the instruction count ...')
    print('input file:')
    print(argv[1])
    print(argv[2])
    print('The format is:')
    print('column 1: Count of instructions ')
    print('column 2: starting code store location ')
    print('column 3: File name and line number ')
    for inst, filen, lineno in int_res:
        inst_cnt += 1

        for src in NIC_SRCS:
            if src in filen:
                if cur_filen:
                    inst_func.append([inst_cnt, cur_inst,cur_filen,
                                     cur_lineno])
                    #print "%4d -> %4d: %s:%d" % (inst_cnt, cur_inst,
                    #                  cur_filen, cur_lineno)
                cur_inst = inst
                cur_filen = filen
                cur_lineno = lineno
                inst_cnt = 0
    sort_inst_func = sorted(inst_func, key=lambda func: func[0], reverse=True)

    for func_usage in sort_inst_func:
        print("%4d -> %4d: %s:%d" % (func_usage[0], func_usage[1],
                                     func_usage[2], func_usage[3]))

    # Analyzing the liveinfo file for register usage
    inf = open(argv[1], "r")

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
    res[cur_addr]['c_file'] = None
    res[cur_addr]['c_line'] = None

    curr_live = ''
    pl = ''
    while True:
        ppl = pl
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
                    res[cur_addr]['c_line'] = lnr
                    res[cur_addr]['src'] = "%s: %s" % (lnr, src)
                else:
                    res[cur_addr]['src'] = ""
                    res[cur_addr]['c_line'] = None
                if ppl.startswith("#########"):
                    _, _, c_src = ppl.partition(' ')
                    res[cur_addr]['c_file'] = c_src
                else:
                    res[cur_addr]['c_file'] = None


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

    # Fill the empty c file name and c file line fields
    # based on previous instruction
    p_c_line = None
    p_c_file = None
    for addr in addrs:
        if res[addr]['c_file']:
            p_c_file = res[addr]['c_file']
        else:
            res[addr]['c_file'] = '%s' % p_c_file
        if res[addr]['c_line']:
            p_c_line = res[addr]['c_line']
        else:
            res[addr]['c_line'] = '%s' % p_c_line
    # Filter out all non NIC_SRCS c file name and line fields
    # replace with the last found NIC_SRCS c file name and line
    # Also calculate the reg_usage based on the c file name
    p_c_line = None
    p_c_file = None
    for addr in addrs:
        key_found = False
        for src in NIC_SRCS:
            if src in res[addr]['c_file']:
                key_found = True

        if key_found:
            p_c_file = res[addr]['c_file']
            p_c_line = res[addr]['c_line']
        else:
            res[addr]['c_file'] = p_c_file
            res[addr]['c_line'] = p_c_line
    # Also calculate the reg_usage based on the c file name
    p_c_line = None
    p_c_file = None
    start_inst = 0
    #cur_inst = 0
    inst_cnt = 0
    reg_func = []
    for addr in addrs:
        inst_cnt += 1
        if p_c_line != res[addr]['c_line'] or p_c_file != res[addr]['c_file']:
            reg_check_in_func(start_inst, inst_cnt, p_c_file, p_c_line, res,
                              reg_func)
            start_inst = int(addr)
            inst_cnt = 0
            p_c_file = res[addr]['c_file']
            p_c_line = res[addr]['c_line']
        #cur_inst += 1

    # Sort the reg_usage
    calc_reg_func = []
    for i in range(0, len(reg_func)):
        delta_reg_usage = {}
        if not i:
            delta_reg_usage = reg_func[i][0]
        else:
            for rt in limit.keys():
                delta_reg_usage[rt] = reg_func[i][0][rt] - reg_func[i-1][1][rt]
                #delta_reg_usage[rt] = reg_func[i-1][1][rt]
        calc_reg_func.append(delta_reg_usage)
    for i in range(0, len(reg_func)):
        reg_func[i][1] = calc_reg_func[i]

    if len(argv) < 4:
        sort_key = 'gpr'
    else:
        sort_key = argv[3][2:]
    sort_reg_func = sorted(reg_func, key=lambda reg: reg[0][sort_key],
                           reverse=True)
    sort_reg_delta_func = sorted(reg_func, key=lambda reg: reg[1][sort_key],
                           reverse=True)


    # Simply print out register usage based on analysis on liveinfo file

    print('Analyzing register usage per function...')
    print('Sorted by %s reg usage' % sort_key)
    print('input file:')
    print(argv[1])
    print(argv[2])
    print('The format is:')
    print('column 1~6: Register usage ')
    print('            (actual_use/reg_use_increase/reg_limit/reg_name) ')
    print('            Note: actual_use = Max usage during code location specified in column 7:')
    print('            reg_use_increase = actual_use - usage at the end of the last function')
    print('            It indicates reg usage increment per function.')
    print('column 7: starting and ending code store location ')
    print('column 8: File name and line number ')

    for reg_usage in sort_reg_func:
        reg_str=''
        for rt in limit.keys():
            reg_str+=' %4d(%3d)/%2d-%s' % (reg_usage[0][rt], reg_usage[1][rt],
                                           limit[rt], rt)
        print("%s -> %4d~%4d: %s:%s" % (reg_str, reg_usage[2], reg_usage[3],
                                        reg_usage[4], reg_usage[5]))

    print('Analyzing register usage per function...')
    print('Sorted by %s reg usage increment' % sort_key)
    print('input file:')
    print(argv[1])
    print(argv[2])
    print('The format is:')
    print('column 1~6: Register usage ')
    print('            (actual_use/reg_use_increase/reg_limit/reg_name) ')
    print('            Note: actual_use = Max usage during code location specified in column 7:')
    print('            reg_use_increase = actual_use - usage at the end of the last function')
    print('            It indicates reg usage increment per function.')
    print('column 7: starting and ending code store location ')
    print('column 8: File name and line number ')

    for reg_usage in sort_reg_delta_func:
        reg_str=''
        for rt in limit.keys():
            reg_str+=' %4d(%3d)/%2d-%s' % (reg_usage[0][rt], reg_usage[1][rt],
                                           limit[rt], rt)
        print("%s -> %4d~%4d: %s:%s" % (reg_str, reg_usage[2], reg_usage[3],
                                        reg_usage[4], reg_usage[5]))

    # Simply print out register usage per Instruction based on liveinfo file
    print('Analyzing register usage per Instruction...')
    print('input file:')
    print(argv[1])
    print(argv[2])
    print('The format is:')
    print('[code store location] Instruction')
    print('List of register usage ')
    for addr in addrs:
        print("[%04d] %s%s" % (addr, res[addr]['inst'],
                               ("; %s" % res[addr]['src']
                                if res[addr]['src'] else '')))
        #print("%s" % (res[addr]['c_file'] if res[addr]['c_file'] else ''))
        #print("line:%s" % (res[addr]['c_line'] if res[addr]['c_line'] else ''))
        tw = textwrap.TextWrapper(width=cols,
                                  subsequent_indent="                  ")

        for rt in limit.keys():
            if len(res[addr][rt]) > limit[rt]:
                pref = "XXX"
            elif len(res[addr][rt]) > limit[rt] - 2:
                pref = "~~~"
            else:
                pref = "   "
            print(tw.fill("%s %3s:  %s" % (pref, rt,
                                           print_list(res[addr], rt))))
        print('')

if __name__ == '__main__':
    sys.exit(main(sys.argv))
