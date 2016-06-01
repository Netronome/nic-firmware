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

NFP_COMMON    := $(abspath $(CURDIR))
NETRONOME = /opt/netronome

DEPS_DIR      = $(NFP_COMMON)/deps
SCRIPTS_DIR   = $(NFP_COMMON)/scripts
FIRMWARE_DIR  = $(NFP_COMMON)/firmware
HOST_DIR      = $(NFP_COMMON)/src
KERN_DIR      = $(NFP_COMMON)/kernel
DOC_DIR       = $(NFP_COMMON)/docs
TEST_DIR      = $(NFP_COMMON)/test
SRCPKG_DIR    = $(NFP_COMMON)/srcpkg

Q ?= @

ALL: firmware_all

clean: firmware_clean srcpkg_clean

veryclean: firmware_veryclean

help:
	@echo "Type 'make firmware_help' to get a list of firmware targets"

include $(DEPS_DIR)/Makefile
include $(FIRMWARE_DIR)/Makefile
include $(HOST_DIR)/Makefile
include $(KERN_DIR)/Makefile
include $(SCRIPTS_DIR)/Makefile
include $(DOC_DIR)/Makefile
include $(TEST_DIR)/Makefile
include $(SRCPKG_DIR)/Makefile
