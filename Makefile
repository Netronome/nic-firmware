#a Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
#
# @file        Makefile
# @brief       Top level makefile to set paths and include submakes
#
SHELL = /bin/bash
NFP_COMMON    := $(abspath $(CURDIR))
#NETRONOME ?= /opt/netronome
NETRONOME ?= /opt/netronome/nfp-sdk-6-devel

DEPS_DIR      = $(NFP_COMMON)/deps
FIRMWARE_DIR  = $(NFP_COMMON)/firmware
DOC_DIR       = $(NFP_COMMON)/docs
TEST_DIR      = $(NFP_COMMON)/test

#Q ?= @
Q ?=

HG_USERNAME ?= $(shell whoami)

#Firmware name
BPF ?= $(shell echo "bpf")
#git SHA tag (first 7 characters)
GIT_TAG = $(shell git rev-parse HEAD | cut -c1-7)
#Add a "+" if building with un-committed/un-added changes
GIT_DIFF_UNC=
ifneq ($(shell git diff --name-only),)
	GIT_DIFF_UNC="+"
endif
#Add a "+" if building with added (staged) but un-committed changes
ifneq ($(shell git diff --staged --name-only),)
	ifeq ($(GIT_DIFF_UNC),)
		GIT_DIFF_UNC="+"
	endif
endif

ALL: firmware_all

clean: firmware_clean

veryclean: firmware_veryclean

help:
	@echo "Type 'make firmware_help' to get a list of firmware targets"

include $(DEPS_DIR)/Makefile
include $(FIRMWARE_DIR)/Makefile
include $(DOC_DIR)/Makefile
include $(TEST_DIR)/Makefile
