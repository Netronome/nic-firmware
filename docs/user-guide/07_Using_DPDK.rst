.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Installing, Configuring and Using DPDK
======================================

Enabling IOMMU
--------------

In order to use the NFP device with DPDK applications, the VFIO/IGB module has
to be loaded.

Firstly, the machine has to have IOMMU enabled. The following link:
http://dpdk-guide.gitlab.io/dpdk-guide/setup/binding.html contains some generic
information about binding devices including the possibility of using UIO
instead of VFIO, and also mentions the VFIO no-IOMMU mode.

Although DPDK focuses on avoiding interrupts, there is an option of a NAPI-like
approach using RX interrupts. This is supported by PMD NFP and with VFIO it is
possible to have an RX interrupt per queue (with UIO just one interrupt per
device). Because of this VFIO is the preferred option.

Edit grub configuration file
````````````````````````````

This change is required for working with VFIO, however when using kernels 4.5+,
it is possible to work with VFIO and no-IOMMU mode.  If your system comes with
a kernel > 4.5, you can work with VFIO and no-IOMMU if desired by enabling this
mode::

    # echo 1 > /sys/module/vfio/parameters/enable_unsafe_noiommu_mode

For kernels older than 4.5, working with VFIO requires the enabling of IOMMU in
the kernel at boot time. Add the following kernel parameters to
``/etc/default/grub`` to enable IOMMU::

    GRUB_CMDLINE_LINUX="intel_iommu=on iommu=pt intremap=on"

It is worth noting that ``iommu=pt`` is not required for DPDK if VFIO is used,
but it does avoid a performance impact in host drivers, such as the NFP netdev
driver, when ``intel_iommu=on`` is enabled.

Implement changes
`````````````````

Apply kernel parameters changes and reboot.

Ubuntu::

    # update-grub2
    # reboot

CentOS/RHEL::

    # grub2-mkconfig -o /boot/grub2/grub.cfg
    # reboot

DPDK sources with PF PMD support
--------------------------------

PF PMD multiport support
````````````````````````

The PMD can work with up to 8 ports on the same PF device. The number of
available ports is firmware and hardware dependent, and the driver looks for a
firmware symbol during initialization to know how many can be used.

DPDK apps work with ports, and a port is usually a PF or a VF PCI device.
However, with the NFP PF multiport there is just one PF PCI device. Supporting
this particular configuration requires the PMD to create ports in a special
way, although once they are created, DPDK apps should be able to use them as
normal PCI ports.

NFP ports belonging to same PF can be seen inside PMD initialization with a
suffix added to the PCI ID: **wwww:xx:yy.z_port_n**. For example, a PF with PCI
ID 0000:03:00.0 and four ports is seen by the PMD code as:

.. code-block:: text

    0000:03:00.0_port_0
    0000:03:00.0_port_1
    0000:03:00.0_port_2
    0000:03:00.0_port_3

.. note::

    There are some limitations with multiport support: RX interrupts and device
    hot-plugging are not supported.

Installing DPDK
---------------

Physical Function PMD support has been upstreamed into *DPDK 17.11*. If an
earlier version of DPDK is required, please refer to
:ref:`0D_Obtaining_DPDKns:Appendix D: Obtaining DPDK-ns`.

Install prerequisites::

    # apt-get -y install gcc libnuma-dev make

Obtain DPDK sources::

    # cd /usr/src/
    # wget http://fast.dpdk.org/rel/dpdk-17.11.tar.xz
    # tar xf dpdk-17.11.tar.xz
    # export DPDK_DIR=/usr/src/dpdk-17.11
    # cd $DPDK_DIR

Configure and install DPDK::

    # export DPDK_TARGET=x86_64-native-linuxapp-gcc
    # export DPDK_BUILD=$DPDK_DIR/$DPDK_TARGET
    # make install T=$DPDK_TARGET DESTDIR=install

Binding DPDK PF driver
----------------------

.. note::

    This section details the binding of dpdk-enabled drivers to the **Physical
    Functions**.

Attaching vfio-pci driver
`````````````````````````

Load vfio-pci driver module::

    # modprobe vfio-pci

Unbind current drivers::

    # PCIA=0000:$(lspci -d 19ee:4000 | awk '{print $1}')
    # echo $PCIA > /sys/bus/pci/devices/$PCIA/driver/unbind

Bind vfio-pci driver::

    # echo 19ee 4000 > /sys/bus/pci/drivers/vfio-pci/new_id

Attaching igb-uio driver
````````````````````````

Load igb-uio driver module::

    # modprobe uio
    # DRKO=$(find $DPDK_DIR -iname 'igb_uio.ko' | head -1 )
    # insmod $DRKO

Unbind current drivers::

    # PCIA=0000:$(lspci -d 19ee:4000 | awk '{print $1}')
    # echo $PCIA > /sys/bus/pci/devices/$PCIA/driver/unbind

Bind igb_uio driver::

    # echo 19ee 4000 > /sys/bus/pci/drivers/igb_uio/new_id

Confirm attached driver
```````````````````````

Confirm that the driver has been attached::

    # lspci -kd 19ee:

    01:00.0 Ethernet controller: Netronome Systems, Inc. Device 4000
            Subsystem: Netronome Systems, Inc. Device 4001
            Kernel driver in use: nfp
            Kernel modules: nfp
    01:08.0 Ethernet controller: Netronome Systems, Inc. Device 6003
            Subsystem: Netronome Systems, Inc. Device 4001
            Kernel driver in use: igb_uio
            Kernel modules: nfp

Unbind driver
`````````````

Determine card address::

    # PCIA=$(lspci -d 19ee: | awk '{print $1}')

Unbind vfio-pci driver::

    # echo 0000:$PCIA > /sys/bus/pci/drivers/vfio-pci/unbind

Unbind igb_uio driver::

    # echo 0000:$PCIA > /sys/bus/pci/drivers/igb_uio/unbind

Using DPDK PF driver
--------------------

Create default symlink
``````````````````````

.. note::

    This workaround applies to dpdk versions < 18.05.

In order to use the PF in DPDK applications a symlink named
``nic_dpdk_default.nffw`` pointing to the applicable firmware needs to be
created e.g.

Navigate to firmware directory::

    # cd /lib/firmware/netronome

For Agilio 2x40G::

    # cp -s nic_AMDA0097-0001_2x40.nffw nic_dpdk_default.nffw

For Agilio 2x25G::

    # cp -s nic_AMDA0099-0001_2x25.nffw nic_dpdk_default.nffw

For Agilio 2x40G w/ first port in breakout mode::

    # cp -s nic_AMDA0097-0001_4x10_1x40.nffw nic_dpdk_default.nffw


The following table can be used to map product names to their codes

=============== ========
SmartNIC        Code
=============== ========
Agilio CX 2x10G AMDA0096
Agilio CX 2x25G AMDA0099
Agilio CX 1x40G AMDA0081
Agilio CX 2x40G AMDA0097
=============== ========
