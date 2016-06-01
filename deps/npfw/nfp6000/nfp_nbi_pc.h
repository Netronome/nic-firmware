/*
 * Copyright (C) 2016,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          nfp6000/nfp_nbi_pc.h
 * @brief         NFP6000 NBI Preclassifier CSR definitions
 */

#ifndef _NFP6000__NFP_NBI_PC_H_
#define _NFP6000__NFP_NBI_PC_H_



/**
 * NBI Preclassifier XPB BUS offset for a given NBI island
 */
#define NFP_NBI_PC_XPB_OFF(_isl)  ((_isl << 24) | 0x8280000)

/*
 * NBI Preclassifier XPB block offsets
 */
#define NFP_NBI_PC_PE   0x0000
#define NFP_NBI_PC_CHAR 0x10000
#define NFP_NBI_PC_POL  0x20000

/*
 * NBI Preclassifer Picoengine CSRs
 */

/*
 * Register: NbiPrePicoengSetup
 *   [25]      HashPremult
 *   [24]      HashSboxEnable
 *   [23:20]   HashSbox
 *   [19:16]   HashMult
 *   [11:10]   Predicate
 *   [9:8]     PktPref
 *   [7:6]     SequenceReplace
 *   [5]       PktPtrOp
 *   [4]       Fetch256
 *   [3:0]     StackPtr
 *
 * Name(s):
 * <base>.PicoengineSetup
 */
#define NFP_NBI_PC_PE_SETUP                                0x0004
#define   NFP_NBI_PC_PE_SETUP_HASHPREMULT                    (1 << 25)
#define     NFP_NBI_PC_PE_SETUP_HASHPREMULT_bf               0, 25, 25
#define     NFP_NBI_PC_PE_SETUP_HASHPREMULT_msk              (0x1)
#define     NFP_NBI_PC_PE_SETUP_HASHPREMULT_bit              (25)
#define   NFP_NBI_PC_PE_SETUP_HASHSBOXEN                     (1 << 24)
#define     NFP_NBI_PC_PE_SETUP_HASHSBOXEN_bf                0, 24, 24
#define     NFP_NBI_PC_PE_SETUP_HASHSBOXEN_msk               (0x1)
#define     NFP_NBI_PC_PE_SETUP_HASHSBOXEN_bit               (24)
#define   NFP_NBI_PC_PE_SETUP_HASHSBOX(x)                    (((x) & 0xf) << 20)
#define   NFP_NBI_PC_PE_SETUP_HASHSBOX_of(x)                 (((x) >> 20) & 0xf)
#define     NFP_NBI_PC_PE_SETUP_HASHSBOX_bf                  0, 23, 20
#define     NFP_NBI_PC_PE_SETUP_HASHSBOX_msk                 (0xf)
#define     NFP_NBI_PC_PE_SETUP_HASHSBOX_shf                 (20)
#define   NFP_NBI_PC_PE_SETUP_HASHMULT(x)                    (((x) & 0xf) << 16)
#define   NFP_NBI_PC_PE_SETUP_HASHMULT_of(x)                 (((x) >> 16) & 0xf)
#define     NFP_NBI_PC_PE_SETUP_HASHMULT_bf                  0, 19, 16
#define     NFP_NBI_PC_PE_SETUP_HASHMULT_msk                 (0xf)
#define     NFP_NBI_PC_PE_SETUP_HASHMULT_shf                 (16)
#define   NFP_NBI_PC_PE_SETUP_PRED(x)                        (((x) & 3) << 10)
#define   NFP_NBI_PC_PE_SETUP_PRED_of(x)                     (((x) >> 10) & 3)
#define     NFP_NBI_PC_PE_SETUP_PRED_ALWAYS                  (0)
#define     NFP_NBI_PC_PE_SETUP_PRED_ZS                      (1)
#define     NFP_NBI_PC_PE_SETUP_PRED_CS                      (2)
#define     NFP_NBI_PC_PE_SETUP_PRED_GT                      (3)
#define     NFP_NBI_PC_PE_SETUP_PRED_bf                      0, 11, 10
#define     NFP_NBI_PC_PE_SETUP_PRED_msk                     (0x3)
#define     NFP_NBI_PC_PE_SETUP_PRED_shf                     (10)
#define   NFP_NBI_PC_PE_SETUP_PKTPREF(x)                     (((x) & 3) << 8)
#define   NFP_NBI_PC_PE_SETUP_PKTPREF_of(x)                  (((x) >> 8) & 3)
#define     NFP_NBI_PC_PE_SETUP_PKTPREF_NONE                 (0)
#define     NFP_NBI_PC_PE_SETUP_PKTPREF_PREF16               (1)
#define     NFP_NBI_PC_PE_SETUP_PKTPREF_PREF32               (2)
#define     NFP_NBI_PC_PE_SETUP_PKTPREF_RESVD                (3)
#define     NFP_NBI_PC_PE_SETUP_PKTPREF_bf                   0, 9, 8
#define     NFP_NBI_PC_PE_SETUP_PKTPREF_msk                  (0x3)
#define     NFP_NBI_PC_PE_SETUP_PKTPREF_shf                  (8)
#define   NFP_NBI_PC_PE_SETUP_SEQREPL(x)                     (((x) & 3) << 6)
#define   NFP_NBI_PC_PE_SETUP_SEQREPL_of(x)                  (((x) >> 6) & 3)
#define     NFP_NBI_PC_PE_SETUP_SEQREPL_NONE                 (0)
#define     NFP_NBI_PC_PE_SETUP_SEQREPL_SEQ16                (1)
#define     NFP_NBI_PC_PE_SETUP_SEQREPL_RESVD                (2)
#define     NFP_NBI_PC_PE_SETUP_SEQREPL_SEQ32                (3)
#define     NFP_NBI_PC_PE_SETUP_SEQREPL_bf                   0, 7, 6
#define     NFP_NBI_PC_PE_SETUP_SEQREPL_msk                  (0x3)
#define     NFP_NBI_PC_PE_SETUP_SEQREPL_shf                  (6)
#define   NFP_NBI_PC_PE_SETUP_PKTPTROP                       (1 << 5)
#define     NFP_NBI_PC_PE_SETUP_PKTPTROP_bf                  0, 5, 5
#define     NFP_NBI_PC_PE_SETUP_PKTPTROP_msk                 (0x1)
#define     NFP_NBI_PC_PE_SETUP_PKTPTROP_bit                 (5)
#define   NFP_NBI_PC_PE_SETUP_FETCH256                       (1 << 4)
#define     NFP_NBI_PC_PE_SETUP_FETCH256_bf                  0, 4, 4
#define     NFP_NBI_PC_PE_SETUP_FETCH256_msk                 (0x1)
#define     NFP_NBI_PC_PE_SETUP_FETCH256_bit                 (4)
#define   NFP_NBI_PC_PE_SETUP_STACKPTR(x)                    (((x) & 0xf) << 0)
#define   NFP_NBI_PC_PE_SETUP_STACKPTR_of(x)                 (((x) >> 0) & 0xf)
#define     NFP_NBI_PC_PE_SETUP_STACKPTR_bf                  0, 3, 0
#define     NFP_NBI_PC_PE_SETUP_STACKPTR_msk                 (0xf)
#define     NFP_NBI_PC_PE_SETUP_STACKPTR_shf                 (0)


/*
 * Register: NbiPrePicoengRunControl
 *   [29:28]   SMem
 *   [27:16]   GroupMem
 *   [15:4]    GroupClock
 *   [2]       IgnoreResult
 *   [1:0]     Alloc
 *
 * Name(s):
 * <base>.PicoengineRunControl
 */
