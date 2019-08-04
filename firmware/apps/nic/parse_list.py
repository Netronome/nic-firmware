#!/usr/bin/env python

# Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

import re
import sys
import argparse

[ADDRESS, LABEL, DEBUG, INSTRUCTION] = range(4)

def parse_list(filename, label_prefix, jump_comment_tag, offsets=[]):
    targets = set()
    jump_targets = set()
    uwords = []
    labels = []
    debug = []
    spill = []
    optimizer = []
    instructions = []
    addr = 0
    uword_pat = re.compile(r'^\.([0-9]+)\s+([a-zA-Z0-9]+)\s+')
    label_pat = re.compile(r'^\s*(\w+#):')
    debug_pat = re.compile(r'\.%line')
    skip_pat = re.compile(r'^[\.\;\#]') #skip_pat = re.compile(r'^[\.\;\#]')
    end_pat = re.compile(r'\+ucode_end')
    ins_target_pat = re.compile(r'\w+#')
    label_info = []
    debug_info = ''
    #extra_info = ''
    instruction = ''
    busy = False

    jump_addr = -1

    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()

            # ucode_end
            s = end_pat.search(line)
            if s:
                labels.append(label_info)
                debug.append(debug_info)
                targets |= set(ins_target_pat.findall(instruction))

                if instruction.find('jump[') == 0:
                    jump_targets |= set(ins_target_pat.findall(instruction))

                instructions.append(instruction)
                break

            # uword
            s = uword_pat.search(line)
            if s:
                addr = int(s.group(1))
                uwords.append(addr)
                if busy:
                    labels.append(label_info)
                    label_info = []
                    debug.append(debug_info)
                    debug_info = ''
                    #extra.append(extra_info)
                    #extra_info = ''
                    targets |= set(ins_target_pat.findall(instruction))
                    if instruction.find('jump[') == 0:
                        jump_targets |= set(ins_target_pat.findall(instruction))

                        if (jump_addr == -1) and (jump_comment_tag in instruction):
                            jump_addr = addr

                    instructions.append(instruction)
                    instruction = ''

                else:
                    busy = True
                continue

            # label
            s = label_pat.search(line)
            if s:
                label_info.append(s.group(1))
                continue

            # GPR spill
            '''
            s = gpr_spill_line.match(line)
            if s:
; Following instruction modified for GPR spill
            '''

            # debug
            s = debug_pat.search(line)
            if s:
                # Remember last .%line before the instruction
                debug_info = line
                continue

            # Lines to ignore
            s = skip_pat.search(line)
            if s:
                continue

            # Assume this is part of the (possibly multi-line) instruction
            if busy:
                if len(instruction):
                    instruction += ' '
                instruction += line

    f.close()

    for i, l in enumerate(labels):
        labels[i] = sorted(targets & set(l))

        if len(labels[i]) > 0:
            if label_prefix in labels[i][0]:
                if jump_addr > -1:
                    offsets.append(uwords[i] - jump_addr)


def write_header_file(array_type, array_name, header_file_name, offsets = []):

    lines = []

    with open(header_file_name + '.h', 'w') as f:

        lines.append('#ifndef __' + str(header_file_name).upper() + '_H\n')
        lines.append('#define __' + str(header_file_name).upper() + '_H\n')

        lines.append('\n')

        lines.append(array_type + ' ' + array_name + '[] = {')

        i = 1
        for offset in offsets:
            if(i < len(offsets)):
                lines.append(str(offset) + ', ')
            else:
                lines.append(str(offset) + '}\n ')
            i = i + 1

        lines.append('\n')

        lines.append('#endif\n')
        f.writelines(lines)


    f.close()

if __name__ == '__main__':


    offsets = []
    array_name = ''
    header_file_name = ''

    parser = argparse.ArgumentParser(
        description='Parse list file')

    parser.add_argument('--label_prefix', '-l', action='store', required=True,
                        help='label prefix to find offsets for')

    parser.add_argument('--jump_table_tag', '-j', action='store', required=True,
                        help='Tag to identify the jump table. Will be used as array name')

    parser.add_argument('--header_file_name', '-f', action='store',
                        help='Header file name. If none is given, file name will be in the format JUMP_TABLE_TAG.h')

    parser.add_argument('--array_type', '-t', action='store', default='unsigned int',
                        help='Array type to use. If none is given, type unsigned int will be used')

    parser.add_argument('--array_name', '-a', action='store',
                        help='Array name. If none is given, array name will be in the format ARRAY_TYPE JUMP_TABLE_TAG[] = {}')

    parser.add_argument('listfile',
                        help='List file to parse')

    global arguments
    arguments = parser.parse_args()

    if(arguments.array_name == None):
        array_name = arguments.jump_table_tag

    if(arguments.header_file_name == None):
        header_file_name = arguments.jump_table_tag


    try:
        parse_list(arguments.listfile, arguments.label_prefix, arguments.jump_table_tag, offsets)
        write_header_file(arguments.array_type, array_name, header_file_name, offsets)
    except:
        print 'Error parsing ' + arguments.listfile
        sys.exit(1)





