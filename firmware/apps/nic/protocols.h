/*
 * Copyright (c) 2017-2019 Netronome Systems, Inc. All rights reserved.
 *
 * @file   protocols.h
 * @brief  Bitfield definitions for various protocol headers.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef _PROTOCOLS_H
#define _PROTOCOLS_H

#define MAC_MULTICAST_bf            0, 8, 8
#define IP_VERSION_bf               0, 31, 28  // version field in same location for IPv4 and IPv6

#define ETHERNET_SIZE               14
#define ETH_MAC_SIZE                12
#define ETH_TYPE_SIZE               2
#define ETH_VLAN_SIZE               2
#define NET_ETH_TYPE_SVLAN          0x88A8

#define MPLS_LABEL_SIZE             4

/**
 * IPv4 header (without options)
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-------+-------+-----------+---+-------------------------------+
 *    0  |version|  IHL  |    DSCP   |ECN|          Total Length         |
 *       +-------+-------+-----------+---+-----+-------------------------+
 *    1  |         Identification        |Flags| Fragment Offset         |
 *       +---------------+---------------+-----+-------------------------+
 *    2  |     TTL       |   Protocol    |          Header Checksum      |
 *       +---------------+---------------+-------------------------------+
 *    3  |                         Source Address                        |
 *       +---------------------------------------------------------------+
 *    4  |                       Destination Address                     |
 *       +---------------------------------------------------------------+
 */


#define IPV4_VERSION_bf             IP_VERSION_bf
#define IPV4_HEAD_LEN_bf            0, 27, 24
#define IPV4_DSCP_bf                0, 23, 18
#define IPV4_ECN_bf                 0, 17, 16
#define IPV4_LENGTH_bf              0, 15, 0

#define IPV4_ID_bf                  1, 31, 16
#define IPV4_FLAGS_bf               1, 15, 13
#define IPV4_FRAG_OFFSET_bf         1, 12, 0

#define IPV4_TTL_bf                 2, 31, 24
#define IPV4_PROTOCOL_bf            2, 23, 16
#define IPV4_CHECKSUM_bf            2, 15, 0

#define IPV4_SOURCE_bf              3, 31, 0

#define IPV4_DESTINATION_bf         4, 31, 0

#define IPV4_LEN_OFFS               2
#define IPV4_PROTOCOL_BYTE          2

#define IPV4_PROTO_BYTE_OFFS        9

/*
 * IPv6 header (without extension headers)
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-------+-------+-------+---+---+-------------------------------+
 *    0  |version| Traffic class |              Flow Label               |
 *       +-------+-------+-------+---+---+---------------+---------------+
 *    1  |         Payload Length        |  Next Header  | Hop Limit     |
 *       +---------------+---------------+---------------+---------------+
 *    2  |                                                               |
 *       +                                                               +
 *    3  |                                                               |
 *       +                         Source Address                        +
 *    4  |                                                               |
 *       +                                                               +
 *    5  |                                                               |
 *       +---------------------------------------------------------------+
 *    6  |                                                               |
 *       +                                                               +
 *    7  |                                                               |
 *       +                       Destination Address                     +
 *    8  |                                                               |
 *       +                                                               +
 *    9  |                                                               |
 *       +---------------------------------------------------------------+
 */

#define IPV6_VERSION_bf             IP_VERSION_bf
#define IPV6_TRAFFIC_CLASS_bf       0, 27, 20
#define IPV6_FLOW_LABEL_bf          0, 19, 0

#define IPV6_PAYLOAD_LENGTH_bf      1, 31, 16
#define IPV6_NEXT_HEADER_bf         1, 15, 8
#define IPV6_HOP_LIMIT_bf           1, 7, 0

#define IPV6_PAYLOAD_OFFS           4
#define IPV6_NEXT_HEADER_BYTE       1

#define IP_PROTOCOL_TCP             0x06
#define IP_PROTOCOL_UDP             0x11

#define L4_SOURCE_PORT_bf           0, 31, 16
#define L4_DESTINATION_PORT_bf      0, 15, 0

#define IPV6_HDR_SIZE               40

/*
 * TCP header format (only displaying up to words used or touched by LSO fixup)
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-------------------------------+-------------------------------+
 *    0  |          Source port          |      Destination port         |
 *       +-------------------------------+-------------------------------+
 *    1  |                          Sequence number                      |
 *       +-------------------------------+-------------------------------+
 *    2  |                      Acknowledgement number                   |
 *       +-------+-----+-+-+-+-+-+-+-+-+-+-------------------------------+
 *       |       |     |N|C|E|U|A|P|R|S|F|                               |
 *    3  |Data of|0 0 0|S|W|C|R|C|S|S|Y|I|          Window size          |
 *       |       |     | |R|E|G|K|H|T|N|N|                               |
 *       +-------+-----+-+-+-+-+-+-+-+-+-+-------------------------------+
 *    4  |           Checksum            |        Urgent pointer         |
 *       +---------------------------------------------------------------+
 */

#define TCP_SOURCE_PORT_bf          L4_SOURCE_PORT_bf
#define TCP_DESTINATION_PORT_bf     L4_DESTINATION_PORT_bf

#define TCP_SEQ_bf                  1, 31, 0

#define TCP_ACK_bf                  2, 31, 0

#define TCP_DATA_OFFSET_bf          3, 31, 28
#define TCP_FLAGS_bf                3, 27, 16
#define TCP_WINDOW_SIZE_bf          3, 15, 0

#define TCP_CHECKSUM_bf             4, 31, 16
#define TCP_URGENT_PTR_bf           4, 15, 0

#define TCP_SEQ_OFFS                4
#define TCP_FLAGS_OFFS              12

 /*
 * UDP header
 * Bit    3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
 * -----\ 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
 * Word  +-------------------------------+-------------------------------+
 *    0  |          Source port          |      Destination port         |
 *       +-------------------------------+-------------------------------+
 *    1  |            Length             |           Checksum            |
 *       +-------------------------------+-------------------------------+
 */

#define UDP_SOURCE_PORT_bf          L4_SOURCE_PORT_bf
#define UDP_DESTINATION_PORT_bf     L4_DESTINATION_PORT_bf

#define UDP_LENGTH_bf               1, 31, 16
#define UDP_CHECKSUM_bf             1, 15, 0

#define UDP_LEN_OFFS                4
#define UDP_HDR_SIZE                8

/* Tunnel Definitions */

#define VXLAN_SIZE                   8
#define NVGRE_SIZE                   4
#define GENEVE_SIZE                  8
#define NET_GENEVE_PORT              0x17C1

#endif
