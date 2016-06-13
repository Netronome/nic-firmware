% Basic NIC Getting Started Guide

# Revision History

|Date        |Revision |Author          |Description                           |
|------------|:-------:|----------------|--------------------------------------|
| 2016-03-17 |   0.1   | J.Li           |Initial commit of the document        |
| 2016-06-13 |   0.2   | M.Bridger      |Installation updates                  |
|            |         |                |                                      |

# Installing BSP and SDK

You may need to use root user to run the following cmds

	#remove any installed BSP and SDK

dpkg -r nfp-bsp

dpkg -r nfp-bsp-dkms

dpkg -r nfp-sdk

dpkg -r nfp-bsp-release-2015.11-dkms

dpkg -r nfp-bsp-release-2015.11

	#Install the required version of BSP and SDK

dpkg -i /releases-intern/nfp-sdk/linux-x86_64/nfp-toolchain-5/dpkg/amd64/nfp-sdk_5-devel-5881-2_amd64.deb

dpkg -i /releases-intern/nfp-bsp/distros/nfp-bsp-6000-b0/dpkg/nfp-bsp-6000-b0-dkms_2016.5.25.1605-1_all.deb

dpkg -i /releases-intern/nfp-bsp/distros/nfp-bsp-6000-b0/dpkg/nfp-bsp-6000-b0_2016.5.25.1605-1_amd64.deb

	#Make sure nfp module is loaded

/sbin/ldconfig

rmmod nfp_netvf

rmmod nfp_net

rmmod nfp

modprobe nfp

	#Flash the NFP

/opt/netronome/bin/nfp-flash --i-accept-the-risk-of-overwriting-miniloader -w /opt/netronome/flash/flash-nic.bin

/opt/netronome/bin/nfp-one # Only if hydrogen or lithium

	#Delete the pre-loaded UNDI firmware (causing NFP
	#to fail to reset when loading the firmware)

nfp-fis delete firmware.ca

	#Reboot

reboot

# Build the basic NIC firmware

	# First git clone the nfp-vrouter repo

git clone ssh://hg.netronome.com//data/git/repos/nfp-vrouter.git

cd nfp-vrouter

make clean

make

	# After the firmware is built, it should be
	# in nfp-vrouter/firmware/nffw/

ns_nic_cx40q_1.nffw: for hydrogen NFP

ns_nic_cx10_2.nffw: for lithium NFP

Note:

There is a firmware analysis report generated automatically in the make target, (using ‘nfp-vrouter/firmware/scripts/nic_reg_usage.py’), which includes analysis on register usage per C function, register usage increment per C function, and code storage usage per C function. 

The location of the report is:

	nfp-vrouter/firmware/build/basic_nic/basic_nic_analysis.txt


# Loading the NIC driver and NIC firmware
There are two ways to load the NIC driver and NIC firmware:

 * Kernel space loading (should be the preferred way)

 * User space loading
 
## Kernel space loading

You may need to use root user to run the following cmds

	# you need nfp module for transforming the firmware for kernel loading

rmmod nfp_net

rmmod nfp_netvf

rmmod nfp_net

modprobe nfp nfp_reset=1

	# Prepare the default path for nfp_net driver to pick up the NIC firmware

rm -rf /lib/firmware/netronome

mkdir -p /lib/firmware/netronome

	# transform the NIC firmware format for kernel loading (hydrogen fw as example; for lithium fw, use --amda=AMDA0096-0001 in nfp-nffw2ca)

mkdir /tmp/nic_fw

cd /tmp/nic_fw

cp /YOUR_PATH_GIT/nfp-vrouter/firmware/nffw/ns_nic_cx40q_1.nffw /tmp/nic_fw/

nfp-nffw2ca -z --amda=AMDA0081-0001 /tmp/nic_fw/ns_nic_cx40q_1.nffw /tmp/nic_fw/nfp6000_net.cat

cp /tmp/nic_fw/nfp6000_net.cat /lib/firmware/netronome/nfp6000_net.cat

	# Unload nfp module, check the list of interfaces before kernel loading

rmmod nfp

ifconfig -a | grep HWaddr

	# Loading the nfp_net driver, which will automatically load the firmware

modprobe nfp_net nfp_reset=1 fw_noload=0 num_rings=32

	# check if there is a new interface brought up after kernel loading

ifconfig -a | grep HWaddr

	#clean up the tmp folder

rm -rf /tmp/nic_fw

## User space loading

You may need to use root user to run the following cmds:

	# you need nfp module for loading the firmware in user space

rmmod nfp_net

rmmod nfp_netvf

rmmod nfp_net

modprobe nfp nfp_reset=1

	# Loading the firmware in user space

mkdir /tmp/nic_fw

cd /tmp/nic_fw

cp /YOUR_PATH_GIT/nfp-vrouter/firmware/nffw/ns_nic_cx40q_1.nffw /tmp/nic_fw/

nfp-nffw unload

nfp-nffw load /tmp/nic_fw/ns_nic_cx40q_1.nffw

	# Unload nfp module, check the list of interfaces before loading nfp_net driver

rmmod nfp

ifconfig -a | grep HWaddr

	# Remove the default path for driver to pick up firmware
	# (force it to use the already loaded firmware)

rm -rf /lib/firmware/netronome

	# Loading the nfp_net driver, which will automatically load the firmware

modprobe nfp_net num_rings=32

	# check if there is a new interface brought up after kernel loading

ifconfig -a | grep HWaddr

	#clean up the tmp folder

rm -rf /tmp/nic_fw


# Configure the new NIC interface

	# Bring the interface up to makes sure rss key is written to the BAR 

ifconfig ethX up; ifconfig ethX down
 
	# Configuration

ip addr flush dev ethX;ip route flush dev ethX

ifconfig ethX up;ifconfig eth6 mtu 1500

ifconfig ethX inet6 add fc00:1:0:0::1/64; ifconfig ethX 10.0.0.1/24 up


