/**
 * Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
 *
 * @file          nfd_user_cfg.h
 * @brief         This file is here to satisfy NFD includes.
 *
 */

/*
 * The required options needed to include NFD header files.
 *
 * These are here for applications that do not require NFD, but since libinfra
 * uses NFD, these are done on behalf of the application. An application that
 * intends to use NFD should specify these in the nfd_user_cfg header in a
 * higher priority include path than the libinfra provided one.
 */
#ifndef _NFD_USER_CFG_H_
#define _NFD_USER_CFG_H_

#ifndef NFD_IN_BLM_BLS
#define NFD_IN_BLM_BLS          0
#endif
#ifndef NFD_IN_BLM_POOL
#define NFD_IN_BLM_POOL         BLM_NBI8_BLQ0_EMU_QID
#endif
#ifndef NFD_IN_BLM_RADDR
#define NFD_IN_BLM_RADDR        __LoadTimeConstant("__addr_emem0")
#endif
#ifndef NFD_IN_WQ_SZ
#define NFD_IN_WQ_SZ            64
#endif
#ifndef NFD_OUT_RING_SZ
#define NFD_OUT_RING_SZ         256
#endif
#ifndef NFD_CFG_RING_EMEM
#define NFD_CFG_RING_EMEM       emem0
#endif

#ifndef NFD_MAX_VF_QUEUES
#define NFD_MAX_VF_QUEUES       1
#endif

#ifndef NFD_MAX_PF_QUEUES
#define NFD_MAX_PF_QUEUES       1
#endif

#ifndef NFD_MAX_VFS
#define NFD_MAX_VFS             8
#endif

#ifndef NFD_CFG_PF_CAP
#define NFD_CFG_PF_CAP          NFP_NET_CFG_CTRL_ENABLE
#endif

#ifndef NFD_CFG_VF_CAP
#define NFD_CFG_VF_CAP          NFP_NET_CFG_CTRL_ENABLE
#endif

#endif /* _NFD_USER_CFG_H_ */
