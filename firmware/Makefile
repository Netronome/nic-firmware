# Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# @file        firmware/Makefile
# @brief       Makefile for the firmware
#

FW_BUILD = $(FIRMWARE_DIR)/build
FW_NFFW  = $(FIRMWARE_DIR)/nffw
FW_CAT  = $(FIRMWARE_DIR)/cat

# Card version
NFP_SKU?=nfp-4xxx-b0

# Chip revisions
# 0x00=A0 0x10=B0
NFP_REV_MIN?=0x10
NFP_REV_MAX?=0x10



NFAS = $(NETRONOME)/bin/nfas
NFAS_BASE_INC = -I$(NETRONOME)/components/standardlibrary/include
NFAS_BASE_INC += -I$(NETRONOME)/components/standardlibrary/microcode/include
NFAS_BASE_INC += -I$(NETRONOME)/components/standardlibrary/microcode/src
NFAS_BASE_DEFS =
NFAS_BASE_FLAGS = 			\
        -third_party_addressing_40_bit	\
        -permit_dram_unaligned		\
        -preproc64			\
        -indirect_ref_format_nfp6000	\
        -W3				\
        -C				\
        -R				\
        -lr -go -g			\
        -lm 0

NFAS_CODELESS_FLAGS = 			\
	-codeless			\
        -preproc64			\
        -W3				\
        -C				\
        -go				\
	-g

NFCC = $(NETRONOME)/bin/nfcc
NFCC_BASE_INC = \
	-I$(NETRONOME)/components/standardlibrary/include \
	-I$(NETRONOME)/components/standardlibrary/microc/include \
	-I$(FIRMWARE_DIR)/lib
NFCC_BASE_DEFS =
NFCC_BASE_FLAGS = 			\
	-W3				\
	-Ob2				\
	-mIPOPT_expose_intrinsics	\
	-Qspill=5			\
	-Qno_decl_volatile		\
	-single_dram_signal

NFCC_BASE_CLIBS = $(NETRONOME)/components/standardlibrary/microc/src/rtl.c

PICOCODE_DIR = $(NETRONOME)/components/standardlibrary/picocode/nfp6000

NFLD = $(NETRONOME)/bin/nfld
NFLD_BASE_FLAGS =

NFFW2CA = $(NETRONOME)/bin/nfp-nffw2ca

FW_BUILD_DIRS =

FW_BUILD_TARGETS =
FW_LOAD_TARGETS =
FW_LIST_TARGETS =
FW_TEST_TARGETS =
FW_MKDEP_TARGETS =

include $(FIRMWARE_DIR)/Makefile.templates
include $(FIRMWARE_DIR)/Makefile.deps.templates
include $(FIRMWARE_DIR)/Makefile.apps

firmware_all: tool_version_check firmware_fetch_deps all_nffw all_cat

firmware_fetch_deps:

all_nffw:

all_cat:

test: FORCE_TESTS
	@make `echo $(FW_TEST_TARGETS) | sed 's/\ .*//g'`

FORCE_TESTS:
 
firmware_help:
	@echo "Global commands"
	@echo "	firmware_show_listfiles -- show a list of .list targets"
	@echo "	firmware_fetch_deps -- fetch firmware dependencies"
	@echo "	firmware_clean_deps -- remove firmware dependencies"
	@echo "	firmware_update_deps -- update firmware if revisions changed"
	@echo
	@echo "Firmware build targets"
	@for t in $(FW_BUILD_TARGETS) ; do echo "	$$t" ; done
	@echo
	@echo "Firmware load targets"
	@for t in $(FW_LOAD_TARGETS) ; do echo "	$$t" ; done
	@echo

firmware_show_listfiles:
	@echo "Firmware .list build targets"
	@for t in $(FW_LIST_TARGETS) ; do echo "	$$t" ; done
	@echo

firmware_show_tests:
	@echo "Firmware test targets"
	@for t in $(FW_TEST_TARGETS) ; do echo "	$$t" ; done
	@echo


