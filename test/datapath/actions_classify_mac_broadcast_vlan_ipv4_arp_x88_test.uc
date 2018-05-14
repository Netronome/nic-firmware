;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_32=0x0011
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_33=0x22334455
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_34=0xc0ffee
;TEST_INIT_EXEC nfp-reg mereg:i32.me0.XferIn_35=0xdeadbeef

#include "pkt_vlan_ipv4_arp_x88.uc"
#include <global.uc>
#include "actions_harness.uc"
#include <actions.uc>

.reg expected_pv_broadcast
.reg pkt_len
.reg vlan_id

move(expected_pv_broadcast, (0x190<<BF_L(PV_VLAN_ID_bf) |\
                             1<<BF_L(PV_BROADCAST_ACTIVE_bf)))

pv_get_length(pkt_len, pkt_vec)

alu[vlan_id, --, B, 0]
#define_eval T_IND_INC 0

local_csr_wr[T_INDEX, (32 * 4)]
immed[__actions_t_idx, (32 * 4)]
pv_invalidate_cache(pkt_vec)

test_assert_equal($__actions[0], 0x0011)
test_assert_equal($__actions[1], 0x22334455)

alu[__actions_t_idx, t_idx_ctx, OR, &$__actions[0], <<2]
nop
local_csr_wr[T_INDEX, __actions_t_idx]

__actions_mac_classify(pkt_vec, discards_filter_mac#)

test_assert_equal(pkt_vec[PV_VLAN_wrd], expected_pv_broadcast)

test_assert_equal(*$index++, 0xc0ffee)
test_assert_equal(*$index++, 0xdeadbeef)

test_pass()

discards_filter_mac#:
test_fail()
