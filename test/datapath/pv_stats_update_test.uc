/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC cat firmware/lib/nic_basic/nic_stats.def | awk -f scripts/nic_stats.awk > firmware/lib/nic_basic/nic_stats_gen.h

#include <single_ctx_test.uc>

#include <global.uc>
#include <pv.uc>

#include "pkt_ipv4_udp_x88.uc"

#include <bitfields.uc>
#include <timestamp.uc>

timestamp_enable();

// test constraints on statistic addresses
test_assert_equal(NIC_STATS_QUEUE_RX_IDX, 0)
test_assert_equal(NIC_STATS_QUEUE_RX_UC_IDX, (NIC_STATS_QUEUE_RX_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_RX_MC_IDX, (NIC_STATS_QUEUE_RX_UC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_RX_BC_IDX, (NIC_STATS_QUEUE_RX_MC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_UC_IDX, (NIC_STATS_QUEUE_TX_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_MC_IDX, (NIC_STATS_QUEUE_TX_UC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_BC_IDX, (NIC_STATS_QUEUE_TX_MC_IDX + 1))

.reg bytes
.reg pkts
.reg queue
.reg stat
.reg offset
.reg addr[2]

#macro get_counters(out_pkts, out_bytes, addr)
.begin
    .reg read $value[2]
    .xfer_order $value
    .sig sig_read

    /* wait for stats engine data to settle for bulk read */
    timestamp_sleep(100)

    /* use bulk engine for natural addressing because we are testing stats engine address calcs */
    mem[read, $value[0], addr[0], <<8, addr[1], 1], ctx_swap[sig_read]
    alu[out_bytes, --, B, $value[0]] // test will not wrap 32bits
    alu[out_pkts, --, B, $value[1], >>3]
.end
#endm

move(addr[0], (_nic_stats_queue >> 8))

move(queue, 0)
.while (queue < 512)
    alu[addr[1], --, B, queue, <<(log2(NIC_STATS_QUEUE_SIZE))]
    alu[BF_A(pkt_vec, PV_QUEUE_IN_bf), --, B, queue, <<BF_L(PV_QUEUE_IN_bf)]
    move(stat, NIC_STATS_QUEUE_RX)
    .while (stat < NIC_STATS_QUEUE_COUNT)
        pv_stats_update(pkt_vec, stat, --)
        get_counters(pkts, bytes, addr)
        test_assert_equal(pkts, 1)
        test_assert_equal(bytes, 60)
        alu[stat, stat, +, 1]
        alu[addr[1], addr[1], +, 8]
    .endw
    alu[queue, queue, +, 1]
.endw

move(queue, 42)
alu[addr[1], --, B, queue, <<(log2(NIC_STATS_QUEUE_SIZE))]
alu[BF_A(pkt_vec, PV_QUEUE_IN_bf), --, B, queue, <<BF_L(PV_QUEUE_IN_bf)]
#define_eval STAT NIC_STATS_QUEUE_RX
#while (STAT < NIC_STATS_QUEUE_COUNT)
    pv_stats_update(pkt_vec, STAT, --)
    get_counters(pkts, bytes, addr)
    test_assert_equal(pkts, 2)
    test_assert_equal(bytes, 120)
    alu[addr[1], addr[1], +, 8]
#define_eval STAT (STAT + 1)
#endloop

pv_stats_update(pkt_vec, NIC_STATS_QUEUE_TX_IDX, done#)

#pragma warning(disable: 4702)
test_fail()
#pragma warning(pop)

done#:
alu[addr[1], --, B, queue, <<(log2(NIC_STATS_QUEUE_SIZE))]
alu[addr[1], addr[1], +, NIC_STATS_QUEUE_TX]
get_counters(pkts, bytes, addr)
test_assert_equal(pkts, 3)
test_assert_equal(bytes, 180)

test_pass()

