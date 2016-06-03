/*
 * Copyright 2016 Netronome, Inc.
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
 * @file          include/platform.h
 * @brief         Platform-specific configuration information.
 */

#ifndef __PLATFORM_H__
#define __PLATFORM_H__


/*
 * Macro enumeration of all platform and media type combinations.
 *
 * Notes:
 *   - NS_PLATFORM_FIRST and NS_PLATFORM_LAST can be used to ensure that
 *       NS_PLATFORM_TYPE is a valid value.
 *   - The NS_PLATFORM_TYPE == 0 is intentionally left as an invalid value.
 *   - Any new platform-media-type combinations should generally be added to
 *       the tail of this enumeration/list.  It is best that this enumeration
 *       be a contiguous set of integers.
 */
#define NS_PLATFORM_FIRST                1

#define NS_PLATFORM_HYDROGEN             NS_PLATFORM_FIRST
#define NS_PLATFORM_HYDROGEN_4x10        2
#define NS_PLATFORM_LITHIUM              3
#define NS_PLATFORM_LITHIUM_1x1_1x10     4
#define NS_PLATFORM_LITHIUM_1x10_1x1     5
#define NS_PLATFORM_LITHIUM_2x1          6
#define NS_PLATFORM_BERYLLIUM_1x40       7
#define NS_PLATFORM_BERYLLIUM_2x40       8
#define NS_PLATFORM_BERYLLIUM_4x10       9
#define NS_PLATFORM_BERYLLIUM_4x10_1x40  10
#define NS_PLATFORM_BERYLLIUM_8x10       11

#define NS_PLATFORM_LAST                 NS_PLATFORM_BERYLLIUM_8x10


