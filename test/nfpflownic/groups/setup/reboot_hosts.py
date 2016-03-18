#
# Copyright (C) 2014,  Netronome Systems, Inc.  All rights reserved.
#
"""
Unit test classes for the NFPFlowNICSetup Software Group.
"""

from netro.testinfra import Test, LOG_sec, LOG, LOG_endsec
from netro.testinfra.nrt_result import NrtResult
from libs.thread_pool import ThreadPool
from netro.testinfra.utilities import timed_poll


class RebootHosts(Test):
    """The tests in this file share a lot of common code which is kept
    in this class"""

    summary = "Reboot the connected hosts for the test suite"

    info = """ Reboot the connected hosts for the test suite"""

    def __init__(self, test_obj, timeout=300, delay=3, group=None, name="",
                 summary=None):
        """
        @test_obj:   Object that contains the System objects
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        Test.__init__(self, group, name, summary)

        self.test_obj = test_obj
        self.timeout = timeout
        self.delay = delay

        return

    def run(self):
        """Run the test
        @return:  A result object"""

        LOG_sec("Test Parameters")
        LOG("dut        : %s" % self.test_obj.dut.host)
        LOG("nfes       : %s" % self.test_obj.nfes)
        LOG("src        : %s" % self.test_obj.src.host)
        LOG("src_intf   : %s" % self.test_obj.src_intf)
        LOG("timeout    : %s" % self.timeout)
        LOG("delay      : %s" % self.delay)
        LOG_endsec()

        passed = True
        num_threads = 2

        # Create the threadpool.
        tp = ThreadPool(num_threads)
        # Reboot both hosts.
        tp.queueTask(self.power_cycle, host=self.test_obj.dut)
        tp.queueTask(self.test_obj.src.reboot, timeout=self.timeout,
                     delay=self.delay)
        tp.joinAll()

        # Verify machines are up. If not, an exception will be raised.
        client_list = [self.test_obj.dut, self.test_obj.src]
        for client in client_list:
            timed_poll(self.timeout, client.true_cmd, delay=self.delay)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=passed, comment="")

    def power_cycle(self, host):
        """
        Using ipmitool, power cycle a given host.

        :return: True, otherwise an Exception is raised.
        """
        # Start required kernel modules on dut.
        mods = ['ipmi_devintf', 'ipmi_si']
        for mod in mods:
            cmd = 'modprobe %s' % mod
            host.cmd(cmd)

        # Verify modules are loaded.
        LOG_sec("Verify ipmitool kernel modules are loaded")
        timed_poll(self.timeout, self.verify_kernel_mods_up, self.test_obj.dut,
                   mods, delay=self.delay)
        LOG_endsec()

        # Obtain the current number of reboots for the device.
        LOG_sec("Get number of power cycles for %s" % host.host)
        prev_count = host.get_reboot_count()
        LOG_endsec()

        # Power cycle the host using ipmitool.
        cmd = 'ipmitool power cycle'
        host.cmd(cmd)

        # Verify device came back up properly.
        LOG_sec("Verify %s rebooted with ipmitool" % host.host)
        timed_poll(self.timeout, host.verify_reboot, prev_count,
                   delay=self.delay)
        LOG_endsec()

        return True

    def verify_kernel_mods_up(self, host, mods):
        """
        Given a list of kernel modules starting with "ipmi_", verify,
        using lsmod, the kernel modules are loaded.

        :return: True for mods up, False otherwise.
        """
        cmd = 'lsmod | grep ipmi_'
        _, out = host.cmd(cmd)

        count_mods = 0
        for mod in mods:
            for line in out.splitlines():
                if line.startswith(mod):
                    count_mods += 1
                    break

        if count_mods != len(mods):
            return False

        return True