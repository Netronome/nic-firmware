# Copyright (c) 2019 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause
#
# Declare the project name as 'basic_nic_<platform>', give its source directory
# and a default config file that will establish definitions for the project

ifndef PLATFORM
    $(error PLATFORM is not set)
endif

ifeq ($(FLAVOR), nic)
    NS_FLAVOR_TYPE = 1
else ifeq ($(FLAVOR), sriov)
    NS_FLAVOR_TYPE = 2
endif

ifeq ($(PLATFORM),Hydrogen)
    NS_PLATFORM_TYPE = 1
    MEDIA = 1x40
    AMDA = AMDA0081-0001
    CHIP = AMDA0081-0001:0
else ifeq ($(PLATFORM),Hydrogen_4x10)
    NS_PLATFORM_TYPE = 2
    MEDIA = 4x10
    AMDA = AMDA0081-0001
    CHIP = AMDA0081-0001:0
else ifeq ($(PLATFORM),Lithium)
    NS_PLATFORM_TYPE = 3
    MEDIA = 2x10
    AMDA = AMDA0096-0001
    CHIP = AMDA0096-0001:0
else ifeq ($(PLATFORM),Beryllium)
    NS_PLATFORM_TYPE = 7
    MEDIA = 2x40
    AMDA = AMDA0097-0001
    CHIP = AMDA0097-0001:0
else ifeq ($(PLATFORM),Beryllium_4x10_1x40)
    NS_PLATFORM_TYPE = 8
    MEDIA = 4x10_1x40
    AMDA = AMDA0097-0001
    CHIP = AMDA0097-0001:0
else ifeq ($(PLATFORM),Beryllium_8x10)
    NS_PLATFORM_TYPE = 9
    MEDIA = 8x10
    AMDA = AMDA0097-0001
    CHIP = AMDA0097-0001:0
else ifeq ($(PLATFORM),Carbon)
    NS_PLATFORM_TYPE = 10
    MEDIA = 2x25
    AMDA = AMDA0099-0001
    CHIP = AMDA0099-0001:0
else ifeq ($(PLATFORM),Carbon_2x10)
    NS_PLATFORM_TYPE = 11
    MEDIA = 2x10
    AMDA = AMDA0099-0001
    CHIP = AMDA0099-0001:0
else ifeq ($(PLATFORM),Carbon_1x10_1x25)
    NS_PLATFORM_TYPE = 12
    MEDIA = 1x10_1x25
    AMDA = AMDA0099-0001
    CHIP = AMDA0099-0001:0
else ifeq ($(PLATFORM),Starfighter_2x40)
    NS_PLATFORM_TYPE = 13
    MEDIA = 2x40
    AMDA = AMDA0058-0011
    CHIP = AMDA0058-0011:0
else ifeq ($(PLATFORM),Starfighter_1x100)
    NS_PLATFORM_TYPE = 14
    MEDIA = 1x100
    AMDA = AMDA0078-0011
    CHIP = AMDA0078-0011:0
else ifeq ($(PLATFORM),Starfighter_2x40_passive)
    NS_PLATFORM_TYPE = 15
    MEDIA = 2x40
    AMDA = AMDA0058-0012
    CHIP = AMDA0058-0012:0
else ifeq ($(PLATFORM),Sodium_2x10)
    NS_PLATFORM_TYPE = 16
    MEDIA = 2x10
    AMDA = AMDA0119-0001
    CHIP = AMDA0119-0001:0
else ifeq ($(PLATFORM),Sodium_2x10_crypto)
    NS_PLATFORM_TYPE = 17
    MEDIA = 2x10
    AMDA = AMDA0119-0002
    CHIP = AMDA0119-0002:0
else ifeq ($(PLATFORM),Starfighter_1x100_passive)
    NS_PLATFORM_TYPE = 18
    MEDIA = 1x100
    AMDA = AMDA0078-0012
    CHIP = AMDA0078-0012:0
endif
PROJECT = $(FLAVOR)/nic_$(AMDA)_$(MEDIA)

