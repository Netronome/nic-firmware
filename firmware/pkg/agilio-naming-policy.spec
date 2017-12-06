Name: agilio-naming-policy
Summary: Consistent network device naming policy for Netronome SmartNICs. 
License: Netronome
Version: __VERSION__
Release: 1
BuildArch: noarch
Vendor: Netronome Systems, Inc.
URL: http://netronome.com
Packager: Edwin Peer <edwin.peer@netronome.com>

%description
Consistent network device naming policy for Netronome SmartNICs.

%files
%defattr(-,root, root)
/lib/udev/nfp-name-gen
/lib/udev/rules.d/79-nfp.rules
/usr/lib/dracut/modules.d/50agilio-nic/module-setup.sh

%post
dracut -f