#define NFP_NBI_PC_PE_RUNCONTROL                           0x0008
#define   NFP_NBI_PC_PE_RUNCONTROL_SMEM(x)                   (((x) & 3) << 28)
#define   NFP_NBI_PC_PE_RUNCONTROL_SMEM_of(x)                (((x) >> 28) & 3)
#define     NFP_NBI_PC_PE_RUNCONTROL_SMEM_bf                 0, 29, 28
#define     NFP_NBI_PC_PE_RUNCONTROL_SMEM_msk                (0x3)
#define     NFP_NBI_PC_PE_RUNCONTROL_SMEM_shf                (28)
#define   NFP_NBI_PC_PE_RUNCONTROL_GRPMEM(x)                 (((x) & 0xfff) << 16)
#define   NFP_NBI_PC_PE_RUNCONTROL_GRPMEM_of(x)              (((x) >> 16) & 0xfff)
#define     NFP_NBI_PC_PE_RUNCONTROL_GRPMEM_bf               0, 27, 16
#define     NFP_NBI_PC_PE_RUNCONTROL_GRPMEM_msk              (0xfff)
#define     NFP_NBI_PC_PE_RUNCONTROL_GRPMEM_shf              (16)
#define   NFP_NBI_PC_PE_RUNCONTROL_GRPCLK(x)                 (((x) & 0xfff) << 4)
#define   NFP_NBI_PC_PE_RUNCONTROL_GRPCLK_of(x)              (((x) >> 4) & 0xfff)
#define     NFP_NBI_PC_PE_RUNCONTROL_GRPCLK_bf               0, 15, 4
#define     NFP_NBI_PC_PE_RUNCONTROL_GRPCLK_msk              (0xfff)
#define     NFP_NBI_PC_PE_RUNCONTROL_GRPCLK_shf              (4)
#define   NFP_NBI_PC_PE_RUNCONTROL_IGNRES                    (1 << 2)
#define     NFP_NBI_PC_PE_RUNCONTROL_IGNRES_bf               0, 2, 2
#define     NFP_NBI_PC_PE_RUNCONTROL_IGNRES_msk              (0x1)
#define     NFP_NBI_PC_PE_RUNCONTROL_IGNRES_bit              (2)
#define   NFP_NBI_PC_PE_RUNCONTROL_ALLOC(x)                  (((x) & 3) << 0)
#define   NFP_NBI_PC_PE_RUNCONTROL_ALLOC_of(x)               (((x) >> 0) & 3)
#define     NFP_NBI_PC_PE_RUNCONTROL_ALLOC_NONE              (0)
#define     NFP_NBI_PC_PE_RUNCONTROL_ALLOC_ALLOC             (1)
#define     NFP_NBI_PC_PE_RUNCONTROL_ALLOC_RESVD             (2)
#define     NFP_NBI_PC_PE_RUNCONTROL_ALLOC_ONESHOT           (3)
#define     NFP_NBI_PC_PE_RUNCONTROL_ALLOC_bf                0, 1, 0
#define     NFP_NBI_PC_PE_RUNCONTROL_ALLOC_msk               (0x3)
#define     NFP_NBI_PC_PE_RUNCONTROL_ALLOC_shf               (0)


/*
 * Register: NbiPrePicoengTableConfigExtend
 *   [0]       LookupExt
 *
 * Name(s):
 * <base>.TableExtend
 */
#define NFP_NBI_PC_PE_TBLEXT                               0x000c
#define   NFP_NBI_PC_PE_TBLEXT_LOOKUPEXT                     (1 << 0)
#define     NFP_NBI_PC_PE_TBLEXT_LOOKUPEXT_bf                0, 0, 0
#define     NFP_NBI_PC_PE_TBLEXT_LOOKUPEXT_msk               (0x1)
#define     NFP_NBI_PC_PE_TBLEXT_LOOKUPEXT_bit               (0)


/*
 * Register: NbiPrePicoengActiveLow
 *   [31:0]    Status
 *
 * Name(s):
 * <base>.ActiveSet0Low <base>.ActiveSet1Low
 */
#define NFP_NBI_PC_PE_ACTSET0L                             0x0080
#define NFP_NBI_PC_PE_ACTSET1L                             0x0088
#define   NFP_NBI_PC_PE_ACTSET0L_STATUS(x)                   (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_PE_ACTSET0L_STATUS_of(x)                (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_PE_ACTSET0L_STATUS_bf                 0, 31, 0
#define     NFP_NBI_PC_PE_ACTSET0L_STATUS_msk                (0xffffffff)
#define     NFP_NBI_PC_PE_ACTSET0L_STATUS_shf                (0)


/*
 * Register: NbiPrePicoengActiveHigh
 *   [15:0]    Status
 *
 * Name(s):
 * <base>.ActiveSet0High <base>.ActiveSet1High
 */
#define NFP_NBI_PC_PE_ACTSET0H                             0x0084
#define NFP_NBI_PC_PE_ACTSET1H                             0x008c
#define   NFP_NBI_PC_PE_ACTSET0H_STATUS(x)                   (((x) & 0xffff) << 0)
#define   NFP_NBI_PC_PE_ACTSET0H_STATUS_of(x)                (((x) >> 0) & 0xffff)
#define     NFP_NBI_PC_PE_ACTSET0H_STATUS_bf                 0, 15, 0
#define     NFP_NBI_PC_PE_ACTSET0H_STATUS_msk                (0xffff)
#define     NFP_NBI_PC_PE_ACTSET0H_STATUS_shf                (0)


/*
 * Register: NbiPreClassifiedSmallStatistics
 *   [31]      Saturated
 *   [30:0]    Count
 *
 * Name(s):
 * <base>.ClassifiedSmall
 */
#define NFP_NBI_PC_PE_CLASSSMALL                           0x00c0
#define   NFP_NBI_PC_PE_CLASSSMALL_SATURATED                 (1 << 31)
#define     NFP_NBI_PC_PE_CLASSSMALL_SATURATED_bf            0, 31, 31
#define     NFP_NBI_PC_PE_CLASSSMALL_SATURATED_msk           (0x1)
#define     NFP_NBI_PC_PE_CLASSSMALL_SATURATED_bit           (31)
#define   NFP_NBI_PC_PE_CLASSSMALL_COUNT(x)                  (((x) & 0x7fffffff) << 0)
#define   NFP_NBI_PC_PE_CLASSSMALL_COUNT_of(x)               (((x) >> 0) & 0x7fffffff)
#define     NFP_NBI_PC_PE_CLASSSMALL_COUNT_bf                0, 30, 0
#define     NFP_NBI_PC_PE_CLASSSMALL_COUNT_msk               (0x7fffffff)
#define     NFP_NBI_PC_PE_CLASSSMALL_COUNT_shf               (0)


/*
 * Register: NbiPreClassifiedLargeStatistics
 *   [31]      Saturated
 *   [30:0]    Count
 *
 * Name(s):
 * <base>.ClassifiedLarge
 */
#define NFP_NBI_PC_PE_CLASSLARGE                           0x00c4
#define   NFP_NBI_PC_PE_CLASSLARGE_SATURATED                 (1 << 31)
#define     NFP_NBI_PC_PE_CLASSLARGE_SATURATED_bf            0, 31, 31
#define     NFP_NBI_PC_PE_CLASSLARGE_SATURATED_msk           (0x1)
#define     NFP_NBI_PC_PE_CLASSLARGE_SATURATED_bit           (31)
#define   NFP_NBI_PC_PE_CLASSLARGE_COUNT(x)                  (((x) & 0x7fffffff) << 0)
#define   NFP_NBI_PC_PE_CLASSLARGE_COUNT_of(x)               (((x) >> 0) & 0x7fffffff)
#define     NFP_NBI_PC_PE_CLASSLARGE_COUNT_bf                0, 30, 0
#define     NFP_NBI_PC_PE_CLASSLARGE_COUNT_msk               (0x7fffffff)
#define     NFP_NBI_PC_PE_CLASSLARGE_COUNT_shf               (0)


/*
 * Register: NbiPreTunnelStatistics
 *   [31]      Saturated
 *   [30:0]    Count
 *
 * Name(s):
 * <base>.Tunnel
 */
#define NFP_NBI_PC_PE_CLASSSTUNN                           0x00c8
#define   NFP_NBI_PC_PE_CLASSSTUNN_SATURATED                 (1 << 31)
#define     NFP_NBI_PC_PE_CLASSSTUNN_SATURATED_bf            0, 31, 31
#define     NFP_NBI_PC_PE_CLASSSTUNN_SATURATED_msk           (0x1)
#define     NFP_NBI_PC_PE_CLASSSTUNN_SATURATED_bit           (31)
#define   NFP_NBI_PC_PE_CLASSSTUNN_COUNT(x)                  (((x) & 0x7fffffff) << 0)
#define   NFP_NBI_PC_PE_CLASSSTUNN_COUNT_of(x)               (((x) >> 0) & 0x7fffffff)
#define     NFP_NBI_PC_PE_CLASSSTUNN_COUNT_bf                0, 30, 0
#define     NFP_NBI_PC_PE_CLASSSTUNN_COUNT_msk               (0x7fffffff)
#define     NFP_NBI_PC_PE_CLASSSTUNN_COUNT_shf               (0)


