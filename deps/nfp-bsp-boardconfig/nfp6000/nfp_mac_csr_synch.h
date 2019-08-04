
/*
 * Copyright (C) 2017 Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __NFP_MAC_CSR_SYNC_H__
#define __NFP_MAC_CSR_SYNC_H__

/* Firware Status */
#define ARB_FW_STATUS_ASLEEP    0x23
#define ARB_FW_STATUS_WAKING    0x24
#define ARB_FW_STATUS_AWAKE     0x25
#define ARB_FW_KICKSTART        ARB_FW_STATUS_AWAKE

#define ARB_CLS_RING_NUM   4
#define ARB_CLS_RING_BASE  0x1000
#define ARB_CLS_RING_SIZE  64
#define ARB_CLS_ISLAND     1
#define ARB_ME_ISLAND      1
#define ARB_ME_ID          3

#define ARB_PORTS_STATS_BASE  0x25000

#define ARB_CLS_BASE_ADDR  (ARB_CLS_ISLAND <<34)
#define ARB_CLS_BASE_ADDR39_32  0x04
#define ARB_CLS_BASE_ADDR_Hi32  0x04000000

#define ARB_CODE_ETH_CMD_CFG_NOOP                 0
#define ARB_CODE_ETH_CMD_CFG_RECACHE              1
#define ARB_CODE_ETH_CMD_CFG_ENABLE_RX            2
#define ARB_CODE_ETH_CMD_CFG_ENABLE_TX            3
#define ARB_CODE_ETH_CMD_CFG_DISABLE_RX           4
#define ARB_CODE_ETH_CMD_CFG_DISABLE_TX           5
#define ARB_CODE_ETH_CMD_CFG_ENABLE_FLUSH         6
#define ARB_CODE_ETH_CMD_CFG_DISABLE_FLUSH        7
/* Update MAX when new commands are added */
#define ARB_CODE_MAX                              (ARB_CODE_ETH_CMD_CFG_DISABLE_FLUSH)

#define ARB_CMD(x)         (((x) & 0xff) << 0)
#define ARB_CMD_off(x)     (((x) >>0) & 0xff)
#define ARB_PORT(x)        (((x) & 0x3f) << 8)
#define ARB_PORT_off(x)    (((x) >>8) & 0x3f)
#define ARB_NBI(x)         (((x) & 0x1) << 15)
#define ARB_NBI_off(x)     (((x) >>15) & 0x1)
#define ARB_CORE(x)        (((x) & 0x1) << 14)
#define ARB_CORE_off(x)    (((x) >>14) & 0x1)
#define ARB_RECACHE(x)     (((x) & 0x1) << 16)
#define ARB_RECACHE_off(x) (((x) >>16) & 0x1)
#define ARB_SOURCE(x)      (((x) & 0xff) << 24)
#define ARB_SOURCE_off(x)  (((x) >>24) & 0xff)

/* Mailbox definitions */
#define ARB_FW_KICKSTART_MBOX   0
#define ARB_FW_GPIO_POLL_MBOX   1
#define ARB_FW_DEBUG_MBOX       2
#define ARB_FW_QUIESCE_MBOX     3

#define ARB_QUIESCE        0xff
#define ARB_RESUME         0xf5

#endif /* __NFP_MAC_CSR_SYNC_H__ */
