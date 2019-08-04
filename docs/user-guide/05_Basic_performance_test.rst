.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Basic Performance Test
======================

iPerf is a basic traffic generator and network performance measuring tool that
can be used to quickly determine the throughput achievable by a device.

Set IRQ affinity
----------------

Balance interrupts across available cores located on the NUMA node of the
SmartNIC. A script to perform this action is available for download at
https://raw.githubusercontent.com/Netronome/nfp-drv-kmods/master/tools/set_irq_affinity.sh

The source code of this script is also included at
:ref:`0G_setirq_source:Appendix G: set_irq_affinity.sh Source`

Example output::

    # /nfp-drv-kmods/tools/set_irq_affinity.sh <netdev>

    Device 0000:02:00.0 is on node 0 with cpus 0 1 2 3 4 5 6 7 8 9 20 21 22 23 24 25 26 27 28 29
    IRQ 181 to CPU 0     (irq: 00,00000001 xps: 03,00030003)
    IRQ 182 to CPU 1     (irq: 00,00000002 xps: 00,00000000)
    IRQ 183 to CPU 2     (irq: 00,00000004 xps: 0c,000c000c)
    IRQ 184 to CPU 3     (irq: 00,00000008 xps: 00,00000000)
    IRQ 185 to CPU 4     (irq: 00,00000010 xps: 30,00300030)
    IRQ 186 to CPU 5     (irq: 00,00000020 xps: 00,00000000)
    IRQ 187 to CPU 6     (irq: 00,00000040 xps: c0,00c000c0)
    IRQ 188 to CPU 7     (irq: 00,00000080 xps: 00,00000000)

Install iPerf
-------------

Ubuntu::

    # apt-get install -y iperf

CentOS/RHEL::

    # yum install -y iperf

Run iPerf Test
--------------

Server
``````

Run ``iPerf`` on the server::

    # ip address add 10.0.0.1/24 dev ens1np0
    # iperf -s

Client
``````

Allocate an ip address on the same range as used by the server, then execute
the following on the client to connect to the server and start running the
test::

    # iperf -c 10.0.0.1 -P 4

Example output of 1x40G link::

    # iperf -c 10.0.0.1 -P 4
    ------------------------------------------------------------
    Client connecting to 10.1, TCP port 5001
    TCP window size: 85.0 KByte (default)
    ------------------------------------------------------------
    [  5] local 10.0.0.2 port 56938 connected with 10.0.0.1 port 5001
    [  3] local 10.0.0.2 port 56932 connected with 10.0.0.1 port 5001
    [  4] local 10.0.0.2 port 56934 connected with 10.0.0.1 port 5001
    [  6] local 10.0.0.2 port 56936 connected with 10.0.0.1 port 5001
    [ ID] Interval       Transfer     Bandwidth
    [  6]  0.0-10.0 sec  11.9 GBytes  10.3 Gbits/sec
    [  3]  0.0-10.0 sec  9.85 GBytes  8.46 Gbits/sec
    [  4]  0.0-10.0 sec  11.9 GBytes  10.2 Gbits/sec
    [  5]  0.0-10.0 sec  10.2 GBytes  8.75 Gbits/sec
    [SUM]  0.0-10.0 sec  43.8 GBytes  37.7 Gbits/sec

Using iPerf3
------------

iPerf3 can also be used to measure performance, however multiple instances have
to be chained to properly create multiple threads:

On the server::

    # iperf3 -s -p 5001 & iperf3 -s -p 5002 & iperf3 -s -p 5003 & iperf3 -s -p 5004 &

On the client::

    # iperf3 -c 102.0.0.6 -i 30 -p 5001 & iperf3 -c 102.0.0.6 -i 30 -p 5002 & iperf3 -c 102.0.0.6 -i 30 -p 5003 & iperf3 -c 102.0.0.6 -i 30 -p 5004 &

    Example output:

    [ ID] Interval           Transfer     Bandwidth
    [  5]   0.00-10.04  sec  0.00 Bytes  0.00 bits/sec                  sender
    [  5]   0.00-10.04  sec  9.39 GBytes  8.03 Gbits/sec                  receiver
    [  5]  10.00-10.04  sec  33.1 MBytes  7.77 Gbits/sec
    - - - - - - - - - - - - - - - - - - - - - - - - -
    [ ID] Interval           Transfer     Bandwidth
    [  5]   0.00-10.04  sec  0.00 Bytes  0.00 bits/sec                  sender
    [  5]   0.00-10.04  sec  9.86 GBytes  8.44 Gbits/sec                  receiver
    [  5]  10.00-10.04  sec  53.6 MBytes  11.8 Gbits/sec
    - - - - - - - - - - - - - - - - - - - - - - - - -
    [ ID] Interval           Transfer     Bandwidth
    [  5]   0.00-10.04  sec  0.00 Bytes  0.00 bits/sec                  sender
    [  5]   0.00-10.04  sec  11.9 GBytes  10.2 Gbits/sec                  receiver
    [  5]  10.00-10.04  sec  42.1 MBytes  9.43 Gbits/sec
    - - - - - - - - - - - - - - - - - - - - - - - - -
    [ ID] Interval           Transfer     Bandwidth
    [  5]   0.00-10.04  sec  0.00 Bytes  0.00 bits/sec                  sender
    [  5]   0.00-10.04  sec  10.2 GBytes  8.70 Gbits/sec                  receiver

    Total: 37.7 Gbits/sec

    95.49% of 40GbE link
