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

DEDUP=
ifeq ($(PLATFORM),Hydrogen)
    NS_PLATFORM_TYPE = 1
    MEDIA = 1x40
    AMDA = AMDA0081-0001
    CHIP = AMDA0081-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Hydrogen_4x10)
    NS_PLATFORM_TYPE = 2
    MEDIA = 4x10
    AMDA = AMDA0081-0001
    CHIP = AMDA0081-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Lithium)
    NS_PLATFORM_TYPE = 3
    MEDIA = 2x10
    AMDA = AMDA0096-0001
    CHIP = AMDA0096-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Beryllium)
    NS_PLATFORM_TYPE = 7
    MEDIA = 2x40
    AMDA = AMDA0097-0001
    CHIP = AMDA0097-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Beryllium_4x10_1x40)
    NS_PLATFORM_TYPE = 8
    MEDIA = 4x10_1x40
    AMDA = AMDA0097-0001
    CHIP = AMDA0097-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Beryllium_8x10)
    NS_PLATFORM_TYPE = 9
    MEDIA = 8x10
    AMDA = AMDA0097-0001
    CHIP = AMDA0097-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Carbon)
    NS_PLATFORM_TYPE = 10
    MEDIA = 2x25
    AMDA = AMDA0099-0001
    CHIP = AMDA0099-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Carbon_2x10)
    NS_PLATFORM_TYPE = 11
    MEDIA = 2x10
    AMDA = AMDA0099-0001
    CHIP = AMDA0099-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Carbon_1x10_1x25)
    NS_PLATFORM_TYPE = 12
    MEDIA = 1x10_1x25
    AMDA = AMDA0099-0001
    CHIP = AMDA0099-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Starfighter_2x40)
    NS_PLATFORM_TYPE = 13
    MEDIA = 2x40
    AMDA = AMDA0058-0011
    CHIP = AMDA0058-0011:0
    FLOORPLAN=Agilio_LX
else ifeq ($(PLATFORM),Starfighter_1x100)
    NS_PLATFORM_TYPE = 14
    MEDIA = 1x100
    AMDA = AMDA0078-0011
    CHIP = AMDA0078-0011:0
    FLOORPLAN=Agilio_LX
else ifeq ($(PLATFORM),Starfighter_2x40_passive)
    NS_PLATFORM_TYPE = 15
    MEDIA = 2x40
    AMDA = AMDA0058-0012
    CHIP = AMDA0058-0012:0
    FLOORPLAN=Agilio_LX
else ifeq ($(PLATFORM),Sodium_2x10)
    NS_PLATFORM_TYPE = 16
    MEDIA = 2x10
    AMDA = AMDA0119-0001
    CHIP = AMDA0119-0001:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Sodium_2x10_crypto)
    NS_PLATFORM_TYPE = 17
    MEDIA = 2x10
    AMDA = AMDA0119-0002
    CHIP = AMDA0119-0002:0
    FLOORPLAN=Agilio_CX
else ifeq ($(PLATFORM),Starfighter_1x100_passive)
    NS_PLATFORM_TYPE = 18
    MEDIA = 1x100
    AMDA = AMDA0078-0012
    CHIP = AMDA0078-0012:0
    FLOORPLAN=Agilio_LX
else ifeq ($(PLATFORM),Cadmium_DDR_1x50)
    CHIP = AMDA0133-0001:0
    NS_PLATFORM_TYPE = 19
    MEDIA = 1x50
    AMDA = AMDA0133-0001
    CHIP = AMDA0133-0001:0
    FLOORPLAN=OCP_Multihost
    DEDUP=-dedup
endif
PROJECT = $(FLAVOR)/nic_$(AMDA)_$(MEDIA)

#Location of ME's. These can differ between platform families.
ifeq ($(FLOORPLAN),Agilio_LX)
    #Note: This is still the same as the CX  NIC, but could be improved.
    #E.g: Some LX NICS can use 2 PCIe islands, and all SF's have more mei's

    #GRO ME's
    GRO_MES=mei0.me11 mei1.me11 mei3.me11 mei4.me11

    #cmsg map handler
    MAPCMSG_ME=mei2.me11

    #App_master ME
    APP_MASTER_ME=mei2.me10

    #NFD SVC ME
    NFD_SVC_ME=mei4.me10

    #NFD for PCIE0
    NFD0_NOTIFY_ME=mei3.me10
    NFD0_SB_ME=ila0.me1
    NFD0_PD_MES=ila0.me2 ila0.me3

    #NFD for PCIE1
    NFD1_NOTIFY_ME=
    NFD1_SB_ME=
    NFD1_PD_MES=

    #NFD for PCIE2
    NFD2_NOTIFY_ME=
    NFD2_SB_ME=
    NFD2_PD_MES=

    #NFD for PCIE3
    NFD3_NOTIFY_ME=
    NFD3_SB_ME=
    NFD3_PD_MES=

    #Multicast reaper ME
    MCR_ME=mei0.me10

    #Worker placements
    WORKERS_PER_ISLAND=10
    DATAPATH_ISL=0 1 2 3 4


