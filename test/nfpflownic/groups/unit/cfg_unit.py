#
# Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
#
"""
Unit test classes for the NFPFlowNIC Software Group.
"""

from netro.testinfra.nrt_result import NrtResult
from netro.tests.ping import Ping
from unit import UnitPing
from netro.testinfra.utilities import timed_poll


class NFPFlowNICCfgUnitTest(UnitPing):
    """The tests in this file share a lot of common code which is kept
    in this class"""

    # Information applicable to all subclasses
    _gen_info = """

    """

    def __init__(self, src, dst, group=None, name="", summary=None):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        UnitPing.__init__(self, src, dst, src_mtu=1500, dst_mtu=1500,
                          clean=False, noloss=False, group=group, name=name,
                          summary=summary)

        self.src = None
        self.src_intf = None
        self.dut = None
        self.dut_intf = None

        if src[0]:
            self.src = src[0]
            self.src_intf = src[2]
            self.dst = dst[0]
            self.dst_intf = dst[2]

        # These will be set in the run() method
        self.src_mac = None
        self.src_ip = None
        self.dst_mac = None
        self.dst_ip = None

        return

    def run(self):
        """Run the test
        @return:  A result object"""

        # Reset MTU values just in case.
        self.mtu_cfg_obj.reset_mtu(self.src, self.src_intf)
        self.mtu_cfg_obj.reset_mtu(self.dst, self.dst_intf)

        # Refresh intf objects.
        self.src.refresh()
        self.dst.refresh()

        for num in range(10):
            # Down the interface.
            self.set_up_or_down_intf(self.src, self.src_intf, "down")

            # Verify interface is down.
            timed_poll(30, self.src.if_interface_down, self.src_intf, delay=1)

            # Up the interface.
            self.set_up_or_down_intf(self.src, self.src_intf, "up")

            # Verify interface is up.
            timed_poll(30, self.src.if_interface_up, self.src_intf, delay=1)

            # Ping the endpoint.
            res = Ping.run(self)
            if not res.passed:
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=False,
                                 comment=res.comment)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=True, comment="")

    def set_up_or_down_intf(self, host, intf, up_down=None):
        """
        Simply up or down an interface.

        :param intf: Interface to bring up or down
        :param up_down: String value of "up" or "down"
        :return: None
        """
        cmd = "ip link set dev %s %s" % (intf, up_down)
        host.cmd(cmd)
        return
