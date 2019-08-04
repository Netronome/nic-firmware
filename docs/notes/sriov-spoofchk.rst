.. Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause

=================
SRIOV VF SPOOFCHK
=================

The SRIOV spoofchk option allows the PF to prevent network packets originating
from an associated SRIOV VF interface, from spoofing its source MAC address.

The authoritative SRIOV MAC address (set by the PF), is set for a particular VF
interface as follows:

::

 ip link set ens1np0 vf 0 mac 10:20:30:40:50:60

(In the example above, the PF is interface ens1np0 and VF0 is affected.)

In order to prevent source MAC spoofing, the PF must enable spoofchk on the VF
interface as follows:

::

 ip link set ens1np0 vf 0 spoofchk on

The result is that any packet sent from the VF with a different source MAC
address should be dropped by the interface. This only affects VF TX.

Differences in behaviours
-------------------------

The example above is a simplification looking only at a very straight forward
use case.

The spoofchk feature is affected by many factors, all interpreted slightly
different by vendors.

Factors which influence behavior between vendors are:

1. VF trust
2. Uninitialized or zeroed SRIOV MAC (00:00:00:00:00:00)
3. VF spoofchk

Intel i40e vs Mellanox Connect-X5
=================================

In order to make the table more readable, please assume:

::

 MAC:0 => 00:00:00:00:00:00
 MAC:X => 10:20:30:40:50:0X
 MAC:Y => 10:20:30:40:50:0Y

Mellanox
--------
::

 driver: mlx5_core
 version: 4.5-1.0.1
 firmware-version: 16.25.1020 (MT_0000000080)

Intel (i40e)
------------
::

 driver: i40e
 version: 2.1.14-k
 firmware-version: 6.80 0x80003d05 1.2007.0

Test Results
------------
::

 SRIOV-MAC    VF-BAR-MAC   PACKET-SRC-MAC    SPOOFCHK   TRUST      PASS-MLX   PASS-INTEL
 MAC:0        MAC:X        MAC:Y             NO         off        yes        yes
 MAC:0        MAC:X        MAC:Y             YES        off        yes        no
 MAC:0        MAC:X        MAC:X             YES        off        yes        yes
 MAC:X        MAC:X        MAC:Y             YES        off        no         no
 MAC:Y        MAC:X        MAC:Y             YES        off        yes        yes
 MAC:Y        MAC:X        MAC:X             YES        off        no         no
 MAC:0        MAC:X        MAC:Y             NO         on         yes        yes
 MAC:0        MAC:X        MAC:Y             YES        on         yes        no
 MAC:0        MAC:X        MAC:X             YES        on         yes        yes
 MAC:X        MAC:X        MAC:Y             YES        on         no         no
 MAC:Y        MAC:X        MAC:Y             YES        on         yes        yes
 MAC:Y        MAC:X        MAC:X             YES        on         no         yes
 MAC:Y        MAC:X        MAC:Z             YES        on         no         no

Tests outcome
=============

VF trust disabled (default)
---------------------------

First lets look at the simpler scenario before we introduce
trusted VFs (default startup state).

::

 ip link set ens1np0 vf 0 trust off

In the Mellanox case, the SRIOV MAC is considered the only authoritative source.
This means that even if spoofchk is requested, if the SRIOV MAC is
uninitialized (00:00:00:00:00:00) or explicitly set to zeros, the behavior
is as if spoofchk is off (no drops).

In the Intel case, the SRIOV MAC is considered the authoritative source,
except when it is uninitialized (00:00:00:00:00:00) or explicitly set to
zeros. In the latter case, the MAC set in the VF BAR is used as the
authoritative source.

VF trust enabled
----------------

Next, let's look at the scenario when VF trust is enabled.

::

 ip link set ens1np0 vf 0 trust on

In the Mellanox case spoofchk behavior is not affected by VF trust.

In the Intel i40e case, when the VF is trusted, both the SRIOV MAC and also
the VF BAR MAC is considered valid. If we adopt this behavior, we will have
to perform two checks.
