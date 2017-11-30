# Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
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

firmware_all: firmware_fetch_deps all_nffw all_cat

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
	@rm -rf $(FIRMWARE_DIR)/pkg/deb
	@rm -rf $(FIRMWARE_DIR)/pkg/rpm
	@rm -rf $(FIRMWARE_DIR)/pkg/tgz

firmware_veryclean: firmware_clean firmware_clean_deps

PKG_NAME = $(shell git describe --tags HEAD | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\1/')
PKG_VER = $(shell git describe --tags HEAD | sed 's/\([a-zA-Z\-]*\)-\(.*[0-9].*[[:alnum:]]*\)/\2/' | sed 's/%/~/g' | sed 's/-/\./g')$(GIT_DIFF_UNC)
DEB_PKG = $(FIRMWARE_DIR)/pkg/deb/agilio-$(PKG_NAME)-firmware-$(PKG_VER)-1
DEB_SZ = $(shell du -ck $(FW_NFFW)/*.nffw | grep total$ | cut -f 1)

firmware_deb: firmware_all
	@mkdir -p $(DEB_PKG)/{opt/netronome/firmware/agilio-$(PKG_NAME),DEBIAN}
	@cp $(FW_NFFW)/*.nffw $(DEB_PKG)/opt/netronome/firmware/agilio-$(PKG_NAME)
	@mkdir -p $(DEB_PKG)/lib/udev/rules.d
	@cp $(SCRIPT_DIR)/agilio-nic-name-gen $(DEB_PKG)/lib/udev
	@cp $(SCRIPT_DIR)/79-agilio-nic.rules $(DEB_PKG)/lib/udev/rules.d
	@mkdir -p $(DEB_PKG)/usr/share/initramfs-tools/hooks
	@cp $(SCRIPT_DIR)/initramfs-tools-module-setup.sh $(DEB_PKG)/usr/share/initramfs-tools/hooks/nfp
	@cat $(FIRMWARE_DIR)/pkg/deb.control | sed 's/__VERSION__/$(PKG_VER)-1/g' | sed 's/__FW_NAME__/$(PKG_NAME)/g' > $(DEB_PKG)/DEBIAN/control
	@echo "Installed-Size: $(DEB_SZ)" >> $(DEB_PKG)/DEBIAN/control
	@echo "#!/bin/sh" > $(DEB_PKG)/DEBIAN/postinst
	@cat $(FIRMWARE_DIR)/pkg/postinst | sed 's/__FW_NAME__/$(PKG_NAME)/g' >> $(DEB_PKG)/DEBIAN/postinst
	@echo "update-initramfs -uk all" >> $(DEB_PKG)/DEBIAN/postinst
	@echo "#!/bin/sh" > $(DEB_PKG)/DEBIAN/prerm
	@cat $(FIRMWARE_DIR)/pkg/prerm >> $(DEB_PKG)/DEBIAN/prerm
	@chmod a+x $(DEB_PKG)/DEBIAN/postinst $(DEB_PKG)/DEBIAN/prerm
	@fakeroot dpkg-deb --build $(DEB_PKG)

RPM_PKG = $(FIRMWARE_DIR)/pkg/rpm

firmware_rpm: firmware_all
	@mkdir -p $(RPM_PKG)/{BUILD/opt/netronome/firmware/agilio-$(PKG_NAME),SPECS,RPMS}
	@cp $(FW_NFFW)/*.nffw $(RPM_PKG)/BUILD/opt/netronome/firmware/agilio-$(PKG_NAME)
	@mkdir -p $(RPM_PKG)/BUILD/lib/udev/rules.d
	@cp $(SCRIPT_DIR)/agilio-nic-name-gen $(RPM_PKG)/BUILD/lib/udev
	@cp $(SCRIPT_DIR)/79-agilio-nic.rules $(RPM_PKG)/BUILD/lib/udev/rules.d
	@cat $(FIRMWARE_DIR)/pkg/rpm.spec | sed 's/__VERSION__/$(PKG_VER)/g' | sed 's/__FW_NAME__/$(PKG_NAME)/g' > $(RPM_PKG)/SPECS/agilio-firmware.spec
	@echo "%post" >> $(RPM_PKG)/SPECS/agilio-firmware.spec
	@cat $(FIRMWARE_DIR)/pkg/postinst | sed 's/__FW_NAME__/$(PKG_NAME)/g' >> $(RPM_PKG)/SPECS/agilio-firmware.spec
	@echo "dracut -f" >> $(RPM_PKG)/SPECS/agilio-firmware.spec
	@echo "%preun" >> $(RPM_PKG)/SPECS/agilio-firmware.spec
	@cat $(FIRMWARE_DIR)/pkg/prerm >> $(RPM_PKG)/SPECS/agilio-firmware.spec
	@rpmbuild -bb $(RPM_PKG)/SPECS/agilio-firmware.spec --buildroot $(RPM_PKG)/BUILD --define "_rpmdir $(RPM_PKG)/RPMS"

TGZ_PKG = $(FIRMWARE_DIR)/pkg/tgz

firmware_tgz: firmware_all
	@mkdir -p $(TGZ_PKG)/agilio-$(PKG_NAME)
	@cp $(FW_NFFW)/*.nffw $(TGZ_PKG)/agilio-$(PKG_NAME)
	@cd $(TGZ_PKG) && tar --owner=0 --group=0 -czvf agilio-$(PKG_NAME)-firmware-$(PKG_VER).tgz agilio-$(PKG_NAME)

package: firmware_tgz firmware_deb firmware_rpm

$(foreach mkdep,$(FW_MKDEP_TARGETS),$(eval -include $(mkdep)))
