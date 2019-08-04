.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Using the Linux Driver
======================

.. Configuring SR-IOV
   ------------------
   To configure SR-IOV virtual functions, make sure that SR-IOV is enabled in
   the bios of the host machine. If SR-IOV is disabled or unsupported by the
   motherboard/chipset being used, ``dmesg`` will return a ``PCI SR-IOV:-12``
   error when trying to create a VF. The number of supported virtual functions
   on a netdev is exposed by ``sriov_totalvfs`` in ``sysfs``. For example, if
   *<netdev>* is the  interface associated with the SmartNIC's physical
   function, the following command will output:
   .. code-block:: text
       # cat /sys/class/net/<netdev>/device/sriov_totalvfs
       55
   Virtual functions can be allocated to an network interface (not it’s ports)
   by writing an integer to the sysfs file. For example, to allocate 16 virtual
   functions to *<netdev>*:
   .. code-block:: text
       # echo 16 > /sys/class/net/<netdev>/device/sriov_numvfs
   SR-IOV Virtual functions cannot be re-allocated dynamically. In order to
   change the number of allocated virtual functions, existing functions must
   first be deallocated by writing a ``0`` to the ``sysfs`` file. Otherwise the
   system will return a ``device or resource busy`` error.
   .. code-block:: text
       # echo 0 > /sys/class/net/<netdev>/device/sriov_numvfs
   .. note::
       Make sure to shutdown any VMs or stop any apps that may be using the VFs
       before deallocating them.
   In order to persist the virtual functions on the system, it is suggested
   that the system networking scripts be updated to manage them. The following
   snippet illustrates how to do this with *NetworkManager* for the physical
   function ``p5p1``:
   .. code-block:: text
       # cat >/etc/NetworkManager/dispatcher.d/99-create-vfs << EOF
       #!/bin/sh
       # This is a NetworkManager script to persist the maximum number of VF's
       on a netdev
       [ "p5p1" == "\$1" -a "up" == "\$2" ] && \
           cat /sys/class/net/p5p1/device/sriov_totalvfs >
           /sys/class/net/p5p1/device/sriov_numvfs
        exit
        EOF
        # chmod 755 /etc/NetworkManager/dispatcher.d/99-create-vfs

Configuring Interface Media Mode
--------------------------------

The following sections detail the configuration of the SmartNIC netdev
interfaces.

.. note::

    For older kernels that do not support the configuration methods outlined
    below, please refer to :ref:`0C_Working_with_BSP:Appendix C: Working with
    Board Support Package` on how to make use of the BSP toolset to configure
    interfaces.

Configuring interface link-speed
````````````````````````````````

The following steps explains how to change between 10G mode and 25G mode
on Agilio CX 2x25GbE cards.  The changing of port speed must be done in order,
p0 must be set to 10G before p1 may be set to 10G.

Down the respective interface(s)::

    # ip link set dev enp4s0np0 down

Set interface link-speed to 10G::

    # ethtool -s enp4s0np0 speed 10000

Set interface link-speed to 25G::

    # ethtool -s enp4s0np0 speed 25000

Reload driver for changes to take effect::

    # rmmod nfp; modprobe nfp

.. note::

    The settings above only apply to Agilio CX 25G SmartNICs and older
    drivers/firmware changes may require a system reboot for changes to take
    effect

Configuring interface Maximum Transmission Unit (MTU)
-----------------------------------------------------

The MTU of interfaces can temporarily be set using the ``iproute2`` or
``ifconfig`` tools. Note that this change will not persist. Setting this via
*Network Manager*, or other appropriate OS configuration tool, is recommended.

Set interface MTU to 9000 bytes::

    # ip link set dev <netdev port> mtu 9000

It is the responsibility of the user or the orchestration layer to set
appropriate MTU values when handling jumbo frames or utilizing tunnels.
For example, if packets sent from a VM are to be encapsulated on the card and
egress a physical port, then the MTU of the VF should be set to lower than that
of the physical port to account for the extra bytes added by the additional
header.

If a setup is expected to see fallback traffic between the SmartNIC and the
kernel then the user should also ensure that the PF MTU is appropriately set to
avoid unexpected drops on this path.

Configuring FEC modes
---------------------