/*
 * Register: NbiPreLocalDataTable
 *   [31:22]   Base1
 *   [21:12]   Base0
 *   [11:9]    TableSize
 *   [8:4]     Select
 *   [3:0]     Lookup
 *
 * Name(s):
 * <base>.LocalData0...
 */
#define NFP_NBI_PC_PE_LOCALDATA(x)                         (0x0100 + ((x) * 0x4))
#define   NFP_NBI_PC_PE_LOCALDATA_BASE1(x)                   (((x) & 0x3ff) << 22)
#define   NFP_NBI_PC_PE_LOCALDATA_BASE1_of(x)                (((x) >> 22) & 0x3ff)
#define     NFP_NBI_PC_PE_LOCALDATA_BASE1_bf                 0, 31, 22
#define     NFP_NBI_PC_PE_LOCALDATA_BASE1_msk                (0x3ff)
#define     NFP_NBI_PC_PE_LOCALDATA_BASE1_shf                (22)
#define   NFP_NBI_PC_PE_LOCALDATA_BASE0(x)                   (((x) & 0x3ff) << 12)
#define   NFP_NBI_PC_PE_LOCALDATA_BASE0_of(x)                (((x) >> 12) & 0x3ff)
#define     NFP_NBI_PC_PE_LOCALDATA_BASE0_bf                 0, 21, 12
#define     NFP_NBI_PC_PE_LOCALDATA_BASE0_msk                (0x3ff)
#define     NFP_NBI_PC_PE_LOCALDATA_BASE0_shf                (12)
#define   NFP_NBI_PC_PE_LOCALDATA_TABLESIZE(x)               (((x) & 7) << 9)
#define   NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_of(x)            (((x) >> 9) & 7)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_1              (0)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_4              (1)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_16             (2)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_64             (3)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_256            (4)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_1k             (5)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_Reserved       (6)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_Reserved       (7)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_bf             0, 11, 9
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_msk            (0x7)
#define     NFP_NBI_PC_PE_LOCALDATA_TABLESIZE_shf            (9)
#define   NFP_NBI_PC_PE_LOCALDATA_SELECT(x)                  (((x) & 0x1f) << 4)
#define   NFP_NBI_PC_PE_LOCALDATA_SELECT_of(x)               (((x) >> 4) & 0x1f)
#define     NFP_NBI_PC_PE_LOCALDATA_SELECT_bf                0, 8, 4
#define     NFP_NBI_PC_PE_LOCALDATA_SELECT_msk               (0x1f)
#define     NFP_NBI_PC_PE_LOCALDATA_SELECT_shf               (4)
#define   NFP_NBI_PC_PE_LOCALDATA_LOOKUP(x)                  (((x) & 0xf) << 0)
#define   NFP_NBI_PC_PE_LOCALDATA_LOOKUP_of(x)               (((x) >> 0) & 0xf)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_LUT8              (0)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_LUT16             (1)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_LUT32             (2)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_Multibit          (3)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM32             (4)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM24             (5)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM16             (6)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM8              (7)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM32R16          (8)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM24R16          (9)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM16R16          (0xa)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM8R8            (0xb)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_CAM48R16          (0xc)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_TCAM24R16         (0xd)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_TCAM16R16         (0xe)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_TCAM8R16          (0xf)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_bf                0, 3, 0
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_msk               (0xf)
#define     NFP_NBI_PC_PE_LOCALDATA_LOOKUP_shf               (0)


/*
 * Register: NbiPreLocalInstTable
 *   [31:22]   Base1
 *   [21:12]   Base0
 *   [11:9]    TableSize
 *   [8:4]     Select
 *
 * Name(s):
 * <base>.LocalInst0...
 */
#define NFP_NBI_PC_PE_LOCALINST(x)                         (0x0120 + ((x) * 0x4))
#define   NFP_NBI_PC_PE_LOCALINST_BASE1(x)                   (((x) & 0x3ff) << 22)
#define   NFP_NBI_PC_PE_LOCALINST_BASE1_of(x)                (((x) >> 22) & 0x3ff)
#define     NFP_NBI_PC_PE_LOCALINST_BASE1_bf                 0, 31, 22
#define     NFP_NBI_PC_PE_LOCALINST_BASE1_msk                (0x3ff)
#define     NFP_NBI_PC_PE_LOCALINST_BASE1_shf                (22)
#define   NFP_NBI_PC_PE_LOCALINST_BASE0(x)                   (((x) & 0x3ff) << 12)
#define   NFP_NBI_PC_PE_LOCALINST_BASE0_of(x)                (((x) >> 12) & 0x3ff)
#define     NFP_NBI_PC_PE_LOCALINST_BASE0_bf                 0, 21, 12
#define     NFP_NBI_PC_PE_LOCALINST_BASE0_msk                (0x3ff)
#define     NFP_NBI_PC_PE_LOCALINST_BASE0_shf                (12)
#define   NFP_NBI_PC_PE_LOCALINST_TABLESIZE(x)               (((x) & 7) << 9)
#define   NFP_NBI_PC_PE_LOCALINST_TABLESIZE_of(x)            (((x) >> 9) & 7)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_1              (0)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_4              (1)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_16             (2)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_64             (3)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_256            (4)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_1k             (5)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_Reserved       (6)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_Reserved       (7)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_bf             0, 11, 9
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_msk            (0x7)
#define     NFP_NBI_PC_PE_LOCALINST_TABLESIZE_shf            (9)
#define   NFP_NBI_PC_PE_LOCALINST_SELECT(x)                  (((x) & 0x1f) << 4)
#define   NFP_NBI_PC_PE_LOCALINST_SELECT_of(x)               (((x) >> 4) & 0x1f)
#define     NFP_NBI_PC_PE_LOCALINST_SELECT_bf                0, 8, 4
#define     NFP_NBI_PC_PE_LOCALINST_SELECT_msk               (0x1f)
#define     NFP_NBI_PC_PE_LOCALINST_SELECT_shf               (4)


/*
 * Register: NbiPreSharedDataTable
 *   [31:22]   Base1
 *   [21:12]   Base0
 *   [11:9]    TableSize
 *   [8:4]     Select
 *   [3:0]     Lookup
 *
 * Name(s):
 * <base>.SharedData0...
 */
#define NFP_NBI_PC_PE_SHAREDDATA(x)                        (0x0140 + ((x) * 0x4))
#define   NFP_NBI_PC_PE_SHAREDDATA_BASE1(x)                  (((x) & 0x3ff) << 22)
#define   NFP_NBI_PC_PE_SHAREDDATA_BASE1_of(x)               (((x) >> 22) & 0x3ff)
#define     NFP_NBI_PC_PE_SHAREDDATA_BASE1_bf                0, 31, 22
#define     NFP_NBI_PC_PE_SHAREDDATA_BASE1_msk               (0x3ff)
#define     NFP_NBI_PC_PE_SHAREDDATA_BASE1_shf               (22)
#define   NFP_NBI_PC_PE_SHAREDDATA_BASE0(x)                  (((x) & 0x3ff) << 12)
#define   NFP_NBI_PC_PE_SHAREDDATA_BASE0_of(x)               (((x) >> 12) & 0x3ff)
#define     NFP_NBI_PC_PE_SHAREDDATA_BASE0_bf                0, 21, 12
#define     NFP_NBI_PC_PE_SHAREDDATA_BASE0_msk               (0x3ff)
#define     NFP_NBI_PC_PE_SHAREDDATA_BASE0_shf               (12)
#define   NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE(x)              (((x) & 7) << 9)
#define   NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_of(x)           (((x) >> 9) & 7)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_1             (0)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_4             (1)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_16            (2)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_64            (3)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_256           (4)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_1k            (5)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_Reserved      (6)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_Reserved      (7)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_bf            0, 11, 9
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_msk           (0x7)
#define     NFP_NBI_PC_PE_SHAREDDATA_TABLESIZE_shf           (9)
#define   NFP_NBI_PC_PE_SHAREDDATA_SELECT(x)                 (((x) & 0x1f) << 4)
#define   NFP_NBI_PC_PE_SHAREDDATA_SELECT_of(x)              (((x) >> 4) & 0x1f)
#define     NFP_NBI_PC_PE_SHAREDDATA_SELECT_bf               0, 8, 4
#define     NFP_NBI_PC_PE_SHAREDDATA_SELECT_msk              (0x1f)
#define     NFP_NBI_PC_PE_SHAREDDATA_SELECT_shf              (4)
#define   NFP_NBI_PC_PE_SHAREDDATA_LOOKUP(x)                 (((x) & 0xf) << 0)
#define   NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_of(x)              (((x) >> 0) & 0xf)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_LUT8             (0)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_LUT16            (1)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_LUT32            (2)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_Multibit         (3)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAM32            (4)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAM24            (5)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAM16            (6)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAM8             (7)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAMR32           (8)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAMR24           (9)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAMR16           (0xa)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAMR8            (0xb)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_CAMR48           (0xc)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_TCAMR24          (0xd)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_TCAMR16          (0xe)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_TCAMR8           (0xf)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_bf               0, 3, 0
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_msk              (0xf)
#define     NFP_NBI_PC_PE_SHAREDDATA_LOOKUP_shf              (0)


