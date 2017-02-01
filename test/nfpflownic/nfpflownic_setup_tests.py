#
# Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
#
"""
Configuration and Initializations for the nfpflownic setup test Group.
"""

import collections
import netro.testinfra
from netro.testinfra.system import System
from libs.nrt_system import kill_bg_process
from netro.testinfra.nti_exceptions import NtiFatalError
from nfpflownicpath import BSP, BSP_DKMS, BSP_LOC, LATEST_BSP, LATEST_BSP_DKMS,\
    LATEST_BSP_LOC, SDK, SDK_LOC


###############################################################################
# A group of unit tests
###############################################################################
class _NFPFlowNICSetup(netro.testinfra.Group):
    """Simple unit tests tests"""

    summary = "NFPFlowNICSetup tests"

    _info = """ Run tests that setup a clean environment for the NFPFlowNic
    tests. This group does not configure or load any drivers and should simply
    be used to provide a clean testing environment for tests that follow. """

    _config = collections.OrderedDict()
    _config["General"] = collections.OrderedDict([
        ('noclean', [False, "Don't clean the systems after a run (default "
                            "False). Useful for debugging test failures."])])
    _config["DUT"] = collections.OrderedDict([
        ("name", [True, "Host name of the DUT (can also be <user>@<host> or "
                        "IP address). Assumes root as default."]),
    ])
    _config["HostA"] = collections.OrderedDict([
        ("name", [True, "Host name of the Host A (can also be <user>@<host> "
                        "or IP address). Assumes root as default."]),
        ("eth", [True, "Name of the interface on Host A"]),
    ])

    def __init__(self, name, cfg=None, quick=False, dut_object=None,
                 bsp_tip=False):
        """Initialise base NFPFlowNICSetup class

        @name:       A unique name for the group of tests
        @cfg:        A Config parser object (optional)
        @quick:      Omit some system info gathering to speed up running tests
        @dut_object: A DUT object used for pulling in endpoint/DUT data
                     (optional), only used when the PALAB is used
        """
        self.quick = quick
        self.dut_object = dut_object

        self.tmpdir = None
        self.cfg = cfg

        # BSP and SDK
        if bsp_tip:
            self.bsp = LATEST_BSP
            self.bsp_dkms = LATEST_BSP_DKMS
            self.bsp_loc = LATEST_BSP_LOC
        else:
            self.bsp = BSP
            self.bsp_dkms = BSP_DKMS
            self.bsp_loc = BSP_LOC

        self.sdk = SDK
        self.sdk_loc = SDK_LOC

        # Set up attributes initialised by the config file.
        # If no config was provided these will be None.
        self.noclean = False

        self.dut = None
        self.nfes = 0

        self.src = []
        self.src_intf = None

        # Call the parent's initializer.  It'll set up common attributes
        # and parses/validates the config file.
        netro.testinfra.Group.__init__(self, name, cfg=cfg,
                                       quick=quick, dut_object=dut_object)

    def _init(self):
        """Initialise the systems for tests from this group
        called from the groups run() method.
        """
        return

    def _fini(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        client_list = self.src
        client_list.append(self.dut)
        for client in client_list:
            kill_bg_process(client.host, "TCPKeepAlive")

        netro.testinfra.Group._fini(self)
        return

    def _parse_palab_cfg(self):
        """
        Assign values to the members of System based on the DUT object.
        The DUT object is created by the main.py when the PALAB file is
        pulled and parsed. This method is used when there is no cfg file
        given in the command line.
        """
        # DUT
        self.nfes = int(self.dut_object.nfe_ct)
        self.dut = System(self.dut_object.name, quick=self.quick,
                          _noendsec=True)
        # Host A
        # We assume that only the 0.0 port is activated, and we need to find
        # out which of the two endpoint is the one connected to 1.0 or 0.0,
        # For test DUT with both 4k and 6k, 4k (1.0) has higher priority
        if self.dut_object.client != None and \
                        self.dut_object.client.pifX == '1.0':
            host_a_obj = self.dut_object.client
        elif self.dut_object.server != None and \
                        self.dut_object.server.pifX == '1.0':
            host_a_obj = self.dut_object.server
        elif self.dut_object.client != None and \
                        self.dut_object.client.pifX == '0.0':
            host_a_obj = self.dut_object.client
        elif self.dut_object.server != None and \
                        self.dut_object.server.pifX == '0.0':
            host_a_obj = self.dut_object.server
        else:
            raise NtiFatalError(msg="0.0 port is not connected to any endpoint"
                                    " found in dut_object")
        self.src = System(host_a_obj.name, self.quick, _noendsec=True)
        self.src_intf = host_a_obj.intfX

    def _parse_cfg(self):
        """
        Assign values to the members of NFPFlowNIC based on the cfg file.
        This method is used only when a cfg file is given in the command line
        Make sure the config is suitable for this project of tests
        """
        # General
        if self.cfg.has_option("General", "noclean"):
            self.noclean = self.cfg.getboolean("General", "noclean")

        # BSP
        if self.cfg.has_option("DUT", "bsp"):
            self.bsp = self.cfg.get("DUT", "bsp")
        if self.cfg.has_option("DUT", "bsp_dkms"):
            self.bsp_dkms = self.cfg.get("DUT", "bsp_dkms")
        if self.cfg.has_option("DUT", "bsp_loc"):
            self.bsp_loc = self.cfg.get("DUT", "bsp_loc")
        # SDK
        if self.cfg.has_option("DUT", "sdk"):
            self.sdk = self.cfg.get("DUT", "sdk")
        if self.cfg.has_option("DUT", "sdk_loc"):
            self.sdk_loc = self.cfg.get("DUT", "sdk_loc")

        # NIC
        if self.cfg.has_option("DUT", "nic_deb"):
            self.nic_deb = self.cfg.get("DUT", "nic_deb")
        if self.cfg.has_option("DUT", "nic_deb_loc"):
            self.nic_deb_loc = self.cfg.get("DUT", "nic_deb_loc")

        # DUT
        self.dut_object = None
        if self.cfg.has_option("DUT", "nfp"):
            self.nfes = self.cfg.getint("DUT", "nfp")

        self.dut = System(self.cfg.get("DUT", "name"), quick=self.quick,
                          _noendsec=True)
        # Host A
        host_list = self.cfg.get("HostEP", "names").split(',')
        for i in range(0, len(host_list)):
            if host_list[i].strip() not in self.src:
                self.src.append(System(host_list[i].strip(), self.quick))

        return
