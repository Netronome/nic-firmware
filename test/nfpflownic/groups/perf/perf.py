##
## Copyright (C) 2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Unit test classes for the NFPFlowNIC Software Group.
"""

import os
import re
import time
from netro.testinfra.nti_exceptions import NtiTimeoutError, NtiGeneralError
from netro.tests.iperf import Iperf, _parse_iperf_out, _parse_iperf_bidir_out
from netro.testinfra.nrt_result import NrtResult
from netro.testinfra import Test
from netro.testinfra.log import LOG_sec, LOG, LOG_endsec
from netro.testinfra.utilities import timed_poll

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


class LsoIperf_multiport(Test):
    """
    The sub class of Ping. Adding lso related configuration methods
    """
    def _iperf_init(self, src, dst,
                    time=None, bidirect=False, multi=None,
                    buflen=None, winsz=None,
                    group=None, name="iperf", summary=None):
        """

        @src:      A tuple of System and interface name from which to send
        @dst:      A tuple of System and interface name on which to receive
        @time:     Time (in seconds) to run test (optional)
        @bidirect: Run the test bi-directional (optional)
        @multi:    Uses multiple connections (integer, optional)
        @buflen:   Length of read/write buffer in KB (optional)
        @winsz:    TCP window size (optional)
        @group:    Test group this test instance belongs to
        @name:     The name for this test instance
        @summary:  Optional one line summary for the test

        XXX This test assumes that each interface only has one IP address!
        """
        if multi:
            summary += " (%d streams)" % multi

        Test.__init__(self, group, name, summary)

        self.src = []
        self.src_ifn = []
        self.dst = []
        self.dst_ifn = []
        self.src_tmp_dir = []
        self.dst_tmp_dir = []
        self.src_srv_file = []
        self.dst_pcap_file = []
        self.local_recv_pcap = []
        self.src_stats = []
        self.dst_stats = []

        for i in range(0, self.port_number):
            if src[i]:
                # src and dst maybe None if called without config file for list
                self.src.append(src[i][0])
                self.src_ifn.append(src[i][2])
                self.dst.append(dst[i][0])
                self.dst_ifn.append(dst[i][2])
                self.src_tmp_dir.append(None)
                self.src_srv_file.append(None)
                self.dst_tmp_dir.append(None)
                self.dst_pcap_file.append(None)


        self.time = time
        self.bidirect = bidirect
        self.multi = multi
        self.buflen = buflen
        self.winsz = winsz
        return

    def __init__(self, src, dst, port_number=2, lso_on=False,
                 time=None, bidirect=False, multi=None,
                 buflen=None, winsz=None, nfp_host=None,
                 mtu=1500,
                 group=None, name="LSOperf", summary=None):
        self.port_number = port_number

        self._iperf_init(src, dst, time=time, bidirect=bidirect,
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

    def _ipef_run(self):
        """Do the iperf
        @return:  A result object"""

        # get the source and destination interfaces
        src_if = []
        dst_if = []
        src_stats_before = []
        dst_stats_before = []
        src_stats_after = []
        dst_stats_after = []
        txed = []
        rxed = []
        bw = []
        bw0 = []
        bw1 = []

        for i in range(0, self.port_number):
            src_if.append(self.src[i].netifs[self.src_ifn[i]])
            dst_if.append(self.dst[i].netifs[self.dst_ifn[i]])

        for i in range(0, self.port_number):
            self.src_tmp_dir[i] = self.src[i].make_temp_dir()
            self.dst_tmp_dir[i] = self.dst[i].make_temp_dir()
            self.src_srv_file[i] = 'iperf_srv_%s_%s.txt' % (i, self.src_ifn[i])
            self.dst_pcap_file[i] = 'pcap_rcv_%s_%s.pcap' % (i, self.dst_ifn[i])


        srv_args = cln_args = ""
        gen_args = "--format=m"

        if self.time:
            cln_args = cln_args + " --time=%d" % self.time
        if self.bidirect:
            cln_args = cln_args + " --dualtest"
        if self.multi:
            cln_args = cln_args + " --parallel=%d" % self.multi

        if self.buflen:
            gen_args = gen_args + " --len=%dK" % self.buflen
        if self.winsz:
            gen_args = gen_args + " --window=%dK" % self.winsz

        # Kill existing iperf daemon if present
        for i in range(0, self.port_number):
            self.dst[i].cmd("killall -KILL iperf", fail=False)
        for i in range(0, self.port_number):
            srv_cmd = "iperf -s -B %s  %s %s > /dev/null & sleep 1" % \
                      (dst_if[i].ip, gen_args, srv_args)
            ret, out = self.dst[i].cmd(srv_cmd, fail=False, background=True)
            if not ret == 0:
                # Failed to start iperf server
                return NrtResult(name=self.name,
                                              testtype=self.__class__.__name__,
                                              passed=False, details=out)

        # Give server some time to start
        time.sleep(3)
        for i in range(0, self.port_number):
            src_stats_before.append(src_if[i].stats())
            dst_stats_before.append(dst_if[i].stats())
        for i in range(0, self.port_number):
            cln_cmd = "iperf -c %s %s %s 2>&1 > %s/%s" % (dst_if[i].ip,
                                                          gen_args, cln_args,
                                                          self.src_tmp_dir[i],
                                                          self.src_srv_file[i])
            self.src[i].cmd(cln_cmd, fail=False, background=True)
        # Give client some time to start
        time.sleep(3)
        try:
            #timed_poll((int(self.time) * self.port_number),
            timed_poll(60,
                    self.is_iperf_cli_done, delay=1)
        except NtiTimeoutError:
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=False, comment="Iperf didn't finished "
                                                   "before time out")

        for i in range(0, self.port_number):
            src_stats_after.append(src_if[i].stats())
            dst_stats_after.append(dst_if[i].stats())

            self.src_stats.append(src_stats_after[i] - src_stats_before[i])
            self.dst_stats.append(dst_stats_after[i] - dst_stats_before[i])

        for i in range(0, self.port_number):
            LOG_sec("SRC %s@%s IF stat diff: %s" % (self.src[i].host, self.src_ifn[i], self.src[i]))
            LOG(self.src_stats[i].pp())
            LOG_endsec()

            LOG_sec("DST %s@%s IF stat diff: %s" % (self.dst[i].host, self.dst_ifn[i], self.dst[i]))
            LOG(self.dst_stats[i].pp())
            LOG_endsec()


        if self.bidirect:
            res_list = []
            all_out = ''
            for i in range(0, self.port_number):
                txed.append(self.src_stats[i].host_tx_pkts + self.dst_stats[i].host_tx_pkts)
                rxed.append(self.src_stats[i].host_rx_pkts + self.dst_stats[i].host_rx_pkts)
                cmd = "cat %s/%s" % (self.src_tmp_dir[i], self.src_srv_file[i])
                _, out = self.src[i].cmd(cmd)
                bw0.append(None)
                bw1.append(None)
                bw0[i], bw1[i] = _parse_iperf_bidir_out(out, self.multi)
                res_list.append([bw0[i] + bw1[i], bw0[i], bw1[i], txed[i], rxed[i]])
                all_out += out
            res = NrtResult(name=self.name,
                                         testtype=self.__class__.__name__,
                                         passed=True,
                                         res=res_list, details=all_out)

        else:
            res_list = []
            all_out = ''
            for i in range(0, self.port_number):
                rxed.append(self.dst_stats[i].host_rx_pkts)
                txed.append(self.src_stats[i].host_tx_pkts)
                cmd = "cat %s/%s" % (self.src_tmp_dir[i], self.src_srv_file[i])
                _, out = self.src[i].cmd(cmd)
                bw.append(None)
                bw[i] = _parse_iperf_out(out, self.multi)
                res_list.append([bw[i], 0, 0, txed[i], rxed[i]])
                all_out += out
            res = NrtResult(name=self.name,
                                         testtype=self.__class__.__name__,
                                         passed=True,
                                         res=res_list, details=all_out)

        for i in range(0, self.port_number):
            self.dst[i].cmd("killall -KILL iperf", fail=False)
            self.src[i].cmd("killall -KILL iperf", fail=False)
        return res

    def is_iperf_cli_done(self):


        done = True
        for i in range(0, self.port_number):
             cmd = "cat %s/%s" % (self.src_tmp_dir[i], self.src_srv_file[i])
             _, out = self.src[i].cmd(cmd)
             lines = out.splitlines()
             # example: [  3]  0.0-30.0 sec  16920 MBytes  4731 Mbits/sec
             # example: [SUM]  0.0-10.0 sec  9.34 GBytes  8.00 Gbits/sec
             re_recv_stats_str = '[\s+[0-9]+]\s+[0-9]+.[0-9]+-\s*[0-9]+.[0-9]+' \
                                 '\s*sec\s+[0-9.]+\s*[GMK]*Bytes\s*[0-9.]+\s*' \
                                 '[GMK]*bits/sec'
             if not re.findall(re_recv_stats_str, out):
                  done = False
        return done

    def run(self):

        for i in range(0, self.port_number):
            self.set_lso(i)
        result = self._ipef_run()
        res = result.results
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=result.passed, res=res,
                         comment=result.comment, details=result.details)

    def set_lso(self, i):
        if self.lso_on:
            self.src[i].cmd('ethtool -K %s tso on' % self.src_ifn[i])
            self.src[i].cmd('sysctl -w net.ipv4.tcp_min_tso_segs=2')
            if self.bidirect:
                self.dst[i].cmd('ethtool -K %s tso on' % self.dst_ifn[i])
                self.dst[i].cmd('sysctl -w net.ipv4.tcp_min_tso_segs=2')
        else:
            self.src[i].cmd('ethtool -K %s tso off' % self.src_ifn[i])
            if self.bidirect:
                self.dst[i].cmd('ethtool -K %s tso off' % self.dst_ifn[i])

        self.dst[i].cmd("ifconfig %s mtu %s" % (self.dst_ifn[i], self.dst_mtu))
        self.src[i].cmd("ifconfig %s mtu %s" % (self.src_ifn[i], self.src_mtu))


    # TODO: the following is for cpu usage, needs modification
    """
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

    """