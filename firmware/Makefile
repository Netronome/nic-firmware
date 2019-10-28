# Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
#
# @file        firmware/Makefile
# @brief       Makefile for the firmware
#
# SPDX-License-Identifier: BSD-2-Clause

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
	-v1				\
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
FW_U_TEST_TARGETS =
FW_C_TEST_TARGETS =
FW_MKDEP_TARGETS =

include $(FIRMWARE_DIR)/Makefile.templates
include $(FIRMWARE_DIR)/Makefile.deps.templates
include $(FIRMWARE_DIR)/Makefile.apps

firmware_all: sdk_check firmware_fetch_deps all_nffw all_cat

firmware_fetch_deps:

all_nffw:

all_cat:

test: FORCE_TESTS
	@make `echo $(FW_U_TEST_TARGETS) | sed 's/\ .*//g'`
	@make `echo $(FW_C_TEST_TARGETS) | sed 's/\ .*//g'`

test_u: FORCE_TESTS
	@make `echo $(FW_U_TEST_TARGETS) | sed 's/\ .*//g'`

test_c: FORCE_TESTS
	@make `echo $(FW_C_TEST_TARGETS) | sed 's/\ .*//g'`

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
	@for t in $(FW_U_TEST_TARGETS) ; do echo "    $$t" ; done
	@for t in $(FW_C_TEST_TARGETS) ; do echo "    $$t" ; done
	@echo


