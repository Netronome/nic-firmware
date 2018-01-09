
##
# Copyright (C) 2013,  Netronome Systems, Inc.  All rights reserved.
##

import numpy
import json
import os
import shutil
import time
import collections
import itertools
import datetime
import netro.testinfra
from netro.testinfra.nrt_result import NrtResult
from netro.testinfra.log import LOG_sec, LOG, LOG_endsec


class Attribute_dict(object):
    """
    Object that allows dictionaries to be referenced by attributes
    Used to generate test objects
    """

    def __init__(self, dictionary):
        self.__dict__.update(dictionary)

    def __setitem__(self, key, item):
        self.__dict__[key] = item

    def __getitem__(self, key):
        return self.__dict__[key]

    def keys(self):
        return self.__dict__.keys()

    def values(self):
        return self.__dict__.values()

    def items(self):
        return self.__dict__.items()

    def __contains__(self, item):
        return item in self.__dict__

    def __iter__(self):
        return iter(self.__dict__)

    def __repr__(self):
        return repr([(k, v) for k, v in self.__dict__.items()])

    def return_colums(self):
        "Return key and value pairs in column format"
        return '\n'.join(["%-9s\t%s" % (k, v)
                          for k, v in self.__dict__.items()])

    def csv_output(self, headings=False):
        if headings:
            return','.join([str(k).replace(',', ' ')
                            for k, _ in self.__dict__.items()])
        else:
            return','.join([str(v).replace(',', ' ')
                            for _, v in self.__dict__.items()])


class Perf_Benchmark_Tools():

    """
    Tools/utilities used during tests
    """

    def __init__(self):
        self.date = time.strftime("%Y-%m-%d-%H-%M")

    def create_iterations_list(self, it):
        """
        Create a list of iteration objects from a list of sets.
        """
        iters = collections.OrderedDict(it)
        param = iters.keys()

        combinations = list(itertools.product(
            *(iters[key] for key in param)))

        iterations = [Attribute_dict(zip(param, instance))
                      for instance in combinations]

        return iterations, len(iterations)

    def flatten(self, list_of_list):
        return list(itertools.chain(*list_of_list))

    def filter_dict_list(self, dict_list, key):
        return list(map(lambda x: x[key], dict_list))

    def stretch_list(self, ls, n):
        ls_length = len(ls)
        l2 = [None for _ in range(n)]
        for i, _ in enumerate(l2):
            index = int((float(i) / n) * ls_length)
            l2[i] = ls[index]
        return l2

    def create_folder(self, directory, remove_first=False):
        if not os.path.exists(directory):
            os.makedirs(directory)
        elif remove_first:
            shutil.rmtree(directory)
            os.makedirs(directory)

    def append_line_to_file(self, line, file_name, create_file=False):
        """Append a line to a file"""
        open_method = 'w' if create_file else 'a'
        with open(file_name, open_method) as f:
            f.write('{}\n'.format(line))
            f.close()

    def ping_test(self, devices, port=2):

        cmd_ping = "ping -c 1 {}"
        status = True
        for dev1 in devices:
            for dev2 in devices:
                if dev1 is not dev2:
                    for addr in dev2.addr[:port]:
                        dev1.cmd(cmd_ping.format(addr))
        return status

    def process_data(self, ls, std_nr=1):
        if len(ls) > 2:
            mean = numpy.mean(ls)
            if mean != 0:
                std = std_nr * numpy.std(ls)

                new_ls = [i for i in ls if abs(i - mean) < std]

                return round(numpy.mean(new_ls), 2)
            else:
                return 0
        elif len(ls) == 2:
            return round(numpy.mean(ls), 2)
        else:
            return round(ls[0], 2)

    def get_local_cpus(self, device):

        # List of unformatted commands (in order of execution)
        # ____________________________________________________
        cmd_numa = 'cat /sys/class/net/{}/device/numa_node'
        cmd_local_cpus = ('lscpu'
                          ' | grep "NUMA node{} CPU(s):"'
                          ' | cut -d ":" -f 2')
        cmd_pci = 'ethtool -i {} | grep bus | cut -d" " -f 2'
        # ____________________________________________________

        try:
            status, numa_node = device.cmd(cmd_numa.format(device.intf[0]))
            if status:
                _, pci = device.cmd(cmd_pci.format(device.intf[0]))
                status, numa_node = device.cmd(cmd_numa.format(pci.strip()))

            _, string_local_cpus = device.cmd(cmd_local_cpus.format(
                numa_node.strip()))
            string_local_cpus = string_local_cpus.strip()

            device.local_cpu_list = []
            for cpu in string_local_cpus.split(","):
                split = cpu.split("-")
                if len(split) is 2:
                    device.local_cpu_list.extend(range(int(split[0]),
                                                       int(split[1]) + 1))
                else:
                    device.local_cpu_list.append(int(cpu))
        except Exception as e:
            print "ERROR [get_local_cpus]", e
            device.local_cpu_list = device.cpu_list

    def elapsed_time(self, start_time):
        time_delta = int(time.time() - start_time)
        return str(datetime.timedelta(seconds=time_delta))