/*
 * Platform- and media-type- specific macro definitions.
 *
 * Note: The following macros must be defined for each NS_PLATFORM_TYPE:
 *
 *         - NS_PLATFORM_MAC_CORE(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  MAC core number that a given port belongs to; an
 *                       integer from 0 to 1, inclusive
 *
 *         - NS_PLATFORM_MAC_CORE_SERDES_HI(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Highest MAC core SerDes number used by a given port;
 *                       an integer from  0 to 11, inclusive
 *             - note: The MAC core SerDes number is a relative index from the
 *                     perspective of the MAC core; e.g. MAC core SerDes 0
 *                     would be the first MAC SerDes belonging to a particular
 *                     MAC core
 *
 *         - NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Lowest MAC core SerDes number used by a given port; an
 *                       integer from  0 to 11, inclusive
 *             - note: The MAC core SerDes number is a relative index from the
 *                     perspective of the MAC core; e.g. MAC core SerDes 0
 *                     would be the first MAC SerDes belonging to a particular
 *                     MAC core
 *
 *         - NS_PLATFORM_MAC_CHANNEL_HI(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Highest channel number assigned to a given port; an
 *                       integer from 0 to 127, inclusive
 *             - note:  The MAC channel number is a relative index from the
 *                      perspective of the MAC (or NBI) island; e.g. MAC
 *                      channel 0 would be the lowest MAC channel belonging to
 *                      a particular MAC island
 *
 *         - NS_PLATFORM_MAC_CHANNEL_LO(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Lowest channel number assigned to a given port; an
 *                       integer from 0 to 127, inclusive
 *             - note:  The MAC channel number is a relative index from the
 *                      perspective of the MAC (or NBI) island; e.g. MAC
 *                      channel 0 would be the lowest MAC channel belonging to
 *                      a particular MAC island
 *
 *         - NS_PLATFORM_MAC_PCP_REMAP(_pcp)
 *             - param _pcp  IEEE 802.1p Priority Code Point (PCP); an integer
 *                           from 0 to 7, inclusive
 *             - return  Channel offset to be used for frames w/ a given PCP; an
 *                       integer from 0 to 7, inclusive
 *             - note:  The channel offset is added to the base MAC channel of a
 *                      given port to get the MAC channel used for that port and
 *                      PCP combination
 *
 *         - NS_PLATFORM_MAC_UNTAGGED_MAP
 *             - return  Channel offset to be used for untagged frames; an
 *                       integer from 0 to 7, inclusive
 *             - note:  The channel offset is added to the base MAC channel of a
 *                      given port to get the MAC channel used for untagged
 *                      frames on that port
 *
 *         - NS_PLATFORM_NUM_PORTS_PER_MAC_0
 *             - return  The number of ports belonging to the MAC island 0 for
 *                       that platform; an integer from 0 to 128, inclusive
 *
 *         - NS_PLATFORM_NUM_PORTS_PER_MAC_1
 *             - return  The number of ports belonging to the MAC island 1 for
 *                       that platform; an integer from 0 to 128, inclusive
 *
 *         - NS_PLATFORM_PORT_SPEED(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  The speed of the port, in Gbps; a non-negative integer
 *
 *
 * Note: The following macros will automatically be defined for each platform:
 *
 *         - NS_PLATFORM_MAC(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  MAC island number that a given port belongs to; an
 *                       integer from 0 to 1, inclusive
 *
 *         - NS_PLATFORM_MAC_CHANNEL(_port, _pcp)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - param _pcp   IEEE 802.1p Priority Code Point (PCP); an integer
 *                            from 0 to 7, inclusive
 *             - return  MAC channel number for frames with a given PCP and
 *                       egressing a given port; an integer from 0 to 127,
 *                       inclusive
 *
 *         - NS_PLATFORM_MAC_CHANNEL_UNTAGGED(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  MAC channel number for untagged frames egressing a
 *                       given port; an integer from 0 to 127, inclusive
 *
 *         - NS_PLATFORM_MAC_NUM_SERDES(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Number of SerDes used by a given port; an integer from
 *                       0 to 11, inclusive
 *
 *         - NS_PLATFORM_MAC_SERDES_HI(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Highest MAC SerDes number used by a given port; an
 *                       integer from 0 to 23, inclusive
 *             - note: The MAC SerDes number is a relative index from the
 *                     perspective of the MAC island; e.g. MAC SerDes 12 would
 *                     be the twelth MAC SerDes belonging to a particular MAC
 *                     island
 *
 *         - NS_PLATFORM_MAC_SERDES_LO(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Lowest MAC SerDes number used by a given port; an
 *                       integer from 0 to 23, inclusive
 *             - note: The MAC SerDes number is a relative index from the
 *                     perspective of the MAC island; e.g. MAC SerDes 12 would
 *                     be the twelth MAC SerDes belonging to a particular MAC
 *                     island
 *
 *         - NS_PLATFORM_NBI_TM_QID(_port, _pcp, _l2q)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - param _pcp   IEEE 802.1p Priority Code Point (PCP); an integer
 *                            from 0 to 7, inclusive
 *             - param _l2q   NBI TM level-2 scheduler input queue number
 *                            for a given port and PCP; an integer from 0 to
 *                            63, inclusive
 *             - return  NBI TM queue ID for frames with a given PCP and
 *                       egressing a given port via a given NBI TM level-2
 *                       scheduler input queue; an integer from 0 to 1023,
 *                       inclusive
 *             - note: The NBI TM level-2 scheduler input queue number is a
 *                     relative index from the perspective of the NBI TM
 *                     level-2 scheduler.  Each NBI TM level-2 scheduler has 8
 *                     input queues, and each MAC channel is mapped either to
 *                     a level-1 scheduler, a level-2 scheduler or a level-2
 *                     scheduler input queue.  Correspondingly, each MAC
 *                     channel can be assigned up to the 64 NBI TM queues,
 *                     depending on which scheduler or scheduler input the MAC
 *                     channels are mapped to:
 *                       - If the MAC channel is mapped to a level-1 scheduler,
 *                           up to 64 NBI TM queues can be used for a given MAC
 *                           channel
 *                       - If the MAC channel is mapped to a level-2 scheduler,
 *                           up to 8 NBI TM queues can be used for a given MAC
 *                           channel
 *                       - If the MAC channel is mapped to a level-2 scheduler
 *                           input queue, only that NBI TM queue can be used
 *                           for a given MAC channel
 *
 *         - NS_PLATFORM_NBI_TM_QID_HI(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Highest NBI TM queue ID assigned to a given port; an
 *                       integer from 0 to 1023, inclusive
 *
 *         - NS_PLATFORM_NBI_TM_QID_LO(_port)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - return  Lowest NBI TM queue ID assigned to a given port; an
 *                       integer from 0 to 1023, inclusive
 *
 *         - NS_PLATFORM_NBI_TM_QID_UNTAGGED(_port, _l2q)
 *             - param _port  Platform physical port number; an integer from 0
 *                            to NS_PLATFORM_NUM_PORTS, inclusive
 *             - param _l2q   NBI TM level-2 scheduler input queue number for
 *                            untagged frames egressing a given port; an
 *                            integer from 0 to 63, inclusive
 *             - return  NBI TM queue ID for untagged frames egressing a given
 *                       port via a given NBI TM level-2 scheduler input queue;
 *                       an integer from 0 to 1023, inclusive
 *             - note: The NBI TM level-2 scheduler input queue number is a
 *                     relative index from the perspective of the NBI TM
 *                     level-2 scheduler.  Each NBI TM level-2 scheduler has 8
 *                     input queues, and each MAC channel is mapped either to
 *                     a level-1 scheduler, a level-2 scheduler or a level-2
 *                     scheduler input queue.  Correspondingly, each MAC
 *                     channel can be assigned up to the 64 NBI TM queues,
 *                     depending on which scheduler or scheduler input the MAC
 *                     channels are mapped to:
 *                       - If the MAC channel is mapped to a level-1 scheduler,
 *                           up to 64 NBI TM queues can be used for a given MAC
 *                           channel
 *                       - If the MAC channel is mapped to a level-2 scheduler,
 *                           up to 8 NBI TM queues can be used for a given MAC
 *                           channel
 *                       - If the MAC channel is mapped to a level-2 scheduler
 *                           input queue, only that NBI TM queue can be used
 *                           for a given MAC channel
 *
 *         - NS_PLATFORM_NUM_PORTS
 *             - return  The number of ports on the platform; an integer from 0
 *                       to 256, inclusive
 */

