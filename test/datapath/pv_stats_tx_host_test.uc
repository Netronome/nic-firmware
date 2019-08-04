/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC cat firmware/lib/nic_basic/nic_stats.def | awk -f scripts/nic_stats.awk > firmware/lib/nic_basic/nic_stats_gen.h

#define PV_MULTI_PCI

#include <single_ctx_test.uc>

#include <global.uc>
#include <pv.uc>

#include "pkt_ipv4_udp_x88.uc"

#include <bitfields.uc>
#include <timestamp.uc>

timestamp_enable();

.reg bytes
.reg continue
.reg expected
.reg pkts
.reg dst_queue
.reg src_queue
.reg pci_isl
.reg pci_q
.reg stat
.reg src_addr
.reg dst_addr
.reg addr
.reg tmp

test_assert_equal(NIC_STATS_QUEUE_RX_IDX, 0)
test_assert_equal(NIC_STATS_QUEUE_RX_UC_IDX, (NIC_STATS_QUEUE_RX_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_RX_MC_IDX, (NIC_STATS_QUEUE_RX_UC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_RX_BC_IDX, (NIC_STATS_QUEUE_RX_MC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_RX_UC, (NIC_STATS_QUEUE_RX + 8))
test_assert_equal(NIC_STATS_QUEUE_RX_MC, (NIC_STATS_QUEUE_RX_UC + 8))
test_assert_equal(NIC_STATS_QUEUE_RX_BC, (NIC_STATS_QUEUE_RX_MC + 8))

test_assert_equal(NIC_STATS_QUEUE_TX_UC_IDX, (NIC_STATS_QUEUE_TX_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_MC_IDX, (NIC_STATS_QUEUE_TX_UC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_BC_IDX, (NIC_STATS_QUEUE_TX_MC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_UC, (NIC_STATS_QUEUE_TX + 8))
test_assert_equal(NIC_STATS_QUEUE_TX_MC, (NIC_STATS_QUEUE_TX_UC + 8))
test_assert_equal(NIC_STATS_QUEUE_TX_BC, (NIC_STATS_QUEUE_TX_MC + 8))

#macro get_counters(out_pkts, out_bytes, addr, stat)
.begin
    .reg base
    .reg offset
    .reg read $value[2]
    .xfer_order $value
    .sig sig_read

    move(base, (_nic_stats_queue >> 8))
    multiply32(offset, 8, stat, OP_SIZE_8X24)
    alu[offset, addr, +, offset]

    /* wait for stats engine data to settle for bulk read */
    timestamp_sleep(100)

    /* use bulk engine for natural addressing because we are testing stats engine address calcs */
    mem[read, $value[0], base, <<8, offset, 1], ctx_swap[sig_read]
    alu[out_bytes, --, B, $value[0]] // test will not wrap 32bits
    alu[out_pkts, --, B, $value[1], >>3]
.end
#endm

alu[--, pkt_vec--, OR, 0]
move(pkt_vec++, 84)
move(continue, 0)
move(src_queue, 0)
move(dst_queue, 0)
move(dst_addr, 0)
.while (dst_queue < 256)
  .while (src_queue < 512)
        alu[dst_addr, --, B, dst_queue, <<(log2(NIC_STATS_QUEUE_SIZE))]
        alu[dst_addr, dst_addr, +, NIC_STATS_QUEUE_RX] // dst_addr += 0

        alu[src_addr, --, B, src_queue, <<(log2(NIC_STATS_QUEUE_SIZE))]
        alu[src_addr, src_addr, +, NIC_STATS_QUEUE_TX]
        alu[BF_A(pkt_vec, PV_QUEUE_IN_bf), --, B, src_queue, <<BF_L(PV_QUEUE_IN_bf)]

        move(stat, 0)
        .while (stat < 4)
            bitfield_insert__sz2(BF_AML(pkt_vec, PV_MAC_DST_TYPE_bf), stat)
            alu[pci_isl, 0x3, AND, dst_queue, >>6]
            alu[pci_q, dst_queue, AND, 0x3f]
            pv_stats_tx_host(pkt_vec, pci_isl, pci_q, continue, done#, done#)
            #pragma warning(disable: 4702)
            test_fail()
            #pragma warning(pop)
        done#:
            /* check source queue stats */
            .if (src_queue < 256)
                get_counters(pkts, bytes, src_addr, stat)
                alu[expected, dst_queue, +, 1]
                test_assert_equal(pkts, expected)
                multiply32(expected, expected, 84, OP_SIZE_8X24)
                test_assert_equal(bytes, expected)
            .else
                get_counters(pkts, bytes, src_addr, stat)
                test_assert_equal(pkts, 0)
                test_assert_equal(bytes, 0)
            .endif
            /* check dest queue stats */
            get_counters(pkts, bytes, dst_addr, stat)
            immed[expected, 512]
            multiply32(expected, expected, dst_queue, OP_SIZE_8X24)
            alu[expected, expected, +, src_queue]
            alu[expected, expected, +, 1]
            test_assert_equal(pkts, expected)
            multiply32(expected, expected, 60, OP_SIZE_8X24)
            test_assert_equal(bytes, expected)
            alu[stat, stat, +, 1]
        .endw
        immed[tmp, NIC_STATS_QUEUE_SIZE]
        alu[dst_addr, dst_addr, +, tmp]
        alu[src_queue, src_queue, +, 1]
    .endw
    alu[dst_queue, dst_queue, +, 1]
.endw

test_pass()

