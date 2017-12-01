Name: agilio-__FW_NAME__-firmware
Summary: Firmware for Netronome Agilio SmartNICs
License: Netronome
Version: __VERSION__
Conflicts: ns-agilio-corenic
Suggests: agilio-naming-policy
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
/opt/netronome/firmware/agilio-__FW_NAME__