else ifeq ($(FLOORPLAN),OCP_Multihost)

    #GRO ME's
    GRO_MES=ila0.me2 mei2.me11 mei3.me11 mei4.me11

    #App master ME (codeshare with MAPCMSG_ME)
    APP_MASTER_ME=mei5.me6

    #cmsg map handler
    MAPCMSG_ME=mei5.me7

    #NFD SVC ME
    NFD_SVC_ME=mei3.me9

    #NFD for PCIE 0
    NFD0_NOTIFY_ME=ila0.me3
    NFD0_SB_ME=mei0.me9
    NFD0_PD_MES=mei0.me10 mei0.me11

    #NFD for PCIE 1
    NFD1_NOTIFY_ME=mei1.me7
    NFD1_SB_ME=mei1.me9
    NFD1_PD_MES=mei1.me10 mei1.me11

    #NFD for PCIE 2
    NFD2_NOTIFY_ME=mei2.me7
    NFD2_SB_ME=mei6.me9
    NFD2_PD_MES=mei6.me10 mei6.me11

    #NFD for PCIE 3
    NFD3_NOTIFY_ME=mei3.me8
    NFD3_SB_ME=mei5.me9
    NFD3_PD_MES=mei5.me10 mei5.me11

    #Multicast reaper ME
    MCR_ME=mei0.me6

    #Worker placements
    WORKERS_PER_ISLAND=6
    DATAPATH_ISLANDS=0 1 2 3 4 5 6

else
    #All other NICS

    #GRO ME's
    GRO_MES=mei0.me11 mei1.me11 mei3.me11 mei4.me11

    #cmsg map handler
    MAPCMSG_ME=mei2.me11

    #App_master ME
    APP_MASTER_ME=mei2.me10

    #NFD SVC ME
    NFD_SVC_ME=mei4.me10

    #NFD for PCIE0
    NFD0_NOTIFY_ME=mei3.me10
    NFD0_SB_ME=ila0.me1
    NFD0_PD_MES=ila0.me2 ila0.me3

    #NFD for PCIE1
    NFD1_NOTIFY_ME=
    NFD1_SB_ME=
    NFD1_PD_MES=

    #NFD for PCIE2
    NFD2_NOTIFY_ME=
    NFD2_SB_ME=
    NFD2_PD_MES=

    #NFD for PCIE3
    NFD3_NOTIFY_ME=
    NFD3_SB_ME=
    NFD3_PD_MES=

    #Multicast reaper ME
    MCR_ME=mei0.me10

    #Worker placements
    WORKERS_PER_ISLAND=10
    DATAPATH_ISLANDS=0 1 2 3 4
endif


#f NIC_ISL_ME_DEST
#
# Custom config to give ME list to the app master
#
# @param $1 MEI no, in 0-8
# @param $2 ME no, in 0-11
#
define NIC_ISL_ME_DEST

$(shell echo $$((($(1) + 32) * 16 + $(2) + 4)))

endef


#f NIC_BUILD_DP_LIST
#
# @param $1 MEI no, in 0-8
# @param $2 num MEs, in 1-12
#
define NIC_BUILD_DP_LIST

$(eval NIC_APP_ISLANDS += $(strip $(call NIC_ISL_ME_DEST,$1,0)))
$(foreach me, $(shell seq 0 $$(($2 - 1))), \
    $(eval NIC_APP_MES += $(strip $(call NIC_ISL_ME_DEST, $1, $(me)))) \
    $(eval NIC_DP_MES += mei$(1).me$(me)))

endef


# Build datapath ME placement defines
NIC_APP_ISLANDS=
NIC_APP_MES=
NIC_DP_MES=

ifeq ($(words $(WORKERS_PER_ISLAND)), $(words $(DATAPATH_ISLANDS)))
$(foreach isl, $(shell seq 1 $(words $(WORKERS_PER_ISLAND))), \
    $(eval $(call NIC_BUILD_DP_LIST,$(word $(isl),$(DATAPATH_ISLANDS)),$(word $(isl),$(WORKERS_PER_ISLAND)))))
