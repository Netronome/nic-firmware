##
## Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Unit test group for the NFPFlowNIC Software Group.
"""

import collections
from netro.tests.null import NullTest
from netro.tests.iperf import Iperf
from perf import NfpflownicIperf, LsoIperf, LsoIperf_multiport
from ...nfpflownic_tests import _NFPFlowNICPerfTest, \
    _NFPFlowNICPerfTest_nport, _NFPFlowNICPerfTest_nport_no_fw_loading


###########################################################################
# Perf Tests
###########################################################################
class NFPFlowNICPerfTest(_NFPFlowNICPerfTest):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest.__init__(self, name, cfg=cfg, quick=quick,
                             dut_object=dut_object)

        ping_dut = (self.dut, self.eth_x)
        ping_a_t = (self.host_a, self.eth_a)

        dut_t_x = (self.dut, self.addr_x, self.eth_x, self.addr_v6_x)
        a_t = (self.host_a, self.addr_a, self.eth_a, self.addr_v6_a)

        self.perf_dict = Perf_dict(self, dut_t_x, a_t,
                                   ping_dut, ping_a_t)
        self._tests = self.perf_dict.tests


class Perf_dict(object):
    """
    dictionary class for sharing test dictionary in unit groups
    """
    def __init__(self, group, dut_t_x, a_t, ping_dut, ping_a_t):
        """
        generating test dictionary for unit groups
        """
        self.tests = collections.OrderedDict()

        #######################################################################
        # Basic iperf test
        #######################################################################
        # TODO: use several different number of connections, different MSS

        combos = (("toA", ping_dut, ping_a_t), ("fromA", ping_a_t, ping_dut))

        for postf, src, dst in combos:
            tn = "iperf_%s" % postf
            if postf != "bidir":
                self.tests[tn] = NfpflownicIperf(src, dst, multi=16,
                                                 group=group, name=tn,
                                                 summary="Iperf %s" % postf)
            else:
                self.tests[tn] = NfpflownicIperf(src, dst, bidirect=True,
                                                 multi=16, group=group,
                                                 name=tn,
                                                 summary="Iperf %s" % postf)
        iperf_time = 30
        for mtu in [1500, 9000]:
            for multi in [None, 2, 4, 8, 16]:
                for lso_on in [True, False]:
                    tn = 'lso_iperf_toA%s%s%s' \
                         % ("_mtu_%s" % mtu,
                            "_lso_on" if lso_on else "_lso_off",
                            "_multi_%s" % multi if multi else "_single")
                    summary = 'LSO Iperf test toA with %s %s %s' \
                              % ("MTU %s" % mtu,
                                 "LSO on" if lso_on else "LSO off",
                                 "and %s threads" % multi if multi else
                                 "and single thread")
                    self.tests[tn] = LsoIperf(ping_dut, ping_a_t, lso_on=lso_on,
                                              multi=multi, group=group, name=tn,
                                              time=iperf_time, mtu=mtu,
                                              nfp_host='src',
                                              summary=summary)
        for mtu in [1500, 9000]:
            for multi in [None, 2, 4, 8, 16]:
                for lso_on in [True, False]:
                    tn = 'lso_iperf_fromA%s%s%s' \
                         % ("_mtu_%s" % mtu,
                            "_lso_on" if lso_on else "_lso_off",
                            "_multi_%s" % multi if multi else "_single")
                    summary = 'LSO Iperf test fromA with %s %s %s' % \
                              ("MTU %s" % mtu,
                               "LSO on" if lso_on else "LSO off",
                               "and %s threads" % multi if multi else
                               "and single thread")
                    self.tests[tn] = LsoIperf(ping_a_t, ping_dut, lso_on=lso_on,
                                              multi=multi, group=group, name=tn,
                                              time=iperf_time, mtu=mtu,
                                              nfp_host='dst',
                                              summary=summary)

        #Bidirectional perf tests
        #for mtu in [1500, 9000]:
        #    for multi in [None, 2, 4, 8, 16]:
        #        for lso_on in [True, False]:
        #            tn = 'lso_iperf_bidirect_toA%s%s%s' \
        #                 % ("_mtu_%s" % mtu,
        #                    "_lso_on" if lso_on else "_lso_off",
        #                    "_multi_%s" % multi if multi else "_single")
        #            summary = 'LSO Iperf bidirect test toA with %s %s %s' \
        #                      % ("MTU %s" % mtu,
        #                         "LSO on" if lso_on else "LSO off",
        #                         "and %s threads" % multi if multi else
        #                         "and single thread")
        #            self.tests[tn] = LsoIperf(ping_dut, ping_a_t, lso_on=lso_on,
        #                                      bidirect=True,
        #                                      multi=multi, group=group, name=tn,
        #                                      time=iperf_time, mtu=mtu,
        #                                      nfp_host='src',
        #                                      summary=summary)

        #Bidirectional perf tests
        #for mtu in [1500, 9000]:
        #    for multi in [None, 2, 4, 8, 16]:
        #        for lso_on in [True, False]:
        #            tn = 'lso_iperf_bidirect_fromA%s%s%s' \
        #                 % ("_mtu_%s" % mtu,
        #                    "_lso_on" if lso_on else "_lso_off",
        #                    "_multi_%s" % multi if multi else "_single")
        #            summary = 'LSO Iperf bidirect test fromA with %s %s %s' % \
        #                      ("MTU %s" % mtu,
        #                       "LSO on" if lso_on else "LSO off",
        #                       "and %s threads" % multi if multi else
        #                       "and single thread")
        #            self.tests[tn] = LsoIperf(ping_a_t, ping_dut, lso_on=lso_on,
        #                                      bidirect=True,
        #                                      multi=multi, group=group, name=tn,
        #                                      time=iperf_time, mtu=mtu,
        #                                      nfp_host='dst',
        #                                      summary=summary)

        tn = "null"
        self.tests[tn] = NullTest(group, tn)


class Perf_dict_nport(object):
    """
    dictionary class for sharing test dictionary in unit groups
    """
    def __init__(self, group, dut_t_x, a_t, ping_dut, ping_a_t,
                 port_number):
        """
        generating test dictionary for unit groups
        """
        self.tests = collections.OrderedDict()

        #######################################################################
        # Basic iperf test
        #######################################################################
        # TODO: use several different number of connections, different MSS

        combos = (("toA", ping_dut, ping_a_t), ("fromA", ping_a_t, ping_dut))

        self.port_number = port_number
        iperf_time = 30
        for mtu in [1500, 9000]:
            for multi in [None, 2, 4, 8, 16]:
                for lso_on in [True, False]:
                    tn = 'lso_iperf_2port_toEP%s%s%s' \
                         % ("_mtu_%s" % mtu,
                            "_lso_on" if lso_on else "_lso_off",
                            "_multi_%s" % multi if multi else "_single")
                    summary = 'LSO Iperf 2port test toEP with %s %s %s' \
                              % ("MTU %s" % mtu,
                                 "LSO on" if lso_on else "LSO off",
                                 "and %s threads" % multi if multi else
                                 "and single thread")
                    self.tests[tn] = LsoIperf_multiport(dut_t_x, a_t,
                                                        port_number=self.port_number,
                                                        lso_on=lso_on,
                                                        multi=multi,
                                                        group=group,
                                                        name=tn,
                                                        time=iperf_time, mtu=mtu,
                                                        nfp_host='src',
                                                        summary=summary)
        for mtu in [1500, 9000]:
            for multi in [None, 2, 4, 8, 16]:
                for lso_on in [True, False]:
                    tn = 'lso_iperf_2port_fromEP%s%s%s' \
                         % ("_mtu_%s" % mtu,
                            "_lso_on" if lso_on else "_lso_off",
                            "_multi_%s" % multi if multi else "_single")
                    summary = 'LSO Iperf 2port test fromEP with %s %s %s' % \
                              ("MTU %s" % mtu,
                               "LSO on" if lso_on else "LSO off",
                               "and %s threads" % multi if multi else
                               "and single thread")
                    self.tests[tn] = LsoIperf_multiport(dut_t_x, a_t,
                                                        port_number=self.port_number,
                                                        lso_on=lso_on,
                                                        multi=multi,
                                                        group=group,
                                                        name=tn,
                                                        time=iperf_time, mtu=mtu,
                                                        nfp_host='dst',
                                                        summary=summary)


        tn = "null"
        self.tests[tn] = NullTest(group, tn)


###########################################################################
# multi-port Perf Tests
###########################################################################
class NFPFlowNICPerfTest_2port(_NFPFlowNICPerfTest_nport):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest_nport.__init__(self, name, cfg=cfg, quick=quick,
                                           dut_object=dut_object,
                                           expected_ports=2)

        ping_dut = []
        ping_ep = []

        dut_t_x = []
        a_t = []

        for i in range(0, self.expected_ports):
            ping_dut.append((self.dut, self.eth_d[i]))
            ping_ep.append((self.host_ep[i], self.eth_ep[i]))

            dut_t_x.append((self.dut, self.addr_d[i], self.eth_d[i],
                       self.addr_v6_d[i], self.rss_key, self.rm_nc_bin))
            a_t.append((self.host_ep[i], self.addr_ep[i], self.eth_ep[i],
                   self.addr_v6_ep[i], None, self.rm_nc_bin))

        self.perf_dict = Perf_dict_nport(self, dut_t_x, a_t,
                                         ping_dut, ping_ep, 2)
        self._tests = self.perf_dict.tests


class NFPFlowNICPerfTest_4port(_NFPFlowNICPerfTest_nport):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest_nport.__init__(self, name, cfg=cfg, quick=quick,
                                           dut_object=dut_object,
                                           expected_ports=4)

        ping_dut = []
        ping_ep = []

        dut_t_x = []
        a_t = []

        for i in range(0, self.expected_ports):
            ping_dut.append((self.dut, self.eth_d[i]))
            ping_ep.append((self.host_ep[i], self.eth_ep[i]))

            dut_t_x.append((self.dut, self.addr_d[i], self.eth_d[i],
                       self.addr_v6_d[i], self.rss_key, self.rm_nc_bin))
            a_t.append((self.host_ep[i], self.addr_ep[i], self.eth_ep[i],
                   self.addr_v6_ep[i], None, self.rm_nc_bin))

        self.perf_dict = Perf_dict_nport(self, dut_t_x, a_t,
                                         ping_dut, ping_ep, 4)
        self._tests = self.perf_dict.tests


class NFPFlowNICPerfTest_8port(_NFPFlowNICPerfTest_nport):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest_nport.__init__(self, name, cfg=cfg, quick=quick,
                                           dut_object=dut_object,
                                           expected_ports=8)

        ping_dut = []
        ping_ep = []

        dut_t_x = []
        a_t = []

        for i in range(0, self.expected_ports):
            ping_dut.append((self.dut, self.eth_d[i]))
            ping_ep.append((self.host_ep[i], self.eth_ep[i]))

            dut_t_x.append((self.dut, self.addr_d[i], self.eth_d[i],
                       self.addr_v6_d[i], self.rss_key, self.rm_nc_bin))
            a_t.append((self.host_ep[i], self.addr_ep[i], self.eth_ep[i],
                   self.addr_v6_ep[i], None, self.rm_nc_bin))

        self.perf_dict = Perf_dict_nport(self, dut_t_x, a_t,
                                         ping_dut, ping_ep, 8)
        self._tests = self.perf_dict.tests

###########################################################################
# multi-port no-fw-loading Perf Tests
###########################################################################
class NFPFlowNICPerfTest_2_no_fw_ld(_NFPFlowNICPerfTest_nport_no_fw_loading):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest_nport_no_fw_loading.__init__(self, name, cfg=cfg,
                                                         quick=quick,
                                                         dut_object=dut_object,
                                                         expected_ports=2)

        ping_dut = []
        ping_ep = []

        dut_t_x = []
        a_t = []

        for i in range(0, self.expected_ports):
            ping_dut.append((self.dut, self.eth_d[i]))
            ping_ep.append((self.host_ep[i], self.eth_ep[i]))

            dut_t_x.append((self.dut, self.addr_d[i], self.eth_d[i],
                       self.addr_v6_d[i], self.rss_key, self.rm_nc_bin))
            a_t.append((self.host_ep[i], self.addr_ep[i], self.eth_ep[i],
                   self.addr_v6_ep[i], None, self.rm_nc_bin))

        self.perf_dict = Perf_dict_nport(self, dut_t_x, a_t,
                                         ping_dut, ping_ep, 2)
        self._tests = self.perf_dict.tests


class NFPFlowNICPerfTest_4_no_fw_ld(_NFPFlowNICPerfTest_nport_no_fw_loading):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest_nport_no_fw_loading.__init__(self, name, cfg=cfg,
                                                         quick=quick,
                                                         dut_object=dut_object,
                                                         expected_ports=4)
        ping_dut = []
        ping_ep = []

        dut_t_x = []
        a_t = []

        for i in range(0, self.expected_ports):
            ping_dut.append((self.dut, self.eth_d[i]))
            ping_ep.append((self.host_ep[i], self.eth_ep[i]))

            dut_t_x.append((self.dut, self.addr_d[i], self.eth_d[i],
                       self.addr_v6_d[i], self.rss_key, self.rm_nc_bin))
            a_t.append((self.host_ep[i], self.addr_ep[i], self.eth_ep[i],
                   self.addr_v6_ep[i], None, self.rm_nc_bin))

        self.perf_dict = Perf_dict_nport(self, dut_t_x, a_t,
                                         ping_dut, ping_ep, 4)
        self._tests = self.perf_dict.tests


class NFPFlowNICPerfTest_8_no_fw_ld(_NFPFlowNICPerfTest_nport_no_fw_loading):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with kernel space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest_nport_no_fw_loading.__init__(self, name, cfg=cfg,
                                                         quick=quick,
                                                         dut_object=dut_object,
                                                         expected_ports=8)

        ping_dut = []
        ping_ep = []

        dut_t_x = []
        a_t = []

        for i in range(0, self.expected_ports):
            ping_dut.append((self.dut, self.eth_d[i]))
            ping_ep.append((self.host_ep[i], self.eth_ep[i]))

            dut_t_x.append((self.dut, self.addr_d[i], self.eth_d[i],
                       self.addr_v6_d[i], self.rss_key, self.rm_nc_bin))
            a_t.append((self.host_ep[i], self.addr_ep[i], self.eth_ep[i],
                   self.addr_v6_ep[i], None, self.rm_nc_bin))

        self.perf_dict = Perf_dict_nport(self, dut_t_x, a_t,
                                         ping_dut, ping_ep, 8)
        self._tests = self.perf_dict.tests