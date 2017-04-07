# Declare the project name as 'basic_nic_<platform>', give its source directory
# and a default config file that will establish definitions for the project

ifndef PLATFORM
    $(error PLATFORM is not set)
endif

ifeq ($(PLATFORM),Hydrogen)
    NS_PLATFORM_TYPE = 1
    MEDIA = 1x40
    AMDA = AMDA0081-0001
else ifeq ($(PLATFORM),Hydrogen_4x10)
    NS_PLATFORM_TYPE = 2
    MEDIA = 4x10
    AMDA = AMDA0081-0001
else ifeq ($(PLATFORM),Lithium)
    NS_PLATFORM_TYPE = 3
    MEDIA = 2x10
    AMDA = AMDA0096-0001
else ifeq ($(PLATFORM),Beryllium)
    NS_PLATFORM_TYPE = 7
    MEDIA = 2x40
    AMDA = AMDA0097-0001
else ifeq ($(PLATFORM),Beryllium_4x10_1x40)
    NS_PLATFORM_TYPE = 8
    MEDIA = 4x10_1x40
    AMDA = AMDA0097-0001
else ifeq ($(PLATFORM),Beryllium_8x10)
    NS_PLATFORM_TYPE = 9
    MEDIA = 8x10
    AMDA = AMDA0097-0001
else ifeq ($(PLATFORM),Carbon)
    NS_PLATFORM_TYPE = 10
    MEDIA = 2x25
    AMDA = AMDA0099-0001
else ifeq ($(PLATFORM),Carbon_2x10)
    NS_PLATFORM_TYPE = 11
    MEDIA = 2x10
    AMDA = AMDA0099-0001
endif
PROJECT = nic_$(AMDA)_$(MEDIA)

$(eval $(call nffw.setup,$(PROJECT),apps/nic,config.h))
$(eval $(call nffw.set_amda,$(PROJECT),$(AMDA)))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/include))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/deps/nfp-bsp-boardconfig))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/deps/npfw))
$(eval $(call nffw.add_ppc,$(PROJECT),i8,$(PICOCODE_DIR)/catamaran/catamaran.npfw))

# Add flowenv to the project
$(eval $(call fwdep.add_flowenv,$(PROJECT)))
# Add flowenv's NFP initialization routines
$(eval $(call fwdep.add_flowenv_nfp_init_flag,$(PROJECT),-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add GRO MEs
$(eval $(call fwdep.add_gro_flag,$(PROJECT),mei0.me11 mei1.me11 mei2.me11 mei3.me11,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add 1 BLM ME
$(eval $(call fwdep.add_blm_flag,$(PROJECT),ila0.me0,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Custom config to give ME list to the app master
define NIC_ISL_ME_DEST
((($(1) + 32) << 4) + ($(2) + 4))
endef
NIC_APP_ISLANDS := \
	"$(call NIC_ISL_ME_DEST, 0, 0), \
	$(call NIC_ISL_ME_DEST, 1, 0), \
	$(call NIC_ISL_ME_DEST, 2, 0), \
	$(call NIC_ISL_ME_DEST, 3, 0)"
	
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
        $(call NIC_ISL_ME_DEST, 0, 10), \
        $(call NIC_ISL_ME_DEST, 0, 11), \
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
        $(call NIC_ISL_ME_DEST, 1, 10), \
        $(call NIC_ISL_ME_DEST, 1, 11), \
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
        $(call NIC_ISL_ME_DEST, 2, 10), \
        $(call NIC_ISL_ME_DEST, 2, 11), \
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
        $(call NIC_ISL_ME_DEST, 3, 10), \
        $(call NIC_ISL_ME_DEST, 3, 11)"

# Add Global NFD config
$(eval $(call fwdep.add_nfd,$(PROJECT)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_svc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,app_config_tables))
$(eval $(call fwdep.add_nfd_svc,$(PROJECT),apps/nic,app_master_main.c,ila0.me2,ila0.me3))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,nic_basic))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,link_state))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,npfw))
$(eval $(call micro_c.add_src_lib.abspath,$(PROJECT),nfd_app_master,$(NFD_DIR)/me/blocks/vnic/svc,msix))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qnn_mode=1))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,APP_MES_LIST=$(NIC_APP_MES)))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,APP_WORKER_ISLAND_LIST=$(NIC_APP_ISLANDS)))

# Add NFD for PCIE0
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_issue0,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_issue1,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_gather,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_notify,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call fwdep.add_nfd_in,$(PROJECT),0,ila0.me1)) # specify Notify ME
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_cache,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_flags,$(PROJECT),nfd_pcie0_sb,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_flags,$(PROJECT),nfd_pcie0_pd,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call fwdep.add_nfd_out,$(PROJECT),0,mei4.me0,mei4.me1 mei4.me2)) # Stage batch, then packet DMA MEs

# Add microcode datapath
$(eval $(call microcode.assemble,$(PROJECT),datapath,apps/nic,datapath.uc))
$(eval $(call microcode.add_flags,$(PROJECT),datapath,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_flags, $(PROJECT),datapath,-O))
$(eval $(call microcode.add_include,$(PROJECT),datapath,$(BLM_DIR)))
$(eval $(call microcode.add_include,$(PROJECT),datapath,$(GRO_DIR)))
$(eval $(call microcode.add_define,$(PROJECT),datapath,SS=0))
$(eval $(call microcode.add_define,$(PROJECT),datapath,SCS=0))
$(eval $(call microcode.add_define,$(PROJECT),datapath,NBI_COUNT=1))
$(eval $(call microcode.add_define,$(PROJECT),datapath,WORKERS_PER_ISLAND=4))
$(eval $(call nffw.add_obj,$(PROJECT),datapath, \
        mei0.me0 mei0.me1 mei0.me2 mei0.me3 \
        mei1.me0 mei1.me1 mei1.me2 mei1.me3 \
        mei2.me0 mei2.me1 mei2.me2 mei2.me3 \
	mei3.me0 mei3.me1 mei3.me2 mei3.me3 \
	))

# Add TM PM initialization (codeless)
$(eval $(call microcode.assemble.codeless,$(PROJECT),tm_pm_init,lib/infra_basic,init_pms.uc,-DPMS_INIT_TM=1 -DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),tm_pm_init))

# Link
$(eval $(call nffw.add_rtsyms,$(PROJECT)))
# TODO get link_w_analysis to work without adding a warning
$(eval $(call nffw.link,$(PROJECT),nic_rx,nic_tx,datapath))
$(eval $(call nffw.cat,$(PROJECT),nic_rx,nic_tx,datapath))
