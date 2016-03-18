#
# Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
#
"""
Unit test group for the NFPFlowNIC Software Group.
"""

from netro.tests.null import NullTest
from ...nfpflownic_setup_tests import _NFPFlowNICSetup
from ..setup.reboot_hosts import RebootHosts
from ..setup.install_bsp_sdk import InstallBSPSDK

###########################################################################
# Unit Tests
###########################################################################


class NFPFlowNICSetup_tip_bsp(_NFPFlowNICSetup):
    """Unit tests for the NFPFlowNICSetup Software Group"""

    summary = "Tests used for configuring environment for the " \
              "NFPFlowNIC project. "

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):
        """Initialise
        @name:   A unique name for the group of tests
        @cfg:    A Config parser object (optional)
        @quick:  Omit some system info gathering to speed up running tests
        """

        _NFPFlowNICSetup.__init__(self, name, cfg=cfg, quick=quick,
                                  dut_object=dut_object, bsp_tip=True)

        tn = "reboot_hosts_before_tests"
        self._tests[tn] = RebootHosts(self, group=self, name=tn,
                                      summary="Reboot all the connected "
                                              "hosts and required components")

        tn = "install_bsp_sdk"
        self._tests[tn] = InstallBSPSDK(self, group=self, name=tn,
                                        summary="Install LATEST BSP for "
                                                "nfpflownic tests.")

        tn = "reboot_hosts_after_fresh_arm"
        self._tests[tn] = RebootHosts(self, group=self, name=tn,
                                      summary="Reboot all the connected "
                                              "hosts and required components")

        tn = "null"
        self._tests[tn] = NullTest(self, tn)
