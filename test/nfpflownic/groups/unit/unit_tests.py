##
## Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Unit test group for the NFPFlowNIC Software Group.
"""

import collections
from netro.tests.null import NullTest
from ...nfpflownic_tests import _NFPFlowNIC, _NFPFlowNIC_2port
from unit import UnitIPv4, UnitIPv6, NFPFlowNICPing, UnitPing, JumboPacket, \
    RxVlan, Stats_rx_err_cnt, LinkState, RSStest_same_l4_tuple, \
    RSStest_diff_l4_tuple, Stats_per_queue_cntr, RxVlan_rx_byte, \
    RSStest_diff_l4_tuple_modify_table, Kmod_perf, \
    RSStest_diff_part_l4_tuple, NFPFlowNICContentCheck, McPing
from tunnel_unit import TunnelTest, Csum_Tx_tunnel, RSStest_diff_inner_tuple,\
    LSO_tunnel, RSStest_diff_inner_tuple_multi_tunnels, Csum_rx_tnl
from iperf_unit import Csum_Tx, Ring_size, LSO_iperf
from cfg_unit import NFPFlowNICCfgUnitTest
from gather_dma import NFPFlowNICGatherDMA


###########################################################################
# Unit Tests
###########################################################################
class NFPFlowNICUnit(_NFPFlowNIC):
    """Unit tests for the NFPFlowNIC Software Group"""

    summary = "Unit tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNIC.__init__(self, name, cfg=cfg, quick=quick,
                             dut_object=dut_object)

        ping_dut = (self.dut, self.eth_x)
        ping_a_t = (self.host_a, self.eth_a)

        dut_t_x = (self.dut, self.addr_x, self.eth_x, self.addr_v6_x,
                   self.rss_key, self.rm_nc_bin)
        a_t = (self.host_a, self.addr_a, self.eth_a, self.addr_v6_a, None,
               self.rm_nc_bin)

        self.unit_dict = Unit_dict(self, dut_t_x, a_t,
                                   ping_dut, ping_a_t)
        self._tests = self.unit_dict.tests


class Unit_dict(object):
    """
    dictionary class for sharing test dictionary in unit groups
    """
    def __init__(self, group, dut_t_x, a_t, ping_dut, ping_a_t, prefix=''):
        """
        generating test dictionary for unit groups
        """
        self.tests = collections.OrderedDict()
        self.prefix = prefix

        #######################################################################
        # Ping tests
        #######################################################################
        combos = (("fromA", ping_a_t, ping_dut),
                  ("toA", ping_dut, ping_a_t))

        for postf, src, dst in combos:
            tn = self.prefix + "ping_1_%s" % postf
            self.tests[tn] = NFPFlowNICPing(src, dst, clean=True, count=1,
                                             group=group, name=tn,
                                             summary="Send a single ping %s"
                                                     % postf)

        #######################################################################
        # Multicast tests
        #######################################################################

        summary = 'Multicast ping test'
        tn = self.prefix + 'mc_ping'
        self.tests[tn] = McPing(a_t, dut_t_x, ipv4=True, group=group,
                                name=tn, summary=summary)

        #######################################################################
        # LSO tests
        #######################################################################
        # LSO TESTS FROM DUT TO ENDPOINT
        # Here are lso test from DUT to endpoint, which tests lso feature on
        # NFP NIC
        summary = 'LSO IPv4 test without tunneling'
        tn = self.prefix + 'lso_toA_ipv4_tcp_no_tunnel'
        self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=True, l4_type='tcp',
                                   group=group, num_pkts=1,
                                   txcsum_offload=True, name=tn,
                                   summary=summary)
        summary = 'LSO IPv6 test without tunneling'
        tn = self.prefix + 'lso_toA_ipv6_tcp_no_tunnel'
        self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=False, l4_type='tcp',
                                   group=group, num_pkts=1,
                                   txcsum_offload=True, name=tn,
                                   summary=summary)

        summary = 'LSO IPv4 test with vlan'
        tn = self.prefix + 'lso_toA_ipv4_tcp_vlan'
        self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=True, l4_type='tcp',
                                   group=group, num_pkts=1, vlan=True,
                                   txcsum_offload=True, name=tn,
                                   summary=summary)
        summary = 'LSO IPv6 test with vlan'
        tn = self.prefix + 'lso_toA_ipv6_tcp_vlan'
        self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=False, l4_type='tcp',
                                   group=group, num_pkts=1, vlan=True,
                                   txcsum_offload=True, name=tn,
                                   summary=summary)

        for lso_mtu in [576, 1280, 2000, 3000, 4096, 4148, 5000, 6000, 7000, 8000, 9216]:
            if lso_mtu >= 576:
                summary = 'LSO IPv4 MTU (%s) test without tunneling' % lso_mtu
                tn = self.prefix + 'lso_toA_ipv4_tcp_mtu_%s_no_tunnel' % lso_mtu
                self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=True,
                                           l4_type='tcp',
                                           src_mtu=lso_mtu, dst_mtu=lso_mtu,
                                           group=group, num_pkts=1,
                                           txcsum_offload=True, name=tn,
                                           summary=summary)
                summary = 'LSO IPv4 MTU (%s) test with VLAN' % lso_mtu
                tn = self.prefix + 'lso_toA_ipv4_tcp_mtu_%s_vlan' % lso_mtu
                self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=True,
                                           l4_type='tcp',
                                           src_mtu=lso_mtu, dst_mtu=lso_mtu,
                                           group=group, num_pkts=1, vlan=True,
                                           txcsum_offload=True, name=tn,
                                           summary=summary)
            if lso_mtu >= 1280:
                summary = 'LSO IPv6 MTU (%s) test without tunneling' % lso_mtu
                tn = self.prefix + 'lso_toA_ipv6_tcp_mtu_%s_no_tunnel' % lso_mtu
                self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=False,
                                           l4_type='tcp',
                                           src_mtu=lso_mtu, dst_mtu=lso_mtu,
                                           group=group, num_pkts=1,
                                           txcsum_offload=True, name=tn,
                                           summary=summary)
                summary = 'LSO IPv6 MTU (%s) test with VLAN' % lso_mtu
                tn = self.prefix + 'lso_toA_ipv6_tcp_mtu_%s_vlan' % lso_mtu
                self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=False,
                                           l4_type='tcp',
                                           src_mtu=lso_mtu, dst_mtu=lso_mtu,
                                           group=group, num_pkts=1, vlan=True,
                                           txcsum_offload=True, name=tn,
                                           summary=summary)

        summary = 'LSO IPv4 content-check test without tunneling'
        tn = self.prefix + 'lso_toA_ipv4_content_check_no_tunnel'
        self.tests[tn] = NFPFlowNICContentCheck(dut_t_x, a_t, ipv4=True,
                                                l4_type='tcp', group=group,
                                                name=tn, summary=summary)

        summary = 'LSO IPv6 content-check test without tunneling'
        tn = self.prefix + 'lso_toA_ipv6_content_check_no_tunnel'
        self.tests[tn] = NFPFlowNICContentCheck(dut_t_x, a_t, ipv4=False,
                                                l4_type='tcp', group=group,
                                                name=tn, summary=summary)

        for lso_mtu in [576, 1280, 2000, 3000, 4096, 4148, 5000, 6000, 7000, 8000, 9216]:
            if lso_mtu >= 576:
                summary = 'LSO IPv4 MTU (%s) content-check test without tunneling' % lso_mtu
                tn = self.prefix + 'lso_toA_ipv4_content_check_mtu_%s_no_tunnel' % lso_mtu
                self.tests[tn] = NFPFlowNICContentCheck(dut_t_x, a_t, ipv4=True, l4_type='tcp',
                                                        src_mtu=lso_mtu, dst_mtu=lso_mtu,
                                                        group=group, name=tn, summary=summary)

            #if lso_mtu >= 1280:
            #    summary = 'LSO IPv6 MTU (%s) content-check test without tunneling' % lso_mtu
            #    tn = 'lso_toA_ipv6_content_check_mtu_%s_no_tunnel' % lso_mtu
            #    self.tests[tn] = LSO_iperf(dut_t_x, a_t, ipv4=False, l4_type='tcp',
            #                               src_mtu=lso_mtu, dst_mtu=lso_mtu,
            #                               group=group, name=tn, summary=summary)

        summary = 'LSO iperf tests from DUT to endpoint via IPv4 vxlan tunnel'
        tn = self.prefix + 'lso_toA_vxlan_ipv4_tcp'
        self.tests[tn] = LSO_tunnel(dut_t_x, a_t, ipv4=True, l4_type='tcp',
                                    tunnel_type='vxlan', num_pkts=1,
                                    src_mtu=1500, dst_mtu=1500,
                                    txcsum_offload=True,
                                    group=group, name=tn,
                                    summary=summary)

        summary = 'LSO iperf tests from DUT to endpoint via IPv6 vxlan tunnel'
        tn = self.prefix + 'lso_toA_vxlan_ipv6_tcp'
        self.tests[tn] = LSO_tunnel(dut_t_x, a_t, ipv4=False, l4_type='tcp',
                                    tunnel_type='vxlan', num_pkts=1,
                                    src_mtu=1500, dst_mtu=1500,
                                    txcsum_offload=True,
                                    group=group, name=tn,
                                    summary=summary)

        for lso_mtu in [1500, 2000, 3000, 4096, 4148, 5000, 6000, 7000, 8000, 9216]:
            if lso_mtu >= 1500:
                summary = 'LSO iperf tests TX IPv4 MTU (%s) vxlan tunnel' % lso_mtu
                tn = self.prefix + 'lso_toA_vxlan_mtu_%s_ipv4_tcp' % lso_mtu
                self.tests[tn] = LSO_tunnel(dut_t_x, a_t, ipv4=True, l4_type='tcp',
                                            tunnel_type='vxlan', num_pkts=1,
                                            src_mtu=lso_mtu, dst_mtu=lso_mtu,
                                            txcsum_offload=True,
                                            group=group, name=tn,
                                            summary=summary)

            if lso_mtu >= 1500:
                summary = 'LSO iperf tests TX IPv6 MTU (%s) vxlan tunnel' % lso_mtu
                tn = self.prefix + 'lso_toA_vxlan_mtu_%s_ipv6_tcp' % lso_mtu
                self.tests[tn] = LSO_tunnel(dut_t_x, a_t, ipv4=False, l4_type='tcp',
                                            tunnel_type='vxlan', num_pkts=1,
                                            src_mtu=lso_mtu, dst_mtu=lso_mtu,
                                            txcsum_offload=True,
                                            group=group, name=tn,
                                            summary=summary)



        # LSO TESTS FROM ENDPOINT TO DUT
        # Here are lso test from endpoint to DUT, which are only for test
        # debugging proper (it only tests lso feature on fortville)
        # When LSO feature is ready, we need to delete these tests

        #summary = 'LSO IPv4 test without tunneling'
        #tn = 'lso_fromA_ipv4_tcp_no_tunnel'
        #self.tests[tn] = LSO_iperf(a_t, dut_t_x, ipv4=True, l4_type='tcp',
        #                           group=group, num_pkts=1,
        #                           txcsum_offload=True, name=tn,
        #                           summary=summary)
        #summary = 'LSO IPv6 test without tunneling'
        #tn = 'lso_fromA_ipv6_tcp_no_tunnel'
        #self.tests[tn] = LSO_iperf(a_t, dut_t_x, ipv4=False, l4_type='tcp',
        #                           group=group, num_pkts=1,
        #                           txcsum_offload=True, name=tn,
        #                           summary=summary)
        #
        #for lso_mtu in [576, 1280, 2000, 3000, 4096, 4148, 5000, 6000, 7000, 8000, 9216]:
        #    if lso_mtu >= 576:
        #        summary = 'LSO IPv4 MTU (%s) test without tunneling' % lso_mtu
        #        tn = 'lso_fromA_ipv4_tcp_mtu_%s_no_tunnel' % lso_mtu
        #        self.tests[tn] = LSO_iperf(a_t, dut_t_x, ipv4=True, l4_type='tcp',
        #                                   src_mtu=lso_mtu, dst_mtu=lso_mtu,
        #                                   group=group, num_pkts=1,
        #                                   txcsum_offload=True, name=tn,
        #                                   summary=summary)
        #    if lso_mtu >= 1280:
        #        summary = 'LSO IPv6 MTU (%s) test without tunneling' % lso_mtu
        #        tn = 'lso_fromA_ipv6_tcp_mtu_%s_no_tunnel' % lso_mtu
        #        self.tests[tn] = LSO_iperf(a_t, dut_t_x, ipv4=False, l4_type='tcp',
        #                                   src_mtu=lso_mtu, dst_mtu=lso_mtu,
        #                                   group=group, num_pkts=1,
        #                                   txcsum_offload=True, name=tn,
        #                                   summary=summary)
        #
        #summary = 'LSO IPv4 content-check test without tunneling'
        #tn = 'lso_fromA_ipv4_content_check_no_tunnel'
        #self.tests[tn] = NFPFlowNICContentCheck(a_t, dut_t_x, ipv4=True,
        #                                        l4_type='tcp', group=group,
        #                                        name=tn, summary=summary)
        #
        #summary = 'LSO IPv6 content-check test without tunneling'
        #tn = 'lso_fromA_ipv6_content_check_no_tunnel'
        #self.tests[tn] = NFPFlowNICContentCheck(a_t, dut_t_x, ipv4=False,
        #                                        l4_type='tcp', group=group,
        #                                        name=tn, summary=summary)
        #summary = 'LSO iperf tests from endpoint to DUT via IPv4 vxlan tunnel'
        #tn = 'lso_fromA_vxlan_ipv4_tcp'
        #self.tests[tn] = LSO_tunnel(a_t, dut_t_x, ipv4=True, l4_type='tcp',
        #                            tunnel_type='vxlan', num_pkts=1,
        #                            txcsum_offload=True,
        #                            group=group, name=tn,
        #                            summary=summary)
        #
        #summary = 'LSO iperf tests from endpoint to DUT via IPv6 vxlan tunnel'
        #tn = 'lso_fromA_vxlan_ipv6_tcp'
        #self.tests[tn] = LSO_tunnel(a_t, dut_t_x, ipv4=False, l4_type='tcp',
        #                            tunnel_type='vxlan', num_pkts=1,
        #                            txcsum_offload=True,
        #                            group=group, name=tn,
        #                            summary=summary)

        ## The following commented codes enlist only four basic tests to cover
        ## tunnel ping, tx, rx. I suggest to enable these tests first for
        ## testing the ME code as well as verifying the test code.
        #
        ########################################################################
        ## vxlan ping tests
        ########################################################################
        #summary = 'Ping tests from and to DUT via vxlan tunnel'
        #tn = 'tunnel_vxlan_ping'
        #self.tests[tn] = TunnelTest(a_t, dut_t_x, tunnel_type='vxlan',
        #                            group=group, name=tn, summary=summary)
        #
        ########################################################################
        ## vxlan tx checksum tests
        ########################################################################
        #summary = 'Iperf tests from DUT to endpoint via vxlan tunnel'
        #tn = 'tunnel_vxlan_csum_tx'
        #self.tests[tn] = Csum_Tx_tunnel(dut_t_x, a_t, ipv4=True, l4_type='udp',
        #                                tunnel_type='vxlan', num_pkts=10,
        #                                txcsum_offload=True,
        #                                group=group, name=tn,
        #                                summary=summary)
        #
        #
        #######################################################################
        ## Tunnel vxlan RSS tests
        #######################################################################
        #summary = 'RSS tests with tunnel IP packets'
        #tn = 'tunnel_vxlan_rss'
        #self.tests[tn] = RSStest_diff_inner_tuple(a_t, dut_t_x,
        #                                          outer_ipv4=True,
        #                                          outer_l4_type='udp',
        #                                          inner_ipv4=True,
        #                                          inner_l4_type='udp',
        #                                          varies_src_addr=True,
        #                                          varies_dst_addr=True,
        #                                          varies_src_port=True,
        #                                          varies_dst_port=True,
        #                                          tunnel_type='vxlan',
        #                                          outer_vlan_tag=False,
        #                                          inner_vlan_tag=False,
        #                                          group=group, name=tn,
        #                                          summary=summary)
        #
        ########################################################################
        ## Tunnel NVGRE RSS tests
        ########################################################################
        #summary = 'RSS tests with tunnel IP packets'
        #tn = 'tunnel_nvgre_rss'
        #self.tests[tn] = RSStest_diff_inner_tuple(a_t, dut_t_x,
        #                                          outer_ipv4=True,
        #                                          outer_l4_type=None,
        #                                          inner_ipv4=True,
        #                                          inner_l4_type='udp',
        #                                          varies_src_addr=True,
        #                                          varies_dst_addr=True,
        #                                          varies_src_port=True,
        #                                          varies_dst_port=True,
        #                                          tunnel_type='nvgre',
        #                                          outer_vlan_tag=False,
        #                                          inner_vlan_tag=False,
        #                                          group=group, name=tn,
        #                                          summary=summary)

        # The following commented codes enlist a number of tests to cover
        # different combination of traffic setup.
        #
        #######################################################################
        ## Tunnel TX checksum test
        ########################################################################
        def _tnl_csum_tx_hdr_tn(ipv4, l4_type, tx_offload, tunnel_type):
            """generate the tunnel csum_tx test name"""
            ipv4_str = '_ipv4' if ipv4 else '_ipv6'
            l4_str = '_%s' % l4_type
            tx_offload_str = '_tx_csum_offload' if tx_offload else ''

            return "csum_tx_tnl_%s%s%s%s" % (tunnel_type, ipv4_str, l4_str,
                                            tx_offload_str)

        def _tnl_csum_tx_hdr_sum(ipv4, l4_type, tx_offload,
                                 tunnel_type, tail):
            """generate the tunnel csum_tx test summary"""
            ip_str = 'with IPV4 ' if ipv4 else 'with IPV6 '
            ip_str += l4_type.upper() + ' pckts'
            tnl_type_str = 'through %s ' % tunnel_type.upper()
            tx_offload_str = 'and TX checksum offload enabled' if tx_offload \
                              else 'and tx checksum offload disabled'

            return "Tunnel TX checksum offload test " \
                   "%s%s%s%s" % (ip_str, tnl_type_str, tx_offload_str,
                                   tail if tail else "")

        tunnel_type = 'vxlan'
        for ipv4 in [True, False]:
            for l4_type in ['tcp', 'udp']:
                for tx_offload in [True, False]:
                    tn = self.prefix + _tnl_csum_tx_hdr_tn(ipv4, l4_type, tx_offload, tunnel_type)
                    summary = _tnl_csum_tx_hdr_sum(ipv4, l4_type, tx_offload,
                                                   tunnel_type, None)
                    self.tests[tn] = Csum_Tx_tunnel(dut_t_x, a_t, ipv4=ipv4,
                                                    l4_type=l4_type,
                                                    tunnel_type=tunnel_type,
                                                    num_pkts=10,
                                                    txcsum_offload=tx_offload,
                                                    group=group, name=tn,
                                                    summary=summary)

        #######################################################################
        # Tunnel RSS tests
        #######################################################################
        def _tnl_rss_hdr_tn(varies_src_addr, varies_dst_addr, varies_src_port,
                        varies_dst_port, ipv4, l4_type, tail, tunnel_type,
                        vlan_tag=False):
            """generate the tunnel rss test name"""
            if l4_type:
               l4_str = '_%s' % l4_type + ('_vlan' if vlan_tag else '')
            else:
               l4_str = '_vlan' if vlan_tag else ''
            return "rss_tnl%s_inner%s%s%s%s%s%s%s" % ("_%s" % tunnel_type,
                                         "_s_addr" if varies_src_addr
                                         else '',
                                         "_d_addr" if varies_dst_addr
                                         else '',
                                         "_sport" if varies_src_port
                                         else '',
                                         "_dport" if varies_dst_port
                                         else '',
                                         "_ipv4" if ipv4 else "_ipv6",
                                         l4_str,
                                         "_" + tail if tail else "")

        def _tnl_rss_hdr_sum(varies_src_addr, varies_dst_addr, varies_src_port,
                         varies_dst_port, ipv4, l4_type, tunnel_type, tail,
                         vlan_tag=False):
            """generate the tunnel rss test summary"""
            if l4_type:
               l4_str = ', and %s' % l4_type.upper() + (' with vlan tag '
                                                       if vlan_tag else '')
            else:
               l4_str =' with vlan tag 'if vlan_tag else ''
            tnl_t_str = tunnel_type.upper()
            return "Test RSS functions" \
                   "%s%s%s%s%s%s%s%s%s" % (" through %s tunnel" % tnl_t_str,
                                         ' by sending IP pckts',
                                         " with inner diff ip src addr," if
                                         varies_src_addr
                                         else ' with the inner same ip '
                                              'src addr,',
                                         " diff ip dst addr," if
                                         varies_dst_addr
                                         else ' the same ip dst addr,',
                                         " different src_ports," if
                                         varies_src_port
                                         else ' the same src_port,',
                                         " different dst_ports," if
                                         varies_dst_port
                                         else ' the same dst_port,',
                                         " IPv4 packets" if ipv4 else
                                         " IPv6 packets",
                                         l4_str,
                                         tail if tail else "")

        for (tunnel_type, l4_type) in [('vxlan', 'udp'), ('nvgre', None)]:
            for (varies_src_addr, varies_dst_addr,
                 varies_src_port, varies_dst_port) in [(True, False,
                                                        False, False),
                                                       (False, True,
                                                        False, False),
                                                       (False, False,
                                                        True, False),
                                                       (False, False,
                                                        False, True)]:
                for ipv4 in [True, False]:
                    for inner_l4_type in ['udp', 'tcp']:
                        for vlan_tag in [True, False]:
                            tn = self.prefix + _tnl_rss_hdr_tn(varies_src_addr,
                                                 varies_dst_addr,
                                                 varies_src_port,
                                                 varies_dst_port, ipv4,
                                                 inner_l4_type,
                                                 None, tunnel_type,
                                                 vlan_tag=vlan_tag)
                            summary = _tnl_rss_hdr_sum(varies_src_addr,
                                                       varies_dst_addr,
                                                       varies_src_port,
                                                       varies_dst_port,
                                                       ipv4, inner_l4_type,
                                                       tunnel_type, None,
                                                       vlan_tag=vlan_tag)
                            self.tests[tn] = RSStest_diff_inner_tuple(a_t,
                                                      dut_t_x,
                                                      outer_ipv4=True,
                                                      outer_l4_type=l4_type,
                                                      outer_vlan_tag=False,
                                                      inner_ipv4=ipv4,
                                                      inner_l4_type=
                                                      inner_l4_type,
                                                      varies_src_addr=
                                                      varies_src_addr,
                                                      varies_dst_addr=
                                                      varies_dst_addr,
                                                      varies_src_port=
                                                      varies_src_port,
                                                      varies_dst_port=
                                                      varies_dst_port,
                                                      tunnel_type=tunnel_type,
                                                      inner_vlan_tag=vlan_tag,
                                                      group=group, name=tn,
                                                      summary=summary)

        ######################################################################
        # Multiple Tunnels vxlan RSS tests
        ######################################################################
        summary = 'RSS tests with multiple tunnel IP packets'
        tn = self.prefix + 'rss_tnl_vxlan_multi_tunnel'
        self.tests[tn] = RSStest_diff_inner_tuple_multi_tunnels(a_t, dut_t_x,
                                                  outer_ipv4=True,
                                                  outer_l4_type='udp',
                                                  inner_ipv4=True,
                                                  inner_l4_type='udp',
                                                  varies_src_addr=True,
                                                  varies_dst_addr=True,
                                                  varies_src_port=True,
                                                  varies_dst_port=True,
                                                  tunnel_type='vxlan',
                                                  outer_vlan_tag=False,
                                                  inner_vlan_tag=False,
                                                  group=group, name=tn,
                                                  summary=summary)

        #######################################################################
        # RSS tests
        #######################################################################

        def _rss_hdr_tn(varies_src_addr, varies_dst_addr, varies_src_port,
                        varies_dst_port, ipv4, l4_type, modified_table, tail,
                        vlan_tag=False):
           """generate the rss test name"""
           l4_str = '_%s' % l4_type + ('_vlan' if vlan_tag else '')
           return "rss%s%s%s%s%s%s%s%s" % ("_table" if modified_table
                                        else '',
                                        "_s_addr" if varies_src_addr
                                        else '',
                                        "_d_addr" if varies_dst_addr
                                        else '',
                                        "_sport" if varies_src_port
                                        else '',
                                        "_dport" if varies_dst_port
                                        else '',
                                        "_ipv4" if ipv4 else "_ipv6",
                                        l4_str,
                                        "_" + tail if tail else "")

        def _rss_hdr_sum(varies_src_addr, varies_dst_addr, varies_src_port,
                         varies_dst_port, ipv4, l4_type, modified_table, tail,
                         vlan_tag=False):
           """generate the rss test summary"""
           l4_str = ', and %s' % l4_type.upper() + (' with vlan tag '
                                                    if vlan_tag else '')
           return "Test RSS functions" \
                  "%s%s%s%s%s%s%s%s%s" % (" with modified hash table" if
                                        modified_table
                                        else '',
                                        ' by sending IP pckts',
                                        " with diff ip src addr," if
                                        varies_src_addr
                                        else ' with the same ip src addr,',
                                        " diff ip dst addr," if
                                        varies_dst_addr
                                        else ' the same ip dst addr,',
                                        " different src_ports," if
                                        varies_src_port
                                        else ' the same src_port,',
                                        " different dst_ports," if
                                        varies_dst_port
                                        else ' the same dst_port,',
                                        " IPv4 packets" if ipv4 else
                                        " IPv6 packets",
                                        l4_str,
                                        tail if tail else "")

        def _rss_byte_hdr_tn(varies_src_addr, varies_dst_addr,
                             varies_src_byte_index, varies_dst_byte_index,
                             l4_type, vlan_tag, tail):
           """generate the rss test name"""
           l4_str = '_ipv6_%s' % l4_type
           return "rss%s%s%s%s%s" % ("_s_addr_byte_%s" % varies_src_byte_index
                                   if varies_src_addr else '',
                                   "_d_addr_byte_%s" % varies_dst_byte_index
                                   if varies_dst_addr else '',
                                   l4_str,
                                   "_vlan" if vlan_tag else '',
                                   "_" + tail if tail else "")

        def _rss_byte_hdr_sum(varies_src_addr, varies_dst_addr,
                              varies_src_byte_index, varies_dst_byte_index,
                              l4_type, vlan_tag, tail):
           """generate the rss test summary"""
           l4_str = ' IPv6 packets, %s payload' % l4_type.upper()
           return "Test RSS functions" \
                  "%s%s%s%s%s%s" % (' by sending IP pckts',
                                    " with diff byte %s in ip src addr," %
                                    varies_src_byte_index if varies_src_addr
                                    else ' with the same ip src addr,',
                                    " diff byte %s in ip dst addr," %
                                    varies_dst_byte_index if varies_dst_addr
                                    else ' the same ip dst addr,',
                                    l4_str,
                                    ' and vlan tag' if vlan_tag else
                                    '',
                                    tail if tail else "")

        for (varies_src_addr, varies_dst_addr) in [(True, False), (False, True)]:
            for byte_index in [0, 2, 4, 6]:
                varies_src_byte_index = None
                varies_dst_byte_index = None
                if varies_src_addr:
                    varies_src_byte_index = byte_index
                if varies_dst_addr:
                    varies_dst_byte_index = byte_index
                for l4_type in ['tcp', 'udp']:
                    for vlan_tag in [True, False]:
                        tn = self.prefix + _rss_byte_hdr_tn(varies_src_addr, varies_dst_addr,
                                              varies_src_byte_index,
                                              varies_dst_byte_index,
                                              l4_type, vlan_tag, None)
                        summary = _rss_byte_hdr_sum(varies_src_addr,
                                                    varies_dst_addr,
                                                    varies_src_byte_index,
                                                    varies_dst_byte_index,
                                                    l4_type, vlan_tag, None)
                        self.tests[tn] = RSStest_diff_part_l4_tuple(a_t,
                                    dut_t_x, ipv4=False, l4_type=l4_type,
                                    varies_src_addr=varies_src_addr,
                                    varies_dst_addr=varies_dst_addr,
                                    varies_src_byte_index=varies_src_byte_index,
                                    varies_dst_byte_index=varies_dst_byte_index,
                                    vlan_tag=vlan_tag, group=group,
                                    name=tn, summary=summary)


        ipv4 = True
        l4_type = 'tcp'
        varies_src_addr = True
        varies_dst_addr = True
        varies_src_port = True
        varies_dst_port = True
        modified_table = True
        tn = self.prefix + _rss_hdr_tn(varies_src_addr, varies_dst_addr,
                         varies_src_port, varies_dst_port,
                         ipv4, l4_type, modified_table, None)
        summary = _rss_hdr_sum(varies_src_addr, varies_dst_addr,
                               varies_src_port, varies_dst_port,
                               ipv4, l4_type, modified_table, None)
        self.tests[tn] = RSStest_diff_l4_tuple_modify_table(a_t,
                                    dut_t_x, ipv4=ipv4, l4_type=l4_type,
                                    varies_src_addr=varies_src_addr,
                                    varies_dst_addr=varies_dst_addr,
                                    varies_src_port=varies_src_port,
                                    varies_dst_port=varies_dst_port,
                                    group=group, name=tn, summary=summary)


        for varies_src_addr in [True, False]:
            for varies_dst_addr in [True, False]:
                for varies_src_port in [True, False]:
                    for varies_dst_port in [True, False]:
                        for ipv4 in [True, False]:
                            for l4_type in ['tcp', 'udp']:
                                modified_table = False
                                tn = self.prefix + _rss_hdr_tn(varies_src_addr,
                                                 varies_dst_addr,
                                                 varies_src_port,
                                                 varies_dst_port,
                                                 ipv4, l4_type,
                                                 modified_table, None)
                                summary = _rss_hdr_sum(varies_src_addr,
                                                       varies_dst_addr,
                                                       varies_src_port,
                                                       varies_dst_port,
                                                       ipv4, l4_type,
                                                       modified_table, None)
                                if not varies_src_addr and not varies_dst_addr \
                                        and not varies_src_port \
                                        and not varies_dst_port:
                                    self.tests[tn] = RSStest_same_l4_tuple(a_t,
                                                                dut_t_x,
                                                                ipv4=ipv4,
                                                                l4_type=l4_type,
                                                                group=group,
                                                                name=tn,
                                                                summary=summary)

                                else:
                                    self.tests[tn] = RSStest_diff_l4_tuple(a_t,
                                                               dut_t_x,
                                                               ipv4=ipv4,
                                                               l4_type=l4_type,
                                                               varies_src_addr=
                                                               varies_src_addr,
                                                               varies_dst_addr=
                                                               varies_dst_addr,
                                                               varies_src_port=
                                                               varies_src_port,
                                                               varies_dst_port=
                                                               varies_dst_port,
                                                               group=group,
                                                               name=tn,
                                                               summary=summary)

        for (varies_src_addr, varies_dst_addr, varies_src_port,
             varies_dst_port) in [(True, False, False, False),
                                  (False, True, False, False),
                                  (False, False, True, False),
                                  (False, False, False, True)]:
            for ipv4 in [True, False]:
                for l4_type in ['tcp', 'udp']:
                    modified_table = False
                    vlan_tag = True
                    tn = self.prefix + _rss_hdr_tn(varies_src_addr,
                                     varies_dst_addr,
                                     varies_src_port,
                                     varies_dst_port,
                                     ipv4, l4_type,
                                     modified_table, None,
                                     vlan_tag=vlan_tag)
                    summary = _rss_hdr_sum(varies_src_addr,
                                           varies_dst_addr,
                                           varies_src_port,
                                           varies_dst_port,
                                           ipv4, l4_type,
                                           modified_table, None,
                                           vlan_tag=vlan_tag)

                    self.tests[tn] = RSStest_diff_l4_tuple(a_t,
                                                           dut_t_x,
                                                           ipv4=ipv4,
                                                           l4_type=l4_type,
                                                           varies_src_addr=
                                                           varies_src_addr,
                                                           varies_dst_addr=
                                                           varies_dst_addr,
                                                           varies_src_port=
                                                           varies_src_port,
                                                           varies_dst_port=
                                                           varies_dst_port,
                                                           vlan_tag=vlan_tag,
                                                           group=group,
                                                           name=tn,
                                                           summary=summary)

        ########################################################################
        ## RX checksum test
        ########################################################################
        def _csum_rx_hdr_tn(ipv4, ipv4_opt, ipv6_rt, ipv6_hbh, l4_type, ip_err,
                           l4_err, promisc, tail):
           """generate the csum_rx test name"""
           l4_str = '_%s' % l4_type
           l4err_str = '_%serr' % l4_type
           return "csum_rx%s%s%s%s%s%s%s%s%s" % ("_ipv4" if ipv4 else "_ipv6",
                                                 "_opt" if ipv4_opt else "",
                                                 "_rt" if ipv6_rt else "",
                                                 "_hbh" if ipv6_hbh else "",
                                                 l4_str,
                                                 "_iperr" if ip_err else "",
                                                 l4err_str if l4_err else "",
                                                 "_promisc" if promisc else "",
                                                 "_" + tail if tail else "")

        def _csum_rx_hdr_sum(tst_cls, ipv4_opt, ipv6_rt, ipv6_hbh, l4_type,
                            ip_err, l4_err, promisc, tail):
           """generate the csum_rx test summary"""
           l4_str = ', %s payload ' % l4_type.upper()
           if ip_err and l4_err:
               err_str = " with IP and %s csum err" % l4_type.upper()
           elif ip_err:
               err_str = " with IP csum err"
           elif l4_err:
               err_str = " with %s csum err" % l4_type.upper()
           else:
               err_str = ""
           return "%s%s%s%s%s%s%s" % (tst_cls.summary,
                                      " + IP option" if ipv4_opt else "",
                                      " + IPv6 RT extension hdr"
                                      if ipv6_rt else "",
                                      " + IPv6 HOPOPT extension hdr"
                                      if ipv6_hbh else "",
                                      err_str,
                                      " in promisc mode " if promisc else "",
                                      tail if tail else "")

        src = a_t
        dst = dut_t_x
        ipv4 = True
        ipv6_rt = False
        ipv6_hbh = False
        tail = None
        for promisc in [True]:
           for ipv4_opt in [False, True]:
               for l4_type in ['icmp', 'udp', 'tcp']:
                   for ip_err in [False, True]:
                       if l4_type == 'udp' or l4_type == 'tcp':
                           for l4_err in [False, True]:
                               # An IPv4 test
                               tn = self.prefix + _csum_rx_hdr_tn(ipv4, ipv4_opt, ipv6_rt,
                                                    ipv6_hbh, l4_type, ip_err,
                                                    l4_err, promisc, tail)
                               summary = _csum_rx_hdr_sum(UnitIPv4, ipv4_opt,
                                                          ipv6_rt, ipv6_hbh,
                                                          l4_type, ip_err,
                                                          l4_err, promisc,
                                                          tail)
                               self.tests[tn] = UnitIPv4(src, dst,
                                                          ipv4_opt=ipv4_opt,
                                                          l4_type=l4_type,
                                                          iperr=ip_err,
                                                          l4err=l4_err,
                                                          promisc=promisc,
                                                          group=group, name=tn,
                                                          summary=summary)
                       else:
                           # when neither udp nor tcp are used, there is no
                           # need to insert udp/tcp checksum error
                           l4_err = False
                           tn = self.prefix + _csum_rx_hdr_tn(ipv4, ipv4_opt, ipv6_rt,
                                                ipv6_hbh, l4_type, ip_err,
                                                l4_err, promisc, tail)
                           summary = _csum_rx_hdr_sum(UnitIPv4, ipv4_opt,
                                                      ipv6_rt, ipv6_hbh,
                                                      l4_type, ip_err, l4_err,
                                                      promisc, tail)
                           self.tests[tn] = UnitIPv4(src, dst,
                                                      ipv4_opt=ipv4_opt,
                                                      l4_type=l4_type,
                                                      iperr=ip_err,
                                                      l4err=l4_err,
                                                      promisc=promisc,
                                                      group=group, name=tn,
                                                      summary=summary)
        ipv4 = False
        ipv4_opt = False
        ip_err = False
        for promisc in [True]:
           for ipv6_rt in [False, True]:
               for ipv6_hbh in [False, True]:
                   for l4_type in ['udp', 'tcp']:
                       for l4_err in [False, True]:
                           # An IPv6 test
                           tn = self.prefix + _csum_rx_hdr_tn(ipv4, ipv4_opt, ipv6_rt,
                                                ipv6_hbh, l4_type, ip_err,
                                                l4_err, promisc, tail)
                           summary = _csum_rx_hdr_sum(UnitIPv6, ipv4_opt,
                                                      ipv6_rt, ipv6_hbh,
                                                      l4_type, ip_err, l4_err,
                                                      promisc, tail)
                           self.tests[tn] = UnitIPv6(src, dst,
                                                      ipv6_rt=ipv6_rt,
                                                      ipv6_hbh=ipv6_hbh,
                                                      l4_type=l4_type,
                                                      l4err=l4_err,
                                                      promisc=promisc,
                                                      group=group, name=tn,
                                                      summary=summary)

        ########################################################################
        ## RX checksum tunnel test
        ########################################################################
        def _csum_rx_tnl_hdr_tn(tunnel, ipv4, ipv4_opt, ipv6_rt, ipv6_hbh,
                                l4_type, ip_err, l4_err, promisc, tail):
           """generate the csum_rx test name"""
           l4_str = '_%s' % l4_type
           l4err_str = '_%serr' % l4_type
           return "csum_rx%s%s%s%s%s%s%s%s%s%s" % ("_%s" % tunnel,
                                                 "_ipv4" if ipv4 else "_ipv6",
                                                 "_opt" if ipv4_opt else "",
                                                 "_rt" if ipv6_rt else "",
                                                 "_hbh" if ipv6_hbh else "",
                                                 l4_str,
                                                 "_iperr" if ip_err else "",
                                                 l4err_str if l4_err else "",
                                                 "_promisc" if promisc else "",
                                                 "_" + tail if tail else "")

        def _csum_rx_tnl_hdr_sum(tst_cls, tunnel, ipv4_opt, ipv6_rt, ipv6_hbh,
                                 l4_type, ip_err, l4_err, promisc, tail):
           """generate the csum_rx test summary"""
           l4_str = ', %s payload ' % l4_type.upper()
           if ip_err and l4_err:
               err_str = " with IP and %s csum err" % l4_type.upper()
           elif ip_err:
               err_str = " with IP csum err"
           elif l4_err:
               err_str = " with %s csum err" % l4_type.upper()
           else:
               err_str = ""
           return "%s%s%s%s%s%s%s%s" % (tst_cls.summary,
                                      " + IP option" if ipv4_opt else "",
                                      " + IPv6 RT extension hdr"
                                      if ipv6_rt else "",
                                      " + IPv6 HOPOPT extension hdr"
                                      if ipv6_hbh else "",
                                      err_str,
                                      " in promisc mode " if promisc else "",
                                      tail if tail else "",
                                      " in %s tunnel" % tunnel)

        src = a_t
        dst = dut_t_x
        ipv4 = True
        ipv6_rt = False
        ipv6_hbh = False
        tail = None
        for tunnel in ['vxlan']:
            # add nvgre later
            for promisc in [True]:
               for ipv4_opt in [False, True]:
                   for l4_type in ['icmp', 'udp', 'tcp']:
                       for ip_err in [False, True]:
                           if l4_type == 'udp' or l4_type == 'tcp':
                               for l4_err in [False, True]:
                                   # An IPv4 test
                                   tn = self.prefix + _csum_rx_tnl_hdr_tn(tunnel, ipv4,
                                                            ipv4_opt, ipv6_rt,
                                                            ipv6_hbh, l4_type,
                                                            ip_err, l4_err,
                                                            promisc, tail)
                                   summary = _csum_rx_tnl_hdr_sum(UnitIPv4,
                                                                  tunnel,
                                                                  ipv4_opt,
                                                                  ipv6_rt,
                                                                  ipv6_hbh,
                                                                  l4_type,
                                                                  ip_err,
                                                                  l4_err,
                                                                  promisc, tail)
                                   self.tests[tn] = Csum_rx_tnl(src, dst,
                                                             tunnel_type=tunnel,
                                                             ipv4_opt=ipv4_opt,
                                                             l4_type=l4_type,
                                                             iperr=ip_err,
                                                             l4err=l4_err,
                                                             promisc=promisc,
                                                             group=group,
                                                             name=tn,
                                                             summary=summary)

                           else:
                               # when neither udp nor tcp are used, there is no
                               # need to insert udp/tcp checksum error
                               l4_err = False
                               tn = self.prefix + _csum_rx_tnl_hdr_tn(tunnel, ipv4, ipv4_opt,
                                                        ipv6_rt, ipv6_hbh,
                                                        l4_type, ip_err,
                                                        l4_err, promisc, tail)
                               summary = _csum_rx_tnl_hdr_sum(UnitIPv4,
                                                              tunnel,
                                                              ipv4_opt,
                                                              ipv6_rt, ipv6_hbh,
                                                              l4_type, ip_err,
                                                              l4_err, promisc,
                                                              tail)
                               self.tests[tn] = Csum_rx_tnl(src, dst,
                                                            tunnel_type=tunnel,
                                                            ipv4=True,
                                                            ipv4_opt=ipv4_opt,
                                                            l4_type=l4_type,
                                                            iperr=ip_err,
                                                            l4err=l4_err,
                                                            promisc=promisc,
                                                            group=group,
                                                            name=tn,
                                                            summary=summary)
            ipv4 = False
            ipv4_opt = False
            ip_err = False
            # no support for IPV6 RT/HBH over tunnels
            for promisc in [True]:
               for ipv6_rt in [False]:
                   for ipv6_hbh in [False]:
                       for l4_type in ['udp', 'tcp']:
                           for l4_err in [False, True]:
                               # An IPv6 test
                               tn = self.prefix + _csum_rx_tnl_hdr_tn(tunnel, ipv4, ipv4_opt,
                                                        ipv6_rt, ipv6_hbh,
                                                        l4_type, ip_err,
                                                        l4_err, promisc, tail)
                               summary = _csum_rx_tnl_hdr_sum(UnitIPv6,
                                                              tunnel,
                                                              ipv4_opt,
                                                              ipv6_rt,
                                                              ipv6_hbh,
                                                              l4_type, ip_err,
                                                              l4_err, promisc,
                                                              tail)
                               self.tests[tn] = Csum_rx_tnl(src, dst,
                                                            tunnel_type=tunnel,
                                                            ipv4=False,
                                                            ipv6_rt=ipv6_rt,
                                                            ipv6_hbh=ipv6_hbh,
                                                            l4_type=l4_type,
                                                            l4err=l4_err,
                                                            promisc=promisc,
                                                            group=group,
                                                            name=tn,
                                                            summary=summary)


        #######################################################################
        # Promiscuous mode test
        #######################################################################
        def _promisc_hdr_tn(promisc, ipv4, l4_type, dst_mac_type, src_mac_type,
                            ip_err, l4_err,tail):
            """generate the promisc test name"""
            promisc_str = '_on' if promisc else '_off'
            ipv4_str = '_ipv4' if ipv4 else '_ipv6'
            l4_str = '_%s' % l4_type
            l4err_str = '_%serr' % l4_type
            iperr_str = '_iperr' if ip_err else ''
            dst_mac_str = '_to_%s' % dst_mac_type
            src_mac_str = '_from_%s' % src_mac_type

            return "promisc%s%s%s%s%s%s%s%s" % (promisc_str, ipv4_str, l4_str,
                                                src_mac_str, dst_mac_str,
                                                iperr_str,
                                                l4err_str if l4_err else "",
                                                "_" + tail if tail else "")

        def _promisc_hdr_sum(tst_cls, promisc, ipv4, l4_type, dst_mac_type,
                             src_mac_type, ip_err, l4_err, tail):
            """generate the promisc test summary"""
            if ip_err and l4_err:
                err_str = " with IP and %s csum err" % l4_type.upper()
            elif ip_err:
                err_str = " with IP csum err"
            elif l4_err:
                err_str = " with %s csum err" % l4_type.upper()
            else:
                err_str = ""

            promisc_str = " in promisc mode" if promisc else ""
            if src_mac_type == 'src':
                src_mac_str = ' from src MAC addr'
            else:
                src_mac_str = ' from a %s src MAC addr' % src_mac_type
            if dst_mac_type == 'tgt':
                dst_mac_str = ' to the tgt MAC addr'
            else:
                dst_mac_str = ' to a %s dst MAC addr' % dst_mac_type

            return "%s%s%s%s%s%s" % (tst_cls.summary,
                                     src_mac_str, dst_mac_str, err_str,
                                     promisc_str,
                                     tail if tail else "")

        src = a_t
        dst = dut_t_x
        ipv4 = True
        l4_type = 'tcp'
        tail = None
        for promisc in [False, True]:
            for (src_mac_type, dst_mac_type) in [("src", "tgt"),
                                                 ("src", "diff"),
                                                 ("src", "mc"),
                                                 ("src", "bc"),
                                                 ("bc", "tgt"),
                                                 ("mc", "tgt")]:
                if src_mac_type == 'src' and dst_mac_type == 'tgt':
                    # Enable these when rx checksum offload is ready
                    #for (ip_err, l4_err) in [(False, False),
                    #                         (True, False),
                    #                         (False, True)]:
                    for (ip_err, l4_err) in [(False, False)]:
                        tn = self.prefix + _promisc_hdr_tn(promisc, ipv4, l4_type,
                                             dst_mac_type, src_mac_type,
                                             ip_err, l4_err, tail)
                        summary = _promisc_hdr_sum(UnitIPv4, promisc, ipv4,
                                                   l4_type, dst_mac_type,
                                                   src_mac_type, ip_err,
                                                   l4_err, tail)
                        self.tests[tn] = UnitIPv4(src, dst,
                                                   l4_type=l4_type,
                                                   iperr=ip_err, l4err=l4_err,
                                                   src_mac_type=src_mac_type,
                                                   dst_mac_type=dst_mac_type,
                                                   promisc=promisc,
                                                   group=group, name=tn,
                                                   summary=summary)
                else:
                    ip_err = False
                    l4_err = False
                    tn = self.prefix + _promisc_hdr_tn(promisc, ipv4, l4_type, dst_mac_type,
                                         src_mac_type, ip_err, l4_err, tail)
                    summary = _promisc_hdr_sum(UnitIPv4, promisc, ipv4,
                                               l4_type, dst_mac_type,
                                               src_mac_type, ip_err,
                                               l4_err, tail)
                    self.tests[tn] = UnitIPv4(src, dst,
                                               l4_type=l4_type,
                                               iperr=ip_err, l4err=l4_err,
                                               src_mac_type=src_mac_type,
                                               dst_mac_type=dst_mac_type,
                                               promisc=promisc,
                                               group=group, name=tn,
                                               summary=summary)

        #######################################################################
        ## TX checksum test
        ########################################################################
        def _csum_tx_hdr_tn(ipv4, l4_type, vlan_offload, vlan):
            """generate the csum_tx test name"""
            ipv4_str = '_ipv4' if ipv4 else '_ipv6'
            l4_str = '_%s' % l4_type
            if vlan:
                vlan_str = '_vlan_tag'
                vlan_str += '_txvlan_offld' if vlan_offload \
                    else '_no_txvlan_offld'
            else:
                vlan_str = '_no_vlan_tag'

            return "csum_tx%s%s%s" % (ipv4_str, l4_str, vlan_str)

        def _csum_tx_hdr_sum(tst_cls, ipv4, l4_type, vlan_offload, vlan, tail):
            """generate the csum_tx test summary"""
            ip_str = ' with IPV4 ' if ipv4 else ' with IPV6 '
            ip_str += l4_type.upper() + ' pckts'

            vlan_str = (' with' if vlan else ' without') + ' VLAN tag'

            if vlan_offload:
                vlan_str += ' + TX VLAN offload enable'
            else:
                vlan_str += ' + TX VLAN offload disable'

            return "%s%s%s%s" % (tst_cls.summary, ip_str, vlan_str,
                                 tail if tail else "")

        dst = a_t
        src = dut_t_x
        num_pkts = 10
        for ipv4 in [True, False]:
            for l4_type in ['udp', 'tcp']:
                # Use this for loop to test TxVlan when it is ready
                for (vlan_offload, vlan) in [(False, False), (False, True),
                                             (True, True)]:
                #for (vlan_offload, vlan) in [(False, False)]:
                    tn = self.prefix + _csum_tx_hdr_tn(ipv4, l4_type, vlan_offload, vlan)
                    summary = _csum_tx_hdr_sum(Csum_Tx, ipv4, l4_type,
                                               vlan_offload, vlan, None)
                    self.tests[tn] = Csum_Tx(src, dst, ipv4=ipv4,
                                              l4_type=l4_type,
                                              vlan_offload=vlan_offload,
                                              vlan=vlan, num_pkts=num_pkts,
                                              group=group, name=tn,
                                              summary=summary)

       #######################################################################
        # MTU ping test
        #######################################################################
        # for a given ping size S (ping -s S), the minimum MTU is (S + 28)
        # 20 for the IP header and 8 for the ICMP header
        diff_ping_mtu = 28

        src = a_t
        dst = dut_t_x

        def mtu_to_ping(mtu_value):
            return mtu_value - diff_ping_mtu

        def _mtu_ping_hdr_tn(src_mtu, dst_mtu, ping_size, ping_drop):
            """generate the mtu_ping test name"""
            drop_str = '_drop' if ping_drop else '_recv'
            src_mtu_str = '_s_%d' % src_mtu
            dst_mtu_str = '_d_%d' % dst_mtu
            ping_size_str = '_p_%d' % ping_size

            return "mtu_ping%s%s%s%s" % (drop_str, src_mtu_str, dst_mtu_str,
                                         ping_size_str)

        def _mtu_ping__hdr_sum(tst_cls, src_mtu, dst_mtu, ping_size, ping_drop,
                               tail=None):
            """generate the mtu_ping test summary"""

            drop_str = ' (pckt dropping)' if ping_drop \
                       else ' (pckt receiving)'
            src_mtu_str = ' with src MTU = %d' % src_mtu
            dst_mtu_str = ' + dst MTU = %d' % dst_mtu
            ping_size_str = ' + ping pckt size = %d' % ping_size

            return "%s%s%s%s%s%s" % (tst_cls.summary,
                                     drop_str, src_mtu_str, dst_mtu_str,
                                     ping_size_str,
                                     tail if tail else "")

        for src_mtu in [68, 600, 1500, 3000, 6000, 9000]:
            for dst_mtu in [68, 600, 1500, 3000, 6000, 9000]:
                ping_size = mtu_to_ping(src_mtu)
                ping_drop = True if (src_mtu > dst_mtu) else False
                tn = self.prefix + _mtu_ping_hdr_tn(src_mtu, dst_mtu, ping_size, ping_drop)
                summary = _mtu_ping__hdr_sum(UnitPing, src_mtu, dst_mtu,
                                             ping_size, ping_drop)
                self.tests[tn] = UnitPing(src, dst,
                                           src_mtu=src_mtu,
                                           dst_mtu=dst_mtu,
                                           ping_drop=ping_drop,
                                           ping_size=ping_size,
                                           group=group, name=tn,
                                           summary=summary)
                if src_mtu == dst_mtu:
                    ping_size = mtu_to_ping(src_mtu) + 1
                    ping_drop = True
                    tn = self.prefix + _mtu_ping_hdr_tn(src_mtu, dst_mtu, ping_size,
                                          ping_drop)
                    summary = _mtu_ping__hdr_sum(UnitPing, src_mtu, dst_mtu,
                                                 ping_size, ping_drop)
                    self.tests[tn] = UnitPing(src, dst,
                                               src_mtu=src_mtu,
                                               dst_mtu=dst_mtu,
                                               ping_drop=ping_drop,
                                               ping_size=ping_size,
                                               group=group, name=tn,
                                               summary=summary)

        #Jumbo_frame_test
        src_mtu = 9000
        dst_mtu = 9000
        tn = self.prefix + 'mtu_jumbo_frame_cmp_toA'
        summary = 'Send and compare Jumbo frame packets from Host A to DUT'
        self.tests[tn] = JumboPacket(dut_t_x, a_t, group=group,
                                      src_mtu=src_mtu, dst_mtu=dst_mtu,
                                      jumbo_frame=True, name=tn,
                                      summary=summary)
        tn = self.prefix + 'mtu_jumbo_frame_cmp_fromA'
        summary = 'Send and compare Jumbo frame packets from DUT to Host A'
        self.tests[tn] = JumboPacket(a_t, dut_t_x, group=group,
                                      src_mtu=src_mtu, dst_mtu=dst_mtu,
                                      jumbo_frame=True, name=tn,
                                      summary=summary)
        tn = 'mtu_jumbo_frame_cmp_fromA_rss'
        summary = 'Send and compare Jumbo UDP packet from DUT to Host A with RSS'
        self.tests[tn] = JumboPacket(a_t, dut_t_x, group=group,
                                     src_mtu=src_mtu, dst_mtu=dst_mtu,
                                     force_rss=True, jumbo_frame=True, name=tn,
                                     summary=summary)

        #######################################################################
        # rxvlan test
        #######################################################################
        def _rxvlan_hdr_tn(vlan_offload, vlan):
            """generate the rxvlan test name"""
            offload_str = '_enable' if vlan_offload else '_disable'
            tag_str = '_vlantag' if vlan else '_no_vlantag'

            return "rxvlan_offload%s%s" % (offload_str, tag_str)

        def _rxvlan_hdr_sum(tst_cls, vlan_offload, vlan, tail=None):
            """generate the rxvlan test summary"""

            offload_str = ', rxVLAN offload is ' + ('enabled' if vlan_offload
                                                    else 'disabled')
            tag_str = 'with VLAN tag inserted' if vlan else 'without VLAN ' \
                                                            'tag inserted'

            return "%s%s%s%s" % (tst_cls.summary, tag_str, offload_str,
                                 tail if tail else "")

        for vlan_offload in [False, True]:
            for vlan in [False, True]:
                tn = self.prefix + _rxvlan_hdr_tn(vlan_offload, vlan)
                summary = _rxvlan_hdr_sum(RxVlan, vlan_offload, vlan)
                self.tests[tn] = RxVlan(a_t, dut_t_x, group=group,
                                         vlan_offload=vlan_offload, vlan=vlan,
                                         name=tn, summary=summary)

        tn = self.prefix + 'rxvlan_offload_check_rx_byte'
        summary = 'Send IP packets with and without RXVLAN offload, check ' \
                  'rx_byte counters'
        self.tests[tn] = RxVlan_rx_byte(a_t, dut_t_x, group=group,
                                 name=tn, summary=summary)


        #######################################################################
        # statistic tests
        #######################################################################
        # statistic rx_error test
        def _stats_cntr_rx_err_hdr_tn(src_mtu, dst_mtu, pck_size):
            """generate the stats_rx_err test name"""
            if dst_mtu < pck_size and src_mtu > pck_size:
                err_str = '_expect_rx_err'
            else:
                err_str = '_no_rx_err'

            return "stats_cntr_rx_err%s" % err_str

        def _stats_cntr_rx_err_hdr_sum(tst_cls, src_mtu, dst_mtu, pck_size,
                                  tail=None):
            """generate the stats_rx_err test summary"""

            mtu_str = '(src MTU %d; dst MTU  %d; ' \
                      'pck_size %d. ' % (src_mtu, dst_mtu, pck_size)
            if dst_mtu < pck_size and src_mtu > pck_size:
                err_str = ' dev_rx_errors increases. )'
            else:
                err_str = ' No dev_rx_errors increase. )'

            return "%s%s%s%s" % (tst_cls.summary, mtu_str, err_str,
                                 tail if tail else "")

        for (src_mtu, dst_mtu, pck_size) in [(2000, 1500, 1500),
                                             (2000, 1500, 1501)]:
            tn = self.prefix + _stats_cntr_rx_err_hdr_tn(src_mtu, dst_mtu, pck_size)
            summary = _stats_cntr_rx_err_hdr_sum(Stats_rx_err_cnt, src_mtu,
                                                 dst_mtu, pck_size)
            self.tests[tn] = Stats_rx_err_cnt(a_t, dut_t_x,
                                               l4_type=l4_type,
                                               src_mtu=src_mtu,
                                               dst_mtu=dst_mtu,
                                               payload_size=pck_size,
                                               group=group, name=tn,
                                               summary=summary)

        tn = self.prefix + 'stats_cntr_per_queue_cntr'
        summary = 'Stats tests: check per queue counters'
        self.tests[tn] = Stats_per_queue_cntr(a_t, dut_t_x, ipv4=True,
                                               l4_type='tcp',group=group,
                                               name=tn, summary=summary)

        #######################################################################
        # Link state monitoring test
        #######################################################################

        tn = self.prefix + 'link_state_monitoring'
        summary = 'Power down and up the PHY of the NIC and check the link ' \
                  'state'

        self.tests[tn] = LinkState(dut_t_x, a_t, group=group, name=tn,
                                               summary=summary)

        #######################################################################
        # Driver and firmware loading performance test
        #######################################################################
        tn = self.prefix + 'kmod_ld_perf'
        summary = 'Measuring the time to load driver and firmware in ' \
                  'kernel mode. '
        self.tests[tn] = Kmod_perf(dut_t_x, a_t, target_time=1.0, group=group,
                                    name=tn, summary=summary)

        tn = "null"
        self.tests[tn] = NullTest(group, tn)

'''
        #######################################################################
        # cfg changes tests
        #######################################################################
        tn = 'cfg_simple_down_up'
        self.tests[tn] = NFPFlowNICCfgUnitTest(dut_t_x, a_t, group=group,
                                                name=tn,
                                                summary="Unit tests for "
                                                        "configuration "
                                                        "changes.")

        for ring_size in [256, 512, 1024, 2048]:
            tn = 'cfg_ring_%d_iperf' % ring_size
            summary = '%s with ring_size = %d' % (Ring_size.summary, ring_size)
            self.tests[tn] = Ring_size(a_t, dut_t_x, iperf_time=30,
                                        tx_ring_size=ring_size,
                                        rx_ring_size=ring_size, group=group,
                                        name=tn, summary=summary)

        #######################################################################
        # Gather DMA test
        #######################################################################
        tn = 'gather_dma'
        self.tests[tn] = NFPFlowNICGatherDMA(dut_t_x, a_t, group=group,
                                              name=tn,
                                              summary="Unit test for gather "
                                                      "DMA.")
'''


###########################################################################
# Unit Tests
###########################################################################
class NFPFlowNICUnit_2_port(_NFPFlowNIC_2port):
    """Unit tests for the NFPFlowNIC Software Group"""

    summary = "Unit tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNIC_2port.__init__(self, name, cfg=cfg, quick=quick,
                                   dut_object=dut_object)

        ping_dut = (self.dut, self.eth_x)
        ping_a_t = (self.host_a, self.eth_a)

        dut_t_x = (self.dut, self.addr_x, self.eth_x, self.addr_v6_x,
                   self.rss_key, self.rm_nc_bin)
        a_t = (self.host_a, self.addr_a, self.eth_a, self.addr_v6_a, None,
               self.rm_nc_bin)

        self.unit_dict = Unit_dict(self, dut_t_x, a_t,
                                   ping_dut, ping_a_t, prefix='port_a_')
        self._tests = self.unit_dict.tests

        ping_dut = (self.dut, self.eth_y)
        ping_b_t = (self.host_b, self.eth_b)

        dut_t_y = (self.dut, self.addr_y, self.eth_y, self.addr_v6_y,
                   self.rss_key, self.rm_nc_bin)
        b_t = (self.host_b, self.addr_b, self.eth_b, self.addr_v6_b, None,
               self.rm_nc_bin)

        self.unit_dict = Unit_dict(self, dut_t_y, b_t,
                                   ping_dut, ping_b_t, prefix='port_b_')
        self._tests.update(self.unit_dict.tests)

