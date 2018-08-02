Name: __FW_NAME__
Summary: Firmware for Netronome Agilio SmartNICs
License: Netronome
Version: __VERSION__
Conflicts: ns-agilio-corenic
Suggests: agilio-naming-policy
Release: 1
BuildArch: noarch
Vendor: Netronome Systems, Inc.
URL: http://netronome.com
Source: __FW_NAME__-__VERSION__.tgz
Packager: Edwin Peer <edwin.peer@netronome.com>

%description
Firmware for Netronome Agilio SmartNICs

%prep
%setup -q

%install
mkdir -p $RPM_BUILD_ROOT/opt/netronome/__FW_NAME__
cp * $RPM_BUILD_ROOT/opt/netronome/__FW_NAME__

%files
%define _binaries_in_noarch_packages_terminate_build 0
%defattr(-,root, root)
/opt/netronome/__FW_NAME__