$(eval $(call nffw.setup,$(PROJECT),apps/nic,config.h))
$(eval $(call nffw.set_amda,$(PROJECT),$(AMDA)))
$(eval $(call nffw.set_chip,$(PROJECT),$(CHIP)))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/include))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/deps/nfp-bsp-boardconfig))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/deps/npfw))
$(eval $(call nffw.add_ppc,$(PROJECT),i8,$(PICOCODE_DIR)/catamaran/catamaran.npfw))

# Add flowenv to the project
$(eval $(call fwdep.add_flowenv,$(PROJECT)))
# Add flowenv's NFP initialization routines
$(eval $(call fwdep.add_flowenv_nfp_init_flag,$(PROJECT),-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add GRO MEs
$(eval $(call fwdep.add_gro_flag,$(PROJECT),mei0.me11 mei1.me11 mei3.me11 mei4.me11,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE) -DNS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))

# Add 1 BLM ME
$(eval $(call fwdep.add_blm_flag,$(PROJECT),ila0.me0,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add Multicast Buffer Reaper
$(eval $(call microcode.assemble,$(PROJECT),mcr,apps/nic,mc_reaper.uc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_include,$(PROJECT),mcr,firmware/lib))
$(eval $(call microcode.add_include,$(PROJECT),mcr,firmware/apps/nic/lib))
$(eval $(call microcode.add_include,$(PROJECT),mcr,deps/ng-nfd.hg))
$(eval $(call microcode.add_include,$(PROJECT),mcr,$(BLM_DIR)))
$(eval $(call microcode.add_define,$(PROJECT),mcr,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call nffw.add_obj,$(PROJECT),mcr,mei0.me10))

# Add microcode datapath
$(eval $(call dep.gen_awk,$(PROJECT),datapath,firmware/lib/nic_basic/nic_stats_gen.h,firmware/lib/nic_basic/nic_stats.def,scripts/nic_stats.awk))
$(eval $(call microcode.assemble,$(PROJECT),datapath,apps/nic,datapath.uc))
$(eval $(call microcode.add_tests,$(PROJECT),datapath))
$(eval $(call microcode.add_flags,$(PROJECT),datapath,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_flags,$(PROJECT),datapath,-O))
#$(eval $(call microcode.add_flags,$(PROJECT),datapath,-d40))
#$(eval $(call microcode.add_flags,$(PROJECT),datapath,-verbose))
$(eval $(call microcode.add_flags,$(PROJECT),datapath,-keep_unreachable_code))
$(eval $(call microcode.add_include,$(PROJECT),datapath,firmware/lib))
$(eval $(call microcode.add_include,$(PROJECT),datapath,firmware/apps/nic/lib))
$(eval $(call microcode.add_include,$(PROJECT),datapath,firmware/apps/nic/maps))
$(eval $(call microcode.add_include,$(PROJECT),datapath,deps/ng-nfd.hg))
$(eval $(call microcode.add_include,$(PROJECT),datapath,$(BLM_DIR)))
$(eval $(call microcode.add_include,$(PROJECT),datapath,$(GRO_DIR)))
$(eval $(call microcode.add_define,$(PROJECT),datapath,SS=0))
$(eval $(call microcode.add_define,$(PROJECT),datapath,SCS=0))
$(eval $(call microcode.add_define,$(PROJECT),datapath,NBI_COUNT=1))
$(eval $(call microcode.add_define,$(PROJECT),datapath,WORKERS_PER_ISLAND=10))
$(eval $(call microcode.add_define,$(PROJECT),datapath,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
#$(eval $(call microcode.add_define,$(PROJECT),datapath,PARANOIA))
$(eval $(call nffw.add_obj,$(PROJECT),datapath, \
        mei0.me0 mei0.me1 mei0.me2 mei0.me3 mei0.me4 mei0.me5 mei0.me6 mei0.me7 mei0.me8 mei0.me9 \
        mei1.me0 mei1.me1 mei1.me2 mei1.me3 mei1.me4 mei1.me5 mei1.me6 mei1.me7 mei1.me8 mei1.me9 \
        mei2.me0 mei2.me1 mei2.me2 mei2.me3 mei2.me4 mei2.me5 mei2.me6 mei2.me7 mei2.me8 mei2.me9 \
	mei3.me0 mei3.me1 mei3.me2 mei3.me3 mei3.me4 mei3.me5 mei3.me6 mei3.me7 mei3.me8 mei3.me9 \
	mei4.me0 mei4.me1 mei4.me2 mei4.me3 mei4.me4 mei4.me5 mei4.me6 mei4.me7 mei4.me8 mei4.me9 \
	))

# Custom config to give ME list to the app master
define NIC_ISL_ME_DEST
((($(1) + 32) << 4) + ($(2) + 4))
endef

NIC_APP_ISLANDS := \
	"$(call NIC_ISL_ME_DEST, 0, 0), \
	$(call NIC_ISL_ME_DEST, 1, 0), \
	$(call NIC_ISL_ME_DEST, 2, 0), \
	$(call NIC_ISL_ME_DEST, 3, 0), \
	$(call NIC_ISL_ME_DEST, 4, 0)"

NIC_APP_MES := \
        "$(call NIC_ISL_ME_DEST, 0, 0), \
        $(call NIC_ISL_ME_DEST, 0, 1), \
        $(call NIC_ISL_ME_DEST, 0, 2), \
        $(call NIC_ISL_ME_DEST, 0, 3), \
        $(call NIC_ISL_ME_DEST, 0, 4), \
        $(call NIC_ISL_ME_DEST, 0, 5), \
        $(call NIC_ISL_ME_DEST, 0, 6), \
        $(call NIC_ISL_ME_DEST, 0, 7), \
        $(call NIC_ISL_ME_DEST, 0, 8), \
        $(call NIC_ISL_ME_DEST, 0, 9), \
        \
        $(call NIC_ISL_ME_DEST, 1, 0), \
        $(call NIC_ISL_ME_DEST, 1, 1), \
        $(call NIC_ISL_ME_DEST, 1, 2), \
        $(call NIC_ISL_ME_DEST, 1, 3), \
        $(call NIC_ISL_ME_DEST, 1, 4), \
        $(call NIC_ISL_ME_DEST, 1, 5), \
        $(call NIC_ISL_ME_DEST, 1, 6), \
        $(call NIC_ISL_ME_DEST, 1, 7), \
        $(call NIC_ISL_ME_DEST, 1, 8), \
        $(call NIC_ISL_ME_DEST, 1, 9), \
        \
        $(call NIC_ISL_ME_DEST, 2, 0), \
        $(call NIC_ISL_ME_DEST, 2, 1), \
        $(call NIC_ISL_ME_DEST, 2, 2), \
        $(call NIC_ISL_ME_DEST, 2, 3), \
        $(call NIC_ISL_ME_DEST, 2, 4), \
        $(call NIC_ISL_ME_DEST, 2, 5), \
        $(call NIC_ISL_ME_DEST, 2, 6), \
        $(call NIC_ISL_ME_DEST, 2, 7), \
        $(call NIC_ISL_ME_DEST, 2, 8), \
        $(call NIC_ISL_ME_DEST, 2, 9), \
        \
        $(call NIC_ISL_ME_DEST, 3, 0), \
        $(call NIC_ISL_ME_DEST, 3, 1), \
        $(call NIC_ISL_ME_DEST, 3, 2), \
        $(call NIC_ISL_ME_DEST, 3, 3), \
        $(call NIC_ISL_ME_DEST, 3, 4), \
        $(call NIC_ISL_ME_DEST, 3, 5), \
        $(call NIC_ISL_ME_DEST, 3, 6), \
        $(call NIC_ISL_ME_DEST, 3, 7), \
        $(call NIC_ISL_ME_DEST, 3, 8), \
        $(call NIC_ISL_ME_DEST, 3, 9), \
		\
        $(call NIC_ISL_ME_DEST, 4, 0), \
        $(call NIC_ISL_ME_DEST, 4, 1), \
        $(call NIC_ISL_ME_DEST, 4, 2), \
        $(call NIC_ISL_ME_DEST, 4, 3), \
        $(call NIC_ISL_ME_DEST, 4, 4), \
        $(call NIC_ISL_ME_DEST, 4, 5), \
        $(call NIC_ISL_ME_DEST, 4, 6), \
        $(call NIC_ISL_ME_DEST, 4, 7), \
        $(call NIC_ISL_ME_DEST, 4, 8), \
        $(call NIC_ISL_ME_DEST, 4, 9)"

# Add cmsg map handler
$(eval $(call microcode.assemble,$(PROJECT),mapcmsg,apps/nic/maps,cmsg_app.uc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,firmware/lib))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,firmware/apps/nic/lib))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,firmware/apps/nic/maps))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,deps/ng-nfd.hg))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,$(DEPS_DIR)/flowenv.git/me/blocks/blm))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,$(BLM_DIR)))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,$(GRO_DIR)))
$(eval $(call microcode.add_define,$(PROJECT),mapcmsg,WORKERS_PER_ISLAND=4))
$(eval $(call microcode.add_define,$(PROJECT),mapcmsg,GLOBAL_INIT=1))
$(eval $(call microcode.add_define,$(PROJECT),mapcmsg,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call nffw.add_obj,$(PROJECT),mapcmsg,mei2.me11))

