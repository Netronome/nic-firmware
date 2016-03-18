##
## Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Unit test classes for the NFPFlowNIC Software Group.
"""

import os
import re
from netro.testinfra.nti_exceptions import NtiTimeoutError, NtiGeneralError
from netro.tests.iperf import Iperf
from netro.testinfra.nrt_result import NrtResult

class NfpflownicIperf(Iperf):
    """
    The wrapper class of Ping. Return NrtResult instead of Result
    """
    def run(self):

        result = Iperf.run(self)
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=result.passed, res=result.results,
                         comment=result.comment, details=result.details)

class LsoIperf(Iperf):
    """
    The sub class of Ping. Adding lso related configuration methods
    """
    def __init__(self, src, dst, lso_on=False,
                 time=None, bidirect=False, multi=None,
                 buflen=None, winsz=None, nfp_host=None,
                 mtu=1500,
                 group=None, name="LSOperf", summary=None):
        Iperf.__init__(self, src, dst, time=time, bidirect=bidirect,
                       multi=multi, buflen=buflen, winsz=winsz, group=group,
                       name=name, summary=summary)

        self.lso_on = lso_on
        self.dst_mtu = mtu
        self.src_mtu = mtu
        self.nfp_host = nfp_host
        self.tcache_out = None
        self.top_out = None
        self.nfp_tx_drop = None
        self.nfp_rx_drop = None
        self.cpu_avg = None

    def run(self):

        self.set_lso()
        self.run_tcache_and_top()
        result = Iperf.run(self)
        self.check_tcache_tm_drop_and_top()
        res = result.results
        res.append(self.nfp_rx_drop)
        res.append(self.nfp_tx_drop)
        res.append(self.cpu_avg)
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=result.passed, res=res,
                         comment=result.comment, details=result.details)

    def set_lso(self):
        if self.lso_on:
            self.src.cmd('ethtool -K %s tso on' % self.src_ifn)
            self.src.cmd('sysctl -w net.ipv4.tcp_min_tso_segs=2')
            if self.bidirect:
                self.dst.cmd('ethtool -K %s tso on' % self.dst_ifn)
                self.dst.cmd('sysctl -w net.ipv4.tcp_min_tso_segs=2')
        else:
            self.src.cmd('ethtool -K %s tso off' % self.src_ifn)
            if self.bidirect:
                self.dst.cmd('ethtool -K %s tso off' % self.dst_ifn)

        self.dst.cmd("ifconfig %s mtu %s" % (self.dst_ifn, self.dst_mtu))
        self.src.cmd("ifconfig %s mtu %s" % (self.src_ifn, self.src_mtu))

    def run_tcache_and_top(self):

        if self.nfp_host == 'dst':
            nfp_device = self.dst
        elif self.nfp_host == 'src':
            nfp_device = self.src
        else:
            raise NtiGeneralError(msg="nfp_host should be 'dst'/'src'. ")

        tmp_perf_folder = '/tmp/perf_tcache/'
        nfp_device.cmd('rm -rf %s' % tmp_perf_folder, fail=False)
        nfp_device.cmd('mkdir -p %s' % tmp_perf_folder)
        nfp_device.killall("nfp-tcache-diag", fail=False)
        nfp_device.killall("top", fail=False)
        if self.time:
            tcache_wait = self.time / 3
        else:
            tcache_wait = 0
        self.tcache_out = os.path.join(tmp_perf_folder, 'tcache_out.txt')
        self.top_out = os.path.join(tmp_perf_folder, 'top_out.txt')
        nfp_device.cmd('sleep %s; nfp-tcache-diag -p -e 0 -i 5000 > %s 2>&1' %
                       (tcache_wait, self.tcache_out), background=True)
        nfp_device.cmd('top -b -d1 > %s 2>&1' % self.top_out, background=True)

    def check_tcache_tm_drop_and_top(self):

        if self.nfp_host == 'dst':
            nfp_device = self.dst
            nfp_stats = self.dst_stats
        elif self.nfp_host == 'src':
            nfp_device = self.src
            nfp_stats = self.src_stats
        else:
            raise NtiGeneralError(msg="nfp_host should be 'dst'/'src'. ")

        nfp_device.killall("nfp-tcache-diag", fail=False)
        nfp_device.killall("top", fail=False)

        nfp_device.cmd('cat %s' % self.tcache_out, fail=False)

        self.nfp_tx_drop = nfp_stats.ethtool['dev_tx_discards']
        self.nfp_rx_drop = nfp_stats.ethtool['dev_rx_discards']

        _, out = nfp_device.cmd('cat %s | grep iperf' % self.top_out)
        cpu_usage_list = []
        lines = out.splitlines()
        for line in lines:
            pid, user, pr, ni, virt, res, shr, s, cpu, mem, time, cmd = \
                line.split()
            cpu_usage = float(cpu)
            if cpu_usage > 0:
                cpu_usage_list.append(cpu_usage)

        cpu_sum = 0
        # remove the first and the last non_zero cpu usage value
        # as they were measured during the startup/shutdown of iperf
        for i in range(1, len(cpu_usage_list) - 1):
            cpu_sum += cpu_usage_list[i]
        self.cpu_avg = cpu_sum / (len(cpu_usage_list) - 2)
