.. Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause

==============================
SR-IOV and trusted VFs support
==============================

This note is to document the meaning of trusted VFs and which features
it can enable that non trusted VFs do not have access to.

From a quick search it does seem that what a trusted VF means is not
entirely defined and probably up for interpretation:

-  “grant to the VF all the privilege groups the PF has” Edward Cree
   from SFC `ML <https://patchwork.ozlabs.org/patch/474105/>`__
-  “Trusted VFs would be allowed to receive promiscuous and multicast
   promiscuous data.” Yuval Mintz from Cavium
   `ML <https://www.mail-archive.com/netdev@vger.kernel.org/msg145303.html>`__
-  “perform some privileged operations, such as enabling VF promiscuous
   mode and changing VF MAC address within the guest” Openstack
   `doc <https://specs.openstack.org/openstack/nova-specs/specs/rocky/implemented/sriov-trusted-vfs.html>`__

List of use cases:

1. Change the VF MAC address from the VF e.g. ip link set dev ethX
   addr 66\:11\:22\:33\:44\:55

2. Enable promiscuous mode e.g.ifconfig ethX promisc

3. Enable multicast promiscuous mode e.g. ifconfig ethX allmulti

Other NICs
==========

What do Intel and Mellanox do for the 3 use cases:

1. Change the VF MAC address from the VF. All listed NICs allow
changing the VF MAC address (with packets being steer) at least until
the PF sets it e.g. ip link set ethX vf 0 mac 66:11:22:33:44:55

* Mellanox Connectx-4 (2x25Gbps): the VF’s MAC address can be set from
  the VF even after it being set from the PF
* Intel Fortville (2x40Gbps): only allows the VF to change its MAC
  address if the PF has not set yet the VF's MAC
* Intel 'ixgbe': same as Fortville
* Intel 'igb': same as Fortville

Note that the VFs come up with MAC addresses set by the PF to
00:00:00:00:00:00 as in:

::

   # ip link show
   1: lo: mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
       link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
   2: enp7s0f0: mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
       link/ether 68:05:ca:34:8d:48 brd ff:ff:ff:ff:ff:ff
       vf 0 MAC 00:00:00:00:00:00, spoof checking on, link-state auto, trust off
       vf 1 MAC 00:00:00:00:00:00, spoof checking on, link-state auto, trust off

And that seems to be used to indicate whether the PF has set or not
the VF's MAC. When a VF driver is binded it will read the 0's and
create its own random MAC that is accepted and used by the NIC to
steer packets. Note that the PF set MAC addresses for VFs remain set
to 0s.

2. Enable promiscous mode

* Intel Fortville: in trusted mode a VF gets most packets within the
  same vlan subnet (on a ping both ARP request/reply and ICMP echo
  reply, not ICMP echo request, potential bug?). In non-trusted mode
  (default) the promisc mode is accepted, a warning is printed in the
  logs "i40e 0000:07:00.0: Unprivileged VF 0 is attempting to
  configure promiscuous mode" and there is no impact in the number of
  packets seen (even packets to/from another VF in the same vlan ID
  are not seen)

* Mellanox Connectx-4: no difference between trusted or non trusted
  mode, a VF can only see its own packets and multicast like ARP query
  "who has" on the same vlan subnet.

3. Enable multicast promiscuous mode: similar to promiscuous mode just
   only multicast packets

-  Intel Fortville: the only difference between trusted and non trusted
   is the same warning in the logs as for promiscuous mode. VFs can see
   multicast packets from the same vlan subnet.
-  Mellanox Connectx-4: no difference between trusted or non trusted
   mode, a VF can only see its own packets and multicast like ARP query
   "who has" on the same vlan subnet.

NFP trusted VF support
======================

1. Replicate Intel behaviour of letting the non-trusted VF to change
   its own MAC address only until the PF has set it. And after that
   let only trusted VFs to change their MAC. Also to set VF MAC
   addresses to 0 as seen by the PF netdevs
2. Replicate Intel behaviour for promiscous mode
3. Ignore multicast promiscous mode until really needed.
