Name: agilio-__FW_NAME__-firmware
Summary: Firmware for Netronome Agilio SmartNICs
License: Netronome
Version: __VERSION__
Release: 1
BuildArch: noarch
Vendor: Netronome Systems, Inc.
URL: http://netronome.com
Packager: Edwin Peer <edwin.peer@netronome.com>

%description
Firmware for Netronome Agilio SmartNICs

%files
%define _binaries_in_noarch_packages_terminate_build 0
%defattr(-,root, root)
/lib/firmware/netronome/__FW_NAME__

%post
cd /lib/firmware/netronome
ln -sf __FW_NAME__/*.nffw ./

