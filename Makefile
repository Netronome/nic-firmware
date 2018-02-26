#a Copyright (C) 2015,  Gavin J Stark.  All rights reserved.
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
# @file        Makefile
# @brief       Top level makefile to set paths and include submakes
#
SHELL = /bin/bash
NFP_COMMON    := $(abspath $(CURDIR))
NETRONOME ?= /opt/netronome

REQ_SDK_VER   = = 6.x-devel
REQ_SDK_BUILD = -ge 3540

DEPS_DIR      = $(NFP_COMMON)/deps
FIRMWARE_DIR  = $(NFP_COMMON)/firmware
DOC_DIR       = $(NFP_COMMON)/docs
SCRIPT_DIR    = $(NFP_COMMON)/scripts
TEST_DIR      = test


Q ?= @
#Q ?=

HG_USERNAME ?= $(shell whoami)
FW_ID = $(shell ${SCRIPT_DIR}/describe-head.sh --fw_id)

ALL: tool_version_check firmware_all

clean: firmware_clean

veryclean: firmware_veryclean

help:
	@echo "Type 'make firmware_help' to get a list of firmware targets"

SDK_VER = $(shell $(NETRONOME)/bin/nfas --version | grep "Version:" | sed 's/^[[:space:]]*Version:[[:space:]]*//')
SDK_BUILD = $(shell $(NETRONOME)/bin/nfas --version | grep "Build number:" | sed 's/^[[:space:]]*Build number:[[:space:]]*//')

tool_version_check:
	@[ $(SDK_VER) $(REQ_SDK_VER) ] || ( echo "Need SDK_VERSION: $(REQ_SDK_VER)" && exit 1 )
	@[ $(SDK_BUILD) $(REQ_SDK_BUILD) ] || ( echo "Need SDK_BUILD: $(REQ_SDK_BUILD)" && exit 1 )

include $(DEPS_DIR)/Makefile
include $(FIRMWARE_DIR)/Makefile
include $(DOC_DIR)/Makefile
include $(TEST_DIR)/Makefile