/*
 * Register: NbiPreSharedInstTable
 *   [31:22]   Base1
 *   [21:12]   Base0
 *   [11:9]    TableSize
 *   [8:4]     Select
 *
 * Name(s):
 * <base>.SharedInst0...
 */
#define NFP_NBI_PC_PE_SHAREDINST(x)                        (0x0160 + ((x) * 0x4))
#define   NFP_NBI_PC_PE_SHAREDINST_BASE1(x)                  (((x) & 0x3ff) << 22)
#define   NFP_NBI_PC_PE_SHAREDINST_BASE1_of(x)               (((x) >> 22) & 0x3ff)
#define     NFP_NBI_PC_PE_SHAREDINST_BASE1_bf                0, 31, 22
#define     NFP_NBI_PC_PE_SHAREDINST_BASE1_msk               (0x3ff)
#define     NFP_NBI_PC_PE_SHAREDINST_BASE1_shf               (22)
#define   NFP_NBI_PC_PE_SHAREDINST_BASE0(x)                  (((x) & 0x3ff) << 12)
#define   NFP_NBI_PC_PE_SHAREDINST_BASE0_of(x)               (((x) >> 12) & 0x3ff)
#define     NFP_NBI_PC_PE_SHAREDINST_BASE0_bf                0, 21, 12
#define     NFP_NBI_PC_PE_SHAREDINST_BASE0_msk               (0x3ff)
#define     NFP_NBI_PC_PE_SHAREDINST_BASE0_shf               (12)
#define   NFP_NBI_PC_PE_SHAREDINST_TABLESIZE(x)              (((x) & 7) << 9)
#define   NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_of(x)           (((x) >> 9) & 7)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_1             (0)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_4             (1)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_16            (2)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_64            (3)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_256           (4)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_1k            (5)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_Reserved      (6)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_Reserved      (7)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_bf            0, 11, 9
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_msk           (0x7)
#define     NFP_NBI_PC_PE_SHAREDINST_TABLESIZE_shf           (9)
#define   NFP_NBI_PC_PE_SHAREDINST_SELECT(x)                 (((x) & 0x1f) << 4)
#define   NFP_NBI_PC_PE_SHAREDINST_SELECT_of(x)              (((x) >> 4) & 0x1f)
#define     NFP_NBI_PC_PE_SHAREDINST_SELECT_bf               0, 8, 4
#define     NFP_NBI_PC_PE_SHAREDINST_SELECT_msk              (0x1f)
#define     NFP_NBI_PC_PE_SHAREDINST_SELECT_shf              (4)


/*
 * Register: NbiPreMulticycleTable
 *   [31:0]    Table
 *
 * Name(s):
 * <base>.MulticycleTable0Set0... <base>.MulticycleTable0Set1...
 */
#define NFP_NBI_PC_PE_MULTCYCLESET0(x)                     (0x0180 + ((x) * 0x4))
#define NFP_NBI_PC_PE_MULTCYCLESET1(x)                     (0x01a0 + ((x) * 0x4))
#define   NFP_NBI_PC_PE_MULTCYCLESET0_TABLE(x)               (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_PE_MULTCYCLESET0_TABLE_of(x)            (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_PE_MULTCYCLESET0_TABLE_bf             0, 31, 0
#define     NFP_NBI_PC_PE_MULTCYCLESET0_TABLE_msk            (0xffffffff)
#define     NFP_NBI_PC_PE_MULTCYCLESET0_TABLE_shf            (0)



/*
 * NBI Preclassifer Characterizer CSRs
 */

/*
 * Register: NbiPreCharCfg
 *   [31:28]   MaxDepth
 *   [27]      ExtendInitialSkip
 *   [26]      DisableInner
 *   [25]      DisablePPP
 *   [24]      DisableEthernet
 *   [21:20]   PPPAddressSkip
 *   [18]      GFPControlIgn
 *   [17]      GFPBarker
 *   [16]      GFPExtension
 *   [11]      PBBEnable
 *   [10]      EnableInitialTag
 *   [9:8]     MaxVlans
 *   [7:4]     InitialTagSize
 *   [3:0]     ProtSkip
 *
 * Name(s):
 * <base>.Config
 */
