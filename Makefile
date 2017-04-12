#a Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
#
# @file        Makefile
# @brief       Top level makefile to set paths and include submakes
#

NFP_COMMON    := $(abspath $(CURDIR))
NETRONOME ?= /opt/netronome

DEPS_DIR      = $(NFP_COMMON)/deps
FIRMWARE_DIR  = $(NFP_COMMON)/firmware
DOC_DIR       = $(NFP_COMMON)/docs
TEST_DIR      = $(NFP_COMMON)/test

Q ?= @

HG_USERNAME ?= $(shell whoami)

ALL: firmware_all

clean: firmware_clean

veryclean: firmware_veryclean

help:
	@echo "Type 'make firmware_help' to get a list of firmware targets"

include $(DEPS_DIR)/Makefile
include $(FIRMWARE_DIR)/Makefile
include $(DOC_DIR)/Makefile
include $(TEST_DIR)/Makefile