class Iperf3_Test(netro.testinfra.Test):

    summary = "Executes Iperf3 performance tests"

    info = """
    1. (__init__) SETUP TEST PARAMETERS AND VARIABLES
        1.1 Declare test as an NTI test object and declare tools variable
        1.2 Declare static variables
        1.3 Declare client and Server objects
        1.4 Declare Iperf3 thread related variables
        1.5 Calculate Iperf3 folder and file locations

    Skip certain test cases

    2. (setup_test) PREPARE TO EXECUTE TEST
        2.1 Create results folder
        2.2 Prepare devices (install iperf3 and get local cpu list)
        2.3 Setup Interfaces, set MTU and set irq affinity
        2.4 Check connectivity
        2.5 Set auto values

    3. (generate_thread_parameters) GENERATE DICTIONARIES FOR EACH THREAD
        3.1 Create a dictionary list for all the thread
        3.2 Support multiple frame sizes. Stretch list of packet
            sizes to match nr threads
        3.3 Add attributes to thread dictionaries
            3.3.1 Calculate parameter values
            3.3.2 Set basic values
            3.3.3 Optional parameters and parameters requiring logic
            3.3.4 Give iteration object the required attributes

    4. (run_test) LAUNCH IPERF3 SERVERS AND CLIENTS
        4.1 Empty temporary iterations folder
        4.2 SERVERS
            4.2.1 Kill previous servers
            4.2.2 Start new servers
            4.2.3 Check if all the server instances were created
            4.2.4 Determine if servers has to be regenerated
            4.2.5 Terminate if correct amount of servers was generated
        4.3 CLIENTS
            4.3.1 Kill previous Iperf3 client threads
            4.3.2 Launch Iperf3 client threads
        4.4 Wait for test iteration to complete

    5. (read_data) READ TEST RESULTS
        5.1 Create result store object
        5.2 Copy files from remote client
        5.3 Extract data from all the thread files
            5.3.1 Read file
            5.3.2 Append thread throughput to result object
            5.3.3 Append detailed topological results to results object
        5.4 Aggregate result
        5.5 Remove raw result folder

    6. (save_data) SAVE TEST RESULTS
        6.1 Create object containing relevant data to save
        6.2 Write csv headings
        6.2 Write csv body
    """

    def __init__(self, client=None, server=None,
                 group=None, test=None, tools=None):

        #######################################################################
        #            1. SETUP TEST PARAMETERS AND VARIABLES
        #######################################################################

        # 1.1 Declare test as an NTI test object and declare tools variable
        # `````````````````````````````````````````````````````````````````
        netro.testinfra.Test.__init__(self, group, test.name,
                                      test.summary)
        self.tools = tools

        # 1.2 Declare static variables
        # ````````````````````````````
        self.result_folder = "/root/Results"
        self.max_errors = 10
        self.trials = 2
        self.settle_time = 2

        # 1.3 Declare client and Server objects
        # `````````````````````````````````````
        self.client = client
        self.server = server
        self.devices = [server]
        self.devices.extend(self.client)

        # 1.4 Declare Iperf3 thread related variables
        # ```````````````````````````````````````````
        self.number = test.nr
        self.traffic_generator = test.traffic_generator
        self.time = test.time
        self.port = test.port
        self.top = test.top
        self.type = test.type
        self.threads = test.threads
        self.packet_size = test.packet_size
        self.zero_copy = test.zero_copy
        self.parallel = test.parallel
        self.omit = test.omit
        self.client_bind = test.client_bind
        self.server_bind = test.server_bind
        self.affinity = test.affinity
        self.streams = {'Bi': ['Forward', 'Reverse'],
                        'Uni': ['Forward']}[self.top]

        # 1.5 Calculate Iperf3 folder and file locations
        # ``````````````````````````````````````````````
        _folder_par = (self.result_folder, self.tools.date,
                       self.traffic_generator)
        self.temp_dir = '/tmp/{1}_threads/'.format(*_folder_par)
        self.results_file = ("{0}/{1}-{2}_Aggregate_results.csv"
                             ).format(*_folder_par)

        return

    def run(self):

        # Skip certain test cases
        # ````````````````````````
        if self.top == 'Bi' and self.type == 'UDP':
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=True, res="",
                             comment="Skip UDP Bidirectional tests",
                             details="")

        start_time = time.time()

        # PREPARE TO EXECUTE TEST
        # ```````````````````````
        status, msg = self.setup_test()
        if not status:
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=status, res="",
                             comment=msg,
                             details="")

        # GENERATE DICTIONARIES FOR EACH THREAD
        # `````````````````````````````````````
        self.generate_thread_parameters()

        trial_results, trial, trial_errors = [], 0, 0
        while trial < self.trials:

            # LAUNCH IPERF3 SERVERS AND CLIENTS
            # `````````````````````````````````
            self.run_test()

            # READ TEST RESULTS
            # `````````````````
            error, agg_results, _ = self.read_data()

            if not error:
                trial += 1
                trial_results.append(agg_results)

            else:
                trial_errors += 1

                if trial_errors > self.max_errors:
                    return NrtResult(name=self.name,
                                     testtype=self.__class__.__name__,
                                     passed=False, res="",
                                     comment=("The test failed more than {}"
                                              ).format(self.max_errors),
                                     details="")
        # SAVE TEST RESULTS
        # `````````````````
        thru = self.save_data(trial_results)
        elapsed_time = self.tools.elapsed_time(start_time)
        comment = ("{0} Gbps"
                   ).format(thru)
        details = ("{0} Gbps {1}-trials {2}-time {3}-trial-errors"
                   ).format(thru,
                            self.trials,
                            elapsed_time,
                            trial_errors)
        return NrtResult(name=self.name,
                         testtype=self.__class__.__name__,
                         passed=True, res="",
                         comment=comment,
                         details=details)

    def setup_test(self):
        #######################################################################
        #                    2. PREPARE TO EXECUTE TEST
        #######################################################################

        # List of unformatted commands (in order of execution)
        # ____________________________________________________
        cmd_install = 'sudo apt-get install -y iperf3'
        cmd_ifconfig = ("ifconfig {0} down; "
                        "ifconfig {0} up; "
                        "ifconfig {0} {1} up;"
                        "ifconfig {0} mtu {2}")
        cmd_set_affinity = "/opt/netronome/bin/set_irq_affinity.sh {0}"
        # ____________________________________________________

        # 2.1 Create results folder
        # `````````````````````````
        self.tools.create_folder(self.result_folder)

        # 2.2 Prepare device (install iperf3 and get local cpu list)
        # ``````````````````````````````````````````````````````````
        for dev in self.devices:
            dev.cmd(cmd_install, fail=False)
            self.tools.get_local_cpus(dev)

        # 2.3 Setup Interfaces, set MTU and set irq affinity
        # ``````````````````````````````````````````````````
        mtu = max(self.packet_size) if isinstance(
            self.packet_size, list) else self.packet_size

        for dev in self.devices:
            [dev.cmd(cmd_ifconfig.format(inf, ip, mtu))
             for inf, ip in zip(dev.intf, dev.addr)]
            time.sleep(1)
            [dev.cmd(cmd_set_affinity.format(inf))
             for inf in dev.intf]

        # 2.4 Check connectivity
        # ``````````````````````
        boo_ping = self.tools.ping_test(self.devices)
        if not boo_ping:
            return False, "Ping test failed"

        # 2.5 Set auto values
        # ```````````````````
        if self.threads == 'Auto':
            self.threads = min([len(dev.local_cpu_list)
                                for dev in self.devices])

        return True, ""

    def generate_thread_parameters(self):

        #######################################################################
        #               3. GENERATE DICTIONARIES FOR EACH THREAD
        #######################################################################

        # 3.1 Create a dictionary list for all the threads
        # ````````````````````````````````````````````````
        iteration_list = [('thread', range(self.threads
                                           / len(self.streams)
                                           / self.port)),
                          ('port', range(self.port)),
                          ('stream', self.streams)]

        self.iterations, n_iters = self.tools.create_iterations_list(
            iteration_list)

        # 3.2 Support multiple frame sizes. Stretch list of
        #     packet sizes to match nr threads
        # ``````````````````````````````````````````````````
        if isinstance(self.packet_size, list):
            __size = self.tools.stretch_list(self.packet_size,
                                             n_iters)
        else:
            __size = [self.packet_size] * len(self.iterations)

        # 3.3 Add attributes to thread dictionaries
        # `````````````````````````````````````````
        port_base = 5100
        for i, itr in enumerate(self.iterations):
            # 3.3.1 Calculate parameter values
            # ````````````````````````````````
            client = self.client[itr.port]
            port_base = port_base + 1

            all_cpus = client.local_cpu_list
            first_half = client.local_cpu_list[
                    len(client.local_cpu_list)/2:]
            second_half = client.local_cpu_list[
                    :len(client.local_cpu_list)/2]

            if self.port == 1:
                local_cpu_list = all_cpus
            elif self.port == 2 and itr.port == 0:
                local_cpu_list = first_half
            elif self.port == 2 and itr.port == 1:
                local_cpu_list = second_half
            offset = len(local_cpu_list)/2 if itr.stream == 'Reverse' else 0

            cpu = local_cpu_list[itr.thread % len(
                local_cpu_list) + offset]

            server_ip = self.server.addr[itr.port]
            client_ip = client.addr[0]

            # 3.3.2 Set basic values
            # ``````````````````````
            _0_port = " -p {}".format(port_base)
            _1_s_bind = ''
            _2_s_ip = " -c {}".format(server_ip)
            _3_time = " -t {}".format(self.time)
            _4_c_bind = ''
            _5_packet_size = " -m {}".format(__size[i])
            _6_affinity = ''
            _7_paral = ''
            _8_omit = ''
            _9_udp = ''
            _10_zero_copy = ''
            _11_stream = ''

            # 3.3.3 Optional parameters and parameters requiring logic
            # ````````````````````````````````````````````````````````
            test_case = self.__dict__
            if 'server_bind' in test_case and self.server_bind:
                _1_s_bind = ' -B {}'.format(server_ip)
            if 'client_bind' in test_case and self.client_bind:
                _4_c_bind = ' -B {}'.format(client_ip)
            if 'affinity' in test_case and self.affinity:
                _6_affinity = ' -A {}'.format(cpu)
            if 'parallel' in test_case and self.parallel is not None:
                _7_paral = ' -P {}'.format(self.parallel)
            if 'omit' in test_case and self.omit is not None:
                _8_omit = ' -O {}'.format(self.omit)
            if 'zero_copy' in test_case and self.zero_copy:
                _10_zero_copy = " -Z"
            if self.type == 'UDP':
                _5_packet_size = " -l {}".format(__size[i] - 12)
                _9_udp = " -u -b 0"
            elif self.type == 'TCP':
                _5_packet_size = " -M {} -l {}".format(
                    __size[i] - 40, __size[i] - 52)
            if itr.stream == 'Reverse':
                _11_stream = ' --reverse'

            itr.type = self.type
            itr.file_name = ("{}{}_{}_{}.json"
                             ).format(self.temp_dir,
                                      itr.stream,
                                      itr.port,
                                      itr.thread)

            # 3.3.4 Give iteration object the required attributes
            # ```````````````````````````````````````````````````
            itr.params = [_0_port,
                          _1_s_bind,
                          _2_s_ip,
                          _3_time,
                          _4_c_bind,
                          _5_packet_size,
                          _6_affinity,
                          _7_paral,
                          _8_omit,
                          _9_udp,
                          _10_zero_copy,
                          _11_stream,
                          itr.file_name]

        return

    def run_test(self):

        #######################################################################
        #                4. LAUNCH IPERF3 SERVERS AND CLIENTS
        #######################################################################

        # List of unformatted commands (in order of execution)
        # ____________________________________________________

        cmd_empty_remote_folder = "mkdir -p {0} & rm -rf {0}*"

        cmd_kill_forcefully = "pkill -f iperf3 | true"
        cmd_active_servers = 'ps aux | grep "iperf3 -p"  | wc -l'

        cmd_kill_softly = 'pkill iperf3 | true'

        cmd_server = "iperf3{0} -s -D{1}"
        cmd_client = ("iperf3{0}{2}{3}{4}{5}{6}{7}{8}{9}{10}{11}"
                      " -i 0 -J > {12}")
        # ____________________________________________________

        # 4.1 Empty temporary iterations folder
        # `````````````````````````````````````
        self.tools.create_folder(self.temp_dir, remove_first=True)
        for dev in self.client:
            dev.cmd(cmd_empty_remote_folder.format(self.temp_dir))

        # ------------------------ 4.2 SERVERS ----------------------------
        all_servers_created = False
        server_errors = 0

        while not all_servers_created:

            # 4.2.1 Kill previous servers
            self.server.cmd(cmd_kill_forcefully, fail=False)
            time.sleep(0.5)

            # 4.2.2 Start new servers
            for itr in self.iterations:
                time.sleep(0.25)

                self.server.cmd(cmd_server.format(*itr.params),
                                background=True)

            # 4.2.3 Check if all the server instances were created
            time.sleep(1.5)
            _, nr_created_str = self.server.cmd(cmd_active_servers)

            # 4.2.4 Determine if servers has to be regenerated
            if isinstance(self.packet_size, list):
                nr_created_str = ''.join(nr_created_str)
            nr_created = int(nr_created_str) - 2

            if nr_created == len(self.iterations):
                all_servers_created = True

            # 4.2.5 Terminate if correct amount of servers was generated
            server_errors += 1
            if server_errors > self.max_errors:
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=0, res="",
                                 comment="Could not generate correct "
                                 "amount of Iperf3 servers", details="")

        # ------------------------ 4.2 SERVERS ----------------------------
        time.sleep(1)

        # ------------------------ 4.3 CLIENTS ----------------------------

        # 4.3.1 Kill previous Iperf3 client threads
        # `````````````````````````````````````````
        for dev in self.client:
            dev.cmd(cmd_kill_softly, fail=False)
        time.sleep(0.2)

        # 4.3.2 Launch Iperf3 client threads
        # ``````````````````````````````````
        for i, dev in enumerate(self.client):
            cmd_client_exe = ' &\n'.join(map(
                lambda itr:  cmd_client.format(*itr.params)
                if itr.port == i else ":",
                self.iterations))
            dev.cmd(cmd_client_exe, background=True)

        # ------------------------ 4.3 CLIENTS ----------------------------

        # 4.4 Wait for test iteration to complete
        # ```````````````````````````````````````
        wait_time = self.time + self.settle_time
        time.sleep(wait_time)

        return

    def read_data(self):

        #######################################################################
        #                        5. READ TEST RESULTS
        #######################################################################

        # List of unformatted commands (in order of execution)
        # ____________________________________________________

        cmd_ls = "ls {0}"
        cmd_rm = "rm -rf {0}"
        # ____________________________________________________

        # 5.1 Create result store object
        # ``````````````````````````````
        results, results_per_thread = dict(), dict()

        results_name_list = ['throughput', 'sum_Forward', 'sum_Reverse',
                             'sum_Port_1', 'sum_Port_2']
        for name in results_name_list:
            results[name] = 0
            results_per_thread[name] = []

        # 5.2 Copy files from remote client
        # `````````````````````````````````
        for dev in self.client:
            if not dev.local_cmds:
                _, files = dev.cmd(cmd_ls.format(self.temp_dir))
                for file_name in files.rstrip().split("\n"):
                    file_path = os.path.join(self.temp_dir, file_name)
                    dev.cp_from(file_path, file_path)

        time.sleep(3)
        error = False
        # 5.3 Extract data from all the thread files
        # ``````````````````````````````````````````
        for itr in self.iterations:
            try:
                # 5.3.1 Read file
                # ```````````````
                thread_dict = json.load(open(itr.file_name))
                if 'error' in thread_dict:
                    print itr.file_name, thread_dict['error']
                    error = True
                    break

                par1 = "end"
                par2 = "sum_received" if itr.type == 'TCP' else "sum"
                par3 = "bits_per_second"
                thru = round(thread_dict[par1][par2][par3] * 1e-9, 2)

                # 5.3.2 Append thread throughput to result object
                # ```````````````````````````````````````````````
                results_per_thread['throughput'].append(thru)

                # 5.3.3 Append detailed topological results to results object
                # ```````````````````````````````````````````````````````````
                if itr.stream == 'Forward':
                    results_per_thread['sum_Forward'].append(thru)
                if itr.stream == 'Reverse':
                    results_per_thread['sum_Reverse'].append(thru)
                if itr.port == 0:
                    results_per_thread['sum_Port_1'].append(thru)
                if itr.port == 1:
                    results_per_thread['sum_Port_2'].append(thru)
            except Exception as e:
                print "Error", itr.file_name, e
                error = True
                break

        # 5.4 Aggregate results
        # `````````````````````
        if not error:
            for name in results_name_list:
                if results_per_thread[name]:
                    results[name] = round(sum(results_per_thread[name]), 2)

        # 5.5 Remove raw result folder
        # ````````````````````````````
        for dev in self.devices:
            dev.cmd(cmd_rm.format(self.temp_dir))
        shutil.rmtree(self.temp_dir, ignore_errors=True)
        os.mkdir(self.temp_dir)

        return error, results, results_per_thread

    def save_data(self, trial_results):

        #######################################################################
        #                        6. SAVE TEST RESULTS
        #######################################################################
        # 6.1 Create object containing relevant data to save
        # ``````````````````````````````````````````````````
        fields_from_test = ["packet_size",
                            "traffic_generator",
                            "top",
                            "type",
                            "threads",
                            "time",
                            "port",
                            "parallel",
                            "omit",
                            "server_bind",
                            "client_bind",
                            "affinity",
                            "zero_copy"]
        fields_from_results = ["throughput",
                               "sum_Forward",
                               "sum_Reverse",
                               "sum_Port_1",
                               "sum_Port_2"]

        list_dict_results = []
        for i in range(len(trial_results) + 1):

            result_dict = dict()
            for f in fields_from_test:
                result_dict[f] = getattr(self, f)

            if i == 0:
                result_dict["trial"] = 'All'
                for f in fields_from_results:
                    filed_list = self.tools.filter_dict_list(trial_results, f)
                    result_dict[f] = self.tools.process_data(filed_list)
            else:
                result_dict["trial"] = i
                for f in fields_from_results:
                    result_dict[f] = trial_results[i - 1][f]

            list_dict_results.append(Attribute_dict(result_dict))

        # 6.2 Write csv headings
        # ``````````````````````
        if self.number is 1:
            csv_line = list_dict_results[0].csv_output(headings=True)
            self.tools.append_line_to_file(csv_line,
                                           self.results_file,
                                           create_file=True)
        # 6.2 Write csv body
        # ``````````````````
        for dict_result in list_dict_results:
            csv_line = dict_result.csv_output(headings=False)
            self.tools.append_line_to_file(csv_line,
                                           self.results_file)

        return list_dict_results[0].throughput


