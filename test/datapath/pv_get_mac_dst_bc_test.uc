#include <single_ctx_test.uc>

#include "pkt_bc_ipv4_udp_x88.uc"

#include <global.uc>

#include <pv.uc>

.reg type
pv_seek(pkt_vec, 0, (PV_SEEK_INIT | PV_SEEK_CTM_ONLY))
__pv_get_mac_dst_type(type, pkt_vec)

test_assert_equal(type, 3)

test_pass()