else
ifneq ($(words $(WORKERS_PER_ISLAND)), 1)
$(error Num entries in "WORKERS_PER_ISLAND" must match "DATAPATH_ISLANDS" or be 1)
endif
$(foreach isl, $(DATAPATH_ISLANDS), \
    $(eval $(call NIC_BUILD_DP_LIST,$(isl),$(WORKERS_PER_ISLAND))))
endif

comma := ,
space := $() $()
NIC_APP_ISLANDS := $(subst $(space),$(comma),$(strip $(NIC_APP_ISLANDS)))
NIC_APP_MES := $(subst $(space),$(comma),$(strip $(NIC_APP_MES)))


$(eval $(call nffw.setup,$(PROJECT),apps/nic,config.h))
$(eval $(call nffw.set_amda,$(PROJECT),$(AMDA)))
$(eval $(call nffw.set_chip,$(PROJECT),$(CHIP)))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/include))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/deps/nfp-bsp-boardconfig))
$(eval $(call nffw.add_include,$(PROJECT),$(NFP_COMMON)/deps/npfw))
$(eval $(call nffw.add_ppc,$(PROJECT),i8,$(PICOCODE_DIR)/catamaran/catamaran.npfw))
$(eval $(call nffw.add_define,$(PROJECT),NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call nffw.add_define,$(PROJECT),NS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add flowenv to the project
$(eval $(call fwdep.add_flowenv,$(PROJECT)))
# Add flowenv's NFP initialization routines
$(eval $(call fwdep.add_flowenv_nfp_init_flag,$(PROJECT),-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add GRO MEs
$(eval $(call fwdep.add_gro_flag,$(PROJECT),$(GRO_MES),-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE) -DNS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))

# Add 1 BLM ME
$(eval $(call fwdep.add_blm_flag,$(PROJECT),ila0.me0,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))

# Add Multicast Buffer Reaper
$(eval $(call microcode.assemble,$(PROJECT),mcr,apps/nic,mc_reaper.uc))
$(eval $(call microcode.add_include,$(PROJECT),mcr,firmware/lib))
$(eval $(call microcode.add_include,$(PROJECT),mcr,firmware/apps/nic/lib))
$(eval $(call microcode.add_include,$(PROJECT),mcr,deps/ng-nfd.hg))
$(eval $(call microcode.add_include,$(PROJECT),mcr,$(BLM_DIR)))
$(eval $(call microcode.add_define,$(PROJECT),mcr,NS_FLAVOR_TYPE=$(NS_FLAVOR_TYPE)))
$(eval $(call nffw.add_obj,$(PROJECT),mcr,$(MCR_ME)))

# Add microcode datapath
$(eval $(call dep.gen_awk,$(PROJECT),datapath,firmware/lib/nic_basic/nic_stats_gen.h,firmware/lib/nic_basic/nic_stats.def,scripts/nic_stats.awk))
$(eval $(call microcode.assemble,$(PROJECT),datapath,apps/nic,datapath.uc))
$(eval $(call microcode.add_tests,$(PROJECT),datapath))
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
$(eval $(call microcode.add_define,$(PROJECT),datapath,WORKERS_PER_ISLAND=$(WORKERS_PER_ISLAND)))
#$(eval $(call microcode.add_define,$(PROJECT),datapath,PARANOIA))
$(eval $(call nffw.add_obj,$(PROJECT),datapath, $(NIC_DP_MES)))

# Add cmsg map handler
$(eval $(call microcode.assemble,$(PROJECT),mapcmsg,apps/nic/maps,cmsg_app.uc,-DNS_PLATFORM_TYPE=$(NS_PLATFORM_TYPE)))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,firmware/lib))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,firmware/apps/nic/lib))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,firmware/apps/nic/maps))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,deps/ng-nfd.hg))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,$(DEPS_DIR)/flowenv.git/me/blocks/blm))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,$(BLM_DIR)))
$(eval $(call microcode.add_include,$(PROJECT),mapcmsg,$(GRO_DIR)))
$(eval $(call microcode.add_define,$(PROJECT),mapcmsg,WORKERS_PER_ISLAND=$(WORKERS_PER_ISLAND)))
$(eval $(call microcode.add_define,$(PROJECT),mapcmsg,GLOBAL_INIT=1))
$(eval $(call nffw.add_obj,$(PROJECT),mapcmsg,$(MAPCMSG_ME)))