# Add Global NFD config
$(eval $(call fwdep.add_nfd,$(PROJECT)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_svc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_svc,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,app_config_tables))
$(eval $(call fwdep.add_nfd_svc,$(PROJECT),apps/nic,app_master_main.c,mei2.me10,mei4.me10))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,nic_basic))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,link_state))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,npfw))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,nic_tables))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,app_mac_vlan_config_cmsg))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,trng))
$(eval $(call micro_c.add_src_lib.abspath,$(PROJECT),nfd_app_master,$(DEPS_DIR)/flowenv.git/me/blocks/blm,libblm))
$(eval $(call micro_c.add_src_lib.abspath,$(PROJECT),nfd_app_master,$(DEPS_DIR)/flowenv.git/me/lib/pkt,libpkt))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qnn_mode=1))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qip_no_inlining))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qnolur=_cfg_changes_loop))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Ob0))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,APP_MES_LIST=$(NIC_APP_MES)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,APP_WORKER_ISLAND_LIST=$(NIC_APP_ISLANDS)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,CFG_NIC_LIB_DBG_JOURNAL=1))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call micro_c.add_tests,$(PROJECT),nfd_app_master))

# Add NFD for PCIE0
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_issue0,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_pcie0_issue0,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_issue1,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_pcie0_issue1,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_gather,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_pcie0_gather,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_notify,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_pcie0_notify,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call fwdep.add_nfd_in,$(PROJECT),0,mei3.me10)) # specify Notify ME
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_cache,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_pcie0_cache,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call microcode.add_flags,$(PROJECT),nfd_pcie0_sb,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_define,$(PROJECT),nfd_pcie0_sb,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call microcode.add_flags,$(PROJECT),nfd_pcie0_pd,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_define,$(PROJECT),nfd_pcie0_pd,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call fwdep.add_nfd_out,$(PROJECT),0,ila0.me1,ila0.me2 ila0.me3)) # Stage batch, then packet DMA MEs

