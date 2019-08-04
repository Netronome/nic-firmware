.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Validating the Driver
=======================

The Netronome SmartNIC physical function driver with support for OVS-TC offload
is included in Linux 4.13 and later kernels. The list of minimum required
operating system distributions and their respective kernels which include the
nfp driver are as follows:

=================== ======================
Operating System    Kernel package version
=================== ======================
RHEL/CentOS 7.4+    default
Ubuntu 16.04.04 LTS default
=================== ======================

In order to upgrade Ubuntu 16.04.0 - 16.04.3 to a supported version, the
following commands must be run::

    # apt-get update
    # apt-get upgrade
    # apt-get dist-upgrade

Confirm Upstreamed NFP Driver
-----------------------------

To confirm that your current Operating System contains the upstreamed nfp
module::

    # modinfo nfp | head -3
    filename:
    /lib/modules/<kernel package version>/kernel/drivers/net/ethernet/netronome/nfp/nfp.ko.xz
    description:    The Netronome Flow Processor (NFP) driver.
    license:        GPL

.. note::

    If the module is not found in your current kernel, refer to
    :ref:`0B_Install_oot_nfp_driver:Appendix B: Installing the Out-of-Tree
    NFP Driver` for instructions on installing the out-of-tree NFP driver, or
    simply upgrade your distributions and kernel version to include the
    upstreamed drivers.

Confirm that the NFP Driver is Loaded
-------------------------------------

Use ``lsmod`` to list the loaded driver modules and use grep to match the
expression for the NFP drivers::

    # lsmod | grep nfp
    nfp                   161364  0

If the NFP driver is not loaded, try run the following command to manually
load the module::

    # modprobe nfp

SmartNIC netdev interfaces
--------------------------

The ``agilio-naming-policy`` package ensures consistent naming of Netronome
SmartNIC network interfaces. Please note that this package is **optional** and
not required if your distribution has a sufficiently new *systemd*
installation.

Please refer to :ref:`0A_Netronome_Repositories:Appendix A: Netronome
Repositories` on how to configure the Netronome repository applicable to your
distribution. When the repository has been successfully enabled install the
naming package using the commands below.

Ubuntu::

    # apt-get install agilio-naming-policy

CentOS/RHEL::

    # yum install agilio-naming-policy

At nfp driver initialization new *netdev* interfaces will be created::

    # ip link

    4: enp6s0np0s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
        link/ether 00:15:4d:13:01:db brd ff:ff:ff:ff:ff:ff
    5: enp6s0np0s1: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
        link/ether 00:15:4d:13:01:dd brd ff:ff:ff:ff:ff:ff
    6: enp6s0np0s2: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
        link/ether 00:15:4d:13:01:de brd ff:ff:ff:ff:ff:ff
    7: enp6s0np0s3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
        link/ether 00:15:4d:13:01:df brd ff:ff:ff:ff:ff:ff
    8: enp6s0np1: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
        link/ether 00:15:4d:13:01:dc brd ff:ff:ff:ff:ff:ff

.. note::

    Netdev naming may vary depending on your linux distribution and
    configuration e.g. enpAsXnpYsZ, pXpY.

To confirm the names of the interfaces, view the contents of
``/sys/bus/pci/devices/<pci addr>/net``, using the PCI address obtained in
:ref:`02_Hardware_installation:Hardware Installation` e.g.

.. code-block:: bash
    :linenos:

    #!/bin/bash
    PCIA=$(lspci -d 19ee:4000 | awk '{print $1}' | xargs -Iz echo 0000:z)
    echo $PCIA | tr ' ' '\n' | xargs -Iz echo "ls /sys/bus/pci/devices/z/net" | bash

The output of such a script would be similar to::

    enp6s0np0s0  enp6s0np0s1  enp6s0np0s2  enp6s0np0s3  enp6s0np1

In the worst case scenario netdev types can also be discovered by reading the
kernel logs.

