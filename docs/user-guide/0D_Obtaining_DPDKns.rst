.. Copyright (c) 2018 Netronome Systems, Inc. All rights reserved.
   SPDX-License-Identifier: BSD-2-Clause.

.. highlight:: console

Appendix D: Obtaining DPDK-ns
=============================

Netronome specific DPDK sources can be acquired from the Official Netronome
Support site (https://help.netronome.com). If you do not have an account
already, you can request access by sending an email to help@netronome.com.

Download the dpdk-ns sources or deb/rpm package from the Netronome-Support site
and perform the following steps to build or install DPDK.

Build DPDK-ns from sources
--------------------------

To build DPDK-ns from source assuming the tarball has been downloaded to the
``/root`` directory::

    # cd /root
    # tar zxvf dpdk-ns.tar.gz
    # cd dpdk-ns

    # export RTE_SDK=/root/dpdk-ns
    # export RTE_TARGET=x86_64-native-linuxapp-gcc
    # make T=$RTE_TARGET install

Install DPDK-ns from packages
-----------------------------

Ubuntu::

    # apt-get install -y netronome-dpdk*.deb

CentOS/RHEL::

    # yum install -y netronome-dpdk*.rpm