#define NFP_NBI_PC_CHAR_CFG                                0x0004
#define   NFP_NBI_PC_CHAR_CFG_MAXDEPTH(x)                    (((x) & 0xf) << 28)
#define   NFP_NBI_PC_CHAR_CFG_MAXDEPTH_of(x)                 (((x) >> 28) & 0xf)
#define     NFP_NBI_PC_CHAR_CFG_MAXDEPTH_bf                  0, 31, 28
#define     NFP_NBI_PC_CHAR_CFG_MAXDEPTH_msk                 (0xf)
#define     NFP_NBI_PC_CHAR_CFG_MAXDEPTH_shf                 (28)
#define   NFP_NBI_PC_CHAR_CFG_EXTENDSKIP                     (1 << 27)
#define     NFP_NBI_PC_CHAR_CFG_EXTENDSKIP_bf                0, 27, 27
#define     NFP_NBI_PC_CHAR_CFG_EXTENDSKIP_msk               (0x1)
#define     NFP_NBI_PC_CHAR_CFG_EXTENDSKIP_bit               (27)
#define   NFP_NBI_PC_CHAR_CFG_INNERDISABLE                   (1 << 26)
#define     NFP_NBI_PC_CHAR_CFG_INNERDISABLE_bf              0, 26, 26
#define     NFP_NBI_PC_CHAR_CFG_INNERDISABLE_msk             (0x1)
#define     NFP_NBI_PC_CHAR_CFG_INNERDISABLE_bit             (26)
#define   NFP_NBI_PC_CHAR_CFG_PPPDISABLE                     (1 << 25)
#define     NFP_NBI_PC_CHAR_CFG_PPPDISABLE_bf                0, 25, 25
#define     NFP_NBI_PC_CHAR_CFG_PPPDISABLE_msk               (0x1)
#define     NFP_NBI_PC_CHAR_CFG_PPPDISABLE_bit               (25)
#define   NFP_NBI_PC_CHAR_CFG_ETHDISABLE                     (1 << 24)
#define     NFP_NBI_PC_CHAR_CFG_ETHDISABLE_bf                0, 24, 24
#define     NFP_NBI_PC_CHAR_CFG_ETHDISABLE_msk               (0x1)
#define     NFP_NBI_PC_CHAR_CFG_ETHDISABLE_bit               (24)
#define   NFP_NBI_PC_CHAR_CFG_PPPADDSKP(x)                   (((x) & 3) << 20)
#define   NFP_NBI_PC_CHAR_CFG_PPPADDSKP_of(x)                (((x) >> 20) & 3)
#define     NFP_NBI_PC_CHAR_CFG_PPPADDSKP_bf                 0, 21, 20
#define     NFP_NBI_PC_CHAR_CFG_PPPADDSKP_msk                (0x3)
#define     NFP_NBI_PC_CHAR_CFG_PPPADDSKP_shf                (20)
#define   NFP_NBI_PC_CHAR_CFG_GFPCTLIGN                      (1 << 18)
#define     NFP_NBI_PC_CHAR_CFG_GFPCTLIGN_bf                 0, 18, 18
#define     NFP_NBI_PC_CHAR_CFG_GFPCTLIGN_msk                (0x1)
#define     NFP_NBI_PC_CHAR_CFG_GFPCTLIGN_bit                (18)
#define   NFP_NBI_PC_CHAR_CFG_GFPBARK                        (1 << 17)
#define     NFP_NBI_PC_CHAR_CFG_GFPBARK_bf                   0, 17, 17
#define     NFP_NBI_PC_CHAR_CFG_GFPBARK_msk                  (0x1)
#define     NFP_NBI_PC_CHAR_CFG_GFPBARK_bit                  (17)
#define   NFP_NBI_PC_CHAR_CFG_GFPEXT                         (1 << 16)
#define     NFP_NBI_PC_CHAR_CFG_GFPEXT_bf                    0, 16, 16
#define     NFP_NBI_PC_CHAR_CFG_GFPEXT_msk                   (0x1)
#define     NFP_NBI_PC_CHAR_CFG_GFPEXT_bit                   (16)
#define   NFP_NBI_PC_CHAR_CFG_PBBENABLE                      (1 << 11)
#define     NFP_NBI_PC_CHAR_CFG_PBBENABLE_bf                 0, 11, 11
#define     NFP_NBI_PC_CHAR_CFG_PBBENABLE_msk                (0x1)
#define     NFP_NBI_PC_CHAR_CFG_PBBENABLE_bit                (11)
#define   NFP_NBI_PC_CHAR_CFG_INITTAGEN                      (1 << 10)
#define     NFP_NBI_PC_CHAR_CFG_INITTAGEN_bf                 0, 10, 10
#define     NFP_NBI_PC_CHAR_CFG_INITTAGEN_msk                (0x1)
#define     NFP_NBI_PC_CHAR_CFG_INITTAGEN_bit                (10)
#define   NFP_NBI_PC_CHAR_CFG_MAXVLANS(x)                    (((x) & 3) << 8)
#define   NFP_NBI_PC_CHAR_CFG_MAXVLANS_of(x)                 (((x) >> 8) & 3)
#define     NFP_NBI_PC_CHAR_CFG_MAXVLANS_bf                  0, 9, 8
#define     NFP_NBI_PC_CHAR_CFG_MAXVLANS_msk                 (0x3)
#define     NFP_NBI_PC_CHAR_CFG_MAXVLANS_shf                 (8)
#define   NFP_NBI_PC_CHAR_CFG_INITIALTAGSIZE(x)              (((x) & 0xf) << 4)
#define   NFP_NBI_PC_CHAR_CFG_INITIALTAGSIZE_of(x)           (((x) >> 4) & 0xf)
#define     NFP_NBI_PC_CHAR_CFG_INITIALTAGSIZE_bf            0, 7, 4
#define     NFP_NBI_PC_CHAR_CFG_INITIALTAGSIZE_msk           (0xf)
#define     NFP_NBI_PC_CHAR_CFG_INITIALTAGSIZE_shf           (4)
#define   NFP_NBI_PC_CHAR_CFG_PROTSKIP(x)                    (((x) & 0xf) << 0)
#define   NFP_NBI_PC_CHAR_CFG_PROTSKIP_of(x)                 (((x) >> 0) & 0xf)
#define     NFP_NBI_PC_CHAR_CFG_PROTSKIP_bf                  0, 3, 0
#define     NFP_NBI_PC_CHAR_CFG_PROTSKIP_msk                 (0xf)
#define     NFP_NBI_PC_CHAR_CFG_PROTSKIP_shf                 (0)


/*
 * Register: NbiPreCharEnetTcamTagCtrl
 *   [5:4]     Length
 *   [0]       Enable
 *
 * Name(s):
 * <base>.TcamTagControl0...
 */
#define NFP_NBI_PC_CHAR_TCAMTAGCTL(x)                      (0x0008 + ((x) * 0x4))
#define   NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH(x)               (((x) & 3) << 4)
#define   NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_of(x)            (((x) >> 4) & 3)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_2              (0)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_3              (1)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_4              (2)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_Reserved       (3)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_bf             0, 5, 4
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_msk            (0x3)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_LENGTH_shf            (4)
#define   NFP_NBI_PC_CHAR_TCAMTAGCTL_ENABLE                  (1 << 0)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_ENABLE_bf             0, 0, 0
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_ENABLE_msk            (0x1)
#define     NFP_NBI_PC_CHAR_TCAMTAGCTL_ENABLE_bit            (0)


/*
 * Register: NbiPreCharEnetTcamTag
 *   [31:16]   Mask
 *   [15:0]    Value
 *
 * Name(s):
 * <base>.TcamTag0...
 */
#define NFP_NBI_PC_CHAR_TCAMTAG(x)                         (0x0010 + ((x) * 0x4))
#define   NFP_NBI_PC_CHAR_TCAMTAG_MASK(x)                    (((x) & 0xffff) << 16)
#define   NFP_NBI_PC_CHAR_TCAMTAG_MASK_of(x)                 (((x) >> 16) & 0xffff)
#define     NFP_NBI_PC_CHAR_TCAMTAG_MASK_bf                  0, 31, 16
#define     NFP_NBI_PC_CHAR_TCAMTAG_MASK_msk                 (0xffff)
#define     NFP_NBI_PC_CHAR_TCAMTAG_MASK_shf                 (16)
#define   NFP_NBI_PC_CHAR_TCAMTAG_VALUE(x)                   (((x) & 0xffff) << 0)
#define   NFP_NBI_PC_CHAR_TCAMTAG_VALUE_of(x)                (((x) >> 0) & 0xffff)
#define     NFP_NBI_PC_CHAR_TCAMTAG_VALUE_bf                 0, 15, 0
#define     NFP_NBI_PC_CHAR_TCAMTAG_VALUE_msk                (0xffff)
#define     NFP_NBI_PC_CHAR_TCAMTAG_VALUE_shf                (0)


/*
 * Register: NbiPreCharSequence
 *   [15:0]    Number
 *
 * Name(s):
 * <base>.Sequence
 */
#define NFP_NBI_PC_CHAR_SEQUENCE                           0x0018
#define   NFP_NBI_PC_CHAR_SEQUENCE_SEQNUM(x)                 (((x) & 0xffff) << 0)
#define   NFP_NBI_PC_CHAR_SEQUENCE_SEQNUM_of(x)              (((x) >> 0) & 0xffff)
#define     NFP_NBI_PC_CHAR_SEQUENCE_SEQNUM_bf               0, 15, 0
#define     NFP_NBI_PC_CHAR_SEQUENCE_SEQNUM_msk              (0xffff)
#define     NFP_NBI_PC_CHAR_SEQUENCE_SEQNUM_shf              (0)


/*
 * Register: NbiPreCharTableSet
 *   [31]      OneShot
 *   [7:6]     CharacterizerInUse
 *   [5:4]     PicoengineInUse
 *   [0]       Active
 *
 * Name(s):
 * <base>.TableSet
 */
