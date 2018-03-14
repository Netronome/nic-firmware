#include <single_ctx_test.uc>

#include "pkt_ipv4_udp_x88.uc"

#include <global.uc>

#include <pv.uc>

.reg type
__pv_get_mac_dst_type(type, pkt_vec)

test_assert_equal(type, 0)

test_pass()