/* Hydrogen 1x40GE */
#if (NS_PLATFORM_TYPE == NS_PLATFORM_HYDROGEN)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) 3
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) 0
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)     3
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     0
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       1
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         40

/* Hydrogen 4x10GE (using breakout) */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_HYDROGEN_4x10)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) (_port)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) \
        NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 2)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       4
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         10

/* Lithium 2x10GE */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_LITHIUM)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) ((_port) << 2)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) \
        NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 4)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       2
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         10

/* Lithium 1x1GE + 1x10GE */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_LITHIUM_1x1_1x10)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) ((_port) << 2)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) \
        NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 4)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       2
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         ((_port == 0) ? 1 : 10)

/* Lithium 1x10GE + 1x1GE */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_LITHIUM_1x10_1x1)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) ((_port) << 2)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) \
        NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 4)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       2
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         ((_port == 0) ? 10 : 1)

/* Lithium 2x1GE */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_LITHIUM_2x1)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) ((_port) << 2)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) \
        NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 4)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       2
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         1

/* Beryllium 1x40GE */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_BERYLLIUM_1x40)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) 7
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) 4
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)     19
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     16
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       1
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         40

/* Beryllium 2x40GE */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_BERYLLIUM_2x40)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) ((_port) << 2)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port)   \
        (NS_PLATFORM_MAC_CORE_SERDES_LO(_port) + 3)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 4)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       2
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         40

