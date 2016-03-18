##
## Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Unit test group for the NFPFlowNIC Software Group.
"""

import collections
from ...nfpflownic_tests import _NFPFlowNIC_userspace
from ..unit.unit_tests import Unit_dict


###########################################################################
# Unit Tests
###########################################################################
class NFPFlowNICUnit_userspace(_NFPFlowNIC_userspace):
    """Unit tests for the NFPFlowNIC Software Group"""

    summary = "Unit tests for the NFPFlowNIC project with user space " \
              "firmware loading. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNIC_userspace.__init__(self, name, cfg=cfg, quick=quick,
                                       dut_object=dut_object)

        ping_dut = (self.dut, self.eth_x)
        ping_a_t = (self.host_a, self.eth_a)

        dut_t_x = (self.dut, self.addr_x, self.eth_x, self.addr_v6_x,
                   self.rss_key, self.rm_nc_bin)
        a_t = (self.host_a, self.addr_a, self.eth_a, self.addr_v6_a, None,
               self.rm_nc_bin)

        self.unit_dict = Unit_dict(self, dut_t_x, a_t,
                                   ping_dut, ping_a_t)
        if 'kmod_ld_perf' in self.unit_dict.tests:
            del self.unit_dict.tests['kmod_ld_perf']
        self._tests = self.unit_dict.tests



