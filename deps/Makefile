#
# Change these revisions to suit the project
#
# FLOWENV_REV - Tip as of January 17 2017
FLOWENV_REV=59c0f4f94bb4
# GRO_REV  - Tip as of July 12 2016
GRO_REV=25c868a8c724
# NFD_REV - Tip of default branch as of 27 Oct 2016
NFD_REV=98afbcd74ef6

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
FLOWENV_DIR = $(DEPS_DIR)/flowenv.hg
FLOWENV_INC = -I$(FLOWENV_DIR)/me/lib

$(DEPS_DIR)/flowenv.hg:
	hg clone -r $(FLOWENV_REV) \
		ssh://$(HG_USERNAME)@hg//data/hg/repos/flowenv.hg $(FLOWENV_DIR)

HG_DEPS += $(FLOWENV_DIR)
HG_REVS += $(FLOWENV_REV)


#
# Flowenv
#
BLM_DIR = $(FLOWENV_DIR)/me/blocks/blm
BLM_INC = -I$(BLM_DIR)/me/lib


#
# GRO
#
GRO_DIR = $(DEPS_DIR)/gro.hg
GRO_INC = -I$(GRO_DIR)

$(DEPS_DIR)/gro.hg:
	hg clone -r $(GRO_REV) \
		ssh://$(HG_USERNAME)@hg//data/hg/repos/gro.hg $(GRO_DIR)

HG_DEPS += $(GRO_DIR)
HG_REVS += $(GRO_REV)


#
# NFD
#
NFD_DIR = $(DEPS_DIR)/ng-nfd.hg
NFD_INC = -I$(NFD_DIR)/shared \
	  -I$(NFD_DIR)/me/blocks/vnic

$(DEPS_DIR)/ng-nfd.hg:
	hg clone -r $(NFD_REV) \
	       	ssh://$(HG_USERNAME)@hg//data/hg/repos/ng-nfd.hg $(NFD_DIR)
	patch $(NFD_DIR)/dpdk/pmd/nfp_net.c $(NFD_DIR)/../nfp_net.c.patch
	patch $(NFD_DIR)/kernel/nfp_net_ctrl.h $(NFD_DIR)/../nfp_net_ctrl.h.patch
	patch $(NFD_DIR)/me/blocks/vnic/pci_in/issue_dma.c $(NFD_DIR)/../issue_dma.c.patch
	patch $(NFD_DIR)/me/blocks/vnic/nfd_in.uc $(NFD_DIR)/../nfd_in.uc.patch
	patch $(NFD_DIR)/me/blocks/vnic/svc/msix_qmon.c $(NFD_DIR)/../msix_qmon.c.patch
	patch $(NFD_DIR)me/blocks/vnic/nfd_common.h $(NFD_DIR)/../nfd_common.h.patch

HG_DEPS += $(NFD_DIR)
HG_REVS += $(NFD_REV)

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

