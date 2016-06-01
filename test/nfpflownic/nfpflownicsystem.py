##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##

"""
Subclasses to handle NFPFLOWNIC system

These are functions to encapsulate the loading, configuring of NFPFLOWNIC.

"""

import os
import re
from netro.testinfra import LOG_sec, LOG_endsec, NFESystem, LOG
from libs.nrt_system import NrtSystem
from netro.testinfra.nti_exceptions import NtiFatalError, NtiTimeoutError
from nfpflownicpath import VROUTER_BUILD_PATH
from netro.testinfra.utilities import timed_poll


class NFPFlowNICSystem(NFESystem, NrtSystem):
    """A class for a system running NFPFLOWNIC"""

    def __init__(self, remote, cfg=None, dut=None, nfp=0, vnic_fn="nfp_net",
                 mefw_fn="basic_nic.nffw", nfpkmods=None, vnickmod=None,
                 mefw=None, macinitjson=None, macinitjson_fn=None,
                 initscript=None, initscript_fn=None,
                 mkfirmware=None, mkfirmware_fn='mkfirmware-device.sh',
                 load_mode='kernel', customized_kmod=False, expected_ports=1,
                 quick=False, _noendsec=False):
        """
        Initialise the system object.

        @remote:     How to get to the host. This can be user@host
                     or just a host.  A host is either a hostname or an IP
                     address.  If only a host is given root is assumed as user.
        @quick:      Omit some/most of the system gathering to speed up init

        """

        NFESystem.__init__(self, remote, quick=quick, _noendsec=True)
        NrtSystem.__init__(self, remote, quick=quick)

        self.cfg = cfg
        self.dut_object = dut
        self.nfp = nfp
        self.vnic_fn = vnic_fn
        self.mefw_fn = mefw_fn
        self.nfpkmods = nfpkmods
        self.vnickmod = vnickmod
        self.mefw = mefw
        self.macinitjson = macinitjson
        self.macinitjson_fn = macinitjson_fn
        self.initscript = initscript
        self.initscript_fn = initscript_fn

        self.mkfirmware = mkfirmware
        self.mkfirmware_fn = mkfirmware_fn
        self.load_mode = load_mode
        self.customized_kmod = customized_kmod
        self.expected_ports = expected_ports

        self.tmpdir = None
        self.eth_x = None
        self.eht_y = None
        self.eth_list = []
        self.linux_rev = None
        self.eth_dict = None
        self.rss_key = None

        if self.cfg or self.dut_object:
            self.setup_dut()

        if not _noendsec:
            LOG_endsec()
        return

    def setup_dut(self):
        """Initialise the systems for tests from this group
        called from the groups run() method.
        """
        #
        # DUT Setup
        #
        LOG_sec("Initialise DUT: %s" % self.host)
        # make tmpdir unique per DUT
        self.tmpdir = self.make_temp_dir()
        before_eth_dict = {}

        if self.dut_object:
            platform = None
            chip_rev = None
            self.get_sysctl()
            kernel_ver = self._sysctl["kernel.osrelease"]

            # Kernel version in the tarball does not matter as we only
            # use the firmware from it
            build_name = 'LATEST-vrouter_3.13.0-40_hydrogen_B0'
            build_file = os.path.join(VROUTER_BUILD_PATH, build_name)
            cmd = 'cp ' + build_file + ' ' + self.tmpdir
            try:
                self.cmd(cmd)
            except:
                self.rm_dir(self.tmpdir)
                raise NtiFatalError(msg="Fail to cp vrouter build in DUT")

            # Untar the build.
            tmp_build_file = os.path.join(self.tmpdir, build_name)
            cmd = 'tar -C ' + self.tmpdir + ' -xvf ' + tmp_build_file + \
                  ' --strip 2'
            self.cmd(cmd)
            self.cmd("rmmod %s" % self.vnic_fn, fail=False)
            self.cmd("rmmod nfp_netvf", fail=False)
            self.cmd("rmmod nfp_net", fail=False)
            self.cmd("modprobe nfp nfp_reset=1", fail=False)

            if self.load_mode == 'userspace':
                ## User space loading.
                ## Soft-reset NFP (in case that fw has been loaded before)
                before_eth_dict = self.userspace_mode_setup(use_cfg=False)

            elif self.load_mode == 'kernel':
                # Kernel loading
                # Create the directory where the firmware is going to live.
                # Soft-reset NFP (in case that fw has been loaded before)
                lib_netro_dir = os.path.join(os.path.sep, 'lib', 'firmware',
                                             'netronome')
                cmd = 'rm -rf %s' % lib_netro_dir
                self.cmd(cmd, fail=False)
                cmd = 'mkdir -p %s' % lib_netro_dir
                self.cmd(cmd, fail=False)
                self.cmd('ls %s' % self.tmpdir, fail=False)
                #self.unload_preload_mefw()

                try:
                    cmd = ('nfp-nffw2ca -a `nfp-hwinfo | grep -o "AMDA.*$"` -z %s %s' %
                           (os.path.join(self.tmpdir, 'firmware', self.mefw_fn),
                            os.path.join(self.tmpdir, 'firmware',
                                         'nfp6000_net.cat')))
                    self.cmd(cmd)

                    # Copy the newly created image into the default location.
                    cmd = 'cp %s %s' % (os.path.join(self.tmpdir, 'firmware',
                                                     'nfp6000_net.cat'),
                                        os.path.join(lib_netro_dir,
                                                     'nfp6000_net.cat'))
                    self.cmd(cmd)

                    self.cmd("rmmod nfp", fail=False)

                except:
                    msg = 'Faile to create nfp6000_net.cat. ' \
                          'You may need to power cycle the DUT. '
                    self.rm_dir(self.tmpdir)
                    raise NtiFatalError(msg=msg)

                try:
                    before_eth_dict = self.get_eth_dict()
                    self.load_nfp_net()
                except:
                    msg = 'Faile to load nfp_net. ' \
                          'You may need to power cycle the DUT. '
                    self.rm_dir(self.tmpdir)
                    raise NtiFatalError(msg=msg)

        elif self.cfg:
            if self.load_mode == 'kernel':
                self.cmd("rmmod nfp_netvf", fail=False)
                self.cmd("rmmod nfp_net", fail=False)
                if self.nfpkmods:
                    self.cp_to(self.nfpkmods, self.tmpdir)
                    nfp_ko_file = os.path.join(self.tmpdir, "nfp.ko")
                    self.cmd('insmod %s nfp_reset=1' % nfp_ko_file)
                else:
                    self.cmd("modprobe nfp nfp_reset=1")

                lib_netro_dir = os.path.join(os.path.sep, 'lib', 'firmware',
                                             'netronome')
                cmd = 'rm -rf %s' % lib_netro_dir
                self.cmd(cmd, fail=False)
                cmd = 'mkdir -p %s' % lib_netro_dir
                self.cmd(cmd, fail=False)
                #self.unload_preload_mefw()

                try:
                    # Create the firmware image.
                    self.cp_to(self.mefw, self.tmpdir)
                    cmd = ('nfp-nffw2ca -a `nfp-hwinfo | grep -o "AMDA.*$"` -z %s %s' %
                           (os.path.join(self.tmpdir, self.mefw_fn),
                            os.path.join(self.tmpdir, 'nfp6000_net.cat')))
                    self.cmd(cmd)

                    # Copy the newly created image into the default location.
                    cmd = 'cp %s %s' % (os.path.join(self.tmpdir,
                                                     'nfp6000_net.cat'),
                                        os.path.join(lib_netro_dir,
                                                     'nfp6000_net.cat'))
                    self.cmd(cmd)

                    self.cmd("rmmod nfp", fail=False)

                except:
                    msg = 'Faile to create nfp6000_net.cat. ' \
                          'You may need to power cycle the DUT. '
                    self.rm_dir(self.tmpdir)
                    raise NtiFatalError(msg=msg)

                try:
                    before_eth_dict = self.get_eth_dict()

                    if self.customized_kmod:
                        self.cp_to(self.vnickmod, self.tmpdir)
                        self.vnic_fn = os.path.basename(self.vnickmod)
                        kmod_file = os.path.join(self.tmpdir, self.vnic_fn)
                        self.load_nfp_net(ko_file=kmod_file)

                    else:
                        self.load_nfp_net()
                except:
                    msg = 'Faile to load nfp_net. ' \
                          'You may need to power cycle the DUT. '
                    self.rm_dir(self.tmpdir)
                    raise NtiFatalError(msg=msg)
            elif self.load_mode == 'userspace':
                if self.nfpkmods:
                    self.cp_to(self.nfpkmods, self.tmpdir)
                    nfp_ko_file = os.path.join(self.tmpdir, "nfp.ko")
                else:
                    nfp_ko_file = None

                if self.customized_kmod:
                    self.cp_to(self.vnickmod, self.tmpdir)
                    self.vnic_fn = os.path.basename(self.vnickmod)
                    nfp_net_ko_file = os.path.join(self.tmpdir, self.vnic_fn)

                else:
                    nfp_net_ko_file = None

                before_eth_dict = \
                    self.userspace_mode_setup(nfp_net_ko_file=nfp_net_ko_file,
                                              nfp_ko_file=nfp_ko_file)
        # Check that a new interface was created.
        LOG_sec("Verify a new interface was created.")
        try:
            timed_poll(60, self.check_for_new_interface, before_eth_dict,
                       delay=1)
        except NtiTimeoutError:
            raise NtiFatalError(msg="Failed to install vNIC module!")
        finally:
            # Clean up.
            self.rm_dir(self.tmpdir)
            LOG_endsec()  # Close out LOG_sec() from above.
        # Check that the name of the new interface has not been changed for 3s.
        LOG_sec("Verify the name of the new interface has not been changed "
                "for 3s.")
        try:
            timed_poll(20, self.is_eth_dict_stable, delay=1)
            after_eth_dict = self.get_eth_dict()
            diff_eth_list = list(set(after_eth_dict.keys()) -
                                 set(before_eth_dict.keys()))
            if len(diff_eth_list) > self.expected_ports:
                # Multiple interfaces are generated, we do not support this yet.
                raise NtiFatalError(msg="More interfaces are created, new "
                                        "configuration code needs to be added!")
            elif len(diff_eth_list) == self.expected_ports:
                # Expected one interface to be created, update the
                # classes eth_list and return.
                diff_eth_list.sort(key=lambda eth: after_eth_dict[eth])
                self.eth_list = diff_eth_list
        except NtiTimeoutError:
            raise NtiFatalError(msg="The name of new interface has been changed"
                                    " repeatedly")

        finally:
            # Clean up.
            self.rm_dir(self.tmpdir)
            LOG_endsec()  # Close out LOG_sec() from above.

        for eth in self.eth_list:
            # Bring the interface up to makes sure rss key is written to the
            # BAR after driver commit 0203dee66dcb ("nfp_net: perform RSS init
            # only during device initialization")
            self.cmd('ifconfig %s up ; ifconfig %s down' % (eth, eth))

        # Checking the value of _pf0_net_bar0 to get the RSS key
        # To parse it, we need to use the info from
        # nfp-drv-kmods.git/src/nfp_net_ctrl. (see SB-116 Pablo's comment)
        reg_name = '_pf0_net_bar0'
        cmd = 'nfp-rtsym %s' % reg_name
        _, out = self.cmd(cmd)
        # The following value is from nfp-drv-kmods.git/src/nfp_net_ctrl
        rss_base = '0x0100'
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

        bit_number = {'0': 0, '1': 1, '2': 1, '3': 2, '4': 1, '5': 2, '6': 2,
                      '7': 3, '8': 1, '9': 2, 'a': 2, 'b': 3, 'c': 2, 'd': 3,
                      'e': 3, 'f': 4}
        rss_str_stripped = rss_str[2:]
        total_1_bits = 0
        for i in range(0, len(rss_str_stripped)):
            total_1_bits += bit_number[rss_str_stripped[i]]
        LOG_sec("Checking the RSS key from nfp-rtsym")
        LOG('The RSS key is: ')
        LOG(rss_str)
        LOG('The number of bit 1 in RSS key is: %d' % total_1_bits)
        LOG_endsec()
        self.rss_key = rss_str

        return

    def get_assembly_model(self, fail=True):
        """ Get the assembly model from the nfp-hwinfo
        @return: Return the assembly model of the DUT
        """
        cmd = ("/opt/netronome/bin/nfp-hwinfo -n 0 2>/dev/null | "
               "grep assembly[.]model | cut -d = -f 2")
        ret = self.cmd(cmd, fail)
        result = ret[1].strip()

        return result

    def check_for_new_interface(self, before_eth_dict):
        """
        Check if new interface(s) created.

        :param before_eth_dict: List of current interfaces on the host before
                                adding the vNIC interface.
        :return: True if one new interface was created, Fatal if more than one,
                 False otherwise.
        """
        # Check for any new interfaces with after_eth_dict.
        after_eth_dict = self.get_eth_dict()
        diff_eth_list = list(set(after_eth_dict.keys()) -
                             set(before_eth_dict.keys()))

        if len(diff_eth_list) > self.expected_ports:
            # Multiple interfaces are generated, we do not support this yet.
            raise NtiFatalError(msg="More interfaces are created, new "
                                    "configuration code needs to be added!")
        elif len(diff_eth_list) == self.expected_ports:
            # Expected one interface to be created, update the
            # classes eth_list and return.
            return True
        else:
            return False

    def is_eth_dict_change(self):
        """
        return true if the dictionary of eth interfaces has been changed
        """
        cur_dict = self.get_eth_dict()
        if self.eth_dict == cur_dict:
            return False
        else:
            self.eth_dict = cur_dict
            return True

    def is_eth_dict_stable(self):
        """
        return true if the dictionary of eth interfaces has not been changed
        by wait_time seconds
        """
        wait_time = 3
        try:
            timed_poll(wait_time, self.is_eth_dict_change, delay=1)
        except NtiTimeoutError:
            # the dictionary of eth interfaces has not been changed
            return True
        # the dictionary of eth interfaces has been changed
        return False


    def get_eth_dict(self):
        """
        To get the dictionary of eth interfaces which have MAC addresses
        An example of the output of cmd 'ifconfig -a | grep -r HWaddr':
        eth0      Link encap:Ethernet  HWaddr 00:30:67:aa:7e:7a
        eth1      Link encap:Ethernet  HWaddr 52:51:61:89:b8:81
        """
        cmd = 'ifconfig -a | grep HWaddr'
        _, out = self.cmd(cmd)
        lines = out.splitlines()
        eth_dict = {}
        for line in lines:
            line_re = '[\w\-_]+ +Link encap:Ethernet +HWaddr +' \
                      '([0-9a-f]{2}:){5}[0-9a-f]{2}'
            if re.match(line_re, line):
                name, _, _, _, hw_addr = line.split()
                eth_dict[name] = hw_addr
            else:
                raise NtiFatalError(msg="Unexpected ifconfig output "
                                        "in get_eth_dict")
        return eth_dict

    def _get_netifs(self):
        """Get a list of network interface on the system"""
        # We create a entry with None as the value here for every interface
        # and lazily fill in a NetIF structure when requested.
        _, out = self.cmd("/sbin/ip link")

        self._netifs = {}
        lines = out.split("\n")
        for line in lines[0:]:
            if line == "" or line.startswith(" "):
                continue
            intf = line.split(":", 2)[1].strip()
            if intf == "lo":
                continue # ignore loopback
            self._netifs[intf] = None
        return

    def rmmod_bsp(self):
        """remove the BSP modules (more specifically, rmmod nfp, nfp_net
        nfp_pcie, and nfp_cppcore).
        """
        #cmd = "killall nfp-errlogd; rmmod nfp_err nfp nfp_pcie " \
        #      "nfp_cppcore"
        #self.cmd(cmd, fail=False)
        cmd = 'rmmod nfp'
        self.cmd(cmd, fail=False)
        cmd = 'rmmod %s' % self.vnic_fn
        self.cmd(cmd, fail=False)
        cmd = 'rmmod nfp_pcie'
        self.cmd(cmd, fail=False)
        cmd = 'rmmod nfp_cppcore'
        self.cmd(cmd, fail=False)

    def reload_bsp(self, path=None):
        """Reload the BSP modules (more specifically, rmmod nfp,
        nfp_pcie, and nfp_cppcore, and then insmod nfp only).

        """
        LOG_sec("%s: (re)load BSP modules from %s" %
                (self.host, path if path else "default"))
        try:
            self.rmmod_bsp()
            if path:
                cmd = "insmod %s/nfp.ko" % path
                self.cmd(cmd)
            else:
                self.cmd("modprobe nfp")
        except:
            self.rm_dir(self.tmpdir)
            raise NtiFatalError(msg="Fail to reload_bsp in NFPFlowNICSystem")
        finally:
            LOG_endsec()

    def load_nfp_net(self,  mode='kernel', ko_file=None):
        """Reload the BSP modules (more specifically, rmmod nfp,
        nfp_pcie, and nfp_cppcore, and then insmod nfp only).

        """
        LOG_sec("%s: nfp_net modules from /lib/module" % self.host)
        try:
            if mode == 'userspace':
                # User space loading
                self.cmd("rm -rf /lib/firmware/netronome", fail=False)
                if ko_file:
                    self.cmd("modprobe vxlan", fail=False)
                    self.cmd("insmod %s num_rings=32" % ko_file)
                else:
                    self.cmd('modprobe %s num_rings=32' % self.vnic_fn)

            elif mode == 'kernel':
                # Kernel loading
                # fw_noload=0 to override grub global setting
                if ko_file:
                    self.cmd("modprobe vxlan", fail=False)
                    self.cmd("insmod %s nfp_reset=1 fw_noload=0 "
                             "num_rings=32" % ko_file)
                else:
                    self.cmd('modprobe %s nfp_reset=1  fw_noload=0 '
                             'num_rings=32' % self.vnic_fn)
        except:
            self.rm_dir(self.tmpdir)
            raise NtiFatalError(msg="Fail to load_nfp_net in NFPFlowNICSystem")
        finally:
            LOG_endsec()

    def load_mefw(self, path, nfp=0, start=True):
        """Load the specified firmware image onto the specified NFP.
        Unload an existing one before (change the utility name nfp-mefw to
        nfp-nffw).

        Start firmware by default, else no-start of firmware
        execution after load.

        @path:   Path to firmware image
        @nfp    NFP device
        @start  True (Default) to start firmware, False for no-start
                of firmware
        """
        cmd = "nfp-nffw unload -n %d && " % (nfp)
        cmd += "nfp-nffw %s load -n %d" % (path, nfp)
        if start == False:
            cmd += " --no-start"
        try:
            self.cmd(cmd)
        except:
            self.rm_dir(self.tmpdir)
            raise NtiFatalError(msg="Fail to Load the firmware image "
                                    "onto the NFP")
        return

    def start_mefw(self, nfp=0):
        """Start ME execution

        @nfp    NFP device
        """
        cmd = "nfp-nffw start --nfp=%d" % (nfp)
        try:
            self.cmd(cmd)
        except:
            self.rm_dir(self.tmpdir)
            raise NtiFatalError(msg="Fail to start the MEs")

        return

    def unload_mefw(self, nfp=0):
        """Unload an existing firmware image from the specified NFP

        @nfp    NFP device
        """
        cmd = "nfp-nffw unload --nfp %d" % (nfp)
        try:
            self.cmd(cmd, fail=False)
        except:
            self.rm_dir(self.tmpdir)
            raise NtiFatalError(msg="Fail to unload the fw")

        return

    def userspace_mode_setup(self, nfp_net_ko_file=None, nfp_ko_file=None,
                             use_cfg=True):
        """
        load the fw and kernel module in userspace, with cfg
        """
        # Set the DUT up to start getting packets in and out:
        if use_cfg:
            self.cp_to(self.mefw, self.tmpdir)
            mefw = os.path.join(self.tmpdir, self.mefw_fn)
        else:
            mefw = os.path.join(self.tmpdir, 'firmware', self.mefw_fn)

        self.cmd("rmmod nfp", fail=False)
        self.cmd("rmmod nfp_net", fail=False)
        self.cmd("rmmod nfp_netvf", fail=False)

        before_eth_dict = self.get_eth_dict()
        if nfp_ko_file:
            self.cmd("insmod %s nfp_reset=1" % nfp_ko_file)
        else:
            self.cmd("modprobe nfp nfp_reset=1")
        self.cmd("nfp-nffw unload", fail=False)
        self.cmd("nfp-nffw load %s" % mefw)
        self.cmd("rmmod nfp", fail=False)
        self.cmd("rm -rf /lib/firmware/netronome", fail=False)
        if nfp_net_ko_file:
            self.cmd("modprobe vxlan", fail=False)
            self.cmd("insmod %s" % nfp_net_ko_file)
        else:
            self.cmd("modprobe nfp_net")

        return before_eth_dict

    def unload_preload_mefw(self, nfp=0):

        cmd = 'source nfp-shutils; mac_rxctl %s 0 disable' % nfp
        self.cmd(cmd)
        cmd = 'nfp-nffw unload -n %s' % nfp
        self.cmd(cmd)
        cmd = 'nfp-cpp -n %s --len=0x1000 --raw --stdin ' \
              '7:0x8100001000 </dev/zero' % nfp
        self.cmd(cmd)
