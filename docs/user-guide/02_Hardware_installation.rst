.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Hardware Installation
=====================

This user guide focusses on x86 deployments of Agilio hardware. As detailed in
:ref:`03_Driver_and_Firmware:Validating the Driver`, Netronome’s Agilio
SmartNIC firmware is now upstreamed with certain kernel versions of Ubuntu and
RHEL/Centos. Whilst out-of-tree driver source files are available and
build/installation instructions are included in
:ref:`0A_Netronome_Repositories:Appendix A: Netronome Repositories`, it is
highly recommended where possible to make use of the upstreamed drivers.
Wherever applicable separate instructions for RHEL/Centos and Ubuntu are
provided.

Identification
--------------

In a running system the assembly ID and serial number of a PCI device may be
determined using the ``ethtool`` debug interface. This requires knowledge of
the physical function network device identifier, or *<netdev>*, assigned to
the SmartNIC under consideration. Consult the section
:ref:`03_Driver_and_Firmware:SmartNIC Netdev Interfaces` for methods on
determining this identifier. The interface name *<netdev>* can be otherwise
identified using the ``ip link`` command. The following shell snippet
illustrates this method for some particular netdev whose name is cast as the
argument $1:

.. code-block:: bash
    :linenos:

    #!/bin/bash
    DEVICE=$1
    ethtool -W ${DEVICE} 0
    DEBUG=$(ethtool -w ${DEVICE} data /dev/stdout | strings)
    SERIAL=$(echo "${DEBUG}" | grep "^SN:")
    ASSY=$(echo ${SERIAL} | grep -oE AMDA[0-9]{4})
    echo ${SERIAL}
    echo Assembly: ${ASSY}

.. note::

    The ``strings`` command is commonly provided by the *binutils* package.
    This can be installed by ``yum install binutils`` or ``apt-get install
    binutils``, depending on your distribution.

Physical installation
---------------------

Physically install the SmartNIC in the host server and ensure proper cooling
e.g. airflow over card.  Ensure the PCI slot is at least Gen3 x8 (can be placed
in Gen3 x16 slot).  Once installed, power up the server and open a terminal.
Further details and support about the hardware installation process can be
reviewed in the Hardware User Manual available from Netronome’s support site.

Validation
---------------

Use the following command to validate that the SmartNIC is being correctly
detected by the host server and identify its PCI address, 19ee is the
Netronome specific PCI vendor identifier::

    # lspci -Dnnd 19ee:4000; lspci -Dnnd 19ee:6000
    0000:02:00.0 Ethernet controller [0200]: Netronome Systems, Inc. Device    [19ee:4000]

.. note::

    The lspci command is commonly provided by the *pciutils* package. This can
    be installed by ``yum install pciutils`` or ``apt-get install pciutils``,
    depending on your distribution.
