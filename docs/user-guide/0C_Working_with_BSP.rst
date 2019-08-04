.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Appendix C: Working with Board Support Package
==============================================

The NFP BSP provides infrastructure software and a development environment for
managing NFP based platforms.

Install Software from Netronome Repository
------------------------------------------

Please refer to :ref:`0A_Netronome_Repositories:Appendix A: Netronome
Repositories` on how to configure the Netronome repository applicable to your
distribution. When the repository has been successfully added install the BSP
package using the commands below.

RHEL/CentOS 7.5::

    # yum list available | grep nfp-bsp
    nfp-bsp-6000-b0.x86_64                   2017.12.05.1404-1          netronome

    # yum install nfp-bsp-6000-b0 --nogpgcheck
    # reboot

Ubuntu 18.04 LTS::

    # apt-cache search nfp-bsp
    nfp-bsp-6000-b0 - Netronome NFP BSP

    # apt-get install nfp-bsp-6000-b0

Install Software From deb/rpm Package
-------------------------------------

Obtain Software
```````````````

The latest BSP packages can be obtained at the downloads area of the Netronome
Support site (https://help.netronome.com).

Install the prerequisite dependencies
`````````````````````````````````````

RHEL/Centos 7.5 Dependencies
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

No dependency installation required

Ubuntu 18.04 LTS Dependencies
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Install BSP dependencies::

    # apt-get install -y libjansson4

NFP BSP Package
```````````````

Install the NFP BSP package provided by Netronome Support.

RHEL/CentOS 7.5::

    # yum install -y nfp-bsp-6000-*.rpm --nogpgcheck

Ubuntu 18.04 LTS::

    # dpkg -i nfp-bsp-6000-*.deb

Using BSP tools
---------------

Enable CPP access
`````````````````

The NFP has an internal Command Push/Pull (CPP) bus that allows debug access to
the SmartNIC internals. CPP access allows user space tools raw access to chip
internals and is required to enable the use of most BSP tools. Only the
*out-of-tree (oot)* driver allows CPP access.

Follow the steps from :ref:`0B_Install_oot_nfp_driver:Install Driver via
Netronome Repository` to install the oot nfp driver. After the nfp module has
been built load the driver with CPP access::

    # depmod -a
    # rmmod nfp
    # modprobe nfp nfp_dev_cpp=1 nfp_pf_netdev=0

To persist this option across reboots, a number of options are available; the
distribution specific documentation will detail that process more thoroughly.
Care must be taken that the settings are also applied to any initramfs images
generated.

Configure Media Settings
````````````````````````

Alternatively to the process described in
:ref:`04_Using_linux_driver:Configuring Interface Media Mode`, BSP tools
can be used to configure the port speed of the SmartNIC use the following
commands. Note, a reboot is still required for changes to take effect.

Agilio CX 2x25GbE - AMDA0099
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

To set the port speed of the CX 2x25GbE the following commands can be used

Set port 0 and port 1 to 10G mode::

    # nfp-media phy1=10G phy0=10G

Set port 1 to 25G mode::

    # nfp-media phy1=25G+

To change the FEC settings of the 2x25GbE the following commands can be used::

    nfp-media --set-aneg=phy0=[S|A|I|C|F] --set-fec=phy0=[A|F|R|N]

Where the parameters for each argument are:

``--set-aneg=``:

S
    search - Search through supported modes until link is found.
    Only one side should be doing this. It may result in a mode that
    can have physical layer errors depending on SFP type and what the
    other end wants. Long DAC cables with no FEC WILL have physical
    layer errors.
A
    auto - Automatically choose mode based on speed and SFP type.
C
    consortium - Consortium 25G auto-negotiation with link training.
I
    IEEE - IEEE 10G or 25G auto-negotiation with link training.
F
    forced - Mode is forced with no auto-negotiation or link training.

``--set-fec=``:

A
    auto - Automatically choose FEC based on speed and SFP type.
F
    Firecode - BASE-R Firecode FEC compatible with 10G.
R
    Reed-Solomon - Reed-Solomon FEC new for 25G.
N
    none - No FEC is used.

Agilio CX 1x40GbE - AMDA0081
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Set port 0 to 40G mode::

    # nfp-media phy0=40G

Set port 0 to 4x10G fanout mode::

    # nfp-media phy0=4x10G

Agilio CX 2x40GbE - AMDA0097
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Set port 0 and port 1 to 40G mode::

    # nfp-media phy0=40G phy1=40G

Set port 0 to 4x10G fanout mode::

    # nfp-media phy0=4x10G

For mixed configuration the highest port must be in 40G mode e.g::

    # nfp-media phy0=4x10G phy1=40G
