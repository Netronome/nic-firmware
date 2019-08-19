.. role:: raw-html(raw)
   :format: html

CoreNIC Background
------------------

CoreNIC is the product name of Netronome's NIC firmware implementation
for `Agilio SmartNICs
<https://www.netronome.com/products/smartnic/overview/>`_. It provides
a network interface compatible with the `nfp Linux driver
<https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/net/ethernet/netronome/nfp>`_
and `DPDK <http://doc.dpdk.org/guides/nics/nfp.html>`_ supporting the
following features:

- TX Checksum offload (TCP, UDP, TCP/VXLAN, UDP/VXLAN)
- RX Checksum offload (CSUM_COMPLETE, CSUM_UNNECESSARY)
- Receive Side Scaling (RSS, RSS/VXLAN, RSS/NVGRE, RX-HASH)
- TCP Segmentation Offload (TSO, TSO/VXLAN)
- `BPF offload <https://www.netronome.com/technology/ebpf/>`_ (XDP, cls_bpf)
- SR-IOV (MAC VEB, MAC+VLAN VEB)

The data plane is extensible, since it is fully implemented in
software, while supporting high packet rates at 10, 25, 40 and 100Gbps
bandwidths (depending on the chosen hardware's capabilities). This
repository contains the source code that is used to build the binary
release firmware found in the `nic
<https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/netronome/nic>`_
subdirectory of Netronome's firmware as distributed by the `linux-firmware
<https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/>`_
project. Hence, the repository is named nic-firmware instead of
CoreNIC, although they are one and the same.


Why Open Source?
----------------

Aside from the obvious mantra of `Linus's Law
<https://en.wikipedia.org/wiki/Linus%27s_Law>`_, customers are not in
a position to be able to validate the security of their systems
without access to the source code of the firmware running inside those
systems. More so, Netronome believes that developing this firmware in
the open will ultimately lead to better quality code by motivating
engineers to deliver their best, because working under public scrutiny
is a strong incentive to take personal pride in the work.

We are also interested in building a community around supporting new
applications for the underlying network processor technology. Building
on the existing code base may enable creative solutions to interesting
and novel networking problems. Software Defined Networking (SDN) is
certainly a broad and challenging domain with many problems yet to be
solved. Netronome is excited to see where such collaborations may
lead.

Getting Started
---------------

Netronome SmartNICs are available for purchase via `Colfax Direct
<http://www.colfaxdirect.com/store/pc/showsearchresults.asp?IDBrand=38>`_
and other channels. Using one of these fully programmable devices as a
standard NIC is straightforward when combined with a modern Linux
distribution. Plug in the PCIe card and simply configure it using
familiar Linux networking tools. The `firmware
<https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/netronome>`_
and `driver <https://github.com/Netronome/nfp-drv-kmods>`_ have been
upstream since Linux 4.11 and thus the card should be automatically
detected by any distribution shipping a kernel subsequent to this
release. In particular, upstream support for Netronome SmartNICs has
been available since:

- Red Hat Linux 7.4 (`certified in 7.5 and later <https://access.redhat.com/ecosystem/hardware/#/search?q=netronome>`_), and
- Ubuntu Linux 16.04.4.

The `CoreNIC user guide
<https://help.netronome.com/support/solutions/articles/36000049975-basic-firmware-user-guide>`_
(`source
<https://github.com/Netronome/nic-firmware/tree/master/docs/user-guide>`_)
is available on the `Netronome Support Site
<https://help.netronome.com/support/home>`_. Materials covering
advanced use cases, such as `BPF offload
<https://help.netronome.com/support/solutions/articles/36000050009-agilio-ebpf-2-0-6-extended-berkeley-packet-filter>`__,
as well as other firmware loads, such as `Open vSwitch offload
<https://help.netronome.com/support/solutions/articles/36000062974-agilio-open-vswitch-tc>`_,
are also available from Netronome.


Reporting Bugs
--------------

Please file issues against this repository using the GitHub `issue
tracker <https://github.com/Netronome/nic-firmware/issues>`_.

Peeking Under the Hood
----------------------

The Netronome `Network Flow Processor
<https://www.netronome.com/m/documents/WP_Theory_of_Ops.pdf>`_ (NFP)
at the heart of all Agilio SmartNICs comprises a large number of
multi-threaded programmable cores connected to I/Os (PCIe, network
MACs, etc) and intelligent processing memories via a high speed
internal `Distributed Switch Fabric
<https://www.netronome.com/m/documents/WP_Composable-Architecture.pdf>`_
(DSF). As further background, there is a `presentation
<https://open-nfp.org/m/documents/P4DevCon_NFPArchIntro_ukskQIA.pdf>`_
which provides some good introductory material about the NFP by
illustrating some of the architectural concepts in the context of `P4
<https://www.netronome.com/technology/p4/>`_ and `MicroC
<https://open-nfp.org/media/documents/the-joy-of-micro-c_fcjSfra.pdf>`_
software loads.

The CoreNIC data plane is implemented in microcode (the assembly
language for the NFP instruction set architecture) in order to
maximize performance while minimizing code store utilization (each
processing core has a `Harvard architecture
<https://en.wikipedia.org/wiki/Harvard_architecture>`_ with limited
local code store). For BPF offload it was important to have the
implementation of the data plane be as tight as possible in order to
leave sufficient code store available for meaningful user applications
written in BPF (the software extension mechanism intended for the
majority of needs). The CoreNIC source code has been released publicly
for those who want to dig a little deeper and tinker with the
underlying layers.

The primary components of the CoreNIC software architecture are
depicted in the following diagram (these components will not be
exhaustively described in this document):

.. image:: docs/design/source/components.png

At a high level the NIC firmware is logically separated into two
component groupings (each further subdivided). The control plane, the
`App Master
<https://github.com/Netronome/nic-firmware/blob/master/firmware/apps/nic/app_master_main.c>`_
implemented in MicroC_, configures a pool of Workers, the `datapath
<https://github.com/Netronome/nic-firmware/blob/master/firmware/apps/nic/datapath.uc>`_
implemented in microcode, by instantiating a database of Action lists
for the Workers to execute in response to receiving network packets on
a given ingress queue. These `actions
<https://github.com/Netronome/nic-firmware/blob/master/firmware/apps/nic/actions.uc>`_
are optimized microcode implementations of simple packet processing
primitives, such as RSS queue selection, prepending a VLAN tag,
sending packet to PCIe, etc. Actions may also take the form of complex
lookups that return new lists of actions to be executed or represent
chunks of user code written in BPF. The Workers perform out of order
packet processing in parallel under a run to completion processing
model with packets being reordered by a global reorder (GRO) component
prior to packet egress. The Crypto (`KTLS
<https://www.kernel.org/doc/html/latest/networking/tls-offload.html>`_
and `IPsec <https://en.wikipedia.org/wiki/IPsec>`_ offloads) and
Flower (`OVS TC
<https://www.netdevconf.org/2.2/papers/horman-tcflower-talk.pdf>`_
offload) plugins are rendered as planned within the CoreNIC
architecture, but not yet available.

Detailed design documentation is a `work in progress
<https://github.com/Netronome/nic-firmware/tree/master/docs/design>`_. The
plan is to flesh out this documentation in due course and to provide
additional tutorial materials on NFP architecture and microcode
programming. Beyond this, it is hoped that the `CoreNIC microcode
<https://github.com/Netronome/nic-firmware/tree/master/firmware/apps/nic>`_
will prove instructional. The assembler's macro preprocessor and
register allocator generally makes for relatively easy to read
code. That said, the CoreNIC code base generally favors performant
implementation over readability. Fortunately, many of these tricky
optimization techniques have proven idiomatic and these too will be
covered by documentation to follow.

Toolchain and Reference Manuals
-------------------------------

Third party constraints preclude Netronome from releasing the NFP
toolchain and reference materials under a nonproprietary license. One
such constraint also prohibits us from providing the tooling
independently of our hardware. With a verified hardware purchase,
however, these tools and materials are legally accessible in binary
form via `Open-NFP.org <https://open-nfp.org/>`_ free of any
additional charge. Given that a nic-firmware build isn't particularly
useful without the hardware to execute it on, we hope this constraint
is of little practical significance to parties with a genuine interest
in building the code.

In order to obtain the toolchain, you will need to request it by
emailing :raw-html:`<a href="mailto:help@netronome.com?subject=Linux toolchain for CoreNIC - Request">help@netronome.com</a>`, after which,
you will receive a response requesting additional details. Once your
eligibility is determined, you will be provided access to a private
download area. The license conditions are distributed within the
toolchain package in the file "NFP_SDK_EULA.txt".

BY LOADING OR USING THE SOFTWARE, YOU AS AN INDIVIDUAL AND ON BEHALF
OF YOUR EMPLOYER ("YOU") AGREE TO THE TERMS OF THIS AGREEMENT. IF YOU
DO NOT WISH TO SO AGREE, DO NOT INSTALL, OR IF INSTALLED, DELETE ALL
COPIES OF THE SOFTWARE AND DO NOT USE THE SOFTWARE.

The Linux toolchain is provided as an RPM or Debian package that can
be installed and removed using your distribution's package management
system. The package constrains itself under /opt/netronome so as not
to pollute your local filesystem and a compressed tarball is also
available for other distributions. Reference manuals are distributed
as part of the toolchain in the *doc* subdirectory and are subject to
the same license.

Build Instructions
------------------

The build depends on the aforementioned toolchain as well as a number
of basic Unix tools that one might expect to find installed on a
typical developer's machine. No effort has been made to document an
exhaustive list of these commonly installed tools and if one is
missing, the build will simply fail with a command not found error
that any savvy engineer should be able to trivially resolve. Tools
such as make and sed are known requirements, but perhaps a less
obvious tool is awk.

We presently rely on a handful of AWK scripts for code generation and
these scripts have not been written with portability across AWK
implementations in mind. As it stands the build will fail gloriously
in environments that ship mawk as a default implementation instead of
gawk (GNU AWK). If we don't get to it first, an exercise for the
reader is to submit a patch that makes `nic_stats.awk
<https://github.com/Netronome/nic-firmware/blob/master/scripts/nic_stats.awk>`_
portable. :) In the meantime, please select gawk as your default AWK
implementation when building CoreNIC on Ubuntu. The build process is
far from perfect. If we waited until everything was fixed first it
would never be released.

