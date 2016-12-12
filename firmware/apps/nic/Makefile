# Declare the project name as 'basic_nic_<platform>', give its source directory
# and a default config file that will establish definitions for the project

ifndef PLATFORM
    $(error PLATFORM is not set)
endif

ifeq ($(PLATFORM),Hydrogen)
    NS_PLATFORM_TYPE = 1
    PROJECT = ns_nic_cx40q_1
    AMDA = AMDA0081-0001
else ifeq ($(PLATFORM),Hydrogen_4x10)
    NS_PLATFORM_TYPE = 2
    PROJECT = ns_nic_cx40q_1_4x10
    AMDA = AMDA0081-0001
else ifeq ($(PLATFORM),Lithium)
    NS_PLATFORM_TYPE = 3
    PROJECT = ns_nic_cx10_2
    AMDA = AMDA0096-0001
else ifeq ($(PLATFORM),Beryllium)
    NS_PLATFORM_TYPE = 7
    PROJECT = ns_nic_cx40_2
    AMDA = AMDA0097-0001
else ifeq ($(PLATFORM),Carbon)
    NS_PLATFORM_TYPE = 10
    PROJECT = ns_nic_cx25_2
    AMDA = AMDA0099-0001
else ifeq ($(PLATFORM),Carbon_2x10)
    NS_PLATFORM_TYPE = 11
    PROJECT = ns_nic_cx25_2_2x10
    AMDA = AMDA0099-0001
endif

$(eval $(call nffw.setup,$(PROJECT),apps/nic,config.h))
$(eval $(call nffw.set_amda,$(PROJECT),$(AMDA)))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/include))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/deps/npfw))
$(eval $(call nffw.add_ppc,$(PROJECT),i8,$(PICOCODE_DIR)/catamaran/catamaran.npfw))

# Add flowenv to the project
$(eval $(call fwdep.add_flowenv,$(PROJECT)))
# Add flowenv's NFP initialization routines
$(eval $(call fwdep.add_flowenv_nfp_init_flag,$(PROJECT),-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add 1 GRO ME
$(eval $(call fwdep.add_gro_flag,$(PROJECT),mei4.me8,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))


# Add 1 BLM ME
$(eval $(call fwdep.add_blm_flag,$(PROJECT),ila0.me0,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Custom config to give ME list to the app master
define NIC_ISL_ME_DEST
((($(1) + 32) << 4) + ($(2) + 4))
endef

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
$(eval $(call fwdep.add_nfd_svc,$(PROJECT),apps/nic,app_master_main.c,ila0.me2,ila0.me3))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,nic_basic))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,link_state))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,npfw))
$(eval $(call micro_c.add_src_lib.abspath,$(PROJECT),nfd_app_master,$(NFD_DIR)/me/blocks/vnic/svc,msix))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qnn_mode=1))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,APP_MES_LIST=$(NIC_APP_MES)))

# Add NFD for PCIE0
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_issue0,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_issue1,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_gather,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_notify,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call fwdep.add_nfd_in,$(PROJECT),0,mei4.me0)) # specify Notify ME
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_pcie0_cache,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_flags,$(PROJECT),nfd_pcie0_sb,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_flags,$(PROJECT),nfd_pcie0_pd,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call fwdep.add_nfd_out,$(PROJECT),0,mei4.me1,mei4.me2 mei4.me3)) # Stage batch, then packet DMA MEs

# Add a microcoengine named 'nic_rx' written in microC
# Make sure it gets linked with flownenv and GRO.
$(eval $(call micro_c.compile_liveinfo,$(PROJECT),nic_rx,apps/nic,nic_rx_main.c))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nic_rx,apps/nic,pkt_hdrs_cache))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nic_rx,apps/nic,rx_offload))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nic_rx,apps/nic,tx_offload))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_rx,pkt))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_rx,std))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_rx,net))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_rx,lu))
$(eval $(call fwdep.micro_c.add_gro_lib,$(PROJECT),nic_rx))
$(eval $(call fwdep.micro_c.add_blm_lib,$(PROJECT),nic_rx))
$(eval $(call fwdep.micro_c.add_nfd_lib,$(PROJECT),nic_rx))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nic_rx,infra_basic))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nic_rx,nic_basic))
$(eval $(call micro_c.add_define,$(PROJECT),nic_rx,FWNAME='"nic"'))
$(eval $(call micro_c.add_flags,$(PROJECT),nic_rx,-Qnn_mode=1))
$(eval $(call micro_c.add_flags,$(PROJECT),nic_rx,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call nffw.add_obj,$(PROJECT),nic_rx,\
	mei2.me0 mei2.me1 mei2.me2 mei2.me3 mei2.me4 mei2.me5  \
	mei2.me6 mei2.me7 mei2.me8 mei2.me9 mei2.me10 mei2.me11 \
	mei3.me0 mei3.me1 mei3.me2 mei3.me3 mei3.me4 mei3.me5  \
	mei3.me6 mei3.me7 mei3.me8 mei3.me9 mei3.me10 mei3.me11 \
	))

# Add a microcoengine named 'nic_tx' written in microC
# Make sure it gets linked with flownenv.
$(eval $(call micro_c.compile_liveinfo,$(PROJECT),nic_tx,apps/nic,nic_tx_main.c))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nic_tx,apps/nic,pkt_hdrs_cache))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nic_tx,apps/nic,tx_offload))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_tx,pkt))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_tx,std))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_tx,net))
$(eval $(call fwdep.micro_c.add_flowenv_lib,$(PROJECT),nic_tx,lu))
$(eval $(call fwdep.micro_c.add_gro_lib,$(PROJECT),nic_tx))
$(eval $(call fwdep.micro_c.add_blm_lib,$(PROJECT),nic_tx))
$(eval $(call fwdep.micro_c.add_nfd_lib,$(PROJECT),nic_tx))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nic_tx,infra_basic))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nic_tx,nic_basic))
$(eval $(call micro_c.add_define,$(PROJECT),nic_tx,FWNAME='"nic"'))
$(eval $(call micro_c.add_flags,$(PROJECT),nic_tx,-Qnn_mode=1))
$(eval $(call micro_c.add_flags,$(PROJECT),nic_tx,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call nffw.add_obj,$(PROJECT),nic_tx,\
	mei0.me0 mei0.me1 mei0.me2 mei0.me3 mei0.me4 mei0.me5  \
	mei0.me6 mei0.me7 mei0.me8 mei0.me9 mei0.me10 mei0.me11 \
	mei1.me0 mei1.me1 mei1.me2 mei1.me3 mei1.me4 mei1.me5  \
	mei1.me6 mei1.me7 mei1.me8 mei1.me9 mei1.me10 mei1.me11 \
	))

# Add TM PM initialization (codeless)
$(eval $(call microcode.assemble.codeless,$(PROJECT),tm_pm_init,lib/infra_basic,init_pms.uc,-DPMS_INIT_TM=1 -DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),tm_pm_init))

# Link
$(eval $(call nffw.add_rtsyms,$(PROJECT)))
# TODO get link_w_analysis to work without adding a warning
$(eval $(call nffw.link,$(PROJECT),nic_rx,nic_tx))
$(eval $(call nffw.cat,$(PROJECT),nic_rx,nic_tx))
