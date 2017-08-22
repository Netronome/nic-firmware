##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Iperf test classes for the NFPFlowNIC Software Group.
"""

import os
import re
import random
import time
from netro.testinfra import Test, LOG_sec, LOG, LOG_endsec
from scapy.all import TCP, UDP, IP, IPv6, rdpcap, Raw, PacketList, Packet
from netro.testinfra.utilities import timed_poll
from tempfile import mkstemp
from netro.testinfra.nrt_result import NrtResult
from netro.testinfra.nti_exceptions import NtiTimeoutError, NtiGeneralError
from expect_cntr_list import RingSize_ethtool_tx_cntr, RingSize_ethtool_rx_cntr


##############################################################################
# Iperf test
##############################################################################
class Iperftest(Test):
    """IPerf test"""

    # Information applicable to all subclasses
    _gen_info = """
    Using Iperf to send packets
    """

    def __init__(self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='udp', iperr=False,
                 l4err=False, dst_mac_type="tgt", src_mac_type="src",
                 vlan=False, vlan_id=100, num_pkts=1, iperf_time=1,
                 src_mtu=1500, dst_mtu=1500, group=None, name="iperf",
                 summary=None):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        Test.__init__(self, group, name, summary)

        self.src = None
        self.src_ifn = None
        self.dst = None
        self.dst_ifn = None

        self.promisc = promisc
        self.ipv4 = ipv4

        if src[0]:
            # src and dst maybe None if called without config file for list
            self.src = src[0]
            self.src_addr = src[1]
            self.src_ifn = src[2]
            self.dst = dst[0]
            self.dst_addr = dst[1]
            self.dst_ifn = dst[2]
            self.src_addr_v6 = src[3]
            self.dst_addr_v6 = dst[3]

        # These will be set in the run() method
        self.src_mac = None
        self.src_ip = None
        self.dst_mac = None
        self.dst_ip = None

        # ipv4 indicates IPv4 or IPv6
        # True -> IPv4; False-> IPv6
        self.ipv4 = ipv4
        # l4_type indicates the type of payload
        # 'udp'-> UDP; 'tcp'-> TCP; other -> ICMP;
        self.l4_type = l4_type
        # l4err indicates whether UDP/TCP checksum error is inserted
        self.l4err = l4err
        # promisc indicates whether VNIC is set in promiscuous mode
        self.promisc = promisc
        # iperr indicates whether IPv4 checksum error is inserted
        self.iperr = iperr
        # ipv4_opt indicates whether IPv4 option (NOP) is enabled
        self.ipv4_opt = ipv4_opt
        # ipv6_rt: true if IPv6 extension (header routing) is enabled
        self.ipv6_rt = ipv6_rt
        # ipv6_hbh: true if IPv6 extension (HopByHop) is enabled
        self.ipv6_hbh = ipv6_hbh
        # dst_mac_type: indicate what dst MAC address is used
        # "tgt": the true dst MAC; "diff": a different dst MAC
        # "mc": the multicast dst MAC; "bc": the broadcast dst MAC
        self.dst_mac_type = dst_mac_type
        # src_mac_type: true if a broadcast dst MAC address is used
        self.src_mac_type = src_mac_type
        # vlan: true if VLAN tag is included in the packet
        self.vlan = vlan
        # vlan_id: vlan_id when vlan tag is included in the packet
        self.vlan_id = vlan_id

        self.num_pkts = num_pkts
        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu
        # iperf_time: time in seconds to transmit packet in iperf client
        self.iperf_time = iperf_time
        self.dst_tmp_dir = None
        self.dst_srv_file = None
        self.dst_pcap_file = None
        self.local_recv_pcap = None
        self.rcv_pkts = None
        # Command-line argument strings for iperf server and iperf client
        self.iperf_server_arg_str = ''
        self.iperf_client_arg_str = ''
        self.iperf_s_pid = None
        self.iperf_c_pid = None
        self.tcpdump_dst_pid = None
        self.tcpdump_src_pid = None

        return

    def run(self):

        """Run the test
        @return:  A result object"""

        rc_passed = True
        rc_comment = ''
        try:
            self.get_intf_info()

            self.interface_cfg()

            self.ping_before_iperf()

            self.run_iperf()

            rc_passed, rc_comment = self.check_result()
        except:
            rc_passed = False
            raise
        finally:
            self.clean_up(passed=rc_passed)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=rc_passed, comment=rc_comment)

    def ping_before_iperf(self):

        dst_netifs = self.dst.netifs[self.dst_ifn]
        src_netifs = self.src.netifs[self.src_ifn]
        before_dst_cntrs = dst_netifs.stats()
        before_src_cntrs = src_netifs.stats()
        try:
            timed_poll(20, self.is_pingable)
        except:
            raise NtiTimeoutError(msg='Failed to ping DST before iperf test')
        finally:
            after_dst_cntrs = dst_netifs.stats()
            after_src_cntrs = src_netifs.stats()
            diff_dst_cntrs = after_dst_cntrs - before_dst_cntrs
            diff_src_cntrs = after_src_cntrs - before_src_cntrs
            # dump the stats to the log
            LOG_sec("DST Interface stats difference after ping")
            LOG(diff_dst_cntrs.pp())
            LOG_endsec()
            LOG_sec("SRC Interface stats difference after ping")
            LOG(diff_src_cntrs.pp())
            LOG_endsec()

    def is_pingable(self):

        dst_ip = self.dst_ip

        if self.ipv4:
            cmd = 'ping -c 1  -i 1 %s -w 4' % dst_ip
        else:
            cmd = 'ping6 -c 1  -i 1 %s -w 4' % dst_ip
        ret, _ = self.src.cmd(cmd, fail=False)
        if ret:
            return False
        else:
            return True

    def run_iperf(self):

        self.prepare_temp_dir()
        self.iperf_arg_str_cfg()

        self.start_tshark_listening()
        self.start_iperf_server()
        self.start_iperf_client()
        self.get_result()
        return

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        self.dst.cmd("ethtool -K %s rx on" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s gso off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s gro off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s lro off" % self.dst_ifn)
        if not self.ipv4:
            self.dst.cmd("ifconfig %s allmulti" % self.dst_ifn)
            self.src.cmd("ifconfig %s allmulti" % self.src_ifn)

        return

    def get_intf_info(self):
        """
        get the IP address (IPv4 or IPv6) and mac address of the src and dst
        interfaces
        """
        self.src.refresh()
        self.dst.refresh()
        src_if = self.src.netifs[self.src_ifn]
        dst_if = self.dst.netifs[self.dst_ifn]

        self.src_mac = src_if.mac
        self.dst_mac = dst_if.mac
        if self.ipv4:
            self.src_ip = src_if.ip
            self.dst_ip = dst_if.ip
        else:
            self.src_ip = self.get_ipv6(self.src, self.src_ifn,
                                        self.src_addr_v6)
            self.dst_ip = self.get_ipv6(self.dst, self.dst_ifn,
                                        self.dst_addr_v6)
        return

    def get_ipv6(self, device, intf, predefine_ipv6):
        """
        Run ipv6 addr show on the interface and extract the address.
        Example of 'ip addr show dev %s':
        eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP
        link/ether 00:1b:21:57:ef:04 brd ff:ff:ff:ff:ff:ff
        inet 10.0.0.2/24 scope global eth1
        inet6 fc00:1::2/64 scope global

        """
        _, output = device.cmd("ip addr show dev %s" % intf)
        inet6_str = '\s*inet6\s+([0-9a-fA-F:]+)/[0-9]{2,3}\s+scope global'

        if not re.findall(inet6_str, output):
            device.cmd('ifconfig %s inet6 add %s' % (intf, predefine_ipv6))
            ipv6_re_str = '([0-9a-fA-F:]+)/[0-9]{2,3}'
            m = re.findall(ipv6_re_str, predefine_ipv6)
            ip_v6_addr = m[0]
        else:
            m = re.findall(inet6_str, output)
            ip_v6_addr = m[0]

        return ip_v6_addr

    def prepare_temp_dir(self):
        """
        prepare temporary directory and files for iperf server output and
        tcpdump output
        """
        self.dst_tmp_dir = self.dst.make_temp_dir()
        dst_srv_fname = 'iperf_srv.txt'
        dst_pcap_fname = 'recv.pcap'
        self.dst_srv_file = os.path.join(self.dst_tmp_dir, dst_srv_fname)
        self.dst_pcap_file = os.path.join(self.dst_tmp_dir, dst_pcap_fname)
        return

    def iperf_arg_str_cfg(self):
        """
        Configure the command-line argument strings for both iperf server and
        iperf client
        """
        if not self.ipv4:
            self.iperf_server_arg_str += ' -V'
            self.iperf_client_arg_str += ' -V'
        if self.l4_type == 'udp':
            self.iperf_server_arg_str += ' -u'
            self.iperf_client_arg_str += ' -u'
        if self.l4_type == 'udp' and not self.ipv4:
            # Avoid IPv6 fragmentation
            self.iperf_client_arg_str += ' -l 1K'

        self.iperf_client_arg_str += ' -t %s' % self.iperf_time
        return

    def start_iperf_server(self):
        """
        Start the iperf server, using the command-line argument string
        configured in iperf_arg_str_cfg(). Use a timed_poll method to check if
        the iperf server has started properly.
        """
        if self.vlan:
            dst_ip = self.dst_vlan_ip
        else:
            dst_ip = self.dst_ip
        iperf_s_str = 'iperf -s -B %s' % dst_ip
        cmd = "ps aux | grep \"%s\" | grep -v grep" % iperf_s_str
        ret, _ = self.dst.cmd(cmd, fail=False)
        if ret:
            iperf_pid_file = os.path.join(self.dst_tmp_dir, 'ipf_tmp_pid.txt')
            cmd = "%s %s 2>&1 > %s" % (iperf_s_str,
                                       self.iperf_server_arg_str,
                                       self.dst_srv_file)
            ret, _ = self.dst.cmd_bg_pid_file(cmd, iperf_pid_file,
                                              background=True)
            self.iperf_s_pid = ret[1]
            ## Check output of iperf server to make sure it is running
            timed_poll(30, self.is_iperf_server_running, self.dst_srv_file)
        else:
            raise NtiGeneralError('%s has already started before test, '
                                  'please clean up machines first' %
                                  iperf_s_str)
        return

    def start_iperf_client(self):
        """
        Start the iperf client, using the command-line argument string
        configured in iperf_arg_str_cfg().
        """
        dst_netifs = self.dst.netifs[self.dst_ifn]
        src_netifs = self.src.netifs[self.src_ifn]
        before_dst_cntrs = dst_netifs.stats()
        before_src_cntrs = src_netifs.stats()
        cmd = "iperf -c %s %s" % (self.dst_ip, self.iperf_client_arg_str)
        self.src.cmd(cmd)
        after_dst_cntrs = dst_netifs.stats()
        after_src_cntrs = src_netifs.stats()
        diff_dst_cntrs = after_dst_cntrs - before_dst_cntrs
        diff_src_cntrs = after_src_cntrs - before_src_cntrs
        # dump the stats to the log
        LOG_sec("DST Interface stats difference")
        LOG(diff_dst_cntrs.pp())
        LOG_endsec()
        LOG_sec("SRC Interface stats difference")
        LOG(diff_src_cntrs.pp())
        LOG_endsec()
        return

    def start_tshark_listening(self):
        """
        Start the tcpdump to listening to the interfaces.
        """
        tcpd_pid_file = os.path.join(self.dst_tmp_dir, 'tcpd_tmp_pid.txt')
        cmd = "tcpdump -n -w %s -i %s -p 'ether src %s and ether dst %s' " \
              " 2> %s/tcpdump_stderr.txt " \
              % (self.dst_pcap_file, self.dst_ifn, self.src_mac,
                 self.dst_mac, self.dst_tmp_dir)
        ret, _ = self.dst.cmd_bg_pid_file(cmd, tcpd_pid_file, background=True)
        self.tcpdump_dst_pid = ret[1]
        timed_poll(30, self.dst.exists_host, self.dst_pcap_file, delay=1)
        return

    def is_iperf_traffic_received(self):
        """
        Check the output of iperf server. Return true if the stats line is
        found.
        """
        # find the stats line in iperf server output, such as the last line
        # in this xample:
        #------------------------------------------------------------
        #Server listening on UDP port 5001
        #Receiving 1470 byte datagrams
        #UDP buffer size:  208 KByte (default)
        #------------------------------------------------------------
        #[  3] local fc00:1::2 port 5001 connected with fc00:1::1 port 48836
        #[ ID] Interval       Transfer     Bandwidth        Jitter   Lost/Total Datagrams
        #[  3]  0.0- 0.1 sec  15.0 KBytes  1.05 Mbits/sec   0.003 ms    0/   15 (0%)
        #
        # Without this stats line, it means iperf server receives no traffic

        _, iperf_server_output = self.dst.cmd('cat %s' % self.dst_srv_file)
        re_recv_stats_str = '[\s+[0-9]+]\s+[0-9]+.[0-9]+-\s+[0-9]+.[0-9]+\s' \
                            '+sec\s+[0-9.]+\s+[GMK]*Bytes\s*[0-9.]+\s+[GMK]*' \
                            'bits/sec'
        if re.findall(re_recv_stats_str, iperf_server_output):
            return True
        else:
            return False


    def get_result(self):
        """
        Copy the received pcap file from dst to local machine and read
        packets from the pcap file on the local machine.
        """
        try:
            timed_poll(10, self.is_iperf_traffic_received)
        except NtiTimeoutError:
            self.dst.killall_w_pid(self.iperf_s_pid, signal='-9')
            # check the iperf server output one more time
            if not self.is_iperf_traffic_received():
                msg = 'Iperf server does not receive traffic'
                raise NtiGeneralError(msg)
        # wait a second to allow tcpdump to finish writting packets.
        time.sleep(1)
        self.dst.killall_w_pid(self.tcpdump_dst_pid)
        self.src.killall_w_pid(self.tcpdump_src_pid)
        self.dst.cmd('cat %s' % self.dst_srv_file, fail=False)
        _, self.local_recv_pcap = mkstemp()
        self.dst.cp_from(self.dst_pcap_file, self.local_recv_pcap)
        self.rcv_pkts = rdpcap(self.local_recv_pcap)
        return

    def clean_up(self, passed=True):
        """
        Remove temporary directory and files
        """
        # make sure iperf and tcpdump are stopped.
        self.dst.killall_w_pid(self.iperf_s_pid, signal='-9')
        self.dst.killall_w_pid(self.tcpdump_dst_pid)
        self.src.killall_w_pid(self.tcpdump_src_pid)
        if not self.ipv4:
            self.dst.cmd("ifconfig %s -allmulti" % self.dst_ifn)
            self.src.cmd("ifconfig %s -allmulti" % self.src_ifn)
        if self.local_recv_pcap:
            os.remove(self.local_recv_pcap)
        if self.dst_tmp_dir and passed:
            self.dst.rm_dir(self.dst_tmp_dir)
        return

    def check_result(self):
        """
        This method needs to be defined by each sub test class.
        """
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=False, comment="The check_result method is "
                                               "not defined in the sub test "
                                               "class")

    def is_iperf_server_running(self, iperf_server_output):
        """
        check the output file of iperf server, and return true if iperf server
        has started and is listening now
        """
        passed = False
        expt_str = 'Server listening'
        ret, out = self.dst.cmd('cat %s' % iperf_server_output, fail=False)
        if not ret and expt_str in out:
            passed = True
        return passed


##############################################################################
# TX checksum offload test
##############################################################################
class Csum_Tx(Iperftest):
    """Test class for TX checksum offload test"""

    summary = "TX checksum offload test"

    info = """
    This test send a number of packets from DUT to Host A using Iperf.
    Host receives packets and verifies them.
    """

    def __init__(self, src, dst, ipv4=True, l4_type='udp', group=None,
                 num_pkts=1, vlan_offload=False, vlan=False,
                 txcsum_offload=True, name="ip", summary=None):
        Iperftest.__init__(self, src, dst, ipv4=ipv4, ipv4_opt=False,
                           ipv6_rt=False, ipv6_hbh=False, l4_type=l4_type,
                           iperr=False, l4err=False, promisc=False,
                           group=group, vlan=vlan, dst_mac_type="tgt",
                           src_mac_type="src", num_pkts=num_pkts, iperf_time=1,
                           src_mtu=1500, dst_mtu=1500, name=name,
                           summary=summary)
        self.vlan_offload = vlan_offload
        self.txcsum_offload = txcsum_offload
        self.src_vlan_ifn = '%s.%s' % (self.src_ifn, self.vlan_id)
        self.dst_vlan_ifn = '%s.%s' % (self.dst_ifn, self.vlan_id)
        self.src_vlan_ip = None
        self.dst_vlan_ip = None
        self.hw_tx_csum = None
        self.hw_tx_inner_csum = None
        self.rx_pkts = None

    def run(self):

        """Run the test
        @return:  A result object"""
        if (not self.ipv4) and (self.l4_type == 'udp'):
            _, out = self.src.cmd("uname -r")
            version_num = int(out.split('.')[0])
            if version_num < 4:
                result_string = ": Kernel version (%s) is too old for " \
                                "IPV6_UDP_TX_checksum tests" % out
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=None, res=[result_string])


        ret = Iperftest.run(self)

        return ret

    def iperf_arg_str_cfg(self):
        """
        Configure the command-line argument strings for both iperf server and
        iperf client
        """
        Iperftest.iperf_arg_str_cfg(self)
        if self.vlan:
            self.iperf_client_arg_str += ' -n 384K -B %s' % self.src_vlan_ip
        else:
            self.iperf_client_arg_str += ' -n 384K'

    def vlan_cfg(self):
        """
        Create and configure vlan interfaces
        """
        self.src.vconfig_rem(self.src_ifn, self.vlan_id, fail=False)
        self.src.vconfig_add(self.src_ifn, self.vlan_id)
        self.src.cmd('ip addr flush dev %s' % self.src_vlan_ifn, fail=False)
        self.dst.vconfig_rem(self.dst_ifn, self.vlan_id, fail=False)
        self.dst.vconfig_add(self.dst_ifn, self.vlan_id)
        self.dst.cmd('ip addr flush dev %s' % self.dst_vlan_ifn, fail=False)
        # generate a random number for composing vlan ip (such as 10.255.255.x)
        #  1 and 2 are used on vNIC and endpoint interfaces.
        #src_random_last_octal = str(random.randint(100, 254))
        #dst_random_last_octal = str(random.randint(100, 254))
        #if src_random_last_octal == dst_random_last_octal:
        #    src_random_last_octal = str(int(dst_random_last_octal) - 1)
        src_if = self.src.netifs[self.src_ifn]
        dst_if = self.dst.netifs[self.dst_ifn]
        src_ip6 = self.get_ipv6(self.src, self.src_ifn,
                                    self.src_addr_v6)
        dst_ip6 = self.get_ipv6(self.dst, self.dst_ifn,
                                    self.dst_addr_v6)
        ipv4_re_str = '(\d{1,3}).(\d{1,3}.\d{1,3}.\d{1,3})'
        src_ipv4_octl = re.findall(ipv4_re_str, src_if.ip)
        if src_ipv4_octl:
            new_octl = (int(src_ipv4_octl[0][0]) + 100) % 255
            new_src_ipv4 = '%s.%s' % (new_octl, src_ipv4_octl[0][1])
        else:
            raise NtiGeneralError('Failed to create ipv4 for tunnel intf')
        dst_ipv4_octl = re.findall(ipv4_re_str, dst_if.ip)
        if dst_ipv4_octl:
            new_octl = (int(dst_ipv4_octl[0][0]) + 100) % 255
            new_dst_ipv4 = '%s.%s' % (new_octl, dst_ipv4_octl[0][1])
        else:
            raise NtiGeneralError('Failed to create ipv4 for tunnel intf')

        ipv6_re_str = '(^[a-f\d]{1,4})'
        src_ipv6_octl = re.findall(ipv6_re_str, src_ip6)
        if src_ipv6_octl:
            new_octl = (int(src_ipv6_octl[0], 16) + 100) % 65536
            octl_str = '%s' % hex(new_octl)
            new_src_ipv6 = re.sub(ipv6_re_str, octl_str[2:], src_ip6)
        else:
            raise NtiGeneralError('Failed to create ipv6 for tunnel intf')

        dst_ipv6_octl = re.findall(ipv6_re_str, dst_ip6)
        if dst_ipv6_octl:
            new_octl = (int(dst_ipv6_octl[0], 16) + 100) % 65536
            octl_str = '%s' % hex(new_octl)
            new_dst_ipv6 = re.sub(ipv6_re_str, octl_str[2:], dst_ip6)
        else:
            raise NtiGeneralError('Failed to create ipv6 for tunnel intf')

        if self.ipv4:
            self.src_vlan_ip = new_src_ipv4
            self.src.cmd('ifconfig %s %s/24 up' % (self.src_vlan_ifn,
                                                   self.src_vlan_ip))
            self.dst_vlan_ip = new_dst_ipv4
            self.dst.cmd('ifconfig %s %s/24 up' % (self.dst_vlan_ifn,
                                                   self.dst_vlan_ip))
        else:
            self.src_vlan_ip = new_src_ipv6
            self.src.cmd('ifconfig %s inet6 add %s/64' % (self.src_vlan_ifn,
                                                          self.src_vlan_ip))
            self.src.cmd('ifconfig %s up' % self.src_vlan_ifn)
            self.src.cmd('ifconfig -a')
            self.dst_vlan_ip = new_dst_ipv6
            self.dst.cmd('ifconfig %s inet6 add %s/64' % (self.dst_vlan_ifn,
                                                          self.dst_vlan_ip))
            self.dst.cmd('ifconfig %s up' % self.dst_vlan_ifn)
            self.dst.cmd('ifconfig -a')
            self.dst.cmd("ifconfig %s allmulti" % self.dst_vlan_ifn)
            self.src.cmd("ifconfig %s allmulti" % self.src_vlan_ifn)
        return

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        if self.vlan:
            self.vlan_cfg()
        Iperftest.interface_cfg(self)
        if self.vlan_offload:
            vlan_offload_status = 'on'
        else:
            vlan_offload_status = 'off'
        self.src.cmd("ethtool -K %s txvlan %s" % (self.src_ifn,
                                                  vlan_offload_status))
        if self.txcsum_offload:
            txcsum_status = 'on'
        else:
            txcsum_status = 'off'
        self.src.cmd("ethtool -K %s tx %s" % (self.src_ifn, txcsum_status))
        self.dst.cmd("ethtool -K %s rxvlan on" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s rx on" % self.dst_ifn)

        self.src.cmd("ethtool -k %s" % self.src_ifn)
        self.dst.cmd("ethtool -k %s" % self.dst_ifn)
        return

    def is_pingable(self):

        if self.vlan:
            dst_ip = self.dst_vlan_ip
        else:
            dst_ip = self.dst_ip

        if self.ipv4:
            cmd = 'ping -c 1  -i 1 %s -w 4' % dst_ip
        else:
            cmd = 'ping6 -c 1  -i 1 %s -w 4' % dst_ip
        ret, _ = self.src.cmd(cmd, fail=False)
        if ret:
            return False
        else:
            return True

    def check_csum_cnt(self):

        csum_passed = True
        csum_comment = ''

        if ((self.rx_pkts - self.hw_tx_csum) > 2 and self.txcsum_offload) or \
                (self.hw_tx_csum and not self.txcsum_offload):
            csum_passed = False
            csum_comment = 'hw_tx_csum (%s) != rx_pkts (%s) when ' \
                           'tx_csum offload is %s' % (self.hw_tx_csum,
                                                      self.rx_pkts,
                                                      self.txcsum_offload)
        return csum_passed, csum_comment

    def check_result(self):
        """
        Recalculate the checksum and check if received checksums are the same
        as recalculated ones
        """
        cr_passed = True
        cr_comment = ''
        # the total expected hw_csum pkts
        self.rx_pkts = 0
        for pkt in self.rcv_pkts:
            if UDP in pkt or TCP in pkt:
                # excludes ICMP and ICMPv6
                self.rx_pkts += 1

            ip_chksum = None
            l4_chksum = None
            rc_ip_chksum = None
            rc_l4_chksum = None

            if IP in pkt or IPv6 in pkt:
                # only check checksum of IP/IPv6 packet
                if IP in pkt:
                    ip_chksum = pkt[IP].chksum
                    del pkt[IP].chksum
                if self.l4_type == 'udp' and UDP in pkt:
                    l4_chksum = pkt[UDP].chksum
                    del pkt[UDP].chksum
                elif self.l4_type == 'tcp' and TCP in pkt:
                    l4_chksum = pkt[TCP].chksum
                    del pkt[TCP].chksum

                rc_pkt = pkt.__class__(str(pkt))
                if IP in pkt:
                    rc_ip_chksum = rc_pkt[IP].chksum
                if self.l4_type == 'udp' and UDP in pkt:
                    rc_l4_chksum = rc_pkt[UDP].chksum
                    if rc_l4_chksum == 0:
                        rc_l4_chksum = 65535
                elif self.l4_type == 'tcp' and TCP in pkt:
                    rc_l4_chksum = rc_pkt[TCP].chksum

                if ip_chksum != rc_ip_chksum or l4_chksum != rc_l4_chksum:
                    cr_passed = False
                    cr_comment = 'Checksum error'
                    LOG_sec("checksum error in packets with IP_ID %d" %
                            pkt[IP].id)
                    LOG("ip_chksum, rc_ip_chksum, l4_chksum, rc_l4_chksum")
                    LOG('%s, %s, %s, %s' % (ip_chksum, rc_ip_chksum, l4_chksum,
                                            rc_l4_chksum))
                    LOG_endsec()

        # find the stats line in iperf server output, such as the last line
        # in this xample:
        #------------------------------------------------------------
        #Server listening on UDP port 5001
        #Receiving 1470 byte datagrams
        #UDP buffer size:  208 KByte (default)
        #------------------------------------------------------------
        #[  3] local fc00:1::2 port 5001 connected with fc00:1::1 port 48836
        #[ ID] Interval       Transfer     Bandwidth        Jitter   Lost/Total Datagrams
        #[  3]  0.0- 0.1 sec  15.0 KBytes  1.05 Mbits/sec   0.003 ms    0/   15 (0%)
        #
        # Without this stats line, it means iperf server receives no traffic

        _, iperf_server_output = self.dst.cmd('cat %s' % self.dst_srv_file)
        re_recv_stats_str = '[\s+[0-9]+]\s+[0-9]+.[0-9]+-\s+[0-9]+.[0-9]+\s' \
                            '+sec\s+[0-9.]+\s+[GMK]*Bytes\s*[0-9.]+\s+[GMK]*' \
                            'bits/sec'
        if not re.findall(re_recv_stats_str, iperf_server_output):
            cr_passed = False
            cr_comment += 'Cannot find the iperf server received packets ' \
                          'stats line in iperf server output. Iperf server ' \
                          'may receive no traffic'

        if not cr_passed:
            LOG_sec("Iperf server didn't received packets")
            LOG(cr_comment)
            LOG_endsec()

        csum_passed, csum_comment = self.check_csum_cnt()

        if not csum_passed:
            LOG_sec("Checksum ethtool counter did not match")
            LOG(csum_comment)
            LOG_endsec()

        return (cr_passed and csum_passed), (cr_comment + csum_comment)

    def clean_up(self, passed=True):
        """
        Remove temporary directory and files, remove vlan interfaces
        """
        if self.vlan:
            self.src.vconfig_rem(self.src_ifn, self.vlan_id, fail=False)
            self.dst.vconfig_rem(self.dst_ifn, self.vlan_id, fail=False)
        Iperftest.clean_up(self, passed=passed)
        return

    def start_iperf_client(self):
        """
        Start the iperf client, using the command-line argument string
        configured in iperf_arg_str_cfg().
        """
        if self.vlan:
            dst_ip = self.dst_vlan_ip
        else:
            dst_ip = self.dst_ip

        dst_netifs = self.dst.netifs[self.dst_ifn]
        src_netifs = self.src.netifs[self.src_ifn]
        before_dst_cntrs = dst_netifs.stats()
        before_src_cntrs = src_netifs.stats()
        cmd = "iperf -c %s %s" % (dst_ip, self.iperf_client_arg_str)
        self.src.cmd(cmd)
        after_dst_cntrs = dst_netifs.stats()
        after_src_cntrs = src_netifs.stats()
        diff_dst_cntrs = after_dst_cntrs - before_dst_cntrs
        diff_src_cntrs = after_src_cntrs - before_src_cntrs
        # dump the stats to the log
        LOG_sec("DST Interface stats difference")
        LOG(diff_dst_cntrs.pp())
        LOG_endsec()
        LOG_sec("SRC Interface stats difference")
        LOG(diff_src_cntrs.pp())
        LOG_endsec()
        LOG_sec("rx/tx packets on both ends")
        msg = 'ethtool.rx_packets@DST = %s; ' \
              'ethtool.tx_packets@SRC = %s' % \
              (diff_dst_cntrs.ifconfig['rx_pkts'],
               diff_src_cntrs.ifconfig['tx_pkts'])
        LOG(msg)
        LOG_endsec()
        LOG_sec("rx packets (filtering out non TCP/UDP packets)")
        msg = 'rx packets @DST = %s ' % self.rx_pkts
        LOG(msg)
        LOG_endsec()
        LOG_sec("tx_checksum counters on src (NFP)")
        msg = 'ethtool.hw_tx_csum@SRC = %s; ' \
              'ethtool.hw_tx_inner_csum@SRC = %s' % \
              (diff_src_cntrs.ethtool['hw_tx_csum'],
               diff_src_cntrs.ethtool['hw_tx_inner_csum'])
        LOG(msg)
        LOG_endsec()
        self.hw_tx_csum = diff_src_cntrs.ethtool['hw_tx_csum']
        self.hw_tx_inner_csum = diff_src_cntrs.ethtool['hw_tx_inner_csum']
        return


##############################################################################
# Ring size iperf test
##############################################################################
class Ring_size(Iperftest):
    """Test class for TX checksum offload test"""

    summary = "Ring size iperf test"

    info = """
    This test send a number of packets from Host A to DUT using Iperf.

    """

    def __init__(self, src, dst, ipv4=True, l4_type='udp', group=None,
                 iperf_time=20, tx_ring_size=1024, rx_ring_size=1024,
                 name="ip", summary=None):
        Iperftest.__init__(self, src, dst, ipv4=ipv4, ipv4_opt=False,
                           ipv6_rt=False, ipv6_hbh=False, l4_type=l4_type,
                           iperr=False, l4err=False, promisc=False,
                           group=group, vlan=False, dst_mac_type="tgt",
                           src_mac_type="src", num_pkts=1,
                           iperf_time=iperf_time,
                           src_mtu=1500, dst_mtu=1500, name=name,
                           summary=summary)

        self.tx_ring_size = tx_ring_size
        self.rx_ring_size = rx_ring_size
        # Both self.dst_stats_after_iperf and self.dst_stats_before_iperf are
        # NetIFStats class object, storing statistics for the interface before
        # and after Iperf test
        self.dst_stats_before_iperf = None
        self.dst_stats_after_iperf = None
        # self.dst_csr_pcie_output_before and self.dst_csr_pcie_output_after
        # are the output string (the list of counters) of cmd
        # "nfp3200-csr pcie | grep pcie.Queue" before and after Iperf test
        self.dst_csr_pcie_output_before = ''
        self.dst_csr_pcie_output_after = ''
        self.csr_cmd = 'nfp3200-csr '
        self.default_ring_size = 4096
        # To calculate the corresponding csr counter, we define the offset
        # for tx counter as zero and rx counter as 129
        # rx_i_pckt -> pcie.Queue(i * 2 + offset)
        self.csr_tx_cntr_index_offset = 0
        self.csr_rx_cntr_index_offset = 129
        self.csr_cntr_list = self.list_csr_cntrs('tx')
        self.csr_cntr_list += self.list_csr_cntrs('rx')

    def get_intf_stats(self, device, inf):
        """
        Get the values of ethtool counters
        """
        inf_obj = device.netifs[inf]
        return inf_obj.stats()

    def start_iperf_client(self):
        """
        Start the iperf client, using the command-line argument string
        configured in iperf_arg_str_cfg(). Before start iperf client, we first
        get the values of ethtool counters and csr counters
        """
        _, out = self.dst.cmd(self.csr_cmd + self.csr_cntr_list)
        self.dst_csr_pcie_output_before = out
        self.dst_stats_before_iperf = self.get_intf_stats(self.dst,
                                                          self.dst_ifn)
        Iperftest.start_iperf_client(self)
        return

    def check_result(self):
        """
        Check ethtool counters and CSR counters.
        Use timed_poll to avoid failing the test premuturely.
        """
        try:
            timed_poll(30, self.is_csr_cntr_correct)
        except NtiTimeoutError:
            # check CSR counters for one last time, and get the comment that
            # indicates the list of failed counters.
            _, out = self.dst.cmd(self.csr_cmd + self.csr_cntr_list)
            self.dst_csr_pcie_output_after = out
            self.dst_stats_after_iperf = self.get_intf_stats(self.dst,
                                                             self.dst_ifn)
            df_stats = self.dst_stats_after_iperf - self.dst_stats_before_iperf
            tx_passed, tx_comment = self.check_cntrs(df_stats.ethtool, 'tx')
            rx_passed, rx_comment = self.check_cntrs(df_stats.ethtool, 'rx')
            if not tx_passed or not rx_passed:
                raise NtiTimeoutError(msg=(tx_comment + rx_comment))

        return True, ''

    def is_csr_cntr_correct(self):
        """
        Check ethtool counters and CSR counters, return True when CSR counters
        have the expected values
        """
        _, out = self.dst.cmd(self.csr_cmd + self.csr_cntr_list)
        self.dst_csr_pcie_output_after = out
        # diff_stats.ethtool is a CntrDict class (cntr_dict.py @ NTI/testinfra)
        # object, which is a sub class of dict, storing the ethtool counter
        # values (increment after iperf test).
        self.dst_stats_after_iperf = self.get_intf_stats(self.dst,
                                                         self.dst_ifn)
        diff_stats = self.dst_stats_after_iperf - self.dst_stats_before_iperf
        tx_passed, _ = self.check_cntrs(diff_stats.ethtool, 'tx')
        rx_passed, _ = self.check_cntrs(diff_stats.ethtool, 'rx')
        return tx_passed and rx_passed

    def check_cntrs(self, cntr_dict, tx_or_rx):
        """
        Find the non_zero entries in the dictionary of ethtool tx (or rx)
        counters, and check if the corresponding csr counters have been
        wrapped properly.
        Input:
        cntr_dict: the dictionary of ethtool tx (or rx) counters
        tx_or_rx: the input string to indicate whether 'tx' or 'rx' counters
        to check.
        """

        passed = True
        comment = ''
        if tx_or_rx == 'tx':
            cntr_name_list = RingSize_ethtool_tx_cntr
            re_cntr_name = 'txq_(\d+)_pkts'
            ring_size = self.tx_ring_size
            csr_index_offset = self.csr_tx_cntr_index_offset
        else:
            cntr_name_list = RingSize_ethtool_rx_cntr
            re_cntr_name = 'rxq_(\d+)_pkts'
            ring_size = self.rx_ring_size
            csr_index_offset = self.csr_rx_cntr_index_offset

        for cntr in cntr_name_list:
            # For each rx(tx)q_i_pkts ethtool counter that has a non-zero
            # increase after iperf test, we check the corresponding csr
            # counter (pcie.QueueX.StatusLow.ReadPtr,
            # pcie.QueueX.StatusHigh.WritePtr). The expect wrapper value
            # should be: (csr_before_value + rx(tx)q_i_pkts) % ring_size.
            if cntr_dict[cntr]:
                cntr_index = int(re.findall(re_cntr_name, cntr)[0])
                csr_cntr_index = cntr_index * 2 + csr_index_offset
                re_csr_rd = 'pcie.Queue%d.StatusLow.ReadPtr=([0x\da-fA-F]+)' \
                            % csr_cntr_index
                re_csr_wt = 'pcie.Queue%d.StatusHigh.WritePtr=([0x\da-fA-F]+)' \
                            % csr_cntr_index
                # get the csr counter values (before and after iperf test)
                csr_rd_before = re.findall(re_csr_rd,
                                           self.dst_csr_pcie_output_before)[0]
                csr_wt_before = re.findall(re_csr_wt,
                                           self.dst_csr_pcie_output_before)[0]
                csr_rd_after = re.findall(re_csr_rd,
                                          self.dst_csr_pcie_output_after)[0]
                csr_wt_after = re.findall(re_csr_wt,
                                          self.dst_csr_pcie_output_after)[0]
                # calculate the expected wrapped csr counter value
                expt_csr_rd = (int(csr_rd_before, 16) + cntr_dict[cntr]) % \
                              ring_size
                expt_csr_wt = (int(csr_wt_before, 16) + cntr_dict[cntr]) % \
                              ring_size
                # return error when csr counters are not wrapped properly
                if expt_csr_rd != int(csr_rd_after, 16) or expt_csr_wt \
                        != int(csr_wt_after, 16):
                    passed = False
                    comment += 'CSR wrapping error: Ethtool counter %s = %s; ' \
                               'pcie.Queue%d (before) = %d; pcie.Queue%d ' \
                               '(after) = %d; ring_size =  %d; ' \
                               'expected pcie.Queue%d value (after) = %d. ' \
                               % (cntr, cntr_dict[cntr], csr_cntr_index,
                                  int(csr_rd_before, 16), csr_cntr_index,
                                  int(csr_rd_after, 16), ring_size,
                                  csr_cntr_index, expt_csr_rd)

        return passed, comment

    def list_csr_cntrs(self, tx_or_rx):
        """
        Given the tx or rx ethtool counters list, list all corresponding
        CSR counters in the return string. This list of counter will be used
        when printing the CSR counter value
        Input:
        tx_or_rx: the input string to indicate whether 'tx' or 'rx' counters
        to check.
        """

        return_str = ''
        if tx_or_rx == 'tx':
            cntr_name_list = RingSize_ethtool_tx_cntr
            re_cntr_name = 'txq_(\d+)_pkts'
            csr_index_offset = self.csr_tx_cntr_index_offset
        else:
            cntr_name_list = RingSize_ethtool_rx_cntr
            re_cntr_name = 'rxq_(\d+)_pkts'
            csr_index_offset = self.csr_rx_cntr_index_offset

        for cntr in cntr_name_list:
            cntr_index = int(re.findall(re_cntr_name, cntr)[0])
            csr_cntr_index = cntr_index * 2 + csr_index_offset
            csr_rd_cnrt = ' pcie.Queue%d.StatusLow.ReadPtr' % csr_cntr_index
            csr_wr_cnrt = ' pcie.Queue%d.StatusHigh.WritePtr' % csr_cntr_index
            return_str += csr_rd_cnrt + csr_wr_cnrt
        return return_str

    def interface_cfg(self):
        """
        Configure interfaces (to only set ring size in this test)
        """
        self.set_ring_size(self.dst, self.dst_ifn, self.tx_ring_size,
                           self.rx_ring_size)
        return

    def set_ring_size(self, device, intf, tx_ring_size, rx_ring_size):
        """
        Bring down the interface, set ring sizes, and bring up the interface
        """
        device.cmd('ethtool -G %s rx %s' % (intf, rx_ring_size))
        device.cmd('ethtool -G %s tx %s' % (intf, tx_ring_size))
        device.cmd('ethtool -g %s' % intf)
        return

    def clean_up(self):
        """
        make sure iperf and tcpdump are stopped. And reset the ring size.
        """
        self.dst.killall_w_pid(self.iperf_s_pid, signal='-9')
        self.dst.killall_w_pid(self.tcpdump_dst_pid)
        self.src.killall_w_pid(self.tcpdump_src_pid)
        # reset ring size
        self.set_ring_size(self.dst, self.dst_ifn, self.default_ring_size,
                           self.default_ring_size)
        return

##############################################################################
# LSO test
##############################################################################
class LSO_iperf(Csum_Tx):
    """Test class for TX checksum offload test"""

    summary = "LSO test"

    info = """
    Host receives packets, verifies them and checks IP id, TCP seq and
    other fields in each packet
    """


    def __init__(self, src, dst, ipv4=True, l4_type='tcp', group=None,
                 src_mtu=1500, dst_mtu=1500, vlan=False,
                 num_pkts=1, txcsum_offload=True, name="ip", summary=None):
        Csum_Tx.__init__(self, src, dst, ipv4=ipv4, l4_type=l4_type,
                         txcsum_offload=txcsum_offload,
                         group=group, vlan=vlan, num_pkts=num_pkts,
                         name=name, summary=summary)
        self.src_tmp_dir = None
        self.src_pcap_file = None
        self.local_send_pcap = None
        self.snd_pkts = None
        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu


    def prepare_temp_dir(self):
        """
        prepare temporary directory and files for iperf server output and
        tcpdump output
        """
        Csum_Tx.prepare_temp_dir(self)
        self.src_tmp_dir = self.src.make_temp_dir()
        src_pcap_fname = 'send.pcap'
        self.src_pcap_file = os.path.join(self.src_tmp_dir, src_pcap_fname)

    def start_tshark_listening(self):
        """
        Start the tcpdump to listening to the interfaces.
        """
        #CHANGED, 50 to 200 packet to capture
        tcpd_pid_file = os.path.join(self.dst_tmp_dir, 'tcpd_tmp_pid.txt')
        cmd = "tcpdump -n -w %s -i %s -p 'ether src %s and ether dst %s' " \
              " 2> %s/tcpdump_stderr.txt " \
              % (self.dst_pcap_file, self.dst_ifn, self.src_mac,
                 self.dst_mac, self.dst_tmp_dir)
        ret, _ = self.dst.cmd_bg_pid_file(cmd, tcpd_pid_file,
                                          background=True)
        self.tcpdump_dst_pid = ret[1]
        tcpd_pid_file = os.path.join(self.src_tmp_dir, 'tcpd_tmp_pid.txt')
        cmd = "tcpdump -n -w %s -i %s -p 'ether src %s and ether dst %s' " \
              " 2> %s/tcpdump_stderr.txt " \
              % (self.src_pcap_file, self.src_ifn, self.src_mac,
                 self.dst_mac, self.src_tmp_dir)
        ret, _ = self.src.cmd_bg_pid_file(cmd, tcpd_pid_file, background=True)
        self.tcpdump_src_pid = ret[1]
        timed_poll(30, self.dst.exists_host, self.dst_pcap_file, delay=1)
        timed_poll(30, self.src.exists_host, self.src_pcap_file, delay=1)
        return

    def get_result(self):
        """
        Copy the received pcap file from dst to local machine and read
        packets from the pcap file on the local machine.
        """
        Csum_Tx.get_result(self)
        # wait a second to allow tcpdump to finish writting packets.
        time.sleep(1)
        self.dst.killall_w_pid(self.tcpdump_dst_pid)
        self.src.killall_w_pid(self.tcpdump_src_pid)
        _, self.local_send_pcap = mkstemp()
        self.src.cp_from(self.src_pcap_file, self.local_send_pcap)
        self.snd_pkts = rdpcap(self.local_send_pcap)
        return

    def clean_up(self, passed=True):
        """
        Remove temporary directory and files
        """
        # make sure iperf and tcpdump are stopped.
        self.dst.killall_w_pid(self.iperf_s_pid, signal='-9')
        self.dst.killall_w_pid(self.tcpdump_dst_pid)
        self.src.killall_w_pid(self.tcpdump_src_pid)
        if not self.ipv4:
            self.dst.cmd("ifconfig %s -allmulti" % self.dst_ifn)
            self.src.cmd("ifconfig %s -allmulti" % self.src_ifn)
        if self.local_recv_pcap:
            os.remove(self.local_recv_pcap)
        if self.local_send_pcap:
            os.remove(self.local_send_pcap)
        if self.dst_tmp_dir and passed:
            self.dst.rm_dir(self.dst_tmp_dir)
        if self.src_tmp_dir and passed:
            self.src.rm_dir(self.dst_tmp_dir)
        self.src.cmd('ifconfig %s mtu %s' % (self.src_ifn, 1500))
        self.dst.cmd('ifconfig %s mtu %s' % (self.dst_ifn, 1500))
        return

    def check_tcp_len(self, cur_send_pkt, ipv4):
        """
        Checking the TCP payload length
        """
        if ipv4:
            cur_tcp_len = cur_send_pkt[IP].len - \
                          (cur_send_pkt[IP].ihl +
                           cur_send_pkt[TCP].dataofs) * 4
        else:
            cur_tcp_len = cur_send_pkt[IPv6].plen - \
                          cur_send_pkt[TCP].dataofs * 4

        return cur_tcp_len

    def check_pkts(self, rcv_pkts, snd_pkts, l4_type, ipv4):
        """
        Checking LSO related field in packets
        """

        if l4_type == 'tcp':
            l4_prot = TCP
        elif l4_type == 'udp':
            l4_prot = UDP
        else:
            raise NtiGeneralError('Only TCP/UDP supported in LSO tests')
        if ipv4:
            ip_prot = IP
        else:
            ip_prot = IPv6

        # Check the total_length field of IP header
        total_length_passed = True
        total_length_comment = ''
        num_rcv_pkts = len(rcv_pkts)
        num_snd_pkts = len(snd_pkts)
        num_pkts_passed = True
        num_pkts_msg = ''

        if num_rcv_pkts <= num_snd_pkts:
            num_pkts_passed = False
            num_pkts_msg = ' No LSO packets: Number of send pckt = %d, ' \
                           'Number of recv pckt = %d' % (num_snd_pkts,
                                                         num_rcv_pkts)

        for pkt in rcv_pkts:
            if ip_prot in pkt and l4_prot in pkt and Raw in pkt:
                l4_len = len(pkt[l4_prot])
                # check total length in IPv4 header
                if ipv4 and pkt[ip_prot].len != l4_len + \
                        (pkt[ip_prot].ihl * 4):
                    total_length_passed = False
                    total_length_comment += 'IP total length field is not '\
                                            'correct (IP_id %s): IHL=%s, ' \
                                            'length of packet after IP ' \
                                            'header=%s, total_length_' \
                                            'field=%s; ' % (pkt[ip_prot].id,
                                                          pkt[ip_prot].ihl,
                                                          l4_len,
                                                          pkt[ip_prot].len)
                # check packet length in IPv6 header
                if not ipv4 and pkt[ip_prot].plen != l4_len:
                    total_length_passed = False
                    total_length_comment += 'IPv6 pckt length field is not '\
                                            'correct: packet length =%s, ' \
                                            'packet_length_field=%s; ' % \
                                            (l4_len, pkt[ip_prot].plen)

        ipid_passed = True
        ipid_comment = ''
        fin_psh_passed = True
        fin_psh_comment = ''
        seq_passed = True
        seq_comment = ''
        other_flags_passed = True
        other_flags_comment = ''
        fin_num = 0
        psh_num = 0
        fin_list = []
        psh_list = []
        # IP id is wrapped after 0xFFFF
        max_ipid = 65535
        raw_recv_pkts = PacketList()
        raw_send_pkts = PacketList()
        LOG_sec("Filtering packet")
        LOG('received packet list')
        # filtering out all zero payload packets
        for pkt in rcv_pkts:
            if ip_prot in pkt and Raw in pkt and l4_prot in pkt:
                raw_recv_pkts.append(pkt)
                if l4_type == 'tcp' and ipv4:
                    tcp_len = self.check_tcp_len(pkt, ipv4)
                    LOG('%s, %s, %s, %s' % (pkt[IP].id, pkt[TCP].seq,
                                            tcp_len,
                                            pkt[TCP].seq + tcp_len))
                elif l4_type == 'tcp' and not ipv4:
                    tcp_len = self.check_tcp_len(pkt, ipv4)
                    LOG('%s, %s, %s' % (pkt[TCP].seq, tcp_len,
                                        pkt[TCP].seq + tcp_len))
        LOG('sent packet list')
        for pkt in snd_pkts:
            if ip_prot in pkt and Raw in pkt and l4_prot in pkt:
                raw_send_pkts.append(pkt)
                if l4_type == 'tcp' and ipv4:
                    tcp_len = self.check_tcp_len(pkt, ipv4)
                    LOG('%s, %s, %s, %s' % (pkt[IP].id, pkt[TCP].seq,
                                            tcp_len,
                                            pkt[TCP].seq + tcp_len))
                elif l4_type == 'tcp' and not ipv4:
                    tcp_len = self.check_tcp_len(pkt, ipv4)
                    LOG('%s, %s, %s' % (pkt[TCP].seq, tcp_len,
                                        pkt[TCP].seq + tcp_len))
        LOG_endsec()

        LOG_sec("Checking LSO related field")
        if l4_type == 'tcp':
            # for TCP LSO tests, we first sort and filter packet lists
            flt_snd_passed, flt_snd_comment, sort_send_pkts \
                = self.filtering_pckts(raw_send_pkts, ipv4)
            flt_rcv_passed, flt_rcv_comment, sort_recv_pkts \
                = self.filtering_pckts(raw_recv_pkts, ipv4)
            seq_passed = flt_snd_passed and flt_rcv_passed
            seq_comment = flt_snd_comment + flt_rcv_comment

            while sort_send_pkts:
                # for every large sent segment, we find the corresponding
                # small received packet of this segment, and make sure:
                # 1) IP id of these received packets monotonically increase
                #    (wrapped after 0xFFFF)
                # 2) TCP seq (combined with packet length) doesn't overlap, or
                #    have gaps. And they cover the whole lenght of the large
                #    segment
                # 3) Check FIN and PSH flags. There should be no more than one
                #    FIN in the whole connection, and no more than one in each
                #    large segment.
                # 4) Check TCP flags. All the TCP flags set on the large sent
                #    segment should be set in the generated MTU sized packets
                #    Exception for the FIN, RST and PSH flags, should only be
                #    set in the last MTU sized packet if it was set in the
                #    large sent segment
                FIN = 0x01
                RST = 0x04
                PSH = 0x08
                cur_send_pkt = sort_send_pkts[0]
                cur_send_seq = cur_send_pkt[TCP].seq
                cur_tcp_len = self.check_tcp_len(cur_send_pkt, ipv4)
                cur_send_end_seq = cur_send_pkt[TCP].seq + cur_tcp_len
                if ipv4:
                    cur_send_id = cur_send_pkt[IP].id
                else:
                    cur_send_id = None
                LOG('sent pckt: ipid %s, tcp_seq %s, tcp_seq + '
                    'payload %s' % (cur_send_id, cur_send_seq,
                                         cur_send_end_seq))
                sort_send_pkts.pop(0)
                if sort_send_pkts:
                    is_last_segment = False
                else:
                    # already the last large segment
                    is_last_segment = True
                # find the first and last received packet of this segment
                first_recv_pckt_index = -1
                last_recv_pckt_index = -1
                for i in range(0, len(sort_recv_pkts)):
                    if sort_recv_pkts[i][TCP].seq == cur_send_seq:
                        first_recv_pckt_index = i
                    if not is_last_segment and sort_recv_pkts[i][TCP].seq \
                            < cur_send_end_seq:
                        last_recv_pckt_index = i
                    elif is_last_segment:
                        last_recv_pckt_index = len(sort_recv_pkts) - 1
                LOG('received pckt list: begin index %s, begin end %s' %
                    (first_recv_pckt_index, last_recv_pckt_index))
                if first_recv_pckt_index == -1 or last_recv_pckt_index == -1:
                        seq_passed = False
                        seq_comment += 'TCP_seq err: cannot find the ' \
                                       'first/last of the current larger ' \
                                       'segment %s' % (cur_send_seq)

                # check smaller received pckts in this large sent segment
                prev_recv_pkt = sort_recv_pkts[first_recv_pckt_index]
                cur_tcp_len = self.check_tcp_len(cur_send_pkt, ipv4)
                prev_tcp_len = self.check_tcp_len(prev_recv_pkt, ipv4)
                remain_seg_len = cur_tcp_len - prev_tcp_len
                # No more than one FIN in the whole connection
                if prev_recv_pkt[TCP].flags & 1:
                    fin_num += 1
                    fin_list.append(prev_recv_pkt[TCP].seq)
                # No more than one PSH in each large segment
                psh_num = 0
                psh_list = []
                if prev_recv_pkt[TCP].flags & 8:
                    psh_num += 1
                    psh_list.append(prev_recv_pkt[TCP].seq)

                # 4)
                cur_send_tcp_flags = cur_send_pkt[TCP].flags
                cur_send_tcp_flags_masked = cur_send_tcp_flags &\
                    ~(FIN | RST | PSH)

                if first_recv_pckt_index != last_recv_pckt_index:
                    # for segment that generates more than one received pckts
                    for i in range(first_recv_pckt_index + 1,
                                   last_recv_pckt_index + 1):
                        cur_recv_pkt = sort_recv_pkts[i]
                        if ipv4:
                            #check IP id in IPv4 tests
                            if cur_recv_pkt[IP].id != prev_recv_pkt[IP].id + 1 \
                                    and prev_recv_pkt[IP].id != max_ipid:
                                ipid_passed = False
                                ipid_comment += 'IP_ID err: The previos IP ID '\
                                                '= %s, but the current IP ID ' \
                                                '= %s; ' % \
                                                (prev_recv_pkt[IP].id,
                                                 cur_recv_pkt[IP].id)
                        # Check if TCP seq increases properly
                        prev_tcp_len = self.check_tcp_len(prev_recv_pkt, ipv4)
                        if cur_recv_pkt[TCP].seq != prev_recv_pkt[TCP].seq + \
                                prev_tcp_len:
                            seq_passed = False
                            seq_comment += 'TCP_seq err: The current TCP_' \
                                           'seq = %s, but %s is expected; ' \
                                           % (cur_recv_pkt[TCP].seq,
                                              prev_recv_pkt[TCP].seq +
                                              prev_tcp_len)
                        cur_tcp_len = self.check_tcp_len(cur_recv_pkt, ipv4)
                        remain_seg_len -= cur_tcp_len

                        # check FIN and PSH flag
                        if cur_recv_pkt[TCP].flags & 1:
                            fin_num += 1
                            fin_list.append(cur_recv_pkt[TCP].seq)
                        if cur_recv_pkt[TCP].flags & 8:
                            psh_num += 1
                            psh_list.append(cur_recv_pkt[TCP].seq)

                        cur_recv_tcp_flags = cur_recv_pkt[TCP].flags
                        if i < last_recv_pckt_index:
                            if cur_recv_tcp_flags != cur_send_tcp_flags_masked:
                                other_flags_passed = False
                                other_flags_comment += 'TCP flags err on ' \
                                    'TCP seq %s: expected %s got %s; ' \
                                    % (cur_recv_pkt[TCP].seq,
                                       cur_send_tcp_flags_masked,
                                       cur_recv_tcp_flags )
                        else: # last packet
                            if cur_recv_tcp_flags != cur_send_tcp_flags:
                                other_flags_passed = False
                                other_flags_comment += 'TCP flags err on ' \
                                    'TCP seq %s: expected %s got %s; ' \
                                    % (cur_recv_pkt[TCP].seq,
                                       cur_send_tcp_flags, cur_recv_tcp_flags )


                        prev_recv_pkt = cur_recv_pkt
                # check if the whole length of large segment is received
                if remain_seg_len:
                    seq_passed = False
                    seq_comment += 'TCP_seq err: There are %s bytes of data ' \
                                   'in the current large segment that are ' \
                                   'not send (current TCP seq = %s); ' % \
                                   (remain_seg_len, cur_send_seq)
                # No more than one PSH in each large segment
                if psh_num > 1:
                    fin_psh_passed = False
                    fin_psh_comment += 'TCP flag err: %s PSH flags in ' \
                        'segment %s; ' % (psh_num, cur_send_seq)

            # No more than one FIN in the whole connection
            if fin_num > 1:
                fin_psh_passed = False
                fin_psh_comment += 'TCP flag err: %s FIN flags in the whole ' \
                                'connection; ' % fin_num

        # Logging the detailed error comment
        if not total_length_passed:
            LOG_sec("IP total length not correct")
            LOG(total_length_comment)
            LOG_endsec()
            total_length_comment = "IP total length not correct. "
        if not fin_psh_passed:
            LOG_sec("FIN and/or PSH flag not correct")
            LOG(fin_psh_comment)
            LOG_endsec()
            fin_psh_comment = "Too many FIN and/or PSH flag per connection. "
        if not seq_passed:
            LOG_sec("TCP seq not correct")
            LOG(seq_comment)
            LOG_endsec()
            seq_comment = "TCP seq not correct. "
        if not ipid_passed:
            LOG_sec("IP id not correct")
            LOG(ipid_comment)
            LOG_endsec()
            ipid_comment = "IP id  not correct. "
        if not other_flags_passed:
            LOG_sec("TCP flags not correct")
            LOG(other_flags_comment)
            LOG_endsec()
            other_flags_comment = "TCP flags (not FIN and/or PSH) not correct"
        LOG_endsec()
        return (seq_passed and ipid_passed and fin_psh_passed and
                total_length_passed and other_flags_passed
                and num_pkts_passed), \
               (seq_comment + ipid_comment + fin_psh_comment +
                total_length_comment + other_flags_comment + num_pkts_msg)


    def check_result(self):
        """
        Recalculate the checksum and check if received checksums are the same
        as recalculated ones
        """
        cr_passed, cr_comment = Csum_Tx.check_result(self)

        if not cr_passed:
            LOG_sec("Checksum not correct")
            LOG(cr_comment)
            LOG_endsec()
            cr_comment = "Checksum not correct. "
        lso_passed, lso_comment = self.check_pkts(self.rcv_pkts,
                                                  self.snd_pkts,
                                                  self.l4_type, self.ipv4)
        return (cr_passed and lso_passed), (cr_comment + lso_comment)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        Csum_Tx.interface_cfg(self)
        self.src.cmd('ethtool -K %s tso on' % self.src_ifn)
        self.src.cmd('sysctl -w net.ipv4.tcp_min_tso_segs=2')
        self.src.cmd('ifconfig %s mtu %s' % (self.src_ifn, self.src_mtu))
        self.dst.cmd('ifconfig %s mtu %s' % (self.dst_ifn, self.dst_mtu))
        return

    def filtering_pckts(self, raw_pkts, ipv4):
        """
        Filtering TCP packets (re-order by TCP seq, remove re-transmitting
        TCP packets)
        """
        # re-order by TCP seq
        sort_pkts = sorted(raw_pkts, key=lambda packet: packet[TCP].seq)
        remove_pkts = PacketList()
        passed = True
        comment = ''

        #remove re-transmitting TCP packets
        prev_pkt = sort_pkts[0]
        for i in range(1, len(sort_pkts)):
            cur_pkt = sort_pkts[i]
            cur_tcp_len = self.check_tcp_len(cur_pkt, ipv4)
            prev_tcp_len = self.check_tcp_len(prev_pkt, ipv4)
            if prev_pkt[TCP].seq <= cur_pkt[TCP].seq < prev_pkt[TCP].seq + \
                    prev_tcp_len:
                if cur_pkt[TCP].seq + cur_tcp_len <= prev_pkt[TCP].seq \
                        + prev_tcp_len:
                    # re-transmitting TCP packet, remove it from the result list
                    remove_pkts.append(cur_pkt)
                else:
                    # packet error, the TCP seq is inside (or overlaps) the
                    # previous TCP segment (or packet), however, the length of
                    #  the current payload exceed the previous one, which
                    # should not happen if NIC is re-transmitting the packet(s)
                    passed = False
                    comment += ('TCP_seq error: too long payload in '
                                'transmitting packet (tcp.seq = %s) ' %
                                cur_pkt[TCP].seq)
            else:
                # no re-transmitting TCP packets, move on to the next one
                prev_pkt = cur_pkt
        for pkt in remove_pkts:
            sort_pkts.remove(pkt)
        return passed, comment, sort_pkts

    def start_iperf_client(self):
        """
        Start the iperf client, using the command-line argument string
        configured in iperf_arg_str_cfg().
        """
        if self.vlan:
            dst_ip = self.dst_vlan_ip
        else:
            dst_ip = self.dst_ip

        dst_netifs = self.dst.netifs[self.dst_ifn]
        src_netifs = self.src.netifs[self.src_ifn]
        before_dst_cntrs = dst_netifs.stats()
        before_src_cntrs = src_netifs.stats()
        cmd = "iperf -c %s %s" % (dst_ip, self.iperf_client_arg_str)
        self.src.cmd(cmd)
        after_dst_cntrs = dst_netifs.stats()
        after_src_cntrs = src_netifs.stats()
        diff_dst_cntrs = after_dst_cntrs - before_dst_cntrs
        diff_src_cntrs = after_src_cntrs - before_src_cntrs
        # dump the stats to the log
        LOG_sec("DST Interface stats difference")
        LOG(diff_dst_cntrs.pp())
        LOG_endsec()
        LOG_sec("SRC Interface stats difference")
        LOG(diff_src_cntrs.pp())
        LOG_endsec()
        LOG_sec("rx/tx packets on both ends and tx_lso@SRC ")
        msg = 'ethtool.rx_packets@DST = %s; ' \
              'ethtool.tx_packets@SRC = %s; ' \
              'ethtool.tx_lso@SRC = %s;' % \
              (diff_dst_cntrs.ifconfig['rx_pkts'],
               diff_src_cntrs.ifconfig['tx_pkts'],
               diff_src_cntrs.ethtool['tx_lso'])
        LOG(msg)
        LOG_endsec()
        LOG_sec("rx packets (filtering out non TCP/UDP packets)")
        msg = 'rx packets @DST = %s ' % self.rx_pkts
        LOG(msg)
        LOG_endsec()
        LOG_sec("tx_checksum counters on src (NFP)")
        msg = 'ethtool.hw_tx_csum@SRC = %s; ' \
              'ethtool.hw_tx_inner_csum@SRC = %s' % \
              (diff_src_cntrs.ethtool['hw_tx_csum'],
               diff_src_cntrs.ethtool['hw_tx_inner_csum'])
        LOG(msg)
        LOG_endsec()
        self.hw_tx_csum = diff_src_cntrs.ethtool['hw_tx_csum']
        self.hw_tx_inner_csum = diff_src_cntrs.ethtool['hw_tx_inner_csum']
        if diff_src_cntrs.ethtool['tx_lso']:
            return
        else:
            raise NtiGeneralError(msg='ethtool counters did not increase as '
                                      'expected: tx_lso = %s' %
                                      diff_src_cntrs.ethtool['tx_lso'])



class Tx_Drop_test(Iperftest):
    """Test class for dropping packets by changing MTU during iperf"""
    # Information applicable to all subclasses
    _gen_info = """
    Dropping TX packets by changing MTU during iperf.
    """

    def __init__(self, src, dst,
                 group=None, name="", summary=None):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        Iperftest.__init__(
            self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
            ipv6_rt=False, ipv6_hbh=False, l4_type='tcp', iperr=False,
            l4err=False, dst_mac_type="tgt", src_mac_type="src",
            vlan=False, vlan_id=100, num_pkts=1, iperf_time=20,
            src_mtu=1500, dst_mtu=1500, group=group, name=name,
            summary=summary)

        # in tx_drop (dut_is_dst==False), we change DUT (src)'s MTU, while in
        # rx_drop, we change DUT (dst)'s MTU
    def run(self):

        """Run the test
        @return:  A result object"""

        # Remove get_result() and check_result() from iperftest class, as we
        # use timed_cmd to run iperf client and if it finishes without
        # timeout, it passes. Otherwise, it failed as timeout
        rc_passed = True
        rc_comment = ''
        try:
            self.get_intf_info()

            self.interface_cfg()

            self.ping_before_iperf()

            self.run_iperf()
        except:
            rc_passed = False
            raise
        finally:
            self.clean_up(passed=rc_passed)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=rc_passed, comment=rc_comment)


    def run_iperf(self):

        self.prepare_temp_dir()
        self.iperf_arg_str_cfg()

        self.start_tshark_listening()
        self.start_iperf_server()
        self.start_iperf_client()

        return

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        self.dst.cmd("ethtool -K %s rx on" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s tx on" % self.dst_ifn)
        self.src.cmd("ethtool -K %s rx on" % self.src_ifn)
        self.src.cmd("ethtool -K %s tx on" % self.src_ifn)
        if not self.ipv4:
            self.dst.cmd("ifconfig %s allmulti" % self.dst_ifn)
            self.src.cmd("ifconfig %s allmulti" % self.src_ifn)

        return

    def iperf_arg_str_cfg(self):
        """
        Configure the command-line argument strings for both iperf server and
        iperf client
        """
        Iperftest.iperf_arg_str_cfg(self)
        self.iperf_client_arg_str += ' -P 50'
        return

    def start_iperf_client(self):
        """
        Start the iperf client, using the command-line argument string
        configured in iperf_arg_str_cfg().
        """
        dst_netifs = self.dst.netifs[self.dst_ifn]
        src_netifs = self.src.netifs[self.src_ifn]
        before_dst_cntrs = dst_netifs.stats()
        before_src_cntrs = src_netifs.stats()
        # for Dropping test, we run a background sleep + mtu change cmd on DUT
        # and run iperf client with a timeout. When timeout is not triggered,
        # test passes.
        sleep_time = self.iperf_time / 2
        cmd = 'sleep %s; ifconfig %s mtu 500' % (sleep_time, self.src_ifn)
        #TODO: need to change to the new pid_background method once the parallel
        # test code is pushed. Also need to modify the clean up accordingly
        self.src.cmd(cmd, background=True)
        cmd = "iperf -c %s %s" % (self.dst_ip, self.iperf_client_arg_str)
        iperf_wait_time = self.iperf_time * 2
        self.src.timed_cmd(cmd, timeout=iperf_wait_time)
        after_dst_cntrs = dst_netifs.stats()
        after_src_cntrs = src_netifs.stats()
        diff_dst_cntrs = after_dst_cntrs - before_dst_cntrs
        diff_src_cntrs = after_src_cntrs - before_src_cntrs
        # dump the stats to the log
        LOG_sec("DST Interface stats difference")
        LOG(diff_dst_cntrs.pp())
        LOG_endsec()
        LOG_sec("SRC Interface stats difference")
        LOG(diff_src_cntrs.pp())
        LOG_endsec()
        return

    def clean_up(self, passed=True):
        """
        Reset MTU, and remove temporary directory and files
        """
        self.dst.cmd("ifconfig %s mtu 1500" % self.dst_ifn)
        self.src.cmd("ifconfig %s mtu 1500" % self.src_ifn)
        Iperftest.clean_up(self, passed=passed)
        return