The build also depends on, and will automatically fetch, two
additional public Netronome GitHub repositories:

- `NFD <https://github.com/Netronome/nfd>`_ (The Netronome Flow
  Driver): a firmware component implementing the PCIe driver
  interface, and
- `Flowenv <https://github.com/Netronome/flowenv>`_ (Netronome Flow
  Environment): a set of MicroC libraries and stand alone firmware
  components such as GRO (referring to the global reorder block in the
  above diagram, not generic receive offload) and BLM (the buffer list
  manager).

To build CoreNIC, first clone this repo:

.. code-block:: console

  $ git clone https://github.com/Netronome/nic-firmware.git
  Cloning into 'nic-firmware'...
  remote: Enumerating objects: 12039, done.
  remote: Counting objects: 100% (12039/12039), done.
  remote: Compressing objects: 100% (2713/2713), done.
  remote: Total 12039 (delta 8930), reused 11321 (delta 8212), pack-reused 0
  Receiving objects: 100% (12039/12039), 3.83 MiB | 6.83 MiB/s, done.
  Resolving deltas: 100% (8930/8930), done.

and then build it:

.. code-block:: console
		
  $ cd nic-firmware && make
  git clone -q --no-checkout \
        https://github.com/Netronome/flowenv.git /tmp/nic-firmware/deps/flowenv.git
  cd /tmp/nic-firmware/deps/flowenv.git && git checkout 5be5d1d
  Note: checking out '5be5d1d'.
  
  You are in 'detached HEAD' state. You can look around, make experimental
  changes and commit them, and you can discard any commits you make in this
  state without impacting any branches by performing another checkout.
  
  If you want to create a new branch to retain commits you create, you may
  do so (now or later) by using -b with the checkout command again. Example:
  
    git checkout -b <new-branch-name>

  HEAD is now at 5be5d1d doc: Replace references to hg with git equivalents
  cd /tmp/nic-firmware/deps/flowenv.git && patch -p1 < ../gro_multicast.patch && cd -
  patching file me/blocks/gro/_uc/gro_out.uc
  /tmp/nic-firmware
  cd /tmp/nic-firmware/deps/flowenv.git && patch -p1 < ../big_sleep.patch && cd -
  patching file me/lib/nfp/_c/me.c
  /tmp/nic-firmware
  git clone -q --no-checkout \
          https://github.com/Netronome/nfd.git /tmp/nic-firmware/deps/ng-nfd.git
  cd /tmp/nic-firmware/deps/ng-nfd.git && git checkout 93e9535
  Note: checking out '93e9535'.
  
  You are in 'detached HEAD' state. You can look around, make experimental
  changes and commit them, and you can discard any commits you make in this
  state without impacting any branches by performing another checkout.
  
  If you want to create a new branch to retain commits you create, you may
  do so (now or later) by using -b with the checkout command again. Example:
  
    git checkout -b <new-branch-name>

  HEAD is now at 93e9535 [libnfd] Fix typo in comment
  cd /tmp/nic-firmware/deps/ng-nfd.git && patch -p1 < ../nfd_abi3.patch && cd -
  patching file me/blocks/vnic/nfd_common.h
  /tmp/nic-firmware
  Checking /tmp/nic-firmware/deps/flowenv.git
  Checking /tmp/nic-firmware/deps/ng-nfd.git
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/flowenv_nfp_init.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/gro0.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/gro1.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/gro2.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/gro3.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/blm0.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/mcr.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/datapath.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/mapcmsg.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_app_master/nfd_app_master.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_svc/nfd_svc.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_pcie0_gather/nfd_pcie0_gather.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_pcie0_issue0/nfd_pcie0_issue0.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_pcie0_issue1/nfd_pcie0_issue1.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_pcie0_notify/nfd_pcie0_notify.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_pcie0_cache/nfd_pcie0_cache.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_pcie0_sb.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_pcie0_pd.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/tm_pm_init.list ...
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/dump_spec.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_tlv_init.list ...
  Linking /tmp/nic-firmware/firmware/nffw/nic/nic_AMDA0081-0001_1x40.nffw ...
  ...
  ...
  ... 

