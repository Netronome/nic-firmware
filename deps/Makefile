#
# Change these revisions to suit the project
#
# FLOWENV_REV - Tip as of Apr 23 2018
FLOWENV_REV=a77d5b2
# NFD_REV - Jun 22 2018
NFD_REV=4640b43b

NFP_VROUTER_REV=$(shell git rev-parse HEAD)

#
# Global variables
#
HG_DEPS =
HG_REVS =

GIT_DEPS =
GIT_REVS =

#
# Specific dependencies here
#

#
# Flowenv
#
FLOWENV_DIR = $(DEPS_DIR)/flowenv.git
FLOWENV_INC = -I$(FLOWENV_DIR)/me/lib
GRO_DIR = $(DEPS_DIR)/flowenv.git/me/blocks/gro
GRO_INC = -I$(GRO_DIR)

$(DEPS_DIR)/flowenv.git:
	git clone -q --no-checkout \
		git://source.netronome.com/flowenv.git $(FLOWENV_DIR)
	cd $(FLOWENV_DIR) && git checkout $(FLOWENV_REV)
	cd $(DEPS_DIR)/flowenv.git && patch -p1 < ../gro_multicast.patch && cd -

GIT_DEPS += $(FLOWENV_DIR)
GIT_REVS += $(FLOWENV_REV)

#
# Flowenv
#
BLM_DIR = $(FLOWENV_DIR)/me/blocks/blm
BLM_INC = -I$(BLM_DIR)/me/lib

#
# NFD
#
NFD_DIR = $(DEPS_DIR)/ng-nfd.git
NFD_INC = -I$(NFD_DIR)/shared \
	  -I$(NFD_DIR)/me/blocks/vnic

$(DEPS_DIR)/ng-nfd.git:
	git clone -q --no-checkout \
		git://source.netronome.com/ng-nfd.git $(NFD_DIR)
	cd $(NFD_DIR) && git checkout $(NFD_REV)
	cd $(DEPS_DIR)/ng-nfd.git && patch -p1 < ../nfd_abi3.patch && cd -
	cd $(DEPS_DIR)/ng-nfd.git && patch -p1 < ../nfd_tlv.patch && cd -
	cd $(DEPS_DIR)/ng-nfd.git && patch -p1 < ../nfd_tlv_stats.patch && cd -
	cd $(DEPS_DIR)/ng-nfd.git && patch -p1 < ../nfd_ctm_buf.patch && cd -


GIT_DEPS += $(NFD_DIR)
GIT_REVS += $(NFD_REV)

#
# Processing for all dependencies
#
#

#
# $1 - repo directory
# $2 - revision
#
define update_hg_dep_decl

	$(Q)(echo Checking $1; cd $1 ; if [ `hg id -i` != "$2" ] ; then echo "Updating $1 to revision $2"; hg pull ; hg up -r $2; fi)
endef

#
# $1 - repo directory
# $2 - revision
#
define update_git_dep_decl

	$(Q)(echo Checking $1; cd $1 ; if ! git rev-parse HEAD | grep -q "$2" ; then echo "Updating $1 to revision $2"; git pull; git checkout $2; fi)
endef

firmware_fetch_deps: $(HG_DEPS) $(GIT_DEPS)

$(DEPS_DIR)/Makefile: firmware_update_deps

firmware_update_deps: $(HG_DEPS) $(GIT_DEPS)
	$(foreach d,$(shell seq $(words $(HG_DEPS))),\
		$(call update_hg_dep_decl,$(word $d,$(HG_DEPS)),$(word $d,$(HG_REVS))))
	$(foreach d,$(shell seq $(words $(GIT_DEPS))),\
		$(call update_git_dep_decl,$(word $d,$(GIT_DEPS)),$(word $d,$(GIT_REVS))))

firmware_clean_deps:
	@for dep in $(HG_DEPS) $(GIT_DEPS); do \
		echo "Removing $$dep"; \
		rm -rf $$dep; \
	done
