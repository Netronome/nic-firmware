##
## Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Unit test group for the NFPFlowNIC Software Group.
"""

import collections
from netro.tests.null import NullTest
from netro.tests.iperf import Iperf
from ...nfpflownic_tests import _NFPFlowNICPerfTest_userspace
from ..perf.perf_tests import Perf_dict


###########################################################################
# Perf Tests
###########################################################################
class NFPFlowNICPerfTest_userspace(_NFPFlowNICPerfTest_userspace):
    """Perf tests for the NFPFlowNIC Software Group"""

    summary = "Perf tests for the NFPFlowNIC project with user space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICPerfTest_userspace.__init__(self, name, cfg=cfg,
                                               quick=quick,
                                               dut_object=dut_object)

        ping_dut = (self.dut, self.eth_x)
        ping_a_t = (self.host_a, self.eth_a)

        dut_t_x = (self.dut, self.addr_x, self.eth_x, self.addr_v6_x)
        a_t = (self.host_a, self.addr_a, self.eth_a, self.addr_v6_a)

        self.perf_dict = Perf_dict(self, dut_t_x, a_t,
                                   ping_dut, ping_a_t)
        self._tests = self.perf_dict.tests







