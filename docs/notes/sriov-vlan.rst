.. Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause

====================
SR-IOV and VLAN note
====================

This note aim is to document how traffic is treated by our SR-IOV
capable NIC FW when it comes to VLAN tags.

It is useful to have the following definitions:

-  SRIOV-VLAN: this is the VLAN that a VF is configured with. It is done
   from the PF with command like "ip link set nfp\_p0 vf 0 100". Note
   that VFs are not aware of this VLAN, it is set by the data center
   operator and invisible to the VFs. It gets pushed into the packet by
   the device before transmitting on the wire and is popped out before
   sending to a VF.
-  VLAN traffic: packets associated with a VLAN, either in the packet
   itself or in the TX descriptor. Note that currently
   "rx/tx-vlan-offload" capability is not present for VFs [nor is this
   presently supported on the PF in CoreNIC]
-  Untagged traffic: opposed to the VLAN traffic these are pkts with no
   VLAN tag on them.

On TX (host to wire/host)
=========================

There are a few traffic paths:

1. pkt comes from a PF (vnic/kernel-netdev/dpdk-app): it gets sent as
   is, the PF is trusted.

2. If the pkt comes untagged (no VLAN) from a VF and this VF is
   configured with an SRIOV-VLAN then such VLAN tag is added to it and
   sent. Note that this VLAN is configured by the data center operator
   with e.g. "ip link set nfp\_p0 vf 0 100" and invisible to the
   customer running VMs/other-things in the VF.

   2.1 if the pkt arrives with a VLAN tag the pkt is dropped. That is the
   behaviour with at least Mellanox. It also avoids having to support 2
   VLAN tags on TX and RX. [CoreNIC presently nests VLANs]

3. If the pkt comes from a VF and this VF has not been configured with a
   SRIOV-VLAN (default): then this VF is trusted when it comes to VLAN
   tags.

In case 1. and 3. the pkt with a VLAN tag is not dropped and sent as is.
This VLAN-tagged traffic would come from a VLAN interface created "over"
the regular interface. This VLAN interface id is known to the PF or VF
where the packet comes from but not to the SR-IOV capable NIC VEB.

On RX (wire to host)
====================

1. if pkt is destined to a PF: traffic will be switched by the VEB to
   this PF. The VEB will have an entry with the MAC address of e.g. the
   PF netdev, with no VLAN being set. This entry is created when the
   interface is brought up [CoreNIC has a PF entry in the VEB for each
   possible VLAN].

   a. as a sub case if the pkt was destined to a VLAN interface "within"
      a PF e.g. nfp\_p0.100 then there are 2 options. If the PF had the
      "vlan-filtering" offload enabled then the VEB would be programmed
      with an additional entry with the PF MAC + VLAN. Such pkt will hit
      this entry and reach the desired destination. If "vlan-filtering"
      was off then the VEB would not have that additional entry and so
      the lkp would fail. To support this use case then after a VEB
      lookup miss a loop over the PF netdevs MAC addresses is done (only
      for those with the offload disabled). Note that the
      "vlan-filtering" offload is then only useful to optimize the
      traffic to a PF VLAN netdev and not strictly required for SR-IOV
      support.

2. if pkt is destined to a VF and this VF is configured with a
   SRIOV-VLAN: the pkt needs to have the set VF MAC and VLAN to hit the
   VEB entry and reach the VF. Note that an entry in the VEB that would
   match such VLANed traffic may only exist when the VF was set with an
   SRIOV-VLAN.

3. if pkt is destined to a VF and this VF has no VLAN configured: the
   VEB will have a single entry with the MAC and no-VLAN. Then there are
   2 options: [CoreNIC has a VF entry in the VEB for each possible VLAN]

   a. pkt has no VLAN: it hits the VEB entry and goes to the VF

   b. pkt has a VLAN: this VLAN is unknown to the VEB, after all the VF
      has not been configured with a SRIOV-VLAN. To support this pkt
      reaching the VF as other NICs (Fortville and Mellanox Connectx-3)
      do the solution is:

      1. for multicast traffic e.g. ARP who-has, mirror the pkt not only
         to all VFs in the same VLAN, also to those VFs without a set
         SRIOV-VLAN.
      2. for unicast traffic that has a vlan tag on it and the VEB
         lookup misses then we should do a second lookup with vlan part
         of the key being 'unset'. If that hits a particular VF then we
         check if that VF has not been set on a SRIOV-VLAN tag.

   Note that 3.b.1 is to cover both traffic on between VFs on the same
   SR-IOV VLAN and also all VFs with no SR-IOV VLAN.

   Note this discards the option to add "vlan-filtering" support to the
   VF so that VEB has an entry per vlan interface. The reason is that
   the goal is to support the oldest possible upstream VF driver
   (vanilla linux 4.5)
