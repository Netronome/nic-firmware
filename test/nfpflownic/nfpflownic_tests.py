##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Configuration and Initializations for the nfpflownic test Groups.
"""

import collections
import os
import re

import netro.testinfra
from netro.testinfra import LOG_sec, LOG_endsec
from netro.testinfra.nti_exceptions import NtiError, NtiFatalError
from nfpflownicsystem import NFPFlowNICSystem
from libs.nrt_system import NrtSystem
from libs.nrt_system import kill_bg_process


###############################################################################
# A group of unit tests
###############################################################################
class _NFPFlowNIC(netro.testinfra.Group):
    """Simple unit tests tests"""

    summary = "NFPFlowNIC tests"

    _info = """
    Run a barrage of simple unit tests against an NFP configured as
    Just-a-NIC. The tests are designed to test particular aspects of
    the nfpflowNIC.

    The test configuration looks like this:

                     DUT
                 ethX
                  ^
    Host A        |
      ethA <------+

    The kernel module can also be optionally copied from the controller to
    the DUT and loaded before tests are run. Also, the standard BSP kernel
    modules as well as the ME firmware image can optionally be copied
    and loaded prior to running any tests.

    If cfg file are not used, the tests  will load them from the build located
    in releases-interm->msft->builds. This also allows to run the tests
    against a suitably configured standard NIC as well.

    """

    _config = collections.OrderedDict()
    _config["General"] = collections.OrderedDict([
        ('noclean', [False, "Don't clean the systems after a run (default "
                            "False). Useful for debugging test failures."])])
    _config["DUT"] = collections.OrderedDict([
        ("name", [True, "Host name of the DUT (can also be <user>@<host> or "
                        "IP address). Assumes root as default."]),
        ("addrX", [True, "IPv4 address/mask to be assigned to ethX"]),
        ("addr6X", [True, "IPv6 address/mask to be assigned to ethX"]),
        #("vnickmod", [False, "Path to vNIC kernel module to load on DUT"]),
        #("nfpkmods", [False, "Directory with BSP kernel mods load on DUT"]),
        ("nfp", [False, "NFP device number to use (default 0)"]),
        ("mefw", [False, "Path to firmware image to load"]),
        ("mkfirmware", [False, "Path to the script producing CA kernel ready "
                               "firmware"]),
        ("load_mode", [False, "How to load fw: 'kernel' or 'userspace'"]),
    ])
    _config["HostA"] = collections.OrderedDict([
        ("name", [True, "Host name of the Host A (can also be <user>@<host> "
                        "or IP address). Assumes root as default."]),
        ("eth", [True, "Name of the interface on Host A"]),
        ("addrA", [True, "IPv4 address/mask to be assigned to Host A"]),
        ("addr6A", [True, "IPv4 address/mask to be assigned to Host A"]),
        ("reload", [False, "Attempt to reload the kmod for ethA "
                           "(default false)."])
    ])

    def __init__(self, name, cfg=None, quick=False, dut_object=None):
        """Initialise base NFPFlowNIC class

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

        # Set up attributes initialised by the config file.
        # If no config was provided these will be None.
        self.noclean = False

        self.dut = None
        self.eth_x = None
        self.addr_x = None
        self.addr_v6_x = None
        self.intf_x = None
        self.nfp = 0
        self.vnickmod = None
        self.vnic_fn = None
        self.nfpkmods = None
        self.mefw = None
        self.mefw_fn = None
        self.mkfirmware = None
        self.mkfirmware_fn = None
        self.load_mode = 'kernel'
        self.customized_kmod=False

        self.host_a = None
        self.eth_a = None
        self.addr_a = None
        self.addr_v6_a = None
        self.intf_a = None
        self.reload_a = False
        self.rss_key = None
        self.nc_path = '/tmp/nc_bin/'
        self.nc_repo = './lib/nc.c'
        self.nc_src = 'nc.c'
        self.nc_bin = 'nc'
        self.rm_nc_src = '%s/%s' % (self.nc_path, self.nc_src)
        self.rm_nc_bin = '%s/%s' % (self.nc_path, self.nc_bin)

        # Call the parent's initializer.  It'll set up common attributes
        # and parses/validates the config file.
        netro.testinfra.Group.__init__(self, name, cfg=cfg,
                                       quick=quick, dut_object=dut_object)
        if self.dut_object or self.cfg:
            self._configure_intfs()

    def clean_hosts(self):
        """ Clean host A.
        """
        # Clean attached hosts
        LOG_sec("Cleaning Host A: %s" % self.host_a.host)

        self.host_a.clean_attached_nodes(intf="")

        LOG_endsec()

        return

    def _init(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        netro.testinfra.Group._init(self)
        # Unit test group needs Jakub's netcat tools. So copy and compile
        # it here
        self.dut.cmd('rm -rf %s' % self.nc_path, fail=False)
        self.host_a.cmd('rm -rf %s' % self.nc_path, fail=False)
        self.dut.cmd('mkdir %s' % self.nc_path)
        self.host_a.cmd('mkdir %s' % self.nc_path)
        self.dut.cp_to(self.nc_repo, self.nc_path)
        self.host_a.cp_to(self.nc_repo, self.nc_path)
        self.dut.cmd('gcc %s -o %s' % (self.rm_nc_src, self.rm_nc_bin))
        self.host_a.cmd('gcc %s -o %s' % (self.rm_nc_src, self.rm_nc_bin))

        return


    def _fini(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        client_list = [self.dut, self.host_a]
        for client in client_list:
            kill_bg_process(client.host, "TCPKeepAlive")

        # Unit test group installes Jakub's netcat tools. So clean up here
        self.dut.cmd('rm -rf %s' % self.nc_path, fail=False)
        self.host_a.cmd('rm -rf %s' % self.nc_path, fail=False)

        netro.testinfra.Group._fini(self)
        return

    def _parse_palab_cfg(self):
        """
        Assign values to the members of NFPFlowNIC based on the DUT object.
        The DUT object is created by the main.py when the PALAB file is
        pulled and parsed. This method is used when there is no cfg file
        given in the command line.
        """

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
        self.intf_x = host_a_obj.pifX
        # there are two intf format in PALAB: "Y" and "X.Y" (X and Y as
        # integers). We use Y in forming the ip address
        intf_id_str = "[0-9.]*([0-9]+)"
        intf_find = re.findall(intf_id_str, self.intf_x)
        if intf_find:
            intf_id = intf_find[0]
        else:
            raise NtiFatalError(msg="Error in generating IP address")
        self.addr_x = "10.%s.%s.1/24" % (intf_id, intf_id)
        ipv6 = "fc00:1:%s:%s:" % (intf_id, intf_id)
        ipv6_pl = "64"
        self.addr_v6_x = ipv6 + ":1/" + ipv6_pl

        self.nfp = 0
        self.vnic_fn = 'nfp_net'
        self.mefw_fn = 'basic_nic.nffw'
        self.macinitjson = None
        self.macinitjson_fn = None

        self.dut = NFPFlowNICSystem(self.dut_object.name, cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    vnic_fn=self.vnic_fn,
                                    mefw_fn=self.mefw_fn, quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

        if len(self.dut.eth_list) > 1:
            # multiple interfaces are generated
            raise NtiFatalError(msg="more than one interfaces are created, new"
                                    " configuration code needs to be added")

        # Host A
        self.host_a = NrtSystem(host_a_obj.name, self.quick)
        self.eth_a = host_a_obj.intfX
        self.addr_a = "10.%s.%s.2/24" % (intf_id, intf_id)
        self.addr_v6_a = ipv6 + ":2/" + ipv6_pl
        self.reload_a = False

    def _configure_intfs(self):
        """
        Configure eth_a of the host_a with IPv4 address addr_a and IPv6 address
        addr_v6_a. Also configure eth_x of the DUT with IPv4 address addr_x and
        IPv6 address addr_v6_x
        """

        self.dut.clean_attached_nodes(intf=self.eth_x)
        cmd = 'ip addr flush dev %s; ' % self.eth_x
        cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_x, self.addr_v6_x)
        cmd += 'ifconfig %s %s up; ' % (self.eth_x, self.addr_x)
        ret, _ = self.dut.cmd(cmd)
        if ret:
            raise NtiFatalError(msg="Error in DUT VNIC addr configuration")
        self.host_a.clean_attached_nodes(intf=self.eth_a)
        cmd = 'ip addr flush dev %s; ' % self.eth_a
        cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_a, self.addr_v6_a)
        cmd += 'ifconfig %s %s up; ' % (self.eth_a, self.addr_a)
        ret, _ = self.host_a.cmd(cmd)
        if ret:
            raise NtiFatalError(msg="Error in endpoint intf addr configuration")
        self.dut.refresh()
        self.host_a.refresh()

    def _get_service_status(self, device, service_name):
        """
        To get the status of the given service (start/running, or stop/waiting),
        return "running", "stop", or "fail"
        """
        status = "fail"
        running_str = '%s\s+start/running,\s+process\s+\d+\s+' % service_name
        stop_str = '%s\s+stop/waiting\s+' % service_name
        cmd = 'service %s status' % service_name
        ret, out = device.cmd(cmd, fail=False)
        if not ret:
            if re.findall(running_str, out):
                status = "running"
            elif re.findall(stop_str, out):
                status = "stop"
        return status

    def _parse_cfg(self):
        """
        Assign values to the members of NFPFlowNIC based on the cfg file.
        This method is used only when a cfg file is given in the command line
        Make sure the config is suitable for this project of tests
        """

        # The superclass implementation takes care of sanity checks
        netro.testinfra.Group._parse_cfg(self)

        self.dut_object = None

        # General
        if self.cfg.has_option("General", "noclean"):
            self.noclean = self.cfg.getboolean("General", "noclean")

        # DUT
        self.addr_x = self.cfg.get("DUT", "addrX")
        self.addr_v6_x = self.cfg.get("DUT", "addr6X")

        if self.cfg.has_option("DUT", "nfp"):
            self.nfp = self.cfg.getint("DUT", "nfp")
        if self.cfg.has_option("DUT", "vnickmod"):
            self.vnickmod = self.cfg.get("DUT", "vnickmod")
        if self.cfg.has_option("DUT", "nfpkmods"):
            self.nfpkmods = self.cfg.get("DUT", "nfpkmods")
        if self.cfg.has_option("DUT", "mefw"):
            self.mefw = self.cfg.get("DUT", "mefw")
            self.mefw_fn = os.path.basename(self.mefw)
        if self.cfg.has_option("DUT", "mkfirmware"):
            self.mkfirmware = self.cfg.get("DUT", "mkfirmware")
            self.mkfirmware_fn = os.path.basename(self.mkfirmware)
        if self.cfg.has_option("DUT", "load_mode"):
            self.load_mode = self.cfg.get("DUT", "load_mode")
        if self.cfg.has_option("DUT", "macinitjson"):
            self.macinitjson = self.cfg.get("DUT", "macinitjson")
            self.macinitjson_fn = os.path.basename(self.macinitjson)
        else:
            self.macinitjson = None
            self.macinitjson_fn = None
        if self.cfg.has_option("DUT", "initscript"):
            self.initscript =  self.cfg.get("DUT", "initscript")
            self.initscript_fn = os.path.basename(self.initscript)
        else:
            self.initscript =  "../me/apps/nic/init/nic.sh"
            self.initscript_fn = os.path.basename(self.initscript)
        if self.cfg.has_option("DUT", "customized_kmod"):
            c_km_str = self.cfg.get("DUT", "customized_kmod")
            if c_km_str == 'False':
                self.customized_kmod = False
            elif c_km_str == 'True':
                self.customized_kmod = True

        self.dut = NFPFlowNICSystem(self.cfg.get("DUT", "name"), cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    mefw_fn=self.mefw_fn,
                                    nfpkmods=self.nfpkmods,
                                    vnickmod=self.vnickmod,
                                    mefw=self.mefw,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    initscript = self.initscript,
                                    initscript_fn = self.initscript_fn,
                                    mkfirmware=self.mkfirmware,
                                    mkfirmware_fn=self.mkfirmware_fn,
                                    load_mode=self.load_mode,
                                    customized_kmod=self.customized_kmod,
                                    quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

         # Host A
        self.host_a = NrtSystem(self.cfg.get("HostA", "name"), self.quick)
        self.eth_a = self.cfg.get("HostA", "eth")
        self.addr_a = self.cfg.get("HostA", "addrA")
        self.addr_v6_a = self.cfg.get("HostA", "addr6A")
        if self.cfg.has_option("HostA", "reload"):
            self.reload_a = self.cfg.getboolean("HostA", "reload")

        return


###############################################################################
# A group of unit tests with userspace loading
###############################################################################
class _NFPFlowNIC_userspace(_NFPFlowNIC):

    def _parse_palab_cfg(self):
         """
         Assign values to the members of NFPFlowNIC based on the DUT object.
         The DUT object is created by the main.py when the PALAB file is
         pulled and parsed. This method is used when there is no cfg file
         given in the command line.
         """

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
             raise NtiFatalError(msg="0.0 or 1.0 port is not connected to "
                                     "any endpoint found in dut_object")
         self.intf_x = host_a_obj.pifX
         # there are two intf format in PALAB: "Y" and "X.Y" (X and Y as
         # integers). We use Y in forming the ip address
         intf_id_str = "[0-9.]*([0-9]+)"
         intf_find = re.findall(intf_id_str, self.intf_x)
         if intf_find:
             intf_id = intf_find[0]
         else:
             raise NtiFatalError(msg="Error in generating IP address")
         self.addr_x = "10.%s.%s.1/24" % (intf_id, intf_id)
         ipv6 = "fc00:1:%s:%s:" % (intf_id, intf_id)
         ipv6_pl = "64"
         self.addr_v6_x = ipv6 + ":1/" + ipv6_pl

         self.nfp = 0
         self.vnic_fn = 'nfp_net'
         self.mefw_fn = 'basic_nic.nffw'
         self.macinitjson = None
         self.macinitjson_fn = None

         self.dut = NFPFlowNICSystem(self.dut_object.name,
                                     cfg=self.cfg,
                                     dut=self.dut_object,
                                     nfp=self.nfp,
                                     macinitjson=self.macinitjson,
                                     macinitjson_fn=self.macinitjson_fn,
                                     vnic_fn=self.vnic_fn,
                                     mefw_fn=self.mefw_fn,
                                     load_mode='userspace',
                                     quick=self.quick)
         self.eth_x = self.dut.eth_list[0]
         self.rss_key = self.dut.rss_key

         if len(self.dut.eth_list) > 1:
             # multiple interfaces are generated
             raise NtiFatalError(msg="more than one interfaces are created, new"
                                     " configuration code needs to be added")

         # Host A
         self.host_a = NrtSystem(host_a_obj.name, self.quick)
         self.eth_a = host_a_obj.intfX
         self.addr_a = "10.%s.%s.2/24" % (intf_id, intf_id)
         self.addr_v6_a = ipv6 + ":2/" + ipv6_pl
         self.reload_a = False

    def _parse_cfg(self):
        """
        Assign values to the members of NFPFlowNIC based on the cfg file.
        This method is used only when a cfg file is given in the command line
        Make sure the config is suitable for this project of tests
        """

        # The superclass implementation takes care of sanity checks
        netro.testinfra.Group._parse_cfg(self)

        self.dut_object = None

        # General
        if self.cfg.has_option("General", "noclean"):
            self.noclean = self.cfg.getboolean("General", "noclean")

        # DUT
        self.addr_x = self.cfg.get("DUT", "addrX")
        self.addr_v6_x = self.cfg.get("DUT", "addr6X")

        if self.cfg.has_option("DUT", "nfp"):
            self.nfp = self.cfg.getint("DUT", "nfp")
        if self.cfg.has_option("DUT", "vnickmod"):
            self.vnickmod = self.cfg.get("DUT", "vnickmod")
        if self.cfg.has_option("DUT", "nfpkmods"):
            self.nfpkmods = self.cfg.get("DUT", "nfpkmods")
        if self.cfg.has_option("DUT", "mefw"):
            self.mefw = self.cfg.get("DUT", "mefw")
            self.mefw_fn = os.path.basename(self.mefw)
        if self.cfg.has_option("DUT", "mkfirmware"):
            self.mkfirmware = self.cfg.get("DUT", "mkfirmware")
            self.mkfirmware_fn = os.path.basename(self.mkfirmware)

        self.load_mode = 'userspace'

        if self.cfg.has_option("DUT", "macinitjson"):
            self.macinitjson = self.cfg.get("DUT", "macinitjson")
            self.macinitjson_fn = os.path.basename(self.macinitjson)
        else:
            self.macinitjson = None
            self.macinitjson_fn = None
        if self.cfg.has_option("DUT", "initscript"):
            self.initscript =  self.cfg.get("DUT", "initscript")
            self.initscript_fn = os.path.basename(self.initscript)
        else:
            self.initscript =  "../me/apps/nic/init/nic.sh"
            self.initscript_fn = os.path.basename(self.initscript)
        if self.cfg.has_option("DUT", "customized_kmod"):
            c_km_str = self.cfg.get("DUT", "customized_kmod")
            if c_km_str == 'False':
                self.customized_kmod = False
            elif c_km_str == 'True':
                self.customized_kmod = True

        self.dut = NFPFlowNICSystem(self.cfg.get("DUT", "name"), cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    mefw_fn=self.mefw_fn,
                                    nfpkmods=self.nfpkmods,
                                    vnickmod=self.vnickmod,
                                    mefw=self.mefw,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    initscript = self.initscript,
                                    initscript_fn = self.initscript_fn,
                                    mkfirmware=self.mkfirmware,
                                    mkfirmware_fn=self.mkfirmware_fn,
                                    load_mode=self.load_mode,
                                    customized_kmod=self.customized_kmod,
                                    quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

         # Host A
        self.host_a = NrtSystem(self.cfg.get("HostA", "name"), self.quick)
        self.eth_a = self.cfg.get("HostA", "eth")
        self.addr_a = self.cfg.get("HostA", "addrA")
        self.addr_v6_a = self.cfg.get("HostA", "addr6A")
        if self.cfg.has_option("HostA", "reload"):
            self.reload_a = self.cfg.getboolean("HostA", "reload")

        return


###############################################################################
# A group of Perf tests with kernel loading loading
###############################################################################
class _NFPFlowNICPerfTest(_NFPFlowNIC):

    # Perf test group does not need Jakub's netcat tools. So override the _init
    # and _fini here
    def _init(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        netro.testinfra.Group._init(self)

        return


    def _fini(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        client_list = [self.dut, self.host_a]
        for client in client_list:
            kill_bg_process(client.host, "TCPKeepAlive")

        netro.testinfra.Group._fini(self)
        return

    def _configure_intfs(self):
        """
        Configure eth_a of the host_a with IPv4 address addr_a and IPv6 address
        addr_v6_a. Also configure eth_x of the DUT with IPv4 address addr_x and
        IPv6 address addr_v6_x
        Also Pin interrupts for iperf tests
        """

        _NFPFlowNIC._configure_intfs(self)

        cmd = 'cat /proc/interrupts | grep %s-rxtx | cut -d : -f 1' % self.eth_x
        ret, out = self.dut.cmd(cmd)

        cmd = 'service irqbalance stop'
        self.dut.cmd(cmd, fail=False)

        ir_list = [y for y in (x.strip() for x in out.splitlines()) if y]

        cmd = ""
        i = 0
        for ir in ir_list:
            cmd += "echo %d > /proc/irq/%d/smp_affinity_list && " % (i, int(ir))
            i += 1
        cmd = cmd[:-2]

        self.dut.cmd(cmd)


###############################################################################
# A group of Perf tests with userspace loading
###############################################################################
class _NFPFlowNICPerfTest_userspace(_NFPFlowNIC_userspace):

    # Perf test group does not need Jakub's netcat tools. So override the _init
    # and _fini here
    def _init(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        netro.testinfra.Group._init(self)

        return


    def _fini(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        client_list = [self.dut, self.host_a]
        for client in client_list:
            kill_bg_process(client.host, "TCPKeepAlive")

        netro.testinfra.Group._fini(self)
        return

    def _configure_intfs(self):
        """
        Configure eth_a of the host_a with IPv4 address addr_a and IPv6 address
        addr_v6_a. Also configure eth_x of the DUT with IPv4 address addr_x and
        IPv6 address addr_v6_x
        Also Pin interrupts for iperf tests
        """

        _NFPFlowNIC_userspace._configure_intfs(self)

        cmd = 'cat /proc/interrupts | grep %s-rxtx | cut -d : -f 1' % self.eth_x
        ret, out = self.dut.cmd(cmd)

        cmd = 'service irqbalance stop'
        self.dut.cmd(cmd, fail=False)

        ir_list = [y for y in (x.strip() for x in out.splitlines()) if y]

        cmd = ""
        i = 0
        for ir in ir_list:
            cmd += "echo %d > /proc/irq/%d/smp_affinity_list && " % (i, int(ir))
            i += 1
        cmd = cmd[:-2]

        self.dut.cmd(cmd)


###############################################################################
# A group of 2-port unit tests
###############################################################################
class _NFPFlowNIC_2port(_NFPFlowNIC):
    """Simple unit tests tests"""

    summary = "NFPFlowNIC tests"

    _info = """
    Run a barrage of simple unit tests against an NFP configured as
    Just-a-NIC. The tests are designed to test particular aspects of
    the nfpflowNIC.

    The test configuration looks like this:

                     DUT
                 ethX  ethY
                  ^     ^
    Host A        |     |      Host B
      ethA <------+     +------> ethB

    The kernel module can also be optionally copied from the controller to
    the DUT and loaded before tests are run. Also, the standard BSP kernel
    modules as well as the ME firmware image can optionally be copied
    and loaded prior to running any tests.

    If cfg file are not used, the tests  will load them from the build located
    in releases-interm->msft->builds. This also allows to run the tests
    against a suitably configured standard NIC as well.

    """

    _config = collections.OrderedDict()
    _config["General"] = collections.OrderedDict([
        ('noclean', [False, "Don't clean the systems after a run (default "
                            "False). Useful for debugging test failures."])])
    _config["DUT"] = collections.OrderedDict([
        ("name", [True, "Host name of the DUT (can also be <user>@<host> or "
                        "IP address). Assumes root as default."]),
        ("addrX", [True, "IPv4 address/mask to be assigned to ethX"]),
        ("addr6X", [True, "IPv6 address/mask to be assigned to ethX"]),
        ("addrY", [True, "IPv4 address/mask to be assigned to ethY"]),
        ("addr6Y", [True, "IPv6 address/mask to be assigned to ethY"]),
        #("vnickmod", [False, "Path to vNIC kernel module to load on DUT"]),
        #("nfpkmods", [False, "Directory with BSP kernel mods load on DUT"]),
        ("nfp", [False, "NFP device number to use (default 0)"]),
        ("mefw", [False, "Path to firmware image to load"]),
        ("mkfirmware", [False, "Path to the script producing CA kernel ready "
                               "firmware"]),
        ("load_mode", [False, "How to load fw: 'kernel' or 'userspace'"]),
    ])
    _config["HostA"] = collections.OrderedDict([
        ("name", [True, "Host name of the Host A (can also be <user>@<host> "
                        "or IP address). Assumes root as default."]),
        ("eth", [True, "Name of the interface on Host A"]),
        ("addrA", [True, "IPv4 address/mask to be assigned to Host A"]),
        ("addr6A", [True, "IPv4 address/mask to be assigned to Host A"]),
        ("reload", [False, "Attempt to reload the kmod for ethA "
                           "(default false)."])
    ])

    def __init__(self, name, cfg=None, quick=False, dut_object=None,
                 expected_ports=2):
        """Initialise base NFPFlowNIC class

        @name:       A unique name for the group of tests
        @cfg:        A Config parser object (optional)
        @quick:      Omit some system info gathering to speed up running tests
        @dut_object: A DUT object used for pulling in endpoint/DUT data
                     (optional), only used when the PALAB is used
        """

        self.expected_ports = expected_ports
        self.eth_y = None
        self.addr_y = None
        self.addr_v6_y = None
        self.intf_y = None

        self.host_b = None
        self.eth_b = None
        self.addr_b = None
        self.addr_v6_b = None
        self.intf_b = None
        self.reload_b = False

        _NFPFlowNIC.__init__(self, name, cfg=cfg, quick=quick,
                             dut_object=dut_object)

    ### TODO: need to update for multi-port
    def _parse_palab_cfg(self):
        """
        Assign values to the members of NFPFlowNIC based on the DUT object.
        The DUT object is created by the main.py when the PALAB file is
        pulled and parsed. This method is used when there is no cfg file
        given in the command line.
        """

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
        self.intf_x = host_a_obj.pifX
        # there are two intf format in PALAB: "Y" and "X.Y" (X and Y as
        # integers). We use Y in forming the ip address
        intf_id_str = "[0-9.]*([0-9]+)"
        intf_find = re.findall(intf_id_str, self.intf_x)
        if intf_find:
            intf_id = intf_find[0]
        else:
            raise NtiFatalError(msg="Error in generating IP address")
        self.addr_x = "10.%s.%s.1/24" % (intf_id, intf_id)
        ipv6 = "fc00:1:%s:%s:" % (intf_id, intf_id)
        ipv6_pl = "64"
        self.addr_v6_x = ipv6 + ":1/" + ipv6_pl

        self.nfp = 0
        self.vnic_fn = 'nfp_net'
        self.mefw_fn = 'basic_nic.nffw'
        self.macinitjson = None
        self.macinitjson_fn = None

        self.dut = NFPFlowNICSystem(self.dut_object.name, cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    vnic_fn=self.vnic_fn,
                                    mefw_fn=self.mefw_fn, quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

        if len(self.dut.eth_list) > 1:
            # multiple interfaces are generated
            raise NtiFatalError(msg="more than one interfaces are created, new"
                                    " configuration code needs to be added")

        # Host A
        self.host_a = NrtSystem(host_a_obj.name, self.quick)
        self.eth_a = host_a_obj.intfX
        self.addr_a = "10.%s.%s.2/24" % (intf_id, intf_id)
        self.addr_v6_a = ipv6 + ":2/" + ipv6_pl
        self.reload_a = False

    def _configure_intfs(self):
        """
        Configure eth_a of the host_a with IPv4 address addr_a and IPv6 address
        addr_v6_a. Also configure eth_x of the DUT with IPv4 address addr_x and
        IPv6 address addr_v6_x
        """

        self.dut.clean_attached_nodes(intf=self.eth_x)
        cmd = 'ip addr flush dev %s; ' % self.eth_x
        cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_x, self.addr_v6_x)
        cmd += 'ifconfig %s %s up; ' % (self.eth_x, self.addr_x)
        ret, _ = self.dut.cmd(cmd)
        if ret:
            raise NtiFatalError(msg="Error in DUT VNIC addr configuration")
        self.host_a.clean_attached_nodes(intf=self.eth_a)
        cmd = 'ip addr flush dev %s; ' % self.eth_a
        cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_a, self.addr_v6_a)
        cmd += 'ifconfig %s %s up; ' % (self.eth_a, self.addr_a)
        ret, _ = self.host_a.cmd(cmd)
        if ret:
            raise NtiFatalError(msg="Error in endpoint intf addr configuration")

        self.dut.clean_attached_nodes(intf=self.eth_y)
        cmd = 'ip addr flush dev %s; ' % self.eth_y
        cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_y, self.addr_v6_y)
        cmd += 'ifconfig %s %s up; ' % (self.eth_y, self.addr_y)
        ret, _ = self.dut.cmd(cmd)
        if ret:
            raise NtiFatalError(msg="Error in DUT VNIC addr configuration")
        self.host_a.clean_attached_nodes(intf=self.eth_b)
        cmd = 'ip addr flush dev %s; ' % self.eth_b
        cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_b, self.addr_v6_b)
        cmd += 'ifconfig %s %s up; ' % (self.eth_b, self.addr_b)
        ret, _ = self.host_b.cmd(cmd)
        if ret:
            raise NtiFatalError(msg="Error in endpoint intf addr "
                                    "configuration")
        self.dut.refresh()
        self.host_a.refresh()
        self.host_b.refresh()

    def _parse_cfg(self):
        """
        Assign values to the members of NFPFlowNIC based on the cfg file.
        This method is used only when a cfg file is given in the command line
        Make sure the config is suitable for this project of tests
        """

        # The superclass implementation takes care of sanity checks
        netro.testinfra.Group._parse_cfg(self)

        self.dut_object = None

        # General
        if self.cfg.has_option("General", "noclean"):
            self.noclean = self.cfg.getboolean("General", "noclean")

        # DUT
        self.addr_x = self.cfg.get("DUT", "addrX")
        self.addr_v6_x = self.cfg.get("DUT", "addr6X")

        self.addr_y = self.cfg.get("DUT", "addrY")
        self.addr_v6_y = self.cfg.get("DUT", "addr6Y")

        if self.cfg.has_option("DUT", "nfp"):
            self.nfp = self.cfg.getint("DUT", "nfp")
        if self.cfg.has_option("DUT", "vnickmod"):
            self.vnickmod = self.cfg.get("DUT", "vnickmod")
        if self.cfg.has_option("DUT", "nfpkmods"):
            self.nfpkmods = self.cfg.get("DUT", "nfpkmods")
        if self.cfg.has_option("DUT", "mefw"):
            self.mefw = self.cfg.get("DUT", "mefw")
            self.mefw_fn = os.path.basename(self.mefw)
        if self.cfg.has_option("DUT", "mkfirmware"):
            self.mkfirmware = self.cfg.get("DUT", "mkfirmware")
            self.mkfirmware_fn = os.path.basename(self.mkfirmware)
        if self.cfg.has_option("DUT", "load_mode"):
            self.load_mode = self.cfg.get("DUT", "load_mode")
        if self.cfg.has_option("DUT", "macinitjson"):
            self.macinitjson = self.cfg.get("DUT", "macinitjson")
            self.macinitjson_fn = os.path.basename(self.macinitjson)
        else:
            self.macinitjson = None
            self.macinitjson_fn = None
        if self.cfg.has_option("DUT", "initscript"):
            self.initscript =  self.cfg.get("DUT", "initscript")
            self.initscript_fn = os.path.basename(self.initscript)
        else:
            self.initscript =  "../me/apps/nic/init/nic.sh"
            self.initscript_fn = os.path.basename(self.initscript)
        if self.cfg.has_option("DUT", "customized_kmod"):
            c_km_str = self.cfg.get("DUT", "customized_kmod")
            if c_km_str == 'False':
                self.customized_kmod = False
            elif c_km_str == 'True':
                self.customized_kmod = True

        self.dut = NFPFlowNICSystem(self.cfg.get("DUT", "name"), cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    mefw_fn=self.mefw_fn,
                                    nfpkmods=self.nfpkmods,
                                    vnickmod=self.vnickmod,
                                    mefw=self.mefw,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    initscript = self.initscript,
                                    initscript_fn = self.initscript_fn,
                                    mkfirmware=self.mkfirmware,
                                    mkfirmware_fn=self.mkfirmware_fn,
                                    load_mode=self.load_mode,
                                    customized_kmod=self.customized_kmod,
                                    expected_ports=2,
                                    quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.eth_y = self.dut.eth_list[1]
        self.rss_key = self.dut.rss_key

        # Host A
        self.host_a = NrtSystem(self.cfg.get("HostA", "name"), self.quick)
        self.eth_a = self.cfg.get("HostA", "eth")
        self.addr_a = self.cfg.get("HostA", "addrA")
        self.addr_v6_a = self.cfg.get("HostA", "addr6A")
        if self.cfg.has_option("HostA", "reload"):
            self.reload_a = self.cfg.getboolean("HostA", "reload")


        # Host B
        self.host_b = NrtSystem(self.cfg.get("HostB", "name"), self.quick)
        self.eth_b = self.cfg.get("HostB", "eth")
        self.addr_b = self.cfg.get("HostB", "addrB")
        self.addr_v6_b = self.cfg.get("HostB", "addr6B")
        if self.cfg.has_option("HostB", "reload"):
            self.reload_b = self.cfg.getboolean("HostB", "reload")

        return