firmware_clean:
	@for d in $(FW_BUILD_DIRS) ; do \
		echo "Cleaning $$d" ; \
		rm -rf $$d; \
	done
	@rm -rf $(FW_BUILD)/*
	@rm -rf $(FW_NFFW)/*
	@rm -rf $(FIRMWARE_DIR)/pkg/files
	@rm -rf $(FIRMWARE_DIR)/pkg/deb
	@rm -rf $(FIRMWARE_DIR)/pkg/rpm
	@rm -rf $(FIRMWARE_DIR)/pkg/tgz
	@rm -rf $(FIRMWARE_DIR)/pkg/out
	@rm -rf $(NFP_COMMON)/*.obj

firmware_veryclean: firmware_clean firmware_clean_deps

FW_PKG_VER = $(shell ${SCRIPT_DIR}/describe-head.sh --pkg_ver)
DEB_UDEV_PKG = $(FIRMWARE_DIR)/pkg/deb/agilio-naming-policy-$(FW_PKG_VER)-1
FW_TREE = $(FIRMWARE_DIR)/pkg/files/firmware/$(FLAVOR)
UDEV_TREE = $(FIRMWARE_DIR)/pkg/files/udev
RPM_FW_PKG = $(FIRMWARE_DIR)/pkg/rpm/firmware/$(FLAVOR)
RPM_UDEV_PKG = $(FIRMWARE_DIR)/pkg/rpm/udev
TGZ_PKG = $(FIRMWARE_DIR)/pkg/tgz

define firmware_tree
$(1)__firmware_tree: firmware_all
	@mkdir -p $(FW_TREE)/$(1)/opt/netronome/$(shell $(SCRIPT_DIR)/describe-head.sh --pkg_name $(1))
	@cp $(FW_NFFW)/$(1)/*.nffw $(FW_TREE)/$(1)/opt/netronome/$(shell $(SCRIPT_DIR)/describe-head.sh --pkg_name $(1))
endef
$(foreach FLAVOR,$(FLAVOR_LIST), $(eval $(call firmware_tree,$(FLAVOR))))

define firmware_deb
$(1)__firmware_deb: $(1)__firmware_tree
	$(Q)mkdir -p $(3)/DEBIAN
	$(Q)cp -r $(FW_TREE)/$(1)/* $(3)
	$(Q)mkdir -p $(3)/usr/share/initramfs-tools/hooks
	$(Q)cp $(SCRIPT_DIR)/agilio-nic.initramfs-hook $(3)/usr/share/initramfs-tools/hooks/agilio-$(FLAVOR)-firmware
	$(Q)cat $(FIRMWARE_DIR)/pkg/agilio-firmware.control \
		| sed 's/__VERSION__/$(FW_PKG_VER)-1/g' \
		| sed 's/__FW_NAME__/$(2)/g' \
		> $(3)/DEBIAN/control
	$(Q)echo "Installed-Size: `du -ck $(FW_TREE)/$(1) | grep total$ | cut -f 1`" >> $(3)/DEBIAN/control
	$(Q)echo "#!/bin/sh" > $(3)/DEBIAN/postinst
	$(Q)cat $(FIRMWARE_DIR)/pkg/postinst | sed 's/__FW_NAME__/$(2)/g' >> $(3)/DEBIAN/postinst
	$(Q)echo "update-initramfs -uk all" >> $(3)/DEBIAN/postinst
	$(Q)echo "#!/bin/sh" > $(3)/DEBIAN/prerm
	$(Q)cat $(FIRMWARE_DIR)/pkg/prerm >> $(3)/DEBIAN/prerm
	$(Q)chmod a+x $(3)/DEBIAN/postinst $(3)/DEBIAN/prerm
	$(Q)fakeroot dpkg-deb --build $(3)
endef
$(foreach FLAVOR,$(FLAVOR_LIST), $(eval $(call firmware_deb,$(FLAVOR),$(shell $(SCRIPT_DIR)/describe-head.sh --pkg_name $(FLAVOR)),$(FIRMWARE_DIR)/$(shell $(SCRIPT_DIR)/describe-head.sh --deb_dir $(FLAVOR)))))

define firmware_rpm
$(1)__firmware_rpm: $(1)__firmware_tgz
	$(Q)mkdir -p $(RPM_FW_PKG)/{BUILD,SPECS,SOURCES,RPMS,SRPMS}
	$(Q)cp $(TGZ_PKG)/$(2)-$(FW_PKG_VER).tgz $(RPM_FW_PKG)/SOURCES
	$(Q)cp $(FIRMWARE_DIR)/pkg/agilio-firmware.spec $(RPM_FW_PKG)/SPECS/agilio-firmware.tmp
	$(Q)tar tzvf $(TGZ_PKG)/$(2)-$(FW_PKG_VER).tgz | grep nffw | sed 's/.*\//\/opt\/netronome\/__FW_NAME__\//' >> $(RPM_FW_PKG)/SPECS/agilio-firmware.tmp
	$(Q)cat $(RPM_FW_PKG)/SPECS/agilio-firmware.tmp | sed 's/__VERSION__/$(FW_PKG_VER)/g' | sed 's/__FW_NAME__/$(2)/g' > $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	$(Q)echo "%post" >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	$(Q)cat $(FIRMWARE_DIR)/pkg/postinst | sed 's/__FW_NAME__/$(2)/g' >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	$(Q)echo "dracut -f" >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	$(Q)echo "%preun" >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	$(Q)cat $(FIRMWARE_DIR)/pkg/prerm >> $(RPM_FW_PKG)/SPECS/agilio-firmware.spec
	$(Q)rpmbuild -ba $(RPM_FW_PKG)/SPECS/agilio-firmware.spec --buildroot $(RPM_FW_PKG)/BUILD --define "_rpmdir $(RPM_FW_PKG)/RPMS" --define "_sourcedir $(RPM_FW_PKG)/SOURCES" --define "_srpmdir $(RPM_FW_PKG)/SRPMS" 2>&1 | grep -v "Arch dependent binaries"
endef
$(foreach FLAVOR,$(FLAVOR_LIST), $(eval $(call firmware_rpm,$(FLAVOR),$(shell $(SCRIPT_DIR)/describe-head.sh --pkg_name $(FLAVOR)))))

define firmware_tgz
$(1)__firmware_tgz: firmware_all
	$(Q)mkdir -p $(TGZ_PKG)/$(2)-$(FW_PKG_VER)
	$(Q)cp $(FW_NFFW)/$(1)/*.nffw $(TGZ_PKG)/$(2)-$(FW_PKG_VER)
	$(Q)cd $(TGZ_PKG) && tar --owner=0 --group=0 -czvf $(2)-$(FW_PKG_VER).tgz $(2)-$(FW_PKG_VER)
endef
$(foreach FLAVOR,$(FLAVOR_LIST), $(eval $(call firmware_tgz,$(FLAVOR),$(shell $(SCRIPT_DIR)/describe-head.sh --pkg_name $(FLAVOR)))))

udev_tree:
	$(Q)mkdir -p $(UDEV_TREE)/lib/udev/rules.d
	$(Q)cp $(SCRIPT_DIR)/nfp-name-gen $(UDEV_TREE)/lib/udev
	$(Q)cp $(SCRIPT_DIR)/79-nfp.rules $(UDEV_TREE)/lib/udev/rules.d

udev_deb: udev_tree
	$(Q)mkdir -p $(DEB_UDEV_PKG)/DEBIAN
	$(Q)cp -r $(UDEV_TREE)/* $(DEB_UDEV_PKG)
	$(Q)mkdir -p $(DEB_UDEV_PKG)/usr/share/initramfs-tools/hooks
	$(Q)cp $(SCRIPT_DIR)/agilio-naming.initramfs-hook $(DEB_UDEV_PKG)/usr/share/initramfs-tools/hooks/agilio-naming-policy
	$(Q)cat $(FIRMWARE_DIR)/pkg/agilio-naming-policy.control | sed 's/__VERSION__/$(FW_PKG_VER)-1/g' > $(DEB_UDEV_PKG)/DEBIAN/control
	$(Q)echo "Installed-Size: $(shell du -ck $(UDEV_TREE) | grep total$ | cut -f 1)" >> $(DEB_UDEV_PKG)/DEBIAN/control
	$(Q)echo "#!/bin/sh" > $(DEB_UDEV_PKG)/DEBIAN/postinst
	$(Q)echo "update-initramfs -uk all" >> $(DEB_UDEV_PKG)/DEBIAN/postinst
	$(Q)chmod a+x $(DEB_UDEV_PKG)/DEBIAN/postinst
	$(Q)fakeroot dpkg-deb --build $(DEB_UDEV_PKG)

udev_rpm: udev_tree
	$(Q)mkdir -p $(RPM_UDEV_PKG)/{BUILD,SPECS,RPMS}
	$(Q)cp -r $(UDEV_TREE)/* $(RPM_UDEV_PKG)/BUILD
	$(Q)mkdir -p $(RPM_UDEV_PKG)/BUILD/usr/lib/dracut/modules.d/50agilio-nic
	$(Q)cp $(SCRIPT_DIR)/module-setup.sh.dracut $(RPM_UDEV_PKG)/BUILD/usr/lib/dracut/modules.d/50agilio-nic/module-setup.sh
	$(Q)cat $(FIRMWARE_DIR)/pkg/agilio-naming-policy.spec | sed 's/__VERSION__/$(FW_PKG_VER)/g' > $(RPM_UDEV_PKG)/SPECS/agilio-naming-policy.spec
	$(Q)rpmbuild -bb $(RPM_UDEV_PKG)/SPECS/agilio-naming-policy.spec --buildroot $(RPM_UDEV_PKG)/BUILD --define "_rpmdir $(RPM_UDEV_PKG)/RPMS"

package_tgz: $(foreach FLAVOR,$(FLAVOR_LIST), $(FLAVOR)__firmware_tgz)
	$(Q)mkdir -p $(FIRMWARE_DIR)/pkg/out/tgz
	$(Q)cp $(TGZ_PKG)/*.tgz $(FIRMWARE_DIR)/pkg/out/tgz/

package_rpm: udev_rpm $(foreach FLAVOR,$(FLAVOR_LIST), $(FLAVOR)__firmware_rpm)
	$(Q)mkdir -p $(FIRMWARE_DIR)/pkg/out/rpm
	$(Q)cp $(foreach FLAVOR,$(FLAVOR_LIST), $(FIRMWARE_DIR)/pkg/rpm/firmware/$(FLAVOR)/RPMS/noarch/*.rpm) $(FIRMWARE_DIR)/pkg/out/rpm/
	$(Q)cp $(RPM_UDEV_PKG)/RPMS/noarch/*.rpm $(FIRMWARE_DIR)/pkg/out/rpm/

package_deb: udev_deb $(foreach FLAVOR,$(FLAVOR_LIST), $(FLAVOR)__firmware_deb)
	$(Q)mkdir -p $(FIRMWARE_DIR)/pkg/out/deb
	$(Q)cp $(FIRMWARE_DIR)/pkg/deb/*.deb $(FIRMWARE_DIR)/pkg/out/deb/

package: package_tgz package_deb package_rpm

$(foreach mkdep,$(FW_MKDEP_TARGETS),$(eval -include $(mkdep)))
