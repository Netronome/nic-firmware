#! /usr/bin/env python2.7
# -*- Python -*-

# pcmp.py PCAP_PATH/my_pcap.pcap COUNT OUTPUT_PATH/out_file (EXP_PATH/exp_txt)
# COUNT is the number of iterations the pcap is replayed repeatedly

import subprocess
import sys
import re
import time

def run_script(script_file, out_file):

    out_fh = open(out_file, 'w')
    cmd = 'tshark -x -r %s' % script_file
    fun_ret = subprocess.call(cmd, shell=True, stdout=out_fh,
                            stderr=out_fh)
    out_fh.close()
    if fun_ret:
        return False
    else:
        return True

def extract_output(count, out_file):
    read_fh = open(out_file, 'r')
    res_data = read_fh.read()
    pckt_str = ''
    cmp_str = '^[\da-fA-F]{4}\s([\da-f\s]{0,48})'
    for i in range(int(count)):
        lines = res_data.splitlines()
        for line in lines:
            data = re.findall(cmp_str, line)
            if data:
                pckt_str = pckt_str + data[0]
    return pckt_str

def compare_output(exp_file, pckt_str):
    exp_fh = open(exp_file, 'r')
    exp_data = exp_fh.read()
    if pckt_str == exp_data:
        return True
    else:
        return False

def output_match(out_str, out_file):
    write_fh = open(out_file, 'w')
    write_fh.write(out_str)
    write_fh.close()
    return

script_ret = True
fun_ret = False
out_str = ''
exp_input = False
exp_file = None
script_file = sys.argv[1]
count = sys.argv[2]
out_file = sys.argv[3]

if len(sys.argv) < 4 or len(sys.argv) > 5:
    script_ret = False
    out_str += "script error: need four arguments and one option arguments"
elif len(sys.argv) == 5:
    exp_file = sys.argv[4]
    exp_input = True
else:
    exp_input = False

old_pckt_str = ''

if script_ret:
    try:
        while True:
            ret = run_script(script_file, out_file)
            if not ret:
                out_str += "script error: fails in run_script"
            pckt_str = extract_output(count, out_file)
            if exp_input:
                if old_pckt_str != pckt_str:
                    old_pckt_str = pckt_str
                    ret = compare_output(exp_file, pckt_str)
                    if ret:
                        pckt_str += 'script finds match, done'
                        out_str += pckt_str
                        break
            else:
                out_str += pckt_str
                break
            time.sleep(1)
    except:
        out_str += "script error: exception was thrown"
    finally:
        output_match(out_str, out_file)
