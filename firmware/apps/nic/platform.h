/*
 * Copyright 2015 Netronome, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
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
