#a Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
#
# @file        firmware/Makefile
# @brief       Makefile for the firmware
#

FW_BUILD = $(FIRMWARE_DIR)/build
FW_NFFW  = $(FIRMWARE_DIR)/nffw

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

FW_BUILD_DIRS =

FW_BUILD_TARGETS =
FW_LOAD_TARGETS =
FW_LIST_TARGETS =
FW_MKDEP_TARGETS =

include $(FIRMWARE_DIR)/Makefile.templates
include $(FIRMWARE_DIR)/Makefile.deps.templates
include $(FIRMWARE_DIR)/Makefile.apps

firmware_all: firmware_fetch_deps all_nffw

firmware_fetch_deps:

all_nffw:

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

firmware_clean:
	@for d in $(FW_BUILD_DIRS) ; do \
		echo "Cleaining $$d" ; \
		rm -rf $$d; \
	done
	@rm -f $(FW_BUILD)/*.map
	@rm -f $(FW_NFFW)/*.nffw

firmware_veryclean: firmware_clean firmware_clean_deps

$(foreach mkdep,$(FW_MKDEP_TARGETS),$(eval -include $(mkdep)))