#define NFP_NBI_PC_CHAR_TABLESET                           0x001c
#define   NFP_NBI_PC_CHAR_TABLESET_ONESHOT                   (1 << 31)
#define     NFP_NBI_PC_CHAR_TABLESET_ONESHOT_bf              0, 31, 31
#define     NFP_NBI_PC_CHAR_TABLESET_ONESHOT_msk             (0x1)
#define     NFP_NBI_PC_CHAR_TABLESET_ONESHOT_bit             (31)
#define   NFP_NBI_PC_CHAR_TABLESET_CHINUSE(x)                (((x) & 3) << 6)
#define   NFP_NBI_PC_CHAR_TABLESET_CHINUSE_of(x)             (((x) >> 6) & 3)
#define     NFP_NBI_PC_CHAR_TABLESET_CHINUSE_bf              0, 7, 6
#define     NFP_NBI_PC_CHAR_TABLESET_CHINUSE_msk             (0x3)
#define     NFP_NBI_PC_CHAR_TABLESET_CHINUSE_shf             (6)
#define   NFP_NBI_PC_CHAR_TABLESET_PEINUSE(x)                (((x) & 3) << 4)
#define   NFP_NBI_PC_CHAR_TABLESET_PEINUSE_of(x)             (((x) >> 4) & 3)
#define     NFP_NBI_PC_CHAR_TABLESET_PEINUSE_bf              0, 5, 4
#define     NFP_NBI_PC_CHAR_TABLESET_PEINUSE_msk             (0x3)
#define     NFP_NBI_PC_CHAR_TABLESET_PEINUSE_shf             (4)
#define   NFP_NBI_PC_CHAR_TABLESET_ACTIVE                    (1 << 0)
#define     NFP_NBI_PC_CHAR_TABLESET_ACTIVE_bf               0, 0, 0
#define     NFP_NBI_PC_CHAR_TABLESET_ACTIVE_msk              (0x1)
#define     NFP_NBI_PC_CHAR_TABLESET_ACTIVE_bit              (0)


/*
 * Register: NbiPreCharOverride
 *   [1]       OneShot
 *   [0]       Enable
 *
 * Name(s):
 * <base>.Override
 */
#define NFP_NBI_PC_CHAR_OVERRIDE                           0x0020
#define   NFP_NBI_PC_CHAR_OVERRIDE_ONESHOT                   (1 << 1)
#define     NFP_NBI_PC_CHAR_OVERRIDE_ONESHOT_bf              0, 1, 1
#define     NFP_NBI_PC_CHAR_OVERRIDE_ONESHOT_msk             (0x1)
#define     NFP_NBI_PC_CHAR_OVERRIDE_ONESHOT_bit             (1)
#define   NFP_NBI_PC_CHAR_OVERRIDE_ENB                       (1 << 0)
#define     NFP_NBI_PC_CHAR_OVERRIDE_ENB_bf                  0, 0, 0
#define     NFP_NBI_PC_CHAR_OVERRIDE_ENB_msk                 (0x1)
#define     NFP_NBI_PC_CHAR_OVERRIDE_ENB_bit                 (0)


/*
 * Register: NbiPreCharOverridePort
 *   [31:0]    Port
 *
 * Name(s):
 * <base>.OverridePort
 */
#define NFP_NBI_PC_CHAR_OVPORT                             0x0024
#define   NFP_NBI_PC_CHAR_OVPORT_PORT(x)                     (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_CHAR_OVPORT_PORT_of(x)                  (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_CHAR_OVPORT_PORT_bf                   0, 31, 0
#define     NFP_NBI_PC_CHAR_OVPORT_PORT_msk                  (0xffffffff)
#define     NFP_NBI_PC_CHAR_OVPORT_PORT_shf                  (0)


/*
 * Register: NbiPreCharOverrideFlags
 *   [31:0]    Flags
 *
 * Name(s):
 * <base>.OverrideFlags
 */
#define NFP_NBI_PC_CHAR_OVFLAG                             0x0028
#define   NFP_NBI_PC_CHAR_OVFLAG_FLAGS(x)                    (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_CHAR_OVFLAG_FLAGS_of(x)                 (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_CHAR_OVFLAG_FLAGS_bf                  0, 31, 0
#define     NFP_NBI_PC_CHAR_OVFLAG_FLAGS_msk                 (0xffffffff)
#define     NFP_NBI_PC_CHAR_OVFLAG_FLAGS_shf                 (0)


/*
 * Register: NbiPreCharOverrideOffsets
 *   [31:0]    Offsets
 *
 * Name(s):
 * <base>.OverrideOffsets
 */
#define NFP_NBI_PC_CHAR_OVOFFSET                           0x002c
#define   NFP_NBI_PC_CHAR_OVOFFSET_OFFSETS(x)                (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_CHAR_OVOFFSET_OFFSETS_of(x)             (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_CHAR_OVOFFSET_OFFSETS_bf              0, 31, 0
#define     NFP_NBI_PC_CHAR_OVOFFSET_OFFSETS_msk             (0xffffffff)
#define     NFP_NBI_PC_CHAR_OVOFFSET_OFFSETS_shf             (0)


/*
 * Register: NbiPreCharResultTcamMatchLo
 *   [31:0]    Value
 *
 * Name(s):
 * <base>.TcamMatchLow0...
 */
#define NFP_NBI_PC_CHAR_TCAMMATCHLOW(x)                    (0x0200 + ((x) * 0x10))
#define   NFP_NBI_PC_CHAR_TCAMMATCHLOW_VALUE(x)              (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_CHAR_TCAMMATCHLOW_VALUE_of(x)           (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMATCHLOW_VALUE_bf            0, 31, 0
#define     NFP_NBI_PC_CHAR_TCAMMATCHLOW_VALUE_msk           (0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMATCHLOW_VALUE_shf           (0)


/*
 * Register: NbiPreCharResultTcamMatchHi
 *   [31:0]    Value
 *
 * Name(s):
 * <base>.TcamMatchHigh0...
 */
#define NFP_NBI_PC_CHAR_TCAMMATCHHIGH(x)                   (0x0204 + ((x) * 0x10))
#define   NFP_NBI_PC_CHAR_TCAMMATCHHIGH_VALUE(x)             (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_CHAR_TCAMMATCHHIGH_VALUE_of(x)          (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMATCHHIGH_VALUE_bf           0, 31, 0
#define     NFP_NBI_PC_CHAR_TCAMMATCHHIGH_VALUE_msk          (0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMATCHHIGH_VALUE_shf          (0)


/*
 * Register: NbiPreCharResultTcamMaskLo
 *   [31:0]    Value
 *
 * Name(s):
 * <base>.TcamMaskLow0...
 */
#define NFP_NBI_PC_CHAR_TCAMMASKLOW(x)                     (0x0208 + ((x) * 0x10))
#define   NFP_NBI_PC_CHAR_TCAMMASKLOW_VALUE(x)               (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_CHAR_TCAMMASKLOW_VALUE_of(x)            (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMASKLOW_VALUE_bf             0, 31, 0
#define     NFP_NBI_PC_CHAR_TCAMMASKLOW_VALUE_msk            (0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMASKLOW_VALUE_shf            (0)


/*
 * Register: NbiPreCharResultTcamMaskHi
 *   [31:0]    Value
 *
 * Name(s):
 * <base>.TcamMaskHigh0...
 */
#define NFP_NBI_PC_CHAR_TCAMMASKHIGH(x)                    (0x020c + ((x) * 0x10))
#define   NFP_NBI_PC_CHAR_TCAMMASKHIGH_VALUE(x)              (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_CHAR_TCAMMASKHIGH_VALUE_of(x)           (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMASKHIGH_VALUE_bf            0, 31, 0
#define     NFP_NBI_PC_CHAR_TCAMMASKHIGH_VALUE_msk           (0xffffffff)
#define     NFP_NBI_PC_CHAR_TCAMMASKHIGH_VALUE_shf           (0)


/*
 * Register: NbiPreCharResultTcamMapping
 *   [31:16]   Index
 *   [8]       Override
 *   [7:4]     Metadata
 *   [2:0]     Table
 *
 * Name(s):
 * <base>.TcamMapping0...
 */
#define NFP_NBI_PC_CHAR_TCAMMAPPING(x)                     (0x0300 + ((x) * 0x4))
#define   NFP_NBI_PC_CHAR_TCAMMAPPING_INDEX(x)               (((x) & 0xffff) << 16)
#define   NFP_NBI_PC_CHAR_TCAMMAPPING_INDEX_of(x)            (((x) >> 16) & 0xffff)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_INDEX_bf             0, 31, 16
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_INDEX_msk            (0xffff)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_INDEX_shf            (16)
#define   NFP_NBI_PC_CHAR_TCAMMAPPING_OVERRIDE               (1 << 8)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_OVERRIDE_bf          0, 8, 8
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_OVERRIDE_msk         (0x1)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_OVERRIDE_bit         (8)
#define   NFP_NBI_PC_CHAR_TCAMMAPPING_METADATA(x)            (((x) & 0xf) << 4)
#define   NFP_NBI_PC_CHAR_TCAMMAPPING_METADATA_of(x)         (((x) >> 4) & 0xf)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_METADATA_bf          0, 7, 4
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_METADATA_msk         (0xf)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_METADATA_shf         (4)
#define   NFP_NBI_PC_CHAR_TCAMMAPPING_TABLE(x)               (((x) & 7) << 0)
#define   NFP_NBI_PC_CHAR_TCAMMAPPING_TABLE_of(x)            (((x) >> 0) & 7)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_TABLE_bf             0, 2, 0
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_TABLE_msk            (0x7)
#define     NFP_NBI_PC_CHAR_TCAMMAPPING_TABLE_shf            (0)