The build will take some time to complete and will output an ELF file (.nffw files in firmware/nffw) for each supported hardware target and NIC flavor. The resultant .nffw files can then be placed in /lib/firmware/netronome for the driver to load on a machine where the hardware is installed.

The toolchain version is also checked and the build will fail if it is not as expected, thus updates to this repository may necessitate downloading a new toolchain. Note that the toolchain version check is skipped when a specific target is requested. For example, a build for the 2x25Gbps Agilio CX card can be accomplished as follows:

.. code-block:: console

  [nic-firmware] $ make nic/nic_AMDA0099-0001_2x25.nffw
  Checking /tmp/nic-firmware/deps/flowenv.git
  Checking /tmp/nic-firmware/deps/ng-nfd.git
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/flowenv_nfp_init.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/gro0.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/gro1.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/gro2.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/gro3.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/blm0.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/mcr.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/datapath.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/mapcmsg.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_app_master/nfd_app_master.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_svc/nfd_svc.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_pcie0_gather/nfd_pcie0_gather.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_pcie0_issue0/nfd_pcie0_issue0.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_pcie0_issue1/nfd_pcie0_issue1.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_pcie0_notify/nfd_pcie0_notify.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_pcie0_cache/nfd_pcie0_cache.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_pcie0_sb.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_pcie0_pd.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/tm_pm_init.list ...
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec_init.uc
  Generated /tmp/nic-firmware/firmware/apps/nic/dump_spec.c
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/dump_spec.list ...
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0099-0001_2x25/nfd_tlv_init.list ...
  Linking /tmp/nic-firmware/firmware/nffw/nic/nic_AMDA0099-0001_2x25.nffw ...

