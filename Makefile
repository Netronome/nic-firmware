# Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
#
# @file        Makefile
# @brief       Top level makefile to set paths and include submakes
#
# SPDX-License-Identifier: BSD-2-Clause

SHELL = /bin/bash
NFP_COMMON    := $(abspath $(CURDIR))
NETRONOME     ?= /opt/netronome

REQ_SDK_VER   ?= 6.3.0.1
REQ_SDK_BUILD ?= 4917

DEPS_DIR       = $(NFP_COMMON)/deps
FIRMWARE_DIR   = $(NFP_COMMON)/firmware
DOC_DIR        = $(NFP_COMMON)/docs
SCRIPT_DIR     = $(NFP_COMMON)/scripts
TEST_DIR       = test


Q ?= @
#Q ?=

HG_USERNAME ?= $(shell whoami)

ALL: firmware_all

clean: firmware_clean

veryclean: firmware_veryclean

help:
	@echo "Type 'make firmware_help' to get a list of firmware targets"

SDK_VER = $(shell $(NETRONOME)/bin/nfas --version | grep "Version:" | sed 's/^[[:space:]]*Version:[[:space:]]*//')
SDK_BUILD = $(shell $(NETRONOME)/bin/nfas --version | grep "Build number:" | sed 's/^[[:space:]]*Build number:[[:space:]]*//')


sdk_check: sdk_install_check sdk_version_check

sdk_version_check:
	@[ "$(SDK_VER)" = "$(REQ_SDK_VER)" ] || ( echo "Need SDK_VERSION: $(REQ_SDK_VER)" && exit 1 )
	@[ $(SDK_BUILD) -eq $(REQ_SDK_BUILD) ] || ( echo "Need SDK_BUILD: $(REQ_SDK_BUILD)" && exit 1 )

sdk_install_check:
	@[ -f $(NETRONOME)/bin/nfas ] || ( echo "SDK not found. Please update the SDK22 path variable: export NETRONOME=<path>" && exit 1 )

include $(DEPS_DIR)/Makefile
include $(FIRMWARE_DIR)/Makefile
include $(DOC_DIR)/Makefile
include $(TEST_DIR)/Makefile