class Netperf_Test(netro.testinfra.Test):

    summary = "Executes Netperf performance tests"

    info = """
    1. (__init__) SETUP TEST PARAMETERS AND VARIABLES
        1.1 Declare test as an NTI test object and declare tools variable
        1.2 Declare static variables
        1.3 Declare client and Server objects
        1.4 Declare Netperf thread related variables
        1.5 Calculate Iperf3 folder and file locations

    Skip certain test cases

    2. (setup_test) PREPARE TO EXECUTE TEST
        2.1 Create results folder
        2.2 Prepare devices (install netperf and get local cpu list)
        2.3 Setup Interfaces, set MTU and set irq affinity
        2.4 Check connectivity
        2.5 Set auto values

    3. (generate_thread_parameters) GENERATE DICTIONARIES FOR EACH THREAD
        3.1 Create a dictionary list for all the thread
        3.2 Support multiple frame sizes. Stretch list of packet
            sizes to match nr threads
        3.3 Add attributes to thread dictionaries
            3.3.1 Calculate parameter values
            3.3.2 Set basic values
            3.3.3 Optional parameters and parameters requiring logic
            3.3.4 Give iteration object the required attributes

    4. (run_test) LAUNCH NETPERF SERVER AND CLIENTS
        4.1 Empty temporary iterations folder
        4.2 SERVER
        4.3 CLIENTS
            4.3.1 Kill previous Netperf client threads
            4.3.2 Launch Netperf client threads
        4.4 Wait for test iteration to complete

    5. (read_data) READ TEST RESULTS
        5.1 Create result store object
        5.2 Copy files from remote client
        5.3 Extract data from all the thread files
            5.3.1 Read file
            5.3.2 Append thread throughput to result object
            5.3.3 Append detailed topological results to results object
        5.4 Aggregate result
        5.5 Remove raw result folder

    6. (save_data) SAVE TEST RESULTS
        6.1 Create object containing relevant data to save
        6.2 Write csv headings
        6.2 Write csv body
    """

    def __init__(self, client=None, server=None,
                 group=None, test=None, tools=None):

        #######################################################################
        #            1. SETUP TEST PARAMETERS AND VARIABLES
        #######################################################################

        # 1.1 Declare test as an NTI test object and declare tools variable
        # ````````````````````````````````````````````````````````````````
        netro.testinfra.Test.__init__(self, group, test.name,
                                      test.summary)
        self.tools = tools

        # 1.2 Declare static variables
        # ````````````````````````````
        self.result_folder = "/root/Results"
        self.max_errors = 10
        self.trials = 2
        self.settle_time = 2

        # 1.3 Declare client and Server objects
        # `````````````````````````````````````
        self.client = client
        self.server = server
        self.devices = [server]
        self.devices.extend(self.client)

        # 1.4 Declare Netperf thread related variables
        # ````````````````````````````````````````````
        self.number = test.nr
        self.traffic_generator = test.traffic_generator
        self.time = test.time
        self.port = test.port
        self.top = test.top
        self.type = test.type
        self.threads = test.threads
        self.packet_size = test.packet_size
        self.streams = {'Bi': ['Forward', 'Reverse'],
                        'Uni': ['Forward']}[self.top]

        # 1.5 Calculate Netperf folder and file locations
        # ```````````````````````````````````````````````
        _folder_par = (self.result_folder, self.tools.date,
                       self.traffic_generator)
        self.temp_dir = '/tmp/{1}_threads/'.format(*_folder_par)
        self.results_file = ("{0}/{1}-{2}_Aggregate_results.csv"
                             ).format(*_folder_par)

        return

    def run(self):

        # Skip certain test cases
        # ```````````````````````
        if self.top == 'Bi' and self.type == 'UDP':
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=True, res="",
                             comment="Skip UDP Bidirectional tests",
                             details="")

        start_time = time.time()

        # PREPARE TO EXECUTE TEST
        # ```````````````````````
        status, msg = self.setup_test()
        if not status:
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=status, res="",
                             comment=msg,
                             details="")

        # GENERATE DICTIONARIES FOR EACH THREAD
        # `````````````````````````````````````
        self.generate_thread_parameters()

        trial_results, trial, trial_errors = [], 0, 0
        while trial < self.trials:

            # LAUNCH NETPERF SERVER AND CLIENTS
            # `````````````````````````````````
            self.run_test()

            # READ TEST RESULTS
            # `````````````````
            error, agg_results, _ = self.read_data()

            if not error:
                trial += 1

                trial_results.append(agg_results)
            else:
                trial_errors += 1

                if trial_errors > self.max_errors:
                    return NrtResult(name=self.name,
                                     testtype=self.__class__.__name__,
                                     passed=False, res="",
                                     comment=("The test failed more than {}"
                                              ).format(self.max_errors),
                                     details="")
        # SAVE TEST RESULTS
        # `````````````````
        thru = self.save_data(trial_results)
        elapsed_time = self.tools.elapsed_time(start_time)
        comment = ("{0} Gbps"
                   ).format(thru)
        details = ("{0} Gbps {1}-trials {2}-time {3}-trial-errors"
                   ).format(thru,
                            self.trials,
                            elapsed_time,
                            trial_errors)

        return NrtResult(name=self.name,
                         testtype=self.__class__.__name__,
                         passed=True, res="",
                         comment=comment,
                         details=details)

    def setup_test(self):
        #######################################################################
        #                    2. PREPARE TO EXECUTE TEST
        #######################################################################

        # List of unformatted commands (in order of execution)
        # ____________________________________________________
        cmd_install = 'sudo apt-get install -y netperf'
        cmd_ifconfig = ("ifconfig {0} down; "
                        "ifconfig {0} up; "
                        "ifconfig {0} {1} up;"
                        "ifconfig {0} mtu {2}")
        cmd_set_affinity = "/opt/netronome/bin/set_irq_affinity.sh {0}"
        # ____________________________________________________

        # 2.1 Create results folder
        # `````````````````````````
        self.tools.create_folder(self.result_folder)

        # 2.2 Prepare device (install netperf and get local cpu list)
        # ```````````````````````````````````````````````````````````
        for dev in self.devices:
            dev.cmd(cmd_install, fail=False)
            self.tools.get_local_cpus(dev)

        # 2.3 Setup Interfaces, set MTU and set irq affinity
        # ``````````````````````````````````````````````````
        mtu = max(self.packet_size) if isinstance(
            self.packet_size, list) else self.packet_size

        for dev in self.devices:
            [dev.cmd(cmd_ifconfig.format(inf, ip, mtu))
             for inf, ip in zip(dev.intf, dev.addr)]
            time.sleep(1)
            [dev.cmd(cmd_set_affinity.format(inf))
             for inf in dev.intf]

        # 2.4 Check connectivity
        # ``````````````````````
        boo_ping = self.tools.ping_test(self.devices)
        if not boo_ping:
            return False, "Ping test failed"

        # 2.5 Set auto values
        # ```````````````````
        if self.threads == 'Auto':
            self.threads = min([len(dev.local_cpu_list)
                                for dev in self.devices])

        return True, ""

    def generate_thread_parameters(self):

        #######################################################################
        #               3. GENERATE DICTIONARIES FOR EACH THREAD
        #######################################################################

        # 3.1 Create a dictionary list for all the threads
        # ````````````````````````````````````````````````
        iteration_list = [('thread', range(self.threads
                                           / len(self.streams)
                                           / self.port)),
                          ('port', range(self.port)),
                          ('stream', self.streams)]

        self.iterations, n_iters = self.tools.create_iterations_list(
            iteration_list)

        # 3.2 Support multiple frame sizes. Stretch list of
        #     packet sizes to match nr threads
        # ``````````````````````````````````````````````````
        if isinstance(self.packet_size, list):
            __size = self.tools.stretch_list(self.packet_size,
                                             n_iters)
        else:
            __size = [self.packet_size] * len(self.iterations)

        # 3.3 Add attributes to thread dictionaries
        # `````````````````````````````````````````
        for i, itr in enumerate(self.iterations):

            # 3.3.1 Calculate parameter values
            # ````````````````````````````````
            client = self.client[itr.port]

            all_cpus = client.local_cpu_list
            first_half = client.local_cpu_list[
                    len(client.local_cpu_list)/2:]
            second_half = client.local_cpu_list[
                    :len(client.local_cpu_list)/2]

            if self.port == 1:
                local_cpu_list = all_cpus
            elif self.port == 2 and itr.port == 0:
                local_cpu_list = first_half
            elif self.port == 2 and itr.port == 1:
                local_cpu_list = second_half
            offset = len(local_cpu_list)/2 if itr.stream == 'Reverse' else 0

            cpu = local_cpu_list[itr.thread % len(
                local_cpu_list) + offset]

            server_ip = self.server.addr[itr.port]

            # 3.3.2 Set basic values
            # ``````````````````````
            _0_cpu = " taskset --cpu-list {}".format(cpu)
            _1_host = ' -H {}'.format(server_ip)
            _2_type = ""
            _3_length = " -l {}".format(self.time)
            _4_udp = ""

            # 3.3.3 Optional parameters and parameters requiring logic
            # ````````````````````````````````````````````````````````
            if self.type == 'UDP':
                _2_type = " -t UDP_STREAM"
            elif self.type == 'TCP':
                if itr.stream == 'Forward':
                    _2_type = ' -t TCP_STREAM'
                elif itr.stream == 'Reverse':
                    _2_type = ' -t TCP_MAERTS'
            if self.type == 'UDP':
                _4_udp = "-- -m {}".format(__size[i])
                _11_stream = ' --reverse'

            itr.type = self.type
            itr.file_name = ("{}{}_{}_{}.txt"
                             ).format(self.temp_dir,
                                      itr.stream,
                                      itr.port,
                                      itr.thread)

            # 3.4 Give iteration object the required attributes
            # `````````````````````````````````````````````````
            itr.params = [_0_cpu,
                          _1_host,
                          _2_type,
                          _3_length,
                          _4_udp,
                          itr.file_name]

        return

    def run_test(self):

        #######################################################################
        #                4. LAUNCH NETPERF SERVERS AND CLIENTS
        #######################################################################

        # List of unformatted commands (in order of execution)
        # ____________________________________________________

        cmd_empty_remote_folder = "mkdir -p {0} & rm -rf {0}*"

        cmd_kill_softly = 'killall netserver'

        cmd_server = "netserver"
        cmd_client = ("{0} netperf {1}{2}{3} -c -P0 -f m {4} > {5}")
        # ____________________________________________________

        # 4.1 Empty temporary iterations folder
        # `````````````````````````````````````
        self.tools.create_folder(self.temp_dir, remove_first=True)
        for dev in self.client:
            dev.cmd(cmd_empty_remote_folder.format(self.temp_dir))

        # ------------------------ 4.2 SERVERS ----------------------------
        self.server.cmd(cmd_kill_softly, fail=False)
        time.sleep(0.1)

        self.server.cmd(cmd_server)
        time.sleep(1)
        # ------------------------ 4.3 Clients ----------------------------

        # 4.3.1 Kill previous Netperf client threads
        # ``````````````````````````````````````````
        for dev in self.client:
            dev.cmd(cmd_kill_softly, fail=False)
        time.sleep(0.2)

        # 4.3.2 Launch Netperf client threads
        # ```````````````````````````````````
        cmd_client_exe = ' &\n'.join(map(
            lambda itr: cmd_client.format(*itr.params),
            self.iterations))

        for dev in self.client:
            dev.cmd(cmd_client_exe, background=True)

        # ------------------------ 4.3 Clients ----------------------------

        # 4.4 Wait for test iteration to complete
        # ```````````````````````````````````````
        wait_time = self.time + self.settle_time
        time.sleep(wait_time)

        return

    def read_data(self):

        #######################################################################
        #                        5. READ TEST RESULTS
        #######################################################################

        # List of unformatted commands (in order of execution)
        # ____________________________________________________

        cmd_ls = "ls {0}"
        cmd_rm = "rm -rf {0}"
        # ____________________________________________________

        # 5.1 Create results structure
        # ```````````````````````````
        results, results_per_thread = dict(), dict()

        results_name_list = ['throughput', 'sum_Forward', 'sum_Reverse',
                             'sum_Port_1', 'sum_Port_2']
        for name in results_name_list:
            results[name] = 0
            results_per_thread[name] = []

        # 5.2 Copy files from remote client
        # `````````````````````````````````
        for dev in self.client:
            if not dev.local_cmds:
                _, files = dev.cmd(cmd_ls.format(self.temp_dir))
                for file_name in files.rstrip().split("\n"):
                    file_path = os.path.join(self.temp_dir, file_name)
                    dev.cp_from(file_path, file_path)

        time.sleep(3)
        error = False
        # 5.3 Extract data from all the thread files
        # ``````````````````````````````````````````
        for itr in self.iterations:
            try:
                # 5.3.1 Read file
                # `````````````
                lines = open(itr.file_name, 'r').readlines()
                lines = [line for line in lines if line is not '\n']
                if itr.type == 'TCP':
                    index = 4
                elif itr.type == 'UDP':
                    index = 3
                thru = round(float(lines[0] .split()[index]) * 1e-3, 2)

                # 5.3.2 Add throughput result
                # `````````````````````````
                results_per_thread['throughput'].append(thru)

                # 5.3.3 Topological separation
                # ``````````````````````````
                if itr.stream == 'Forward':
                    results_per_thread['sum_Forward'].append(thru)
                if itr.stream == 'Reverse':
                    results_per_thread['sum_Reverse'].append(thru)
                if itr.port == 0:
                    results_per_thread['sum_Port_1'].append(thru)
                if itr.port == 1:
                    results_per_thread['sum_Port_2'].append(thru)
            except Exception as e:
                print "Error", itr.file_name, e
                error = True
                break

        # 5.4 Aggregate results
        # `````````````````````
        if not error:
            for name in results_name_list:
                if results_per_thread[name]:
                    results[name] = round(sum(results_per_thread[name]), 2)

        # 5.5 Remove raw result folder
        # ````````````````````````````
        for dev in self.devices:
            dev.cmd(cmd_rm.format(self.temp_dir))
        shutil.rmtree(self.temp_dir, ignore_errors=True)
        os.mkdir(self.temp_dir)

        return error, results, results_per_thread

    def save_data(self, trial_results):

        #######################################################################
        #                        6. SAVE TEST RESULTS
        #######################################################################
        # 6.1 Create object containing relevant data to save
        # ``````````````````````````````````````````````````
        fields_from_test = ["packet_size",
                            "traffic_generator",
                            "top",
                            "type",
                            "threads",
                            "time",
                            "port"]
        fields_from_results = ["throughput",
                               "sum_Forward",
                               "sum_Reverse",
                               "sum_Port_1",
                               "sum_Port_2"]

        list_dict_results = []
        for i in range(len(trial_results) + 1):

            result_dict = dict()
            for f in fields_from_test:
                result_dict[f] = getattr(self, f)

            if i == 0:
                result_dict["trial"] = 'All'
                for f in fields_from_results:
                    filed_list = self.tools.filter_dict_list(trial_results, f)
                    result_dict[f] = self.tools.process_data(filed_list)
            else:
                result_dict["trial"] = i
                for f in fields_from_results:
                    result_dict[f] = trial_results[i - 1][f]

            list_dict_results.append(Attribute_dict(result_dict))

        # 6.2 Write csv headings
        # ``````````````````````
        if self.number is 1:
            csv_line = list_dict_results[0].csv_output(headings=True)
            self.tools.append_line_to_file(csv_line,
                                           self.results_file,
                                           create_file=True)
        # 6.2 Write csv body
        # ``````````````````
        for dict_result in list_dict_results:
            csv_line = dict_result.csv_output(headings=False)
            self.tools.append_line_to_file(csv_line,
                                           self.results_file)

        return list_dict_results[0].throughput
