#
# Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
#
"""
Unit test classes for the NFPFlowNIC Software Group.
"""

import os
import re
from netro.testinfra import Test, LOG_sec, LOG, LOG_endsec
from netro.testinfra.nrt_result import NrtResult
from netro.testinfra.nti_exceptions import NtiFatalError


class InstallBSPSDK(Test):
    """The tests in this file share a lot of common code which is kept
    in this class"""

    summary = "Install the requested BSP for the test suite."

    info = """Install the requested BSP for the test suite."""

    def __init__(self, test_obj, group=None, name="", summary=None):
        """
        @test_obj:   Object that contains the System objects
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        Test.__init__(self, group, name, summary)

        self.test_obj = test_obj

        return

    def run(self):
        """Run the test
        @return:  A result object"""

        LOG_sec("Test Parameters")
        LOG("dut              : %s" % self.test_obj.dut.host)
        LOG("bsp              : %s" % self.test_obj.bsp)
        LOG("bsp_dkms         : %s" % self.test_obj.bsp_dkms)
        LOG("bsp_loc          : %s" % self.test_obj.bsp_loc)
        LOG("sdk              : %s" % self.test_obj.sdk)
        LOG("sdk_loc          : %s" % self.test_obj.sdk_loc)
        LOG_endsec()

        if self.test_obj.bsp is None or \
           self.test_obj.bsp_dkms is None or \
           self.test_obj.bsp_loc is None or \
           self.test_obj.sdk is None or \
           self.test_obj.sdk_loc is None:
            return NrtResult(name=self.name, testtype=self.__class__.__name__,
                             passed=False, comment="Unable to install "
                                                   "BSP/SDK, .deb's not "
                                                   "specified from config "
                                                   "file.")

        if 'LATEST' not in self.test_obj.bsp:
            # this is a temporary approach as the driver of the bsp version
            # between 6.10 and 6.24 needs a flash-bin prior to 2015.6.11 BSP.
            # Thus, for every desired BSP after 2015.6.11, we need to install
            # BSP 2015.6.10.202-1, flash the arm, install the desired BSP and
            # SDK then power cycle.
            flash_nic_dt = 20150610
            fix_flash_nic_dt = 20150624
            re_ver_date = '(\d{4}).(\d{1,2}).(\d{1,2})(?:.\d{1,4}){0,1}-\d*'
            date_values = re.findall(re_ver_date, self.test_obj.bsp)
            if date_values:
                bsp_dt = int(date_values[0][0]) * 10000 + \
                         int(date_values[0][1]) * 100 + \
                         int(date_values[0][2])
                if bsp_dt > flash_nic_dt and bsp_dt < fix_flash_nic_dt:
                    # the desired BSP is after 2015.6.11, use the temporary
                    # method to install BSP
                    self.install_bsp_sdk_temp()
                else:
                    self.install_bsp_sdk()
            else:
                raise NtiFatalError('Error: .deb (%s) did not match the '
                                    'naming pattern' % self.test_obj.bsp)
        else:
            # use the normal method to install the LATEST BSP
            self.install_bsp_sdk()

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=True)

    def unload_deb(self, deb):
        """
        Load a .deb package on the host.

        :param rpm: Full path of .deb to load.
        :return: None
        """
        cmd = 'dpkg -r %s' % deb
        self.test_obj.dut.cmd(cmd, fail=False)

        return

    def load_deb(self, deb):
        """
        Load a .deb package on the host.

        :param rpm: Full path of .deb to load.
        :return: None
        """
        try:
            cmd = 'dpkg -i %s' % deb
            self.test_obj.dut.cmd(cmd)
        except:
            raise NtiFatalError('Error: .deb (%s) did not install properly'
                                % deb)

        return

    def install_bsp_sdk_temp(self):
        """
        The method to install BSP and SDK
        (temporary: nfp-flash the flash_nic.bin from BSP 2015.6.10.202-1)
        """
        # Load BSP and SDK.
        flash_nic_bsp_ver = '2015.6.10.202-1'
        flash_nic_bsp = 'nfp-bsp_%s_amd64.deb' % flash_nic_bsp_ver
        flash_nic_bsp_dkms = 'nfp-bsp-dkms_%s_all.deb' % flash_nic_bsp_ver
        self.load_deb(os.path.join(self.test_obj.sdk_loc, self.test_obj.sdk))
        self.load_deb(os.path.join(self.test_obj.bsp_loc, flash_nic_bsp))
        self.load_deb(os.path.join(self.test_obj.bsp_loc,
                                   flash_nic_bsp_dkms))

        # Update the nfp lib
        self.test_obj.dut.cmd('/sbin/ldconfig', fail=False)

        # Make sure the nfp kernel module is loaded before reimaging.
        # A printout for debug, showing nfp related modules
        #self.test_obj.dut.cmd('lsmod |grep nfp', fail=False)
        self.test_obj.dut.cmd('rmmod nfp_netvf', fail=False)
        self.test_obj.dut.cmd('rmmod nfp_net', fail=False)
        self.test_obj.dut.cmd('rmmod nfp', fail=False)
        self.test_obj.dut.cmd('modprobe nfp')

        # Reimage the NFP's ARM Flash device.
        cmd = ('nfp-flash --i-accept-the-risk-of-overwriting-miniloader -w '
               '/opt/netronome/flash/flash-nic.bin')
        self.test_obj.dut.cmd(cmd)

        # Make sure nobody else has pre-installed a bootable firmware
        # on this machine.
        cmd = 'rm -rf /lib/firmware/netronome/*'
        self.test_obj.dut.cmd(cmd)

        # Load BSP and SDK.
        self.load_deb(os.path.join(self.test_obj.bsp_loc, self.test_obj.bsp))
        self.load_deb(os.path.join(self.test_obj.bsp_loc,
                                   self.test_obj.bsp_dkms))
        self.load_deb(os.path.join(self.test_obj.sdk_loc, self.test_obj.sdk))

        # Update the nfp lib
        self.test_obj.dut.cmd('/sbin/ldconfig', fail=False)

        # Make sure nobody else has pre-installed a bootable firmware
        # on this machine.
        cmd = 'rm -rf /lib/firmware/netronome/*'
        self.test_obj.dut.cmd(cmd)

    def install_bsp_sdk(self):
        """
        The method to install BSP and SDK
        (Normal: nfp-flash the flash_nic.bin from the desired BSP)
        """

        # Load BSP and SDK.
        self.unload_deb('nfp-bsp')
        self.unload_deb('nfp-bsp-dkms')
        self.unload_deb('nfp-sdk')
        self.unload_deb('nfp-bsp-release-2015.11-dkms')
        self.unload_deb('nfp-bsp-release-2015.11')
        self.load_deb(os.path.join(self.test_obj.sdk_loc, self.test_obj.sdk))
        self.load_deb(os.path.join(self.test_obj.bsp_loc, self.test_obj.bsp))
        self.load_deb(os.path.join(self.test_obj.bsp_loc,
                                   self.test_obj.bsp_dkms))

        # Update the nfp lib
        self.test_obj.dut.cmd('/sbin/ldconfig', fail=False)

        # Make sure the nfp kernel module is loaded before reimaging.
        # A printout for debug, showing nfp related modules
        #self.test_obj.dut.cmd('lsmod |grep nfp', fail=False)
        self.test_obj.dut.cmd('rmmod nfp_netvf', fail=False)
        self.test_obj.dut.cmd('rmmod nfp_net', fail=False)
        self.test_obj.dut.cmd('rmmod nfp', fail=False)
        self.test_obj.dut.cmd('modprobe nfp')

        # Reimage the NFP's ARM Flash device.
        cmd = ('nfp-flash --i-accept-the-risk-of-overwriting-miniloader -w '
               '/opt/netronome/flash/flash-nic.bin')
        self.test_obj.dut.cmd(cmd)

        # Reimage the NFP's ARM Flash device.
        cmd = ('echo -e \"\\n\" | /opt/netronome/bin/nfp-one')
        self.test_obj.dut.cmd(cmd)

        # Reimage the NFP's ARM Flash device.
        cmd = ('nfp-fis delete firmware.ca')
        self.test_obj.dut.cmd(cmd, fail=False)

        # Make sure nobody else has pre-installed a bootable firmware
        # on this machine.
        cmd = 'rm -rf /lib/firmware/netronome/*'
        self.test_obj.dut.cmd(cmd)