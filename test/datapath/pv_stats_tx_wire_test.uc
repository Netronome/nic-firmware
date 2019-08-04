/* Copyright (c) 2017-2019  Netronome Systems, Inc.  All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

;TEST_INIT_EXEC cat firmware/lib/nic_basic/nic_stats.def | awk -f scripts/nic_stats.awk > firmware/lib/nic_basic/nic_stats_gen.h

#include <single_ctx_test.uc>

#include <global.uc>
#include <pv.uc>

#include <bitfields.uc>
#include <timestamp.uc>
#include <aggregate.uc>

#define pkt_vec *l$index1

timestamp_enable();

.reg bytes
.reg pkts
.reg queue
.reg stat
.reg offset
.reg addr[2]

test_assert_equal(NIC_STATS_QUEUE_TX_UC_IDX, (NIC_STATS_QUEUE_TX_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_MC_IDX, (NIC_STATS_QUEUE_TX_UC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_BC_IDX, (NIC_STATS_QUEUE_TX_MC_IDX + 1))
test_assert_equal(NIC_STATS_QUEUE_TX_UC, (NIC_STATS_QUEUE_TX + 8))
test_assert_equal(NIC_STATS_QUEUE_TX_MC, (NIC_STATS_QUEUE_TX_UC + 8))
test_assert_equal(NIC_STATS_QUEUE_TX_BC, (NIC_STATS_QUEUE_TX_MC + 8))

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
.reg pkt_vec_orig_len_addr
alu[pkt_vec_orig_len_addr, --, B, t_idx_ctx, >>(8 - log2((PV_SIZE_LW * 4 * PV_MAX_CLONES), 1))]
local_csr_wr[ACTIVE_LM_ADDR_2, pkt_vec_orig_len_addr]
nop
nop
nop
alu[--, --, B, *l$index2--]
alu[*l$index2, --, B, 84]

move(queue, 0)

/* check that PCIe queues correctly count packets and ORIG_LENGTH */
.while (queue < 256)
    alu[addr[1], --, B, queue, <<(log2(NIC_STATS_QUEUE_SIZE))]
    alu[addr[1], addr[1], +, NIC_STATS_QUEUE_TX]
    alu[BF_A(pkt_vec, PV_QUEUE_IN_bf), --, B, queue, <<BF_L(PV_QUEUE_IN_bf)]
    move(stat, 0)
    .while (stat < 4)
        bitfield_insert__sz2(BF_AML(pkt_vec, PV_MAC_DST_TYPE_bf), stat)
        pv_stats_tx_wire(pkt_vec, done1#)
        #pragma warning(disable: 4702)
        test_fail()
        #pragma warning(pop)
done1#:
        get_counters(pkts, bytes, addr)
        test_assert_equal(pkts, 1)
        test_assert_equal(bytes, 84)
        alu[stat, stat, +, 1]
        alu[addr[1], addr[1], +, 8]
    .endw
    alu[queue, queue, +, 1]
.endw

/* check that NBI queues are not counted */
.while (queue < 512)
    alu[addr[1], --, B, queue, <<(log2(NIC_STATS_QUEUE_SIZE))]
    alu[addr[1], addr[1], +, NIC_STATS_QUEUE_TX]
    alu[BF_A(pkt_vec, PV_QUEUE_IN_bf), --, B, queue, <<BF_L(PV_QUEUE_IN_bf)]
    move(stat, 0)
    .while (stat < 4)
        bitfield_insert__sz2(BF_AML(pkt_vec, PV_MAC_DST_TYPE_bf), stat)
        pv_stats_tx_wire(pkt_vec, done2#)
        #pragma warning(disable: 4702)
        test_fail()
        #pragma warning(pop)
done2#:
        get_counters(pkts, bytes, addr)
        test_assert_equal(pkts, 0)
        test_assert_equal(bytes, 0)
        alu[stat, stat, +, 1]
        alu[addr[1], addr[1], +, 8]
    .endw
    alu[queue, queue, +, 1]
.endw

test_pass()