Validating the Firmware
-----------------------

Netronome SmartNICs are fully programmable devices and thus depend on the
driver to load firmware onto the device at runtime. It is important to note
that the functionality of the SmartNIC significantly depends on the firmware
loaded. The firmware files should be present in the following directory
(contents may vary depending on the installed firmware)::

    # ls -ogR --time-style="+" /lib/firmware/netronome/
    /lib/firmware/netronome/:
    total 8
    drwxr-xr-x. 2 4096  flower
    drwxr-xr-x. 2 4096  nic
    lrwxrwxrwx  1   31  nic_AMDA0081-0001_1x40.nffw -> nic/nic_AMDA0081-0001_1x40.nffw
    lrwxrwxrwx  1   31  nic_AMDA0081-0001_4x10.nffw -> nic/nic_AMDA0081-0001_4x10.nffw
    lrwxrwxrwx  1   31  nic_AMDA0096-0001_2x10.nffw -> nic/nic_AMDA0096-0001_2x10.nffw
    lrwxrwxrwx  1   31  nic_AMDA0097-0001_2x40.nffw -> nic/nic_AMDA0097-0001_2x40.nffw
    lrwxrwxrwx  1   36  nic_AMDA0097-0001_4x10_1x40.nffw -> nic/nic_AMDA0097-0001_4x10_1x40.nffw
    lrwxrwxrwx  1   31  nic_AMDA0097-0001_8x10.nffw -> nic/nic_AMDA0097-0001_8x10.nffw
    lrwxrwxrwx  1   36  nic_AMDA0099-0001_1x10_1x25.nffw -> nic/nic_AMDA0099-0001_1x10_1x25.nffw
    lrwxrwxrwx  1   31  nic_AMDA0099-0001_2x10.nffw -> nic/nic_AMDA0099-0001_2x10.nffw
    lrwxrwxrwx  1   31  nic_AMDA0099-0001_2x25.nffw -> nic/nic_AMDA0099-0001_2x25.nffw
    lrwxrwxrwx  1   34  pci-0000:04:00.0.nffw -> flower/nic_AMDA0097-0001_2x40.nffw
    lrwxrwxrwx  1   34  pci-0000:06:00.0.nffw -> flower/nic_AMDA0096-0001_2x10.nffw

    /lib/firmware/netronome/flower:
    total 11692
    lrwxrwxrwx. 1      17  nic_AMDA0081-0001_1x40.nffw -> nic_AMDA0097.nffw
    lrwxrwxrwx. 1      17  nic_AMDA0081-0001_4x10.nffw -> nic_AMDA0097.nffw
    lrwxrwxrwx. 1      17  nic_AMDA0096-0001_2x10.nffw -> nic_AMDA0096.nffw
    -rw-r--r--. 1 3987240  nic_AMDA0096.nffw
    lrwxrwxrwx. 1      17  nic_AMDA0097-0001_2x40.nffw -> nic_AMDA0097.nffw
    lrwxrwxrwx. 1      17  nic_AMDA0097-0001_4x10_1x40.nffw -> nic_AMDA0097.nffw
    lrwxrwxrwx. 1      17  nic_AMDA0097-0001_8x10.nffw -> nic_AMDA0097.nffw
    -rw-r--r--. 1 3988184  nic_AMDA0097.nffw
    lrwxrwxrwx. 1      17  nic_AMDA0099-0001_2x10.nffw -> nic_AMDA0099.nffw
    lrwxrwxrwx. 1      17  nic_AMDA0099-0001_2x25.nffw -> nic_AMDA0099.nffw
    -rw-r--r--. 1 3990552  nic_AMDA0099.nffw

    /lib/firmware/netronome/nic:
    total 12220
    -rw-r--r--. 1 1380496  nic_AMDA0081-0001_1x40.nffw
    -rw-r--r--. 1 1389760  nic_AMDA0081-0001_4x10.nffw
    -rw-r--r--. 1 1385608  nic_AMDA0096-0001_2x10.nffw
    -rw-r--r--. 1 1385664  nic_AMDA0097-0001_2x40.nffw
    -rw-r--r--. 1 1391944  nic_AMDA0097-0001_4x10_1x40.nffw
    -rw-r--r--. 1 1397880  nic_AMDA0097-0001_8x10.nffw
    -rw-r--r--. 1 1386616  nic_AMDA0099-0001_1x10_1x25.nffw
    -rw-r--r--. 1 1385608  nic_AMDA0099-0001_2x10.nffw
    -rw-r--r--. 1 1386368  nic_AMDA0099-0001_2x25.nffw

