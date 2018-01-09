##
# Copyright (C) 2013,  Netronome Systems, Inc.  All rights reserved.
##


import netro.testinfra
from netro.testinfra import LOG_sec, LOG_endsec, LOG
from netro.tests.null import NullTest

from perf_multithread import Iperf3_Test, Netperf_Test, Perf_Benchmark_Tools
from ...nfpflownic_tests import _NFPFlowNIC_nport_no_fw_loading


class Performance_Multithread_Iperf3(_NFPFlowNIC_nport_no_fw_loading):

    summary = "Iperf3 perfromance tests"
    info = """

Performance_Benchmark_Iperf3_Tests:

Generates Iperf3 tests from the iteration list provided. Each test is
an instance of Iperf3_Test from perf_benchmark.

List of iteration parameters:
NAME        VALUES        STATUS      COMMENT
port         int          Required    Specifies number of interfaces
time         int          Required    Duration of transmitting traffic
top         'Uni'|'Bi'    Required    Specifies the direction of streams
type        'UDP'|'TCP'   Required    Specifies the the traffic type
threads      int | 'Auto' Optional    Creates multiple Iperf3 instances
                                       'Auto': generates a thread for
                                               each cpu in local_cpu list

packet_size  int|[int]    Required      int  : Specifies the packets sizes
                                               for all threads
                                       [int] : Specify a list of packet sizes
                                               to run simultaneously

zero_copy    True|False   Optional     Adds Zerocopy flag to Iperf3 threads,
                                       ignored with default and False
parallel     int |None    Optional     Creates parallel threads for each Iperf3
                                       instance, ignored with default and None
omit         int |None    Optional     Omits first few seconds of test results,
                                       ignored with default and None
client_bind  True|False   Optional     Add Bind parameter to iperf3 thread.
                                       Binds the thread to the interface ip
                                       ignored with default and False
server_bind  True|False   Optional     Add Bind parameter to iperf3 thread.
                                       Binds the thread to the interface ip
                                       ignored with default and False
affinity     True|False   Optional     Pin each Iperf3 thread to a single cpu
                                       ignored with default and False
"""

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):

        _NFPFlowNIC_nport_no_fw_loading.__init__(self,
                                                 name,
                                                 cfg=cfg,
                                                 quick=quick,
                                                 dut_object=dut_object)
        tools = Perf_Benchmark_Tools()

        list_of_test_parameters, n = tools.create_iterations_list(
            {"type": ['TCP', 'UDP'],
             "top": ['Bi', 'Uni'],
             "packet_size": [128, 136, 168, 200, 232, 256, 272,
                             336, 400, 440, 464, 512, 544, 672,
                             800, 928, 1024, 1056, 1184, 1312,
                             1408, 1500, 1518],
             "threads": ['Auto'],
             "parallel": [10],
             "time": [30],
             "port": [1, 2],
             "omit": [2],
             "client_bind": [True],
             "server_bind": [True],
             "zero_copy": [False],
             "affinity": [True]})

        for i, test in enumerate(list_of_test_parameters):

            test.traffic_generator = 'Iperf3'
            test.nr = i + 1
            pars = (test.traffic_generator, test.type, test.top,
                    test.port, test.packet_size, test.threads,
                    test.zero_copy, test.parallel, test.omit,
                    test.client_bind, test.server_bind,
                    test.affinity, test.nr, n, test.time)

            test.name = ("[{12}|{13}] {0} {1} {2}directional {4}b"
                         " --prt {3}"
                         " --th {5}"
                         " --par {7}"
                         " --t {14}"
                         " --o {8}"
                         " --zc {6}"
                         " --cb {9}"
                         " --sb {10}"
                         " --a {11}"
                         ).format(*pars)
            test.summary = ("Run {0} {1} {2}directional {4}b test"
                            ).format(*pars)
            if all(hosts is not None
                   for hosts in self.host_ep) or self.dut is not None:
                for i, host in enumerate(self.host_ep):
                    host.cpu_list = host.cpus.keys()
                    host.intf = [self.eth_ep[i]]
                    host.addr_with_mask = [self.addr_ep[i]]
                    host.addr = [host.addr_with_mask[0].split('/')[0]]

                self.dut.cpu_list = self.dut.cpus.keys()
                self.dut.intf = self.eth_d
                self.dut.addr_with_mask = self.addr_d
                self.dut.addr = map(lambda addr: addr.split('/')[0],
                                    self.dut.addr_with_mask)

            self._tests[test.name] = Iperf3_Test(client=self.host_ep,
                                                 server=self.dut,
                                                 group=self, test=test,
                                                 tools=tools)


class Performance_Multithread_Netperf(_NFPFlowNIC_nport_no_fw_loading):

    summary = "Netperf perfromance tests"
    info = """

Performance_Benchmark_Netperf_Tests:

Generates Netperf tests from the iteration list provided. Each test is
an instance of Netperf_Test from perf_benchmark.

List of iteration parameters:
NAME        VALUES        STATUS      COMMENT
port         int          Required    Specifies number of interfaces
time         int          Required    Duration of transmitting traffic
top         'Uni'|'Bi'    Required    Specifies the direction of streams
type        'UDP'|'TCP'   Required    Specifies the the traffic type
threads      int | 'Auto' Optional    Creates multiple Netperf instances
                                       'Auto': generates a thread for
                                               each cpu in local_cpu list

packet_size  int|[int]    Required      int  : Specifies the packets sizes
                                               for all threads
                                       [int] : Specify a list of packet sizes
                                               to run simultaneously
"""

    def __init__(self, name, cfg=None,
                 quick=False, dut_object=None):

        _NFPFlowNIC_nport_no_fw_loading.__init__(self,
                                                 name,
                                                 cfg=cfg,
                                                 quick=quick,
                                                 dut_object=dut_object)
        tools = Perf_Benchmark_Tools()

        list_of_test_parameters, n = tools.create_iterations_list(
            {"type": ['TCP', 'UDP'],
             "top": ['Bi', 'Uni'],
             "threads": ['Auto'],
             "packet_size": [128, 136, 168, 200, 232, 256,
                             272, 336, 400, 440, 464, 512,
                             544, 672, 800, 928, 1024, 1056,
                             1184, 1312, 1408, 1500, 1518],
             "time": [30],
             "port": [1, 2],
             })

        for i, test in enumerate(list_of_test_parameters):

            test.traffic_generator = "Netperf"
            test.nr = i + 1
            pars = (test.traffic_generator, test.type, test.top,
                    test.port, test.packet_size, test.threads, test.nr, n,
                    test.time)

            test.name = ("[{6}/{7}] {0} {1} {2}directional {4}b"
                         " --ports {3}"
                         " --threads {5}"
                         " --time {8}").format(*pars)
            test.summary = ("Run {0} {1} {2}directional {4}b test"
                            ).format(*pars)

            if all(hosts is not None
                   for hosts in self.host_ep) or self.dut is not None:
                for i, host in enumerate(self.host_ep):
                    host.cpu_list = host.cpus.keys()
                    host.intf = [self.eth_ep[i]]
                    host.addr_with_mask = [self.addr_ep[i]]
                    host.addr = [host.addr_with_mask[0].split('/')[0]]

                self.dut.cpu_list = self.dut.cpus.keys()
                self.dut.intf = self.eth_d
                self.dut.addr_with_mask = self.addr_d
                self.dut.addr = map(lambda addr: addr.split('/')[0],
                                    self.dut.addr_with_mask)

            self._tests[test.name] = Netperf_Test(client=self.host_ep,
                                                  server=self.dut,
                                                  group=self, test=test,
                                                  tools=tools)
