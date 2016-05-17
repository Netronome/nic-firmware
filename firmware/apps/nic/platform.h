/*
 * Copyright 2015 Netronome, Inc.
 *
 * @file          apps/nic/platform.h
 * @brief         NFP platform configuration for the NIC application.
 */

#ifndef __PLATFORM_H__
#define __PLATFORM_H__

#ifndef NS_PLATFORM_TYPE
#error "NS_PLATFORM_TYPE must be defined"
#endif

#if NS_PLATFORM_TYPE == 1
#define LITHIUM_NFP_NIC
#else
#define HYDROGEN_NFP_NIC
#endif

#endif /* __PLATFORM_H__ */