Agilio CX 2x25GbE SmartNICs support FEC mode configuration, e.g. Auto, Firecode
BaseR, Reed Solomon and Off modes. Each physical port's FEC mode can be set
independently via the ``ethtool`` command. To view the currently supported FEC
modes of the interface use the following::

    # ethtool <netdev>
    Settings for <netdev>:
        Supported ports: [ FIBRE ]
        Supported link modes:   Not reported
        Supported pause frame use: No
        Supports auto-negotiation: No
        Supported FEC modes: None BaseR RS
        Advertised link modes:  Not reported
        Advertised pause frame use: No
        Advertised auto-negotiation: No
        Advertised FEC modes: BaseR RS
        Speed: 25000Mb/s
        Duplex: Full
        Port: Direct Attach Copper
        PHYAD: 0
        Transceiver: internal
        Auto-negotiation: on
        Link detected: yes

One can see above which FEC modes are supported for this interface. Note that
the Agilio CX 2x25GbE SmartNIC used for the example above only supports
Firecode BaseR FEC mode on ports that are forced to 10G speed.

.. note::

    Ethtool FEC support is only available in kernel 4.14 and newer or
    RHEL/Centos 7.5 and equivalent distributions. The Netronome upstream kernel
    driver provides ethtool FEC support from kernel 4.15. Furthermore, the
    SmartNIC NVRAM version must be at least 020025.020025.02006e to support
    ethtool FEC get/set operations.

To determine your version of the current SmartNIC NVRAM, look at the following
system log::

    # dmesg | grep 'nfp.*BSP'
    [2387.682046] nfp 0000:82:00.0: BSP: 020025.020025.020072

This example lists a version of ``020025.020025.020072`` which is sufficient to
support ``ethtool`` FEC mode configuration. To update your SmartNIC NVRAM
flash, refer to :ref:`0E_Updating_Flash:Appendix E: Updating NFP Flash` or
contact `Netronome support <mailto:support@netronome.com>`_.

If the SmartNIC NVRAM or the kernel does not support ``ethtool`` modification
of FEC modes, no supported FEC modes will be listed in the ``ethtool`` output
for the port. This could be because of an outdated kernel version or an
unsupported distribution (e.g. Ubuntu 16.04 irrespective of the kernel
version)::

    # ethtool enp130s0np0
    Settings for enp130s0np0:
    ...
    Supported FEC modes: None

To show the currently active FEC mode for either the *<netdev>* or its physical
port(s) *<netdev port>*::

    # ethtool --show-fec <netdev>/<netdev port>
    FEC parameters for <netdev>:
    Configured FEC encodings: Auto Off BaseR RS
    Active FEC encoding: Auto

To modify the FEC mode to Firecode BaseR::

   # ethtool --set-fec <netdev port> encoding baser

Verify the newly selected mode::

    # ethtool --show-fec enp130s0np0
    FEC parameters for enp130s0np0:
    Configured FEC encodings: Auto Off BaseR RS
    Active FEC encoding: BaseR

To modify the FEC mode to Reed Solomon::

    # ethtool --set-fec enp130s0np0 encoding rs

Verify the newly selected mode::

    # ethtool --show-fec enp130s0np0
    FEC parameters for enp130s0np0:
    Configured FEC encodings: Auto Off BaseR RS
    Active FEC encoding: RS

Verify the newly selected mode::

    # ethtool --show-fec enp130s0np0
    FEC parameters for enp130s0np0:
    Configured FEC encodings: Auto Off BaseR RS
    Active FEC encoding: Off

Revert back to the default Auto setting::

    # ethtool --set-fec enp130s0np0 encoding auto

Finally verify the setting again::

    # ethtool --show-fec enp130s0np0
    FEC parameters for enp130s0np0:
    Configured FEC encodings: Auto Off BaseR RS
    Active FEC encoding: Auto

FEC and auto-negotiation settings are persisted on the SmartNIC across reboots.

.. note::

    In this context setting the interface mode to ``auto`` specifies that the
    encoding scheme should be automatically determined if possible.  It does
    **not** enable auto-negotiation of link speed between 10Gbps and 25Gbps

Setting Interface Breakout Mode
-------------------------------

The following commands only work on kernel versions 4.13 and later. If your
kernel is older than 4.13 or you do not have devlink support enabled refer to
the following section on configuring interfaces:
:ref:`0C_Working_with_BSP:Configure Media Settings`.