Finally, a set of RPM and Debian packages can be output to firmware/pkg/out by means of the *package* make target provided that rpmbuild and dpkg-deb tools are installed on the build machine.

Unit Tests
----------

The project unit `tests
<https://github.com/Netronome/nic-firmware/tree/master/test>`_ depend
on raw hardware access to a Netronome Agilio SmartNIC device installed
in the machine where the tests are executed. This low-level raw access
requires the Netronome BSP tools (available from the toolchain
download area) and the out of tree driver_ loaded with the
*nfp_dev_cpp* option enabled.

First, clone and build the out of tree NFP driver:

.. code-block:: console
		
  $ git clone git@github.com:Netronome/nfp-drv-kmods.git
  Cloning into 'nfp-drv-kmods'...
  remote: Enumerating objects: 183, done.
  remote: Counting objects: 100% (183/183), done.
  remote: Compressing objects: 100% (82/82), done.
  remote: Total 9301 (delta 127), reused 140 (delta 101), pack-reused 9118
  Receiving objects: 100% (9301/9301), 3.46 MiB | 4.46 MiB/s, done.
  Resolving deltas: 100% (7435/7435), done.
  
  $ cd nfp-drv-kmods && make
  make -C /lib/modules/5.2.8-arch1-1-ARCH/build M=`pwd`/src modules
  make[1]: Entering directory '/usr/lib/modules/5.2.8-arch1-1-ARCH/build'
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp6000_pcie.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_nsp.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_cppcore.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_cpplib.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_em_manager.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_hwinfo.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_mip.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_mutex.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_nbi.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_nffw.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_nsp_cmds.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_nsp_eth.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_platform.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_resource.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_rtsym.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_target.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_nbi_mac_eth.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_net_vnic.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_debugdump.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_plat.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_main.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_hwmon.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_dev_cpp.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfpcore/nfp_export.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_app.o
    CC [M]  /tmp/nfp-drv-kmods/src/ccm_mbox.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_ctrl.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_common.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_compat.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_ethtool.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_debugfs.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_sriov.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_port.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_app_nic.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_ctrl.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_main.o
    CC [M]  /tmp/nfp-drv-kmods/src/nic/main.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_devlink.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_shared_buf.o
    CC [M]  /tmp/nfp-drv-kmods/src/ccm.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_asm.o
    CC [M]  /tmp/nfp-drv-kmods/src/bpf/cmsg.o
    CC [M]  /tmp/nfp-drv-kmods/src/bpf/main.o
    CC [M]  /tmp/nfp-drv-kmods/src/bpf/offload.o
    CC [M]  /tmp/nfp-drv-kmods/src/bpf/verifier.o
    CC [M]  /tmp/nfp-drv-kmods/src/bpf/jit.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_net_repr.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/action.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/cmsg.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/lag_conf.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/match.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/metadata.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/offload.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/main.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/tunnel_conf.o
    CC [M]  /tmp/nfp-drv-kmods/src/flower/qos_conf.o
    CC [M]  /tmp/nfp-drv-kmods/src/abm/cls.o
    CC [M]  /tmp/nfp-drv-kmods/src/abm/ctrl.o
    CC [M]  /tmp/nfp-drv-kmods/src/abm/main.o
    CC [M]  /tmp/nfp-drv-kmods/src/abm/qdisc.o
    CC [M]  /tmp/nfp-drv-kmods/src/nfp_netvf_main.o
    LD [M]  /tmp/nfp-drv-kmods/src/nfp.o
    Building modules, stage 2.
    MODPOST 1 modules
    CC      /tmp/nfp-drv-kmods/src/nfp.mod.o
    LD [M]  /tmp/nfp-drv-kmods/src/nfp.ko
  make[1]: Leaving directory '/usr/lib/modules/5.2.8-arch1-1-ARCH/build'

