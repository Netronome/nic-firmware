% Agilio Core NIC Install Instructions

# Revision History

|Date        |Revision |Author          |Description                           |
|------------|:-------:|----------------|--------------------------------------|
| 2016-11-9 |   0.1   | P. Cascón      |Initial rev of install instructions   |


# Requirements

All requirements must be met prior to installation.

## Operating System / Kernel

|             |                                |
|-------------|--------------------------------|
| OS          | Ubuntu 14.04 LTS               |
| Kernel      | 3.13.0-68 quirk_nfp6000 patched kernel |

If you need additional information regarding the quirk_nfp6000 patched kernel
please contact support@netronome.com

## Packages
### Standard .deb packages
#### BSP Deps
    apt-get install autoconf automake bison build-essential dkms flex gawk \
        gettext libftdi-dev libjansson-dev libtool minicom patch pkg-config \
        python python-dev tcl tcl-dev texinfo unzip wget zip

### NFP BSP .deb package

An NFP BSP `.deb` package required for this release should have been
provided by Netronome and installed e.g.:

 dpkg -i nfp-bsp-6000-b0_2016.11.8.1628-1_amd64.deb

# Hardware configuration

Tests have been performed with two machines in a back to back setup.
One ore more ports on a NFP in the first machine connected via fiber
to one or more ports on another NIC in the second machine.  At this
time DACs have not been tested.


### NFP Installation (compute node)

On the compute node(s) with an NFP, enable VT-x in the BIOS and ensure
that the kernel was booted with the:

 intel_iommu=on iommu=pt intremap=on

command-line option (typically set in `/etc/default/grub`). If the
command-line option needs to be added to the grub menu, don't forget
to run `update-grub` before rebooting.

Next, install the Agilio Core NIC package with e.g. the following command:

    dpkg -i ns-agilio-core-nic_0-7_all.deb

The installation process does the following:

  * Checks the running kernel has the quirks

  * Checks the running kernel has the quirk_nfp6000 stopping
installation if it does not have it.

  * Build the ‘nfp_net’ driver modules for all kernels with
quirk_nfp6000 on them

  * Copy the right firmware into /lib/firmware/netronome

  * Check the flash version in the NFP and if needing an update print
the commands to do so (including a reboot).


### Running Basic NIC

Once the package has been installed and the card has the correct flash
version new netdev interfaces named `nfp_pX` should be created e.g. :

```
# ip l
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT
group default link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
...
4: nfp_p0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT
group default qlen 1000 link/ether 00:15:4d:12:27:a7 brd ff:ff:ff:ff:ff:ff
5: nfp_p1: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT
group default qlen 1000 link/ether 00:15:4d:12:27:a8 brd ff:ff:ff:ff:ff:ff
```

The `nfp_net` driver is also loaded at boot time.

The interfaces can be configured at `/etc/network/interfaces` with e.g.:

```
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).
# The loopback network interface
auto lo
iface lo inet loopback
...
auto nfp_p0
iface nfp_p0 inet static
      address 10.7.1.1
      netmask 255.255.255.0

auto nfp_p1
iface nfp_p1 inet static
      address 10.7.2.1
      netmask 255.255.255.0
```

And running (not needed at boot):

```
# ifup nfp_p0 ; ifup nfp_p1
```

That will configure the interfaces setting the link state up and making the
interfaces ready to use.

### Change PHY media configuration

The Hydrogen NFP card has 2 different PHY media configurations: 1x40
Gbps or 4x10 Gbps (using breakout cables).

The media configuration can be checked with:

```
# nfp-media
phy0=40G (unset)
```

The output means that PHY0 is set to 40G.

To change it to 4x10 need first to copy the right firmware:
```
# cp /opt/netronome/firmware/ns-agilio-core-nic/cat/ns_nic_cx40q_1_4x10.cat
/lib/firmware/netronome/nfp6000_net.cat
```
And then change the media configuration:
```
# nfp-media phy0=4x10G
# nfp-media
phy0=40G (4x10G)
# reboot
```

The output of the second nfp-media command means that phy0 is
currently configured to 40G and that in the next reboot it will be set
to 4x10G. After the reboot this can be checked:
```
# nfp-media
phy0=4x10G (unset)
```

To go back to 40G mode:

```
# cp /opt/netronome/firmware/ns-agilio-core-nic/cat/ns_nic_cx40q_1.cat
/lib/firmware/netronome/nfp6000_net.cat
# nfp-media phy0=40G
# nfp-media
phy0=4x10G (40G)
# reboot
```