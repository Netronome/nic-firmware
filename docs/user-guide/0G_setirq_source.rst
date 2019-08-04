.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Appendix G: set_irq_affinity.sh Source
======================================

.. code-block:: bash
    :linenos:

    #!/bin/bash -e

    # Copyright (C) 2018 Netronome Systems, Inc.
    #
    # This software is dual licensed under the GNU General License Version 2,
    # June 1991 as shown in the file COPYING in the top-level directory of this
    # source tree or the BSD 2-Clause License provided below.  You have the
    # option to license this software under the complete terms of either license.
    #
    # The BSD 2-Clause License:
    #
    #     Redistribution and use in source and binary forms, with or
    #     without modification, are permitted provided that the following
    #     conditions are met:
    #
    #      1. Redistributions of source code must retain the above
    #         copyright notice, this list of conditions and the following
    #         disclaimer.
    #
    #      2. Redistributions in binary form must reproduce the above
    #         copyright notice, this list of conditions and the following
    #         disclaimer in the documentation and/or other materials
    #         provided with the distribution.
    #
    # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    # MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
    # BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
    # ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    # SOFTWARE.

    usage() {
        echo "Usage: $0 NETDEV"
        echo "          Optional env vars: IRQ_NAME_FMT"
        exit 1
    }

    [ $# -ne 1 ] && usage

    [ "a$IRQ_NAME_FMT" == a ] && IRQ_NAME_FMT=$1-rxtx

    DEV=$1
    if ! [ -e /sys/bus/pci/devices/$DEV ]; then
        DEV=$(ethtool -i $1 | grep bus | awk '{print $2}')
        N_TX=$(ls /sys/class/net/$1/queues/ | grep tx | wc -l)
        N_CPUS=$(ls /sys/bus/cpu/devices/ | wc -l)
    fi

    [ "a$DEV" == a ] && usage

    NODE=$(cat /sys/bus/pci/devices/$DEV/numa_node)
    CPUL=$(cat /sys/bus/node/devices/node${NODE}/cpulist | tr ',' ' ')

    N_NODES=$(ls /sys/bus/node/devices/ | wc -l)

    for c in $CPUL; do
        # Convert "n-m" into "n n+1 n+2 ... m"
        [[ "$c" =~ '-' ]] && c=$(seq $(echo $c | tr '-' ' '))

        CPUS=(${CPUS[@]} $c)
    done

    echo Device $DEV is on node $NODE with cpus ${CPUS[@]}

    IRQBAL=$(ps aux | grep irqbalance | wc -l)

    [ $IRQBAL -ne 1 ] && echo Killing irqbalance && killall irqbalance

    IRQS=$(ls /sys/bus/pci/devices/$DEV/msi_irqs/)


    IRQS=($IRQS)

    node_mask=$((~(~0 << N_NODES)))
    node_shf=$((N_NODES - 1))
    cpu_shf=$((N_TX << node_shf))

    p_mask=0
    id=0
    for i in $(seq 0 $((${#IRQS[@]} - 1)))
    do
        ! [ -e /proc/irq/${IRQS[i]} ] && continue

        name=$(basename /proc/irq/${IRQS[i]}/$IRQ_NAME_FMT*)
        ls /proc/irq/${IRQS[i]}/$IRQ_NAME_FMT* >>/dev/null 2>/dev/null || continue

        cpu=${CPUS[id % ${#CPUS[@]}]}

        m=0
        m_mask=node_mask
        if [ $N_TX -gt $((id + ${#CPUS[@]})) ]; then
            # Only take one CPU if there will be more rings on this CPU
            m_mask=1
        fi
        # Calc the masks we should cover
        for j in `seq 0 $cpu_shf $((N_CPUS - 1))`; do
            m=$((m << cpu_shf | (m_mask << ((cpu >> node_shf) << node_shf))))
            m=$((m & ~p_mask))
        done
        xps_mask=$(printf "%x" $((m % (1 << N_CPUS))))
        # Insert comma between low and hi 32 bits, if xps_mask is long enough
        xps_mask=`echo $xps_mask | sed 's/\(.\)\(.\{8\}$\)/\1,\2/'`
        p_mask=$((p_mask | m))

        echo $cpu > /proc/irq/${IRQS[i]}/smp_affinity_list
        irq_state="irq: $(cat /proc/irq/${IRQS[i]}/smp_affinity)"

        xps_state='xps: ---'
        xps_file=/sys/class/net/$1/queues/tx-$id/xps_cpus
        if [ -e $xps_file ]; then
            echo $xps_mask > $xps_file
            xps_state="xps: $(cat $xps_file)"
        fi

        echo -e "IRQ ${IRQS[i]} to CPU $cpu     ($irq_state $xps_state)"
        ((++id))
    done