.. note::

    Breakout mode settings are only applicable to Agilio CX 40GbE and CX
    2x40GbE SmartNICs.

Determine the card’s PCI address::

    # lspci -Dkd 19ee:4000
    0000:04:00.0 Ethernet controller: Netronome Systems, Inc. Device 4000
        Subsystem: Netronome Systems, Inc. Device 4001
        Kernel driver in use: nfp
        Kernel modules: nfp

List the devices::

    # devlink dev show
    pci/0000:04:00.0

Split the first physical 40G port from 1x40G to 4x10G ports::

    # devlink port split pci/0000:04:00.0/0 count 4

Split the second physical 40G port from 1x40G to 4x10G ports::

    # devlink port split pci/0000:04:00.0/4 count 4

If the SmartNIC’s port is already configured in breakout mode (it has already
been split) then devlink will respond with an argument error. Whenever change
to the port configuration are made, the original netdev(s) associated with the
port will be removed from the system::

    # dmesg | tail
    [ 5696.432306] nfp 0000:04:00.0: nfp: Port #0 config changed, unregistering. Driver reload required before port will be operational again.
    [ 6270.553902] nfp 0000:04:00.0: nfp: Port #4 config changed, unregistering. Driver reload required before port will be operational again.

The driver needs to be reloaded for the changes to take effect.
Older driver/SmartNIC NVRAM versions may require a system reboot for changes to
take effect. The driver communicates events related to port split/unsplit in
the system logs. The driver may be reloaded with the following command::

    # rmmod nfp; modprobe nfp

After reloading the driver, the netdevs associated with the split ports will be
available for use::

    # ip link show
    ...
    68: enp4s0np0s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    69: enp4s0np0s1: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    70: enp4s0np0s2: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    71: enp4s0np0s3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    72: enp4s0np1s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    73: enp4s0np1s1: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    74: enp4s0np1s2: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    75: enp4s0np1s3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000

.. note::

    There is an ordering constraint to splitting and unsplitting the ports on
    Agilio CX 2x40GbE SmartNICs. The first physical 40G port cannot be split
    without the second physical port also being split, hence 1x40G + 4x10G is
    always invalid even if it’s only intended to be a transitional mode. The
    driver will reject such configurations.

Breakout mode persists on the SmartNIC across reboots. To revert back to the
original 2x40G ports use the unsplit subcommand.

Unsplit Port 1::

    # devlink port unsplit pci/0000:04:00.0/4

Unsplit Port 0::

    # devlink port unsplit pci/0000:04:00.0/0

The NFP drivers will again have to be reloaded (``rmmod nfp`` then ``modprobe
nfp``) for unsplit changes in the port configuration to take effect.

Confirming Connectivity
-----------------------

Allocating IP Addresses
```````````````````````

Under RHEL/Centos 7.5, the network configuration is managed by default using
*NetworkManager*. The default configuration for unset interfaces is *auto*,
which implies that an auto-configuration client is running on them. This means
that any manual configuration made using ``ifconfig`` or ``iproute2`` will be
periodically erased.

Consult the *NetworkManager* documentation for detailed instructions. For
example, if a connection is named ``ens1np0`` (which corresponds to the
physical port representor ``ens1np0`` of the SmartNIC), the following commands
will set the IPv4 address statically, set it to autostart on boot, and up the
interface::

    # nmcli c m <netdev port> ipv4.method manual
    # nmcli c m <netdev port> ipv4.addresses 10.0.0.2/24
    # nmcli c m <netdev port> connection.autoconnect yes
    # nmcli c u <netdev port>

Alternatively, if the interface is not under control of the distribution's
network management subsystem, ``iproute2`` can be used to configure the port::

    # assign IP address to interface
    # ip address add 10.0.0.2/24 dev <netdev port>
    # ip link set <netdev port> up

Pinging interfaces
``````````````````

After you have successfully assigned IP addresses to the NFP interfaces perform
a standard ping test to confirm connectivity::

    # ping 10.0.0.2
    PING 10.0.0.2 (10.0.0.2) 56(84) bytes of data.
    64 bytes from 10.0.0.2: icmp_seq=3 ttl=64 time=0.067 ms
    64 bytes from 10.0.0.2: icmp_seq=4 ttl=64 time=0.062 ms