/*
 * Register: NbiPreCharPortCfg
 *   [7:5]     UserType
 *   [4:2]     Skip
 *   [1:0]     Analysis
 *
 * Name(s):
 * <base>.PortCfg0...
 */
#define NFP_NBI_PC_CHAR_PORTCFG(x)                         (0x0400 + ((x) * 0x4))
#define   NFP_NBI_PC_CHAR_PORTCFG_USERTYPE(x)                (((x) & 7) << 5)
#define   NFP_NBI_PC_CHAR_PORTCFG_USERTYPE_of(x)             (((x) >> 5) & 7)
#define     NFP_NBI_PC_CHAR_PORTCFG_USERTYPE_bf              0, 7, 5
#define     NFP_NBI_PC_CHAR_PORTCFG_USERTYPE_msk             (0x7)
#define     NFP_NBI_PC_CHAR_PORTCFG_USERTYPE_shf             (5)
#define   NFP_NBI_PC_CHAR_PORTCFG_SKIP(x)                    (((x) & 7) << 2)
#define   NFP_NBI_PC_CHAR_PORTCFG_SKIP_of(x)                 (((x) >> 2) & 7)
#define     NFP_NBI_PC_CHAR_PORTCFG_SKIP_bf                  0, 4, 2
#define     NFP_NBI_PC_CHAR_PORTCFG_SKIP_msk                 (0x7)
#define     NFP_NBI_PC_CHAR_PORTCFG_SKIP_shf                 (2)
#define   NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS(x)                (((x) & 3) << 0)
#define   NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_of(x)             (((x) >> 0) & 3)
#define     NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_GFP-F           (0)
#define     NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_Eth             (1)
#define     NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_PPP             (2)
#define     NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_InnerType       (3)
#define     NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_bf              0, 1, 0
#define     NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_msk             (0x3)
#define     NFP_NBI_PC_CHAR_PORTCFG_ANALYSIS_shf             (0)



/*
 * NBI Preclassifer Policer/Sequencer CSRs
 */

/*
 * Register: NbiPrePoliceAccumulator
 *   [31]      Saturate
 *   [30:0]    Credit
 *
 * Name(s):
 * <base>.Accumulator0...
 */
#define NFP_NBI_PC_POL_ACC(x)                              (0x0000 + ((x) * 0x4))
#define   NFP_NBI_PC_POL_ACC_SATURATE                        (1 << 31)
#define     NFP_NBI_PC_POL_ACC_SATURATE_bf                   0, 31, 31
#define     NFP_NBI_PC_POL_ACC_SATURATE_msk                  (0x1)
#define     NFP_NBI_PC_POL_ACC_SATURATE_bit                  (31)
#define   NFP_NBI_PC_POL_ACC_CREDIT(x)                       (((x) & 0x7fffffff) << 0)
#define   NFP_NBI_PC_POL_ACC_CREDIT_of(x)                    (((x) >> 0) & 0x7fffffff)
#define     NFP_NBI_PC_POL_ACC_CREDIT_bf                     0, 30, 0
#define     NFP_NBI_PC_POL_ACC_CREDIT_msk                    (0x7fffffff)
#define     NFP_NBI_PC_POL_ACC_CREDIT_shf                    (0)


/*
 * Register: NbiPrePoliceCreditRate
 *   [31]      CreditShift
 *   [30:20]   Credit
 *   [19:0]    Interval
 *
 * Name(s):
 * <base>.CreditRate0...
 */
#define NFP_NBI_PC_POL_RATE(x)                             (0x0020 + ((x) * 0x4))
#define   NFP_NBI_PC_POL_RATE_SHIFT                          (1 << 31)
#define     NFP_NBI_PC_POL_RATE_SHIFT_bf                     0, 31, 31
#define     NFP_NBI_PC_POL_RATE_SHIFT_msk                    (0x1)
#define     NFP_NBI_PC_POL_RATE_SHIFT_bit                    (31)
#define   NFP_NBI_PC_POL_RATE_CREDIT(x)                      (((x) & 0x7ff) << 20)
#define   NFP_NBI_PC_POL_RATE_CREDIT_of(x)                   (((x) >> 20) & 0x7ff)
#define     NFP_NBI_PC_POL_RATE_CREDIT_bf                    0, 30, 20
#define     NFP_NBI_PC_POL_RATE_CREDIT_msk                   (0x7ff)
#define     NFP_NBI_PC_POL_RATE_CREDIT_shf                   (20)
#define   NFP_NBI_PC_POL_RATE_INTERVAL(x)                    (((x) & 0xfffff) << 0)
#define   NFP_NBI_PC_POL_RATE_INTERVAL_of(x)                 (((x) >> 0) & 0xfffff)
#define     NFP_NBI_PC_POL_RATE_INTERVAL_bf                  0, 19, 0
#define     NFP_NBI_PC_POL_RATE_INTERVAL_msk                 (0xfffff)
#define     NFP_NBI_PC_POL_RATE_INTERVAL_shf                 (0)


/*
 * Register: NbiPrePoliceComparator
 *   [30:0]    Value
 *
 * Name(s):
 * <base>.Comparator0...
 */
#define NFP_NBI_PC_POL_CMP(x)                              (0x0040 + ((x) * 0x4))
#define   NFP_NBI_PC_POL_CMP_VALUE(x)                        (((x) & 0x7fffffff) << 0)
#define   NFP_NBI_PC_POL_CMP_VALUE_of(x)                     (((x) >> 0) & 0x7fffffff)
#define     NFP_NBI_PC_POL_CMP_VALUE_bf                      0, 30, 0
#define     NFP_NBI_PC_POL_CMP_VALUE_msk                     (0x7fffffff)
#define     NFP_NBI_PC_POL_CMP_VALUE_shf                     (0)


/*
 * Register: NbiPrePoliceConfig
 *   [15:0]    ClockDivide
 *
 * Name(s):
 * <base>.Config
 */
#define NFP_NBI_PC_POL_CNFG                                0x0060
#define   NFP_NBI_PC_POL_CNFG_CLKDIV(x)                      (((x) & 0xffff) << 0)
#define   NFP_NBI_PC_POL_CNFG_CLKDIV_of(x)                   (((x) >> 0) & 0xffff)
#define     NFP_NBI_PC_POL_CNFG_CLKDIV_bf                    0, 15, 0
#define     NFP_NBI_PC_POL_CNFG_CLKDIV_msk                   (0xffff)
#define     NFP_NBI_PC_POL_CNFG_CLKDIV_shf                   (0)


/*
 * Register: NbiPreSequence
 *   [31:0]    Sequence
 *
 * Name(s):
 * <base>.Sequence0...
 */
#define NFP_NBI_PC_POL_SEQUENCE(x)                         (0x0080 + ((x) * 0x4))
#define   NFP_NBI_PC_POL_SEQUENCE_SEQUENCE(x)                (((x) & 0xffffffff) << 0)
#define   NFP_NBI_PC_POL_SEQUENCE_SEQUENCE_of(x)             (((x) >> 0) & 0xffffffff)
#define     NFP_NBI_PC_POL_SEQUENCE_SEQUENCE_bf              0, 31, 0
#define     NFP_NBI_PC_POL_SEQUENCE_SEQUENCE_msk             (0xffffffff)
#define     NFP_NBI_PC_POL_SEQUENCE_SEQUENCE_shf             (0)



#if defined(__NFP_LANG_MICROC)

/*
 * NBI Preclassifier Picoengine register structures
 */
