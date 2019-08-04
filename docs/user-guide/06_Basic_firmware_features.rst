.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Basic Firmware Features
=======================

In this section ``ethtool`` will be used to view and configure SmartNIC
interface parameters.

Setting Interface Settings
--------------------------

Unless otherwise stated, changing the interface settings detailed below will
not require reloading of the NFP drivers for changes to take effect, unlike the
interface breakouts described in :ref:`04_Using_linux_driver:Configuring
Interface Media Mode`.

Multiple Queues
---------------

The Physical Functions on a SmartNIC support multiple transmit and receive
queues.

View current settings
`````````````````````

The ``-l`` flag can be used to view current queue/channel configuration e.g::

    #ethtool -l ens1np0
    Channel parameters for ens1np0:
    Pre-set maximums:
    RX:             20
    TX:             20
    Other:          2
    Combined:       20
    Current hardware settings:
    RX:             0
    TX:             12
    Other:          2
    Combined:       8

Configure Queues
````````````````

The ``-L`` flag can be used to change interface queue/channel configuration.
The following parameters can be configured:

rx
    Receive ring interrupts
tx
    Transmit ring interrupts
combined
    interrupts that service both rx & tx rings

.. note::

    Having RXR-only and TXR-only interrupts are not allowed.

In practice use this formula to calculate parameters for the ethtool command:
combined = min(RXR, TXR) ; rx = RXR - combined ; tx = TXR - combined

To configure 8 combined interrupt servicing::

    # ethtool -L <intf> rx 0 tx 0 combined 8

Receive side scaling (RSS)
--------------------------

RSS is a technology that focuses on effectively distributing received traffic
to the spectrum of RX queues available on a given network interface based on a
hash function.

View current hash parameters
````````````````````````````

The ``-n`` flag can be used to view current RSS configuration, for example by
default::

    # ethtool -n <netdev> rx-flow-hash tcp4
    TCP over IPV4 flows use these fields for computing Hash flow key:
    IP SA
    IP DA
    L4 bytes 0 & 1 [TCP/UDP src port]
    L4 bytes 2 & 3 [TCP/UDP dst port]

    # ethtool -n <netdev> rx-flow-hash udp4
    UDP over IPV4 flows use these fields for computing Hash flow key:
    IP SA
    IP DA

Set hash parameters
```````````````````

The ``-N`` flag can be used to change interface RSS configuration e.g::

    # ethtool -N <netdev> rx-flow-hash tcp4 sdfn
    # ethtool -N <netdev> rx-flow-hash udp4 sdfn

The ``ethtool`` man pages can be consulted for full details of what RSS flags
may be set

