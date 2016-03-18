##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Default paths used in the NFPFlowNIC system.
"""

VROUTER_BUILD_PATH = '/releases-intern/vrouter/builds/'
MEFW_PATH = '/opt/netronome/bin/'

# Here we choose the nfp-bsp, nfp-bsp-dkms and nfp-sdk *.deb versions.
# These are taken from nightly dirs as to have the option to choose latest.
# However it is highly recommended to stick to stable versions.
# Before changing the *_VER variables please check the stable versions
# numbers at:
#     /releases-intern/apt/pool/non-free/n/nfp-bsp/
#     /releases-intern/apt/pool/non-free/n/nfp-sdk/

# BSP
BSP_VER = '2016.3.9.1350-1'
BSP = 'nfp-bsp-release-2015.11_%s_amd64.deb' % BSP_VER
BSP_DKMS = 'nfp-bsp-release-2015.11-dkms_%s_all.deb' % BSP_VER
BSP_LOC = '/releases-intern/nfp-bsp/distros/nfp-bsp-release-2015.11/dpkg/'

# LATEST BSP
LATEST_BSP_VER = 'LATEST'
LATEST_BSP = 'nfp-bsp-release-2015.11_%s_amd64.deb' % LATEST_BSP_VER
LATEST_BSP_DKMS = 'nfp-bsp-release-2015.11-dkms_%s_all.deb' % LATEST_BSP_VER
LATEST_BSP_LOC = '/releases-intern/nfp-bsp/distros/nfp-bsp-release-2015.11/dpkg/'

# SDK
SDK_VER = '5-devel-5787-2'
SDK = 'nfp-sdk_%s_amd64.deb' % SDK_VER
SDK_LOC = '/releases-intern/nfp-sdk/linux-x86_64/nfp-toolchain-5/dpkg/amd64/'