struct nfp_nbi_pc_pe_setup {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_26:6;
            unsigned int hashpremult:1;
            unsigned int hashsboxen:1;
            unsigned int hashsbox:4;
            unsigned int hashmult:4;
            unsigned int __reserved_12:4;
            unsigned int pred:2;
            unsigned int pktpref:2;
            unsigned int seqrepl:2;
            unsigned int pktptrop:1;
            unsigned int fetch256:1;
            unsigned int stackptr:4;
#           else
            unsigned int stackptr:4;
            unsigned int fetch256:1;
            unsigned int pktptrop:1;
            unsigned int seqrepl:2;
            unsigned int pktpref:2;
            unsigned int pred:2;
            unsigned int __reserved_12:4;
            unsigned int hashmult:4;
            unsigned int hashsbox:4;
            unsigned int hashsboxen:1;
            unsigned int hashpremult:1;
            unsigned int __reserved_26:6;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_runcontrol {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_30:2;
            unsigned int smem:2;
            unsigned int grpmem:12;
            unsigned int grpclk:12;
            unsigned int __reserved_3:1;
            unsigned int ignres:1;
            unsigned int alloc:2;
#           else
            unsigned int alloc:2;
            unsigned int ignres:1;
            unsigned int __reserved_3:1;
            unsigned int grpclk:12;
            unsigned int grpmem:12;
            unsigned int smem:2;
            unsigned int __reserved_30:2;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_tblext {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_1:31;
            unsigned int lookupext:1;
#           else
            unsigned int lookupext:1;
            unsigned int __reserved_1:31;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_actset0l {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int status:32;
#           else
            unsigned int status:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_actset0h {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_16:16;
            unsigned int status:16;
#           else
            unsigned int status:16;
            unsigned int __reserved_16:16;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_classsmall {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int saturated:1;
            unsigned int count:31;
#           else
            unsigned int count:31;
            unsigned int saturated:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_classlarge {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int saturated:1;
            unsigned int count:31;
#           else
            unsigned int count:31;
            unsigned int saturated:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_classstunn {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int saturated:1;
            unsigned int count:31;
#           else
            unsigned int count:31;
            unsigned int saturated:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_localdata {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int base1:10;
            unsigned int base0:10;
            unsigned int tablesize:3;
            unsigned int select:5;
            unsigned int lookup:4;
#           else
            unsigned int lookup:4;
            unsigned int select:5;
            unsigned int tablesize:3;
            unsigned int base0:10;
            unsigned int base1:10;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_localinst {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int base1:10;
            unsigned int base0:10;
            unsigned int tablesize:3;
            unsigned int select:5;
            unsigned int __reserved_0:4;
#           else
            unsigned int __reserved_0:4;
            unsigned int select:5;
            unsigned int tablesize:3;
            unsigned int base0:10;
            unsigned int base1:10;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_shareddata {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int base1:10;
            unsigned int base0:10;
            unsigned int tablesize:3;
            unsigned int select:5;
            unsigned int lookup:4;
#           else
            unsigned int lookup:4;
            unsigned int select:5;
            unsigned int tablesize:3;
            unsigned int base0:10;
            unsigned int base1:10;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_sharedinst {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int base1:10;
            unsigned int base0:10;
            unsigned int tablesize:3;
            unsigned int select:5;
            unsigned int __reserved_0:4;
#           else
            unsigned int __reserved_0:4;
            unsigned int select:5;
            unsigned int tablesize:3;
            unsigned int base0:10;
            unsigned int base1:10;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pe_multcycleset0 {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int table:32;
#           else
            unsigned int table:32;
#           endif
        };
        unsigned int __raw;
    };
};



/*
 * NBI Preclassifier Characterizer register structures
 */
struct nfp_nbi_pc_char_cfg {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int maxdepth:4;
            unsigned int extendskip:1;
            unsigned int innerdisable:1;
            unsigned int pppdisable:1;
            unsigned int ethdisable:1;
            unsigned int __reserved_22:2;
            unsigned int pppaddskp:2;
            unsigned int __reserved_19:1;
            unsigned int gfpctlign:1;
            unsigned int gfpbark:1;
            unsigned int gfpext:1;
            unsigned int __reserved_12:4;
            unsigned int pbbenable:1;
            unsigned int inittagen:1;
            unsigned int maxvlans:2;
            unsigned int initialtagsize:4;
            unsigned int protskip:4;
#           else
            unsigned int protskip:4;
            unsigned int initialtagsize:4;
            unsigned int maxvlans:2;
            unsigned int inittagen:1;
            unsigned int pbbenable:1;
            unsigned int __reserved_12:4;
            unsigned int gfpext:1;
            unsigned int gfpbark:1;
            unsigned int gfpctlign:1;
            unsigned int __reserved_19:1;
            unsigned int pppaddskp:2;
            unsigned int __reserved_22:2;
            unsigned int ethdisable:1;
            unsigned int pppdisable:1;
            unsigned int innerdisable:1;
            unsigned int extendskip:1;
            unsigned int maxdepth:4;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tcamtagctl {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_6:26;
            unsigned int length:2;
            unsigned int __reserved_1:3;
            unsigned int enable:1;
#           else
            unsigned int enable:1;
            unsigned int __reserved_1:3;
            unsigned int length:2;
            unsigned int __reserved_6:26;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tcamtag {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int mask:16;
            unsigned int value:16;
#           else
            unsigned int value:16;
            unsigned int mask:16;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_sequence {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_16:16;
            unsigned int seqnum:16;
#           else
            unsigned int seqnum:16;
            unsigned int __reserved_16:16;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tableset {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int oneshot:1;
            unsigned int __reserved_8:23;
            unsigned int chinuse:2;
            unsigned int peinuse:2;
            unsigned int __reserved_1:3;
            unsigned int active:1;
#           else
            unsigned int active:1;
            unsigned int __reserved_1:3;
            unsigned int peinuse:2;
            unsigned int chinuse:2;
            unsigned int __reserved_8:23;
            unsigned int oneshot:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_override {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int oneshot:1;
            unsigned int enb:1;
#           else
            unsigned int enb:1;
            unsigned int oneshot:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_ovport {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int port:32;
#           else
            unsigned int port:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_ovflag {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int flags:32;
#           else
            unsigned int flags:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_ovoffset {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int offsets:32;
#           else
            unsigned int offsets:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tcammatchlow {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int value:32;
#           else
            unsigned int value:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tcammatchhigh {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int value:32;
#           else
            unsigned int value:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tcammasklow {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int value:32;
#           else
            unsigned int value:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tcammaskhigh {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int value:32;
#           else
            unsigned int value:32;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_tcammapping {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int index:16;
            unsigned int __reserved_9:7;
            unsigned int override:1;
            unsigned int metadata:4;
            unsigned int __reserved_3:1;
            unsigned int table:3;
#           else
            unsigned int table:3;
            unsigned int __reserved_3:1;
            unsigned int metadata:4;
            unsigned int override:1;
            unsigned int __reserved_9:7;
            unsigned int index:16;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_char_portcfg {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int usertype:3;
            unsigned int skip:3;
            unsigned int analysis:2;
#           else
            unsigned int analysis:2;
            unsigned int skip:3;
            unsigned int usertype:3;
#           endif
        };
        unsigned int __raw;
    };
};



/*
 * NBI Preclassifier Policer/Sequencer register structures
 */
struct nfp_nbi_pc_pol_acc {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int saturate:1;
            unsigned int credit:31;
#           else
            unsigned int credit:31;
            unsigned int saturate:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pol_rate {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int shift:1;
            unsigned int credit:11;
            unsigned int interval:20;
#           else
            unsigned int interval:20;
            unsigned int credit:11;
            unsigned int shift:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pol_cmp {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_31:1;
            unsigned int value:31;
#           else
            unsigned int value:31;
            unsigned int __reserved_31:1;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pol_cnfg {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int __reserved_16:16;
            unsigned int clkdiv:16;
#           else
            unsigned int clkdiv:16;
            unsigned int __reserved_16:16;
#           endif
        };
        unsigned int __raw;
    };
};

struct nfp_nbi_pc_pol_sequence {
    union {
        struct {
#           ifdef BIGENDIAN
            unsigned int sequence:32;
#           else
            unsigned int sequence:32;
#           endif
        };
        unsigned int __raw;
    };
};



#endif /* __NFP_LANG_MICROC */

#endif /* !_NFP6000__NFP_NBI_PC_H_ */