# Add TM PM initialization (codeless)
$(eval $(call microcode.assemble.codeless,$(PROJECT),tm_pm_init,apps/nic,init_pms.uc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),tm_pm_init))

# Add dump_spec (codeless)
$(eval $(call dep.dump_spec,$(PROJECT),datapath,dump_spec.in))
$(eval $(call microcode.assemble.codeless,$(PROJECT),dump_spec,apps/nic,dump_spec_init.uc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),dump_spec))

# Add NFD config BAR TLVs
$(eval $(call microcode.assemble.codeless,$(PROJECT),nfd_tlv_init,apps/nic,init_tlv.uc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_define,$(PROJECT),nfd_tlv_init,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),nfd_tlv_init))

# Link stage
# Write the build info and then the firmware ID to the MIP (one overrides the other in the MIP)
$(eval $(call nffw.add_link_flag,$(PROJECT),$(shell $(SCRIPT_DIR)/describe-head.sh --nfld_args $(FLAVOR))))
$(eval $(call nffw.add_rtsyms,$(PROJECT),$(shell $(SCRIPT_DIR)/describe-head.sh --fw_id $(FLAVOR))))
# TODO get link_w_analysis to work without adding a warning
$(eval $(call nffw.add_link_flag,$(PROJECT),-codeshare mei2.me10 mei2.me11))
$(eval $(call nffw.add_link_flag,$(PROJECT),-noecc)) # required for codeshare on B0
$(eval $(call nffw.link,$(PROJECT),nic_rx,nic_tx,datapath))