firmware_clean:
	@for d in $(FW_BUILD_DIRS) ; do \
		echo "Cleaning $$d" ; \
		rm -rf $$d; \
	done
	@rm -f $(FW_BUILD)/*.map
	@rm -f $(FW_NFFW)/*.nffw
	@rm -f $(FW_CAT)/*.cat
	@rm -f $(FW_CAT)/*.trace
	@rm -rf $(FIRMWARE_DIR)/pkg/files
	@rm -rf $(FIRMWARE_DIR)/pkg/deb
	@rm -rf $(FIRMWARE_DIR)/pkg/rpm
	@rm -rf $(FIRMWARE_DIR)/pkg/tgz
	@rm -rf $(FIRMWARE_DIR)/pkg/out

firmware_veryclean: firmware_clean firmware_clean_deps

FW_PKG_NAME = $(shell ${SCRIPT_DIR}/describe-head.sh --pkg_name)
FW_PKG_VER = $(shell ${SCRIPT_DIR}/describe-head.sh --pkg_ver)
DEB_FW_PKG = $(FIRMWARE_DIR)/pkg/deb/agilio-$(FW_PKG_NAME)-firmware-$(FW_PKG_VER)-1
DEB_UDEV_PKG = $(FIRMWARE_DIR)/pkg/deb/agilio-naming-policy-$(FW_PKG_VER)-1
DEB_SZ = $(shell du -ck $(FW_NFFW)/*.nffw | grep total$ | cut -f 1)

FW_TREE = $(FIRMWARE_DIR)/pkg/files/firmware
UDEV_TREE = $(FIRMWARE_DIR)/pkg/files/udev

firmware_tree: firmware_all
	@mkdir -p $(FW_TREE)/opt/netronome/firmware/agilio-$(FW_PKG_NAME)
	@cp $(FW_NFFW)/*.nffw $(FW_TREE)/opt/netronome/firmware/agilio-$(FW_PKG_NAME)

udev_tree:
	@mkdir -p $(UDEV_TREE)/lib/udev/rules.d
	@cp $(SCRIPT_DIR)/nfp-name-gen $(UDEV_TREE)/lib/udev
	@cp $(SCRIPT_DIR)/79-nfp.rules $(UDEV_TREE)/lib/udev/rules.d

firmware_deb: firmware_tree
	@mkdir -p $(DEB_FW_PKG)/DEBIAN
	@cp -r $(FW_TREE)/* $(DEB_FW_PKG)
	@mkdir -p $(DEB_FW_PKG)/usr/share/initramfs-tools/hooks
	@cp $(SCRIPT_DIR)/agilio-nic.initramfs-hook $(DEB_FW_PKG)/usr/share/initramfs-tools/hooks/agilio-nic-firmware
	@cat $(FIRMWARE_DIR)/pkg/agilio-firmware.control | sed 's/__VERSION__/$(FW_PKG_VER)-1/g' | sed 's/__FW_NAME__/$(FW_PKG_NAME)/g' > $(DEB_FW_PKG)/DEBIAN/control
	@echo "Installed-Size: $(shell du -ck $(FW_TREE) | grep total$ | cut -f 1)" >> $(DEB_FW_PKG)/DEBIAN/control
	@echo "#!/bin/sh" > $(DEB_FW_PKG)/DEBIAN/postinst
	@cat $(FIRMWARE_DIR)/pkg/postinst | sed 's/__FW_NAME__/$(FW_PKG_NAME)/g' >> $(DEB_FW_PKG)/DEBIAN/postinst
	@echo "update-initramfs -uk all" >> $(DEB_FW_PKG)/DEBIAN/postinst
	@echo "#!/bin/sh" > $(DEB_FW_PKG)/DEBIAN/prerm
	@cat $(FIRMWARE_DIR)/pkg/prerm >> $(DEB_FW_PKG)/DEBIAN/prerm
	@chmod a+x $(DEB_FW_PKG)/DEBIAN/postinst $(DEB_FW_PKG)/DEBIAN/prerm
	@fakeroot dpkg-deb --build $(DEB_FW_PKG)

udev_deb: udev_tree
	@mkdir -p $(DEB_UDEV_PKG)/DEBIAN
	@cp -r $(UDEV_TREE)/* $(DEB_UDEV_PKG)
	@mkdir -p $(DEB_UDEV_PKG)/usr/share/initramfs-tools/hooks
	@cp $(SCRIPT_DIR)/agilio-naming.initramfs-hook $(DEB_UDEV_PKG)/usr/share/initramfs-tools/hooks/agilio-naming-policy
	@cat $(FIRMWARE_DIR)/pkg/agilio-naming-policy.control | sed 's/__VERSION__/$(FW_PKG_VER)-1/g' > $(DEB_UDEV_PKG)/DEBIAN/control
	@echo "Installed-Size: $(shell du -ck $(UDEV_TREE) | grep total$ | cut -f 1)" >> $(DEB_UDEV_PKG)/DEBIAN/control
	@echo "#!/bin/sh" > $(DEB_UDEV_PKG)/DEBIAN/postinst
	@echo "update-initramfs -uk all" >> $(DEB_UDEV_PKG)/DEBIAN/postinst
	@chmod a+x $(DEB_UDEV_PKG)/DEBIAN/postinst
	@fakeroot dpkg-deb --build $(DEB_UDEV_PKG)
	
RPM_FW_PKG = $(FIRMWARE_DIR)/pkg/rpm/firmware
RPM_UDEV_PKG = $(FIRMWARE_DIR)/pkg/rpm/udev

firmware_rpm: firmware_tgz
	@mkdir -p $(RPM_FW_PKG)/{BUILD,SPECS,SOURCES,RPMS,SRPMS}
	echo Source: $(TGZ_PKG)/agilio-$(FW_PKG_NAME)-firmware-$(FW_PKG_VER).tgz
	echo Target: $(RPM_FW_PKG)/SOURCES
	cp $(TGZ_PKG)/agilio-$(FW_PKG_NAME)-firmware-$(FW_PKG_VER).tgz $(RPM_FW_PKG)/SOURCES
	@cat $(FIRMWARE_DIR)/pkg/agilio-firmware.spec | sed 's/__VERSION__/$(FW_PKG_VER)/g' | sed 's/__FW_NAME__/$(FW_PKG_NAME)/g' > $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	@echo "%post" >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	@cat $(FIRMWARE_DIR)/pkg/postinst | sed 's/__FW_NAME__/$(FW_PKG_NAME)/g' >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	@echo "dracut -f" >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	@echo "%preun" >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	@cat $(FIRMWARE_DIR)/pkg/prerm >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	@rpmbuild -ba $(RPM_FW_PKG)/SPECS/agilio-firmware.spec --buildroot $(RPM_FW_PKG)/BUILD --define "_rpmdir $(RPM_FW_PKG)/RPMS" --define "_sourcedir $(RPM_FW_PKG)/SOURCES" --define "_srpmdir $(RPM_FW_PKG)/SRPMS" 2>&1 | grep -v "Arch dependent binaries"

udev_rpm: udev_tree
	@mkdir -p $(RPM_UDEV_PKG)/{BUILD,SPECS,RPMS}
	@cp -r $(UDEV_TREE)/* $(RPM_UDEV_PKG)/BUILD
	@mkdir -p $(RPM_UDEV_PKG)/BUILD/usr/lib/dracut/modules.d/50agilio-nic
	@cp $(SCRIPT_DIR)/module-setup.sh.dracut $(RPM_UDEV_PKG)/BUILD/usr/lib/dracut/modules.d/50agilio-nic/module-setup.sh
	@cat $(FIRMWARE_DIR)/pkg/agilio-naming-policy.spec | sed 's/__VERSION__/$(FW_PKG_VER)/g' > $(RPM_UDEV_PKG)/SPECS/agilio-naming-policy.spec
	@rpmbuild -bb $(RPM_UDEV_PKG)/SPECS/agilio-naming-policy.spec --buildroot $(RPM_UDEV_PKG)/BUILD --define "_rpmdir $(RPM_UDEV_PKG)/RPMS"

TGZ_PKG = $(FIRMWARE_DIR)/pkg/tgz

firmware_tgz: firmware_all
	@mkdir -p $(TGZ_PKG)/agilio-$(FW_PKG_NAME)-firmware-$(FW_PKG_VER)
	@cp $(FW_NFFW)/*.nffw $(TGZ_PKG)/agilio-$(FW_PKG_NAME)-firmware-$(FW_PKG_VER)
	@cd $(TGZ_PKG) && tar --owner=0 --group=0 -czvf agilio-$(FW_PKG_NAME)-firmware-$(FW_PKG_VER).tgz agilio-$(FW_PKG_NAME)-firmware-$(FW_PKG_VER)

ifeq ("$(FW_PKG_NAME)","nic")
package: firmware_tgz firmware_deb udev_deb firmware_rpm udev_rpm
else
package: firmware_tgz firmware_deb firmware_rpm
endif
	@mkdir -p $(FIRMWARE_DIR)/pkg/out/{tgz,deb,rpm}
	@mv $(TGZ_PKG)/*.tgz $(FIRMWARE_DIR)/pkg/out/tgz/
	@mv $(FIRMWARE_DIR)/pkg/deb/*.deb $(FIRMWARE_DIR)/pkg/out/deb/
	@mv $(RPM_FW_PKG)/RPMS/noarch/*.rpm $(FIRMWARE_DIR)/pkg/out/rpm/
ifeq ("$(FW_PKG_NAME)","nic")
	@mv $(RPM_UDEV_PKG)/RPMS/noarch/*.rpm $(FIRMWARE_DIR)/pkg/out/rpm/
endif

$(foreach mkdep,$(FW_MKDEP_TARGETS),$(eval -include $(mkdep)))
