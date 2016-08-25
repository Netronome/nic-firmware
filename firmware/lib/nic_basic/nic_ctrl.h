/*
 * Copyright 2014-2015 Netronome, Inc.
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
 * @file          lib/nic/nic_ctrl.h
 * @brief         Control interface for NIC data structures from the host
 */


#ifndef _NIC_CTRL_H_
#define _NIC_CTRL_H_

#if defined(__NFP_LANG_MICROC)
#include <nfp.h>
#include <stdint.h>

#include <net/eth.h>
#endif

#if defined(__STDC__)
#include <stdint.h>

#ifndef NET_ETH_ALEN
#define NET_ETH_ALEN 6
#endif

/* XXX Let's hope this doesn't cause any name-space conflicts */
struct eth_addr {
    uint8_t  a[NET_ETH_ALEN];
};
#endif


#endif /* _NIC_CTRL_H_ */