And then load the compiled driver, ensuring that any existing driver is first unloaded and that raw CPP access is enabled:

.. code-block:: console
		
  [nfp-drv-kmods] # rmmod nfp ; insmod src/nfp.ko nfp_dev_cpp=1

Verify that the driver loaded successfully and that it detected the hardware by inspecting the kernel log output.

Finally, from the root of CoreNIC tree, execute the tests (requires root privileges):

.. code-block:: console

  [nic-firmware] # make test
  Checking /tmp/nic-firmware/deps/flowenv.git
  Checking /tmp/nic-firmware/deps/ng-nfd.git
  make[1]: Entering directory '/tmp/nic-firmware'
  Checking /tmp/nic-firmware/deps/flowenv.git
  Checking /tmp/nic-firmware/deps/ng-nfd.git
  Building /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/datapath.list ...
  scripts/run_tests.sh test test/datapath /tmp/nic-firmware/firmware/build/datapath /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/datapath -third_party_addressing_40_bit -permit_dram_unaligned -preproc64 -indirect_ref_format_nfp6000 -W3 -C -R -lr -go -g -lm 0 -include /tmp/nic-firmware/firmware/apps/nic/config.h -chip AMDA0081-0001:0  -DNS_PLATFORM_TYPE=1 -O -keep_unreachable_code   -DGRO_NUM_BLOCKS=4 -DBLM_CUSTOM_CONFIG -DSS=0 -DSCS=0 -DNBI_COUNT=1 -DWORKERS_PER_ISLAND=10 -DNS_FLAVOR_TYPE=1 -I/opt/netronome/components/standardlibrary/include -I/opt/netronome/components/standardlibrary/microcode/include -I/opt/netronome/components/standardlibrary/microcode/src -I/tmp/nic-firmware/firmware/apps/nic -I/tmp/nic-firmware/include -I/tmp/nic-firmware/deps/nfp-bsp-boardconfig -I/tmp/nic-firmware/deps/npfw -I/tmp/nic-firmware/deps/flowenv.git/me/include -I/tmp/nic-firmware/deps/flowenv.git/me/lib -I/tmp/nic-firmware/deps/flowenv.git/me/blocks -I/tmp/nic-firmware/deps/ng-nfd.git -I/tmp/nic-firmware/deps/ng-nfd.git/shared -I/tmp/nic-firmware/deps/ng-nfd.git/me/include -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks/vnic -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks/vnic/shared -I/tmp/nic-firmware/deps/ng-nfd.git/me/lib -Ifirmware/lib -Ifirmware/apps/nic/lib -Ifirmware/apps/nic/maps -Ideps/ng-nfd.hg -I/tmp/nic-firmware/deps/flowenv.git/me/blocks/blm -I/tmp/nic-firmware/deps/flowenv.git/me/blocks/gro
  pv_seek_14_64B_x80_test : PASS
  pv_parse_vlan_vlan_vlan_mpls_mpls_mpls_mpls_mpls_ipv4_udp_x84_test : PASS
  pv_parse_ipv6_tcp_x88_test : PASS
  actions_rss_ipv4_tcp_no_udp_test : PASS
  pv_seek_206_256B_split_x80_test : PASS
  pv_parse_vlan_vlan_vlan_vlan_mpls_mpls_ipv6_tcp_x80_test : PASS
  pv_parse_ipv4_gre_tcp_x88_test : PASS
  pv_seek_lin_256B_x88_test : PASS
  pv_lso_fixup_ipv4_test : PASS
  ...
  ...
  ...
  actions_csum_complete_9K_x88_test : . PASS
  pv_seek_14_256B_split_x80_test : PASS
  actions_strip_vlan_tag_vlan_ipv4_udp_x84_test : PASS
  pv_init_nfd_lso_fixup_ipv6_end_test : PASS
  actions_csum_complete_max_carry_test : . PASS
  Summary : 153 passed, no failures
  make[1]: Leaving directory '/tmp/nic-firmware'
  make[1]: Entering directory '/tmp/nic-firmware'
  Checking /tmp/nic-firmware/deps/flowenv.git
  Checking /tmp/nic-firmware/deps/ng-nfd.git
  scripts/run_tests.sh test test/nfd_app_master /tmp/nic-firmware/firmware/build/nfd_app_master /tmp/nic-firmware/firmware/build/nic/nic_AMDA0081-0001_1x40/nfd_app_master -I/opt/netronome/components/standardlibrary/include -I/opt/netronome/components/standardlibrary/microc/include -I/tmp/nic-firmware/firmware/lib -I/tmp/nic-firmware/firmware/apps/nic -I/tmp/nic-firmware/include -I/tmp/nic-firmware/deps/nfp-bsp-boardconfig -I/tmp/nic-firmware/deps/npfw -I/tmp/nic-firmware/deps/flowenv.git/me/include -I/tmp/nic-firmware/deps/flowenv.git/me/lib -I/tmp/nic-firmware/deps/flowenv.git/me/blocks -I/tmp/nic-firmware/deps/ng-nfd.git -I/tmp/nic-firmware/deps/ng-nfd.git/shared -I/tmp/nic-firmware/deps/ng-nfd.git/me/include -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks/vnic -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks/vnic/shared -I/tmp/nic-firmware/deps/ng-nfd.git/me/lib  -I/tmp/nic-firmware/deps/ng-nfd.git -I/tmp/nic-firmware/deps/ng-nfd.git/shared -I/tmp/nic-firmware/deps/ng-nfd.git/me/include -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks/vnic -I/tmp/nic-firmware/deps/ng-nfd.git/me/blocks/shared -I/tmp/nic-firmware/firmware/lib/nic_basic -I/tmp/nic-firmware/firmware/lib/link_state -I/tmp/nic-firmware/firmware/lib/npfw -I/opt/netronome/components/standardlibrary/microc/src
  app_master_process_ctrl_reconfig_enable_tables_test : PASS
  app_master_process_ctrl_reconfig_disable_test : PASS
  app_master_handle_sriov_update_test : PASS
  app_master_process_ctrl_reconfig_cfg_msg_error_test : PASS
  app_master_process_ctrl_reconfig_invalid_cap_test : PASS
  app_master_process_ctrl_reconfig_enable_test : PASS
  app_master_vlan_cfg_cmsg_test : PASS
  app_master_process_ctrl_reconfig_valid_cap_test : PASS
  Summary : 8 passed, no failures
  make[1]: Leaving directory '/tmp/nic-firmware'
