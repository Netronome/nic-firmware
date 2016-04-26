/*
 * Copyright 2015 Netronome, Inc.
 *
 * @file          apps/nic/platform.h
 * @brief         NFP platform configuration for the NIC application.
 */

#ifndef __PLATFORM_H__
#define __PLATFORM_H__

#ifndef PLATFORM
#error "PLATFORM must be defined"
#endif

#if PLATFORM == 1
#define LITHIUM_NFP_NIC
#else
#define HYDROGEN_NFP_NIC
#endif

#endif /* __PLATFORM_H__ */
