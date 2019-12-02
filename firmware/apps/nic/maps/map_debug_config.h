/*
 * Copyright (c) 2017-2019 Netronome Systems, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//#undef DEBUG_TRACE

#ifdef _CMSG_MAP_
    #define CMSG_UNITTEST_CODE
    #ifndef __DBG_ID0__
        //#define __DBG_ID0__ 11
        #define __DBG_ID0__ 0
    #endif
#endif /*_CMSG_MAP_ */

#ifdef __HASHMAP_CAM_UC__
    #define __DBG_ID2__ 2
    #define    HASHMAP_UNITTEST_CODE
#endif /* __HASHMAP_CAM_UC__ */

#ifdef __HASHMAP_PRIV_UC__
    #define __DBG_ID5__ 5
#endif /*__HASHMAP_PRIV_UC__*/

#ifdef __HASHMAP_UC__
    // use small mask to debug
    #define __DBG_ID1__ 1
#endif /*__HASHMAP_UC__*/

#ifdef DEBUG_TRACE
    /* debug level: 1 hashmap, 2 hashmap_cam, 5 hashmap_priv */
    /* min level 0 (main), max is 15 */
    #ifndef DEBUG_LEVEL
        //#define DEBUG_LEVEL 0
        #define DEBUG_LEVEL 15
    #endif
    #ifndef JOURNAL_ENABLE
        #define JOURNAL_ENABLE 1
    #endif
#endif

#ifndef DEBUG_ERR_ID
    #define DEBUG_ERR_ID    0x0
#endif