# Add Global NFD config
$(eval $(call fwdep.add_nfd,$(PROJECT)))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,app_config_tables))
$(eval $(call fwdep.add_nfd_svc,$(PROJECT),apps/nic,app_master_main.c,$(APP_MASTER_ME),$(NFD_SVC_ME)))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,nic_basic))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,link_state))
$(eval $(call micro_c.add_fw_lib,$(PROJECT),nfd_app_master,npfw))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,nic_tables))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,app_mac_vlan_config_cmsg))
$(eval $(call micro_c.add_src_lib,$(PROJECT),nfd_app_master,apps/nic,trng))
$(eval $(call micro_c.add_src_lib.abspath,$(PROJECT),nfd_app_master,$(DEPS_DIR)/flowenv.git/me/blocks/blm,libblm))
$(eval $(call micro_c.add_src_lib.abspath,$(PROJECT),nfd_app_master,$(DEPS_DIR)/flowenv.git/me/lib/pkt,libpkt))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qnn_mode=1))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qip_no_inlining))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Qnolur=_cfg_changes_loop))
$(eval $(call micro_c.add_flags,$(PROJECT),nfd_app_master,-Ob0))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,APP_MES_LIST="$(NIC_APP_MES)"))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,APP_WORKER_ISLAND_LIST="$(NIC_APP_ISLANDS)"))
$(eval $(call micro_c.add_define,$(PROJECT),nfd_app_master,CFG_NIC_LIB_DBG_JOURNAL=1))
$(eval $(call micro_c.add_tests,$(PROJECT),nfd_app_master))

# Add NFD for PCIE0
$(eval $(call fwdep.add_nfd_in,$(PROJECT),0,$(NFD0_NOTIFY_ME))) # specify Notify ME
$(eval $(call fwdep.add_nfd_out,$(PROJECT),0,$(NFD0_SB_ME),$(NFD0_PD_MES))) # Stage batch, then packet DMA MEs

ifneq ($(NFD1_NOTIFY_ME),)
# Add NFD for PCIE1
    $(eval $(call fwdep.add_nfd_in,$(PROJECT),1,$(NFD1_NOTIFY_ME))) # specify Notify ME
    $(eval $(call fwdep.add_nfd_out,$(PROJECT),1,$(NFD1_SB_ME),$(NFD1_PD_MES))) # Stage batch, then packet DMA MEs
endif

ifneq ($(NFD2_NOTIFY_ME),)
# Add NFD for PCIE2
    $(eval $(call fwdep.add_nfd_in,$(PROJECT),2,$(NFD2_NOTIFY_ME))) # specify Notify ME
    $(eval $(call fwdep.add_nfd_out,$(PROJECT),2,$(NFD2_SB_ME),$(NFD2_PD_MES))) # Stage batch, then packet DMA MEs
endif

ifneq ($(NFD3_NOTIFY_ME),)
# Add NFD for PCIE3
    $(eval $(call fwdep.add_nfd_in,$(PROJECT),3,$(NFD3_NOTIFY_ME))) # specify Notify ME
    $(eval $(call fwdep.add_nfd_out,$(PROJECT),3,$(NFD3_SB_ME),$(NFD3_PD_MES))) # Stage batch, then packet DMA MEs
endif

# Add TM PM initialization (codeless)
$(eval $(call microcode.assemble.codeless,$(PROJECT),tm_pm_init,apps/nic,init_pms.uc))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),tm_pm_init))

# Add dump_spec (codeless)
$(eval $(call dep.dump_spec,$(PROJECT),datapath,dump_spec.in))
$(eval $(call microcode.assemble.codeless,$(PROJECT),dump_spec,apps/nic,dump_spec_init.uc))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),dump_spec))

# Add NFD config BAR TLVs
$(eval $(call microcode.assemble.codeless,$(PROJECT),nfd_tlv_init,apps/nic,init_tlv.uc))
$(eval $(call nffw.add_obj_codeless,$(PROJECT),nfd_tlv_init))

# Link stage
# Write the build info and then the firmware ID to the MIP (one overrides the other in the MIP)
$(eval $(call nffw.add_link_flag,$(PROJECT),$(shell $(SCRIPT_DIR)/describe-head.sh --nfld_args $(FLAVOR))))
$(eval $(call nffw.add_rtsyms,$(PROJECT),$(shell $(SCRIPT_DIR)/describe-head.sh --fw_id $(FLAVOR))))
# TODO get link_w_analysis to work without adding a warning
$(eval $(call nffw.add_link_flag,$(PROJECT),-codeshare $(APP_MASTER_ME) $(MAPCMSG_ME)))
$(eval $(call nffw.add_link_flag,$(PROJECT),-noecc)) # required for codeshare on B0
$(eval $(call nffw.add_link_flag,$(PROJECT),$(DEDUP))) #Don't duplicate list files. Makes smaller NFFW
$(eval $(call nffw.link,$(PROJECT),nic_rx,nic_tx,datapath))