/* Beryllium 4x10GE (using breakout) */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_BERYLLIUM_4x10)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) ((_port) + 4)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) \
        NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     (((_port) << 2) + 16)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       4
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         10

/* Beryllium 4x10GE (using breakout) + 1x40GE */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_BERYLLIUM_4x10_1x40)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) (_port)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port)                       \
        (NS_PLATFORM_MAC_CORE_SERDES_LO(_port) + ((_port < 4) ? 0 : 3))
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 2)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       5
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         ((_port < 4) ? 10 : 40)

/* Beryllium 8x10GE (using breakout) */
#elif (NS_PLATFORM_TYPE == NS_PLATFORM_BERYLLIUM_8x10)
    #define NS_PLATFORM_MAC_CORE(_port)           0
    #define NS_PLATFORM_MAC_CORE_SERDES_LO(_port) (_port)
    #define NS_PLATFORM_MAC_CORE_SERDES_HI(_port) \
        NS_PLATFORM_MAC_CORE_SERDES_LO(_port)
    #define NS_PLATFORM_MAC_CHANNEL_LO(_port)     ((_port) << 2)
    #define NS_PLATFORM_MAC_CHANNEL_HI(_port)   \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + 3)
    #define NS_PLATFORM_MAC_PCP_REMAP(_pcp)       ((_pcp <= 3) ? _pcp : 3)
    #define NS_PLATFORM_MAC_UNTAGGED_MAP          3
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_0       8
    #define NS_PLATFORM_NUM_PORTS_PER_MAC_1       0
    #define NS_PLATFORM_PORT_SPEED(_port)         10
#endif


#ifdef NS_PLATFORM_TYPE
    /* Derived preprocessor macros, common to all platforms */
    #define NS_PLATFORM_MAC(_port)                          \
        ((_port < NS_PLATFORM_NUM_PORTS_PER_MAC_0) ? 0 : 1)
    #define NS_PLATFORM_MAC_CHANNEL(_port, _pcp)                              \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + NS_PLATFORM_MAC_PCP_REMAP(_pcp))
    #define NS_PLATFORM_MAC_CHANNEL_UNTAGGED(_port)                        \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) + NS_PLATFORM_MAC_UNTAGGED_MAP)
    #define NS_PLATFORM_MAC_NUM_SERDES(_port)       \
        (NS_PLATFORM_MAC_CORE_SERDES_HI(_port) -    \
         NS_PLATFORM_MAC_CORE_SERDES_LO(_port) + 1)
    #define NS_PLATFORM_MAC_SERDES_HI(_port) \
        (NS_PLATFORM_MAC_CORE(_port) * 12 +  \
         NS_PLATFORM_MAC_CORE_SERDES_HI(_port))
    #define NS_PLATFORM_MAC_SERDES_LO(_port) \
        (NS_PLATFORM_MAC_CORE(_port) * 12 +  \
         NS_PLATFORM_MAC_CORE_SERDES_LO(_port))
    #define NS_PLATFORM_NBI_TM_QID(_port, _pcp, _l2q)          \
        ((NS_PLATFORM_MAC_CHANNEL(_port, _pcp) << 3) + (_l2q))
    #define NS_PLATFORM_NBI_TM_QID_HI(_port)           \
        ((NS_PLATFORM_MAC_CHANNEL_HI(_port) << 3) + 7)
    #define NS_PLATFORM_NBI_TM_QID_LO(_port)     \
        (NS_PLATFORM_MAC_CHANNEL_LO(_port) << 3)
    #define NS_PLATFORM_NBI_TM_QID_UNTAGGED(_port, _l2q) \
        (NS_PLATFORM_MAC_CHANNEL_UNTAGGED(_port) << 3)
    #define NS_PLATFORM_NUM_PORTS                                           \
        (NS_PLATFORM_NUM_PORTS_PER_MAC_0 + NS_PLATFORM_NUM_PORTS_PER_MAC_1)
#endif


#endif /* __PLATFORM_H__ */