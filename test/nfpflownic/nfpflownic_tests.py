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
from netro.testinfra import LOG_sec, LOG_endsec, LOG
from netro.testinfra.nti_exceptions import NtiError, NtiFatalError
from nfpflownicsystem import NFPFlowNICSystem, localNrtSystem
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
        ("kmod", [False, "Path to dir containing kernel mod to load on DUT"]),
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
        self.kmod = None
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
        self.mefw_fn = 'basic_nic.nffw'
        self.macinitjson = None
        self.macinitjson_fn = None

        self.dut = NFPFlowNICSystem(self.dut_object.name, cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    mefw_fn=self.mefw_fn, quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

        if len(self.dut.eth_list) > 1:
            # multiple interfaces are generated
            raise NtiFatalError(msg="more than one interfaces are created, new"
                                    " configuration code needs to be added")

        # Host A
        self.host_a = localNrtSystem(host_a_obj.name, self.quick)
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

        cmd = 'ifconfig %s up ; ifconfig %s down' % (self.eth_x, self.eth_x)
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
        if self.cfg.has_option("DUT", "kmod"):
            self.kmod = self.cfg.get("DUT", "kmod")
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

        if self.customized_kmod and not self.kmod:
            raise NtiError('Cannot customized kmod set but no kmod path in cfg')

        self.dut = NFPFlowNICSystem(self.cfg.get("DUT", "name"), cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    mefw_fn=self.mefw_fn,
                                    kmod=self.kmod,
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
        self.host_a = localNrtSystem(self.cfg.get("HostA", "name"), self.quick)
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
         self.mefw_fn = 'basic_nic.nffw'
         self.macinitjson = None
         self.macinitjson_fn = None

         self.dut = NFPFlowNICSystem(self.dut_object.name,
                                     cfg=self.cfg,
                                     dut=self.dut_object,
                                     nfp=self.nfp,
                                     macinitjson=self.macinitjson,
                                     macinitjson_fn=self.macinitjson_fn,
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
         self.host_a = localNrtSystem(host_a_obj.name, self.quick)
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
        if self.cfg.has_option("DUT", "kmod"):
            self.kmod = self.cfg.get("DUT", "kmod")
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

        if self.customized_kmod and not self.kmod:
            raise NtiError('Cannot customized kmod set but no kmod path in cfg')

        self.dut = NFPFlowNICSystem(self.cfg.get("DUT", "name"), cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    mefw_fn=self.mefw_fn,
                                    kmod=self.kmod,
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
        self.host_a = localNrtSystem(self.cfg.get("HostA", "name"), self.quick)
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
        ("kmod", [False, "Path to dir containing kernel mod to load on DUT"]),
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
        self.mefw_fn = 'basic_nic.nffw'
        self.macinitjson = None
        self.macinitjson_fn = None

        self.dut = NFPFlowNICSystem(self.dut_object.name, cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    mefw_fn=self.mefw_fn, quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

        if len(self.dut.eth_list) > 1:
            # multiple interfaces are generated
            raise NtiFatalError(msg="more than one interfaces are created, new"
                                    " configuration code needs to be added")

        # Host A
        self.host_a = localNrtSystem(host_a_obj.name, self.quick)
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
        if self.cfg.has_option("DUT", "kmod"):
            self.kmod = self.cfg.get("DUT", "kmod")
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

        if self.customized_kmod and not self.kmod:
            raise NtiError('Cannot customized kmod set but no kmod path in cfg')

        self.dut = NFPFlowNICSystem(self.cfg.get("DUT", "name"), cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    mefw_fn=self.mefw_fn,
                                    kmod=self.kmod,
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
        self.host_a = localNrtSystem(self.cfg.get("HostA", "name"), self.quick)
        self.eth_a = self.cfg.get("HostA", "eth")
        self.addr_a = self.cfg.get("HostA", "addrA")
        self.addr_v6_a = self.cfg.get("HostA", "addr6A")
        if self.cfg.has_option("HostA", "reload"):
            self.reload_a = self.cfg.getboolean("HostA", "reload")


        # Host B
        self.host_b = localNrtSystem(self.cfg.get("HostB", "name"), self.quick)
        self.eth_b = self.cfg.get("HostB", "eth")
        self.addr_b = self.cfg.get("HostB", "addrB")
        self.addr_v6_b = self.cfg.get("HostB", "addr6B")
        if self.cfg.has_option("HostB", "reload"):
            self.reload_b = self.cfg.getboolean("HostB", "reload")

        return


###############################################################################
# A group of N-port unit tests
###############################################################################
class _NFPFlowNIC_nport(netro.testinfra.Group):
    """Simple unit tests tests"""

    summary = "NFPFlowNIC tests"

    _info = """
    Run a barrage of simple unit tests against an NFP configured as
    Just-a-NIC. The tests are designed to test particular aspects of
    the nfpflowNIC.

    The test configuration looks like this:

                     DUT
                 ethD0  ethD1 (D2 ...)
                    ^     ^
    Host EP0        |     |      Host EP1 (EP2 ...)
      ethEP0 <------+     +------> ethEP1 (EP2 ...)

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
        ("addrD", [True, "IPv4 addresses/masks to be assigned to ethX"]),
        ("addr6D", [True, "IPv6 addresses/masks to be assigned to ethX"]),
        ("kmod", [False, "Path to dir containing kernel mod to load on DUT"]),
        ("nfp", [False, "NFP device number to use (default 0)"]),
        ("num_port", [False, "Number of physical NIC ports and expected "
                             "netdevs"]),
        ("mefw", [False, "Path to firmware image to load"]),
        ("mkfirmware", [False, "Path to the script producing CA kernel ready "
                               "firmware"]),
        ("load_mode", [False, "How to load fw: 'kernel' or 'userspace'"]),
    ])
    _config["HostEP"] = collections.OrderedDict([
        ("names", [True, "Host name of the Host A (can also be <user>@<host> "
                        "or IP address). Assumes root as default."]),
        ("ethEP", [True, "Name of the interface on Host A"]),
        ("addrEP", [True, "IPv4 address/mask to be assigned to Host A"]),
        ("addr6EP", [True, "IPv4 address/mask to be assigned to Host A"]),
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
        self.num_port = None
        self.eth_d = []
        self.addr_d = []
        self.addr_v6_d = []
        self.intf_d = []

        self.host_ep = []
        self.eth_ep = []
        self.addr_ep = []
        self.addr_v6_ep = []
        self.intf_ep = []
        self.reload_ep = []
        self.reload_ep = None
        for i in range(0, self.expected_ports):
            self.eth_d.append(None)
            self.addr_d.append(None)
            self.addr_v6_d.append(None)
            self.intf_d.append(None)

            self.host_ep.append(None)
            self.eth_ep.append(None)
            self.addr_ep.append(None)
            self.addr_v6_ep.append(None)
            self.intf_ep.append(None)


        self.quick = quick
        self.dut_object = dut_object

        self.tmpdir = None
        self.cfg = cfg

        self.noclean = False

        self.dut = None
        self.nfp = 0
        self.kmod = None
        self.mefw = None
        self.mefw_fn = None
        self.mkfirmware = None
        self.mkfirmware_fn = None
        self.load_mode = 'kernel'
        self.customized_kmod=False

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

        for i in range(0, self.num_port):
            LOG_sec("Cleaning Host A: %s" % self.host_ep[i].host)
            self.host_ep[i].clean_attached_nodes(intf="")
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
        self.dut.cmd('mkdir %s' % self.nc_path)
        self.dut.cp_to(self.nc_repo, self.nc_path)
        self.dut.cmd('gcc %s -o %s' % (self.rm_nc_src, self.rm_nc_bin))
        for i in range(0, self.num_port):
            self.host_ep[i].cmd('rm -rf %s' % self.nc_path, fail=False)
            self.host_ep[i].cmd('mkdir %s' % self.nc_path)
            self.host_ep[i].cp_to(self.nc_repo, self.nc_path)
            self.host_ep[i].cmd('gcc %s -o %s' % (self.rm_nc_src,
                                                  self.rm_nc_bin))

        return

    def _fini(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        kill_bg_process(self.dut.host, "TCPKeepAlive")
        for client in self.host_ep:
            kill_bg_process(client.host, "TCPKeepAlive")

        # Unit test group installes Jakub's netcat tools. So clean up here
        self.dut.cmd('rm -rf %s' % self.nc_path, fail=False)
        for i in range(0, self.num_port):
            self.host_ep[i].cmd('rm -rf %s' % self.nc_path, fail=False)

        netro.testinfra.Group._fini(self)
        return

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
        self.mefw_fn = 'basic_nic.nffw'
        self.macinitjson = None
        self.macinitjson_fn = None

        self.dut = NFPFlowNICSystem(self.dut_object.name, cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    mefw_fn=self.mefw_fn, quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

        if len(self.dut.eth_list) != self.expected_ports:
            # multiple interfaces are generated
            raise NtiFatalError(msg=" number of interfaces not matched, new"
                                    " configuration code needs to be added")

        # Host A
        self.host_a = localNrtSystem(host_a_obj.name, self.quick)
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
        for i in range(0, self.num_port):
            self.dut.clean_attached_nodes(intf=self.eth_d[i])
            cmd = 'ip addr flush dev %s; ' % self.eth_d[i]
            cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_d[i],
                                                   self.addr_v6_d[i])
            cmd += 'ifconfig %s %s up; ' % (self.eth_d[i], self.addr_d[i])
            ret, _ = self.dut.cmd(cmd)
            if ret:
                raise NtiFatalError(msg="Error in DUT VNIC addr configuration")

        for i in range(0, self.num_port):
            self.host_ep[i].clean_attached_nodes(intf=self.eth_ep[i])
            cmd = 'ip addr flush dev %s; ' % self.eth_ep[i]
            cmd += 'ifconfig %s inet6 add %s; ' % (self.eth_ep[i],
                                                   self.addr_v6_ep[i])
            cmd += 'ifconfig %s %s up; ' % (self.eth_ep[i], self.addr_ep[i])
            ret, _ = self.host_ep[i].cmd(cmd)
            if ret:
                raise NtiFatalError(msg="Error in endpoint intf addr "
                                        "configuration")
            self.host_ep[i].refresh()

        self.dut.refresh()

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
        if self.cfg.has_option("DUT", "num_port"):
            self.num_port = self.cfg.getint("DUT", "num_port")

        self.addr_d = self.cfg.get("DUT", "addrD").split(',')
        self.addr_v6_d = self.cfg.get("DUT", "addr6D").split(',')


        if self.cfg.has_option("DUT", "nfp"):
            self.nfp = self.cfg.getint("DUT", "nfp")
        if self.cfg.has_option("DUT", "kmod"):
            self.kmod = self.cfg.get("DUT", "kmod")
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

        if self.customized_kmod and not self.kmod:
            raise NtiError('Cannot customized kmod set but no kmod path in cfg')

        self.dut = NFPFlowNICSystem(self.cfg.get("DUT", "name"), cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    mefw_fn=self.mefw_fn,
                                    kmod=self.kmod,
                                    mefw=self.mefw,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    initscript = self.initscript,
                                    initscript_fn = self.initscript_fn,
                                    mkfirmware=self.mkfirmware,
                                    mkfirmware_fn=self.mkfirmware_fn,
                                    load_mode=self.load_mode,
                                    customized_kmod=self.customized_kmod,
                                    expected_ports=self.expected_ports,
                                    quick=self.quick)
        self.eth_d = self.dut.eth_list
        self.rss_key = self.dut.rss_key

        cmd = 'nfp-hwinfo | grep mac'
        _, out = self.dut.cmd(cmd)
        re_ethmac = 'eth\d+.mac='
        ports_strs = re.findall(re_ethmac, out)

        cmd = 'nfp-media'
        _, out = self.dut.cmd(cmd)

        if ports_strs:
            num_ports = len(ports_strs)
            if num_ports != self.expected_ports:
                raise NtiFatalError(msg="%d ports are expected, but only %d "
                                        "created" % (self.expected_ports,
                                                     num_ports))
        else:
            raise NtiFatalError(msg="nfp-hwinfo | grep mac returns no ports")

        if len(self.addr_d) != self.num_port \
                or len(self.addr_v6_d) != self.num_port \
                or self.num_port!= self.expected_ports:
            raise NtiFatalError(msg="number of DUT ports in cfg file not "
                                    "correct")
        # Hosts
        host_list = self.cfg.get("HostEP", "names").split(',')
        for i in range(0, len(host_list)):
            self.host_ep[i] = localNrtSystem(host_list[i], self.quick)
        self.eth_ep = self.cfg.get("HostEP", "ethEP").split(',')
        self.addr_ep = self.cfg.get("HostEP", "addrEP").split(',')
        self.addr_v6_ep = self.cfg.get("HostEP", "addr6EP").split(',')
        if len(self.host_ep) != self.num_port \
                or len(self.eth_ep) != self.num_port \
                or len(self.addr_ep) != self.num_port \
                or len(self.addr_v6_ep) != self.num_port:
            raise NtiFatalError(msg="number of endpoint ports in cfg file not "
                                    "correct")
        if self.cfg.has_option("HostEP", "reload"):
            self.reload_ep = self.cfg.getboolean("HostEP", "reload")

        return

###############################################################################
# A group of unit tests
###############################################################################
class _NFPFlowNIC_no_fw_loading(netro.testinfra.Group):
    """Simple unit tests tests"""

    summary = "NFPFlowNIC tests without auto fw loading"

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
        ("ethX", [True, "Name of the interface on the DUT"]),
        ("addrX", [True, "IPv4 address/mask to be assigned to ethX"]),
        ("addr6X", [True, "IPv6 address/mask to be assigned to ethX"])
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

        self.host_a = None
        self.eth_a = None
        self.addr_a = None
        self.addr_v6_a = None
        self.intf_a = None
        self.reload_a = False
        self.rss_key = None

        self.nc_path = '/tmp/nc/'
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

        if not self.dut.exists_host(self.rm_nc_bin):
            self.dut.cmd('mkdir %s' % self.nc_path)
            self.dut.cp_to(self.nc_repo, self.nc_path)
            self.dut.cmd('gcc %s -o %s' % (self.rm_nc_src, self.rm_nc_bin))
        if not self.host_a.exists_host(self.rm_nc_bin):
            self.host_a.cmd('mkdir %s' % self.nc_path)
            self.host_a.cp_to(self.nc_repo, self.nc_path)
            self.host_a.cmd('gcc %s -o %s' % (self.rm_nc_src, self.rm_nc_bin))

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

    ### TODO: need to update for no-fw-loading
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
        self.mefw_fn = 'basic_nic.nffw'
        self.macinitjson = None
        self.macinitjson_fn = None

        self.dut = NFPFlowNICSystem(self.dut_object.name, cfg=self.cfg,
                                    dut=self.dut_object,
                                    nfp=self.nfp,
                                    macinitjson=self.macinitjson,
                                    macinitjson_fn=self.macinitjson_fn,
                                    mefw_fn=self.mefw_fn, quick=self.quick)
        self.eth_x = self.dut.eth_list[0]
        self.rss_key = self.dut.rss_key

        if len(self.dut.eth_list) > 1:
            # multiple interfaces are generated
            raise NtiFatalError(msg="more than one interfaces are created, new"
                                    " configuration code needs to be added")

        # Host A
        self.host_a = localNrtSystem(host_a_obj.name, self.quick)
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
        self.dut = localNrtSystem(self.cfg.get("DUT", "name"), self.quick)
        self.eth_x = self.cfg.get("DUT", "ethX")
        self.addr_x = self.cfg.get("DUT", "addrX")
        self.addr_v6_x = self.cfg.get("DUT", "addr6X")

        self.rss_key = self.get_rss_key()

         # Host A
        self.host_a = localNrtSystem(self.cfg.get("HostA", "name"), self.quick)
        self.eth_a = self.cfg.get("HostA", "eth")
        self.addr_a = self.cfg.get("HostA", "addrA")
        self.addr_v6_a = self.cfg.get("HostA", "addr6A")
        if self.cfg.has_option("HostA", "reload"):
            self.reload_a = self.cfg.getboolean("HostA", "reload")

        return

    def get_rss_key(self):
        # Bring the interface up to makes sure rss key is written to the
        # BAR after driver commit 0203dee66dcb ("nfp_net: perform RSS init
        # only during device initialization")
        self.dut.cmd('ifconfig %s up ; ifconfig %s down' % (self.eth_x, self.eth_x))
        # Checking the value of _pf0_net_bar0 to get the RSS key
        # To parse it, we need to use the info from
        # nfp-drv-kmods.git/src/nfp_net_ctrl. (see SB-116 Pablo's comment)
        reg_name = '_pf0_net_bar0'
        cmd = 'nfp-rtsym %s' % reg_name
        _, out = self.dut.cmd(cmd)
        # The following value is from nfp-drv-kmods.git/src/nfp_net_ctrl
        rss_keys = []
        for rss_base in ['0x00100', '0x08100', '0x10100', '0x18100',
                         '0x20100', '0x28100', '0x30100', '0x38100']:
            rss_offset = '0x4'
            rss_size = '0x28'

            rss_start = int(rss_base, 16) + int(rss_offset, 16)
            rss_end = int(rss_base, 16) + int(rss_offset, 16) + int(rss_size, 16)
            rss_str = '0x'
            lines = out.splitlines()
            for line in lines:
                line_re = '0x[\da-fA-F]{10}:\s+(?:0x[\da-fA-F]{8}\s*){4}'
                index_re = '(0x[\da-fA-F]{10}):\s+'
                value_re = '\s+(0x[\da-fA-F]{8})'
                if re.match(line_re, line):
                    index = re.findall(index_re, line)
                    values = re.findall(value_re, line)
                    if int(rss_base, 16) <= int(index[0], 16) < rss_end:
                        for i in range(0, 4):
                            cur_index = int(index[0], 16) + i * 4
                            if rss_start <= cur_index < rss_end:
                                rss_str = rss_str + values[i][2:]
            rss_keys.append(rss_str)

        LOG_sec("Checking the RSS key from nfp-rtsym")
        LOG('The RSS keys are: ')
        for rss_str in rss_keys:
            LOG(rss_str)
        LOG_endsec()

        return rss_keys


###############################################################################
# A group of Perf tests with kernel loading
###############################################################################
class _NFPFlowNICPerfTest_nport(_NFPFlowNIC_nport):

    # Perf test group does not need Jakub's netcat tools. So override the _init
    # and _fini here
    def _init(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        netro.testinfra.Group._init(self)

        return

    def _configure_intfs(self):
        """
        Configure eth_a of the host_a with IPv4 address addr_a and IPv6 address
        addr_v6_a. Also configure eth_x of the DUT with IPv4 address addr_x and
        IPv6 address addr_v6_x
        Also Pin interrupts for iperf tests
        """

        _NFPFlowNIC_nport._configure_intfs(self)
        ir_list = []

        for i in range(0, self.num_port):
            cmd = 'cat /proc/interrupts | grep %s-rxtx | cut -d : -f 1' % \
                  self.eth_d[i]
            ret, out = self.dut.cmd(cmd)
            ir_list.append([y for y in (x.strip() for x in out.splitlines()) if y])

        cmd = 'service irqbalance stop'
        self.dut.cmd(cmd, fail=False)

        cmd = ""
        for j in range(0, self.num_port):
            i = 0
            for ir in ir_list[j]:
                cmd += "echo %d > /proc/irq/%d/smp_affinity_list && " % \
                       (i, int(ir))
                i += 1
            cmd = cmd[:-2]
            self.dut.cmd(cmd)

class _NFPFlowNIC_nport_no_fw_loading(_NFPFlowNIC_nport):

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
        if self.cfg.has_option("DUT", "num_port"):
            self.num_port = self.cfg.getint("DUT", "num_port")

        self.eth_d = self.cfg.get("DUT", "ethD").split(',')
        self.addr_d = self.cfg.get("DUT", "addrD").split(',')
        self.addr_v6_d = self.cfg.get("DUT", "addr6D").split(',')

        self.dut = localNrtSystem(self.cfg.get("DUT", "name"), self.quick)
        self.rss_key = self.get_rss_key()

        cmd = 'nfp-hwinfo | grep mac'
        _, out = self.dut.cmd(cmd)
        re_ethmac = 'eth\d+.mac='
        ports_strs = re.findall(re_ethmac, out)

        cmd = 'nfp-media'
        _, out = self.dut.cmd(cmd)

        if ports_strs:
            num_ports = len(ports_strs)
            if num_ports != self.expected_ports:
                raise NtiFatalError(msg="%d ports are expected, but only %d "
                                        "created" % (self.expected_ports,
                                                     num_ports))
        else:
            raise NtiFatalError(msg="nfp-hwinfo | grep mac returns no ports")

        if len(self.addr_d) != self.num_port \
                or len(self.addr_v6_d) != self.num_port \
                or self.num_port!= self.expected_ports:
            raise NtiFatalError(msg="number of DUT ports in cfg file not "
                                    "correct")
        # Hosts
        host_list = self.cfg.get("HostEP", "names").split(',')
        for i in range(0, len(host_list)):
            self.host_ep[i] = localNrtSystem(host_list[i], self.quick)
        self.eth_ep = self.cfg.get("HostEP", "ethEP").split(',')
        self.addr_ep = self.cfg.get("HostEP", "addrEP").split(',')
        self.addr_v6_ep = self.cfg.get("HostEP", "addr6EP").split(',')
        if len(self.host_ep) != self.num_port \
                or len(self.eth_ep) != self.num_port \
                or len(self.addr_ep) != self.num_port \
                or len(self.addr_v6_ep) != self.num_port:
            raise NtiFatalError(msg="number of endpoint ports in cfg file not "
                                    "correct")
        if self.cfg.has_option("HostEP", "reload"):
            self.reload_ep = self.cfg.getboolean("HostEP", "reload")

        return

    def get_rss_key(self):
        # Bring the interface up to makes sure rss key is written to the
        # BAR after driver commit 0203dee66dcb ("nfp_net: perform RSS init
        # only during device initialization")
        for eth in self.eth_d:
            self.dut.cmd('ifconfig %s up ; ifconfig %s down' % (eth, eth))
        # Checking the value of _pf0_net_bar0 to get the RSS key
        # To parse it, we need to use the info from
        # nfp-drv-kmods.git/src/nfp_net_ctrl. (see SB-116 Pablo's comment)
        reg_name = '_pf0_net_bar0'
        cmd = 'nfp-rtsym %s' % reg_name
        _, out = self.dut.cmd(cmd)
        # The following value is from nfp-drv-kmods.git/src/nfp_net_ctrl
        rss_keys = []
        for rss_base in ['0x00100', '0x08100', '0x10100', '0x18100',
                         '0x20100', '0x28100', '0x30100', '0x38100']:
            rss_offset = '0x4'
            rss_size = '0x28'

            rss_start = int(rss_base, 16) + int(rss_offset, 16)
            rss_end = int(rss_base, 16) + int(rss_offset, 16) + int(rss_size, 16)
            rss_str = '0x'
            lines = out.splitlines()
            for line in lines:
                line_re = '0x[\da-fA-F]{10}:\s+(?:0x[\da-fA-F]{8}\s*){4}'
                index_re = '(0x[\da-fA-F]{10}):\s+'
                value_re = '\s+(0x[\da-fA-F]{8})'
                if re.match(line_re, line):
                    index = re.findall(index_re, line)
                    values = re.findall(value_re, line)
                    if int(rss_base, 16) <= int(index[0], 16) < rss_end:
                        for i in range(0, 4):
                            cur_index = int(index[0], 16) + i * 4
                            if rss_start <= cur_index < rss_end:
                                rss_str = rss_str + values[i][2:]
            rss_keys.append(rss_str)

        LOG_sec("Checking the RSS key from nfp-rtsym")
        LOG('The RSS keys are: ')
        for rss_str in rss_keys:
            LOG(rss_str)
        LOG_endsec()

        return rss_keys

class _NFPFlowNICPerfTest_nport_no_fw_loading(_NFPFlowNIC_nport_no_fw_loading):

    # Perf test group does not need Jakub's netcat tools. So override the _init
    # and _fini here
    def _init(self):
        """ Clean up the systems for tests from this group
        called from the groups run() method.
        """
        netro.testinfra.Group._init(self)

        return

    def _configure_intfs(self):
        """
        Configure eth_a of the host_a with IPv4 address addr_a and IPv6 address
        addr_v6_a. Also configure eth_x of the DUT with IPv4 address addr_x and
        IPv6 address addr_v6_x
        Also Pin interrupts for iperf tests
        """

        _NFPFlowNIC_nport._configure_intfs(self)
        ir_list = []

        for i in range(0, self.num_port):
            cmd = 'cat /proc/interrupts | grep %s-rxtx | cut -d : -f 1' % \
                  self.eth_d[i]
            ret, out = self.dut.cmd(cmd)
            ir_list.append([y for y in (x.strip() for x in out.splitlines()) if y])

        cmd = 'service irqbalance stop'
        self.dut.cmd(cmd, fail=False)

        cmd = ""
        for j in range(0, self.num_port):
            i = 0
            for ir in ir_list[j]:
                cmd += "echo %d > /proc/irq/%d/smp_affinity_list && " % \
                       (i, int(ir))
                i += 1
            cmd = cmd[:-2]
            self.dut.cmd(cmd)