The NFP driver will search for firmware in ``/lib/firmware/netronome``.
Firmware is searched for in the following order and the first firmware to be
successfully found and loaded is used by the driver:

.. code-block:: text

    1: serial-_SERIAL_.nffw
    2: pci-_PCI_ADDRESS_.nffw
    3: nic-_ASSEMBLY-TYPE___BREAKOUTxMODE_.nffw

This search is logged by the kernel when the driver is loaded. For example::

    # dmesg | grep -A 4 nfp.*firmware
    [  3.260788] nfp 0000:04:00.0: nfp: Looking for firmware file in order of priority:
    [  3.260810] nfp 0000:04:00.0: nfp:   netronome/serial-00-15-4d-13-51-0c-10-ff.nffw: not found
    [  3.260820] nfp 0000:04:00.0: nfp:   netronome/pci-0000:04:00.0.nffw: not found
    [  3.262138] nfp 0000:04:00.0: nfp:   netronome/nic_AMDA0097-0001_2x40.nffw: found, loading...

The version of the loaded firmware for a particular *<netdev>* interface, as
found in :ref:`03_Driver_and_Firmware:SmartNIC Netdev Interfaces` (for example
enp4s0), or an interface’s port *<netdev port>* (e.g. ``enp4s0np0``) can be
displayed with the ``ethtool`` command::

    # ethtool -i <netdev/netdev port>
    driver: nfp
    version: 3.10.0-862.el7.x86_64 SMP mod_u
    firmware-version: 0.0.3.5 0.22 nic-2.0.4 nic
    expansion-rom-version:
    bus-info: 0000:04:00.0

Firmware versions are displayed in order; NFD version, NSP version, APP FW
version, driver APP. The specific output above shows that basic NIC firmware
is running on the card, as indicated by "nic" in the firmware-version field.

Upgrading the firmware
----------------------

The preferred method to upgrading Agilio firmware is via the Netronome
repositories, however if this is not possible the corresponding installation
packages can be obtained from Netronome Support
(https://help.netronome.com).

Upgrading firmware via the Netronome repository
```````````````````````````````````````````````

Please refer to :ref:`0A_Netronome_Repositories:Appendix A: Netronome
Repositories` on how to configure the Netronome repository applicable to your
distribution. When the repository has been successfully added install the
``agilio-nic-firmware`` package using the commands below.

Ubuntu::

    # apt-get install agilio-nic-firmware
    # rmmod nfp; modprobe nfp
    # update-initramfs -u

CentOS/RHEL::

    # yum install agilio-nic-firmware
    # rmmod nfp; modprobe nfp
    # dracut -f

Upgrading firmware from package installations
`````````````````````````````````````````````

The latest firmware can be obtained at the downloads area of the Netronome
Support site (https://help.netronome.com).

Install the packages provided by Netronome Support using the commands below.

Ubuntu::

    # dpkg -i agilio-nic-firmware-*.deb
    # rmmod nfp; modprobe nfp
    # update-initramfs -u

CentOS/RHEL::

    # yum install -y agilio-nic-firmware-*.rpm
    # rmmod nfp; modprobe nfp
    # dracut -f