Configuring the key
```````````````````

The ``-x`` flag can be used to view current interface key configuration, for
example::

    # ethtool -x <intf>
    # ethtool -X <intf> <hkey>

View Interface Parameters
-------------------------

The ``-k`` flag can be used to view current interface configurations, for
example using a Agilio CX 1x40GbE NIC which has an interface id ``enp4s0np0``::

    # ethtool -k <netdev>
    Features for enp4s0np0:
    rx-checksumming: off [fixed]
    tx-checksumming: off
    tx-checksum-ipv4: off [fixed]
    tx-checksum-ip-generic: off [fixed]
    tx-checksum-ipv6: off [fixed]
    tx-checksum-fcoe-crc: off [fixed]
    tx-checksum-sctp: off [fixed]
    scatter-gather: off
    tx-scatter-gather: off [fixed]
    tx-scatter-gather-fraglist: off [fixed]
    tcp-segmentation-offload: off
    tx-tcp-segmentation: off [fixed]
    tx-tcp-ecn-segmentation: off [fixed]
    tx-tcp6-segmentation: off [fixed]
    tx-tcp-mangleid-segmentation: off [fixed]
    udp-fragmentation-offload: off [fixed]
    generic-segmentation-offload: off [requested on]
    generic-receive-offload: on
    large-receive-offload: off [fixed]
    rx-vlan-offload: off [fixed]
    tx-vlan-offload: off [fixed]
    ntuple-filters: off [fixed]
    receive-hashing: off [fixed]
    highdma: off [fixed]
    rx-vlan-filter: off [fixed]
    vlan-challenged: off [fixed]
    tx-lockless: off [fixed]
    netns-local: off [fixed]
    tx-gso-robust: off [fixed]
    tx-fcoe-segmentation: off [fixed]
    tx-gre-segmentation: off [fixed]
    tx-ipip-segmentation: off [fixed]
    tx-sit-segmentation: off [fixed]
    tx-udp_tnl-segmentation: off [fixed]
    fcoe-mtu: off [fixed]
    tx-nocache-copy: off
    loopback: off [fixed]
    rx-fcs: off [fixed]
    rx-all: off [fixed]
    tx-vlan-stag-hw-insert: off [fixed]
    rx-vlan-stag-hw-parse: off [fixed]
    rx-vlan-stag-filter: off [fixed]
    busy-poll: off [fixed]
    tx-gre-csum-segmentation: off [fixed]
    tx-udp_tnl-csum-segmentation: off [fixed]
    tx-gso-partial: off [fixed]
    tx-sctp-segmentation: off [fixed]
    l2-fwd-offload: off [fixed]
    hw-tc-offload: on
    rx-udp_tunnel-port-offload: off [fixed]

Receive Checksumming (rx-checksumming)
``````````````````````````````````````

When enabled, checksum calculation and error checking comparison for received
packets is offloaded to the NFP SmartNIC’s flow processor rather than the host
CPU.

To enable rx-checksumming::

    # ethtool -K <netdev> rx on

To disable rx-checksumming::

    # ethtool -K <netdev> rx off

Transmit Checksumming (tx-checksumming)
```````````````````````````````````````

When enabled, checksum calculation for outgoing packets is offloaded to the NFP
SmartNIC’s flow processor rather than the host’s CPU.

To enable tx-checksumming::

    # ethtool -K <netdev> tx on

To disable tx-checksumming::

    # ethtool -K <netdev> tx off

Scatter and Gather (scatter-gather)
```````````````````````````````````

When enabled the NFP will use scatter and gather I/O, also known as Vectored
I/O, which allows a single procedure call to sequentially read data from
multiple buffers and write it to a single data stream. Only changes to the
scatter-gather interface settings (from ``on`` to ``off`` or ``off`` to ``on``)
will produce a terminal output as shown below:

To enable scatter-gather::

    # ethtool -K <netdev> sg on
    Actual changes:
    scatter-gather: on
            tx-scatter-gather: on
    generic-segmentation-offload: on

To disable scatter-gather::

    # ethtool -K <netdev> sg off
    Actual changes:
    scatter-gather: on
            tx-scatter-gather: on
    generic-segmentation-offload: on

TCP Segmentation Offload (TSO)
``````````````````````````````

When enabled, this parameter causes all functions related to the segmentation
of TCP packets at egress to be offloaded to the NFP.

To enable tcp-segmentation-offload::

    # ethtool -K <netdev> tso on

To disable tcp-segmentation-offload::

    # ethtool -K <netdev> tso off

Generic Segmentation Offload (GSO)
``````````````````````````````````

This parameter offloads segmentation for transport layer protocol data units
other than segments and datagrams for TCP/UDP respectively to the NFP. GSO
operates at packet egress.

To enable generic-segmentation-offload::

    # ethtool -K <netdev> gso on

To disable generic-segmentation-offload::

    # ethtool -K <netdev> gso off

Generic Receive Offload (GRO)
`````````````````````````````

This parameter enables software implementation of Large Receive Offload (LRO),
which aggregates multiple packets at ingress into a large buffer before they
are passed higher up the networking stack.

To enable generic-receive-offload::

    # ethtool -K <netdev> gro on

To disable generic-receive-offload::

    # ethtool -K <netdev> gro off

.. note::

    Do take note that scripts that use ethtool -i <interface> to get bus-info
    will not work on representors as this information is not populated for
    representor devices.
