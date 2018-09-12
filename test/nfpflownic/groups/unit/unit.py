##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Unit test classes for the NFPFlowNIC Software Group.
"""

import os
import re
import random
import hashlib
import ntpath
import math
import socket
import string
import time
from binascii import hexlify
from netro.testinfra import Test, LOG_sec, LOG, LOG_endsec
from scapy.all import TCP, UDP, IP, Ether, wrpcap, IPv6, ICMP, \
    IPOption_NOP, IPv6ExtHdrRouting, IPv6ExtHdrHopByHop, Dot1Q, Raw, rdpcap, \
    PacketList
from netro.tests.tcpreplay import TCPReplay
from netro.testinfra.utilities import timed_poll
from tempfile import mkstemp
from netro.testinfra.nrt_result import NrtResult
from netro.testinfra.system import cmd_log
from netro.tests.ping import Ping
from libs.pcap_cmp import Pcap_Cmp_BaseTest
from netro.testinfra.nti_exceptions import NtiTimeoutError, NtiGeneralError, \
    NtiError
from netro.testinfra.log import LOG_exception
from expect_cntr_list import UnitIP_dont_care_cntrs, RingSize_ethtool_rx_cntr
from ...common_test import CommonTest

class NFPFlowNICPing(Ping):
    """
    The wrapper class of Ping. Return NrtResult instead of Result
    """

    def run(self):

        # Up the interface.
        cmd = "ip link set dev %s up" % self.dst_ifn
        self.dst.cmd(cmd)

        # Verify interface is up.
        timed_poll(30, self.dst.if_interface_up, self.dst_ifn, delay=1)

        res = Ping.run(self)
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=res.passed,
                         comment="" if res.passed else res.comment)


class NFPFlowNICMTU():
    def set_mtu(self, device, inf, mtu_value):
        """
        Set the MTU of the given interface on the given machine
        """
        device.cmd("ifconfig -a")
        device.change_mtu(inf, mtu_value)
        device.cmd("ifconfig -a")
        return

    def get_mtu(self, device, inf):
        """
        Get the current MTU value of the given interface on the device
        """
        mtu_str = '\s+mtu\s+(\d+)\s+'
        cmd = "ip addr show dev %s" % inf
        _, out = device.cmd(cmd, fail=False)
        mtu = re.findall(mtu_str, out)
        if mtu:
            return int(mtu[0])
        else:
            return None

    def reset_mtu(self, device, inf):
        """
        Reset the MTU value (1500) of the given interface on the device
        """
        self.set_mtu(device, inf, '1500')

class NFPFlowMultiQueue():
    """
    An object class for multiple queue counter list
    """
    def __init__(self, queue_list):
        """
        queue_list: the index list of queue enabled in the NIC
        """
        self.num_q = None
        self.recv_cntrs = []
        self.rxq_cntrs = []
        self.txq_cntrs = []
        self.rxq_pkts_cntrs = []
        self.txq_pkts_cntrs = []
        self.recv_rx_pkts_cntrs = []
        self.recv_tx_pkts_cntrs = []
        queue_index =queue_list
        if queue_index:
            #max_index = 0
            for i in queue_index:
                self.recv_cntrs.append('rvec_%s_rx_pkts' % i)
                self.recv_rx_pkts_cntrs.append('rvec_%s_rx_pkts' % i)
                self.recv_cntrs.append('rvec_%s_tx_pkts' % i)
                self.recv_tx_pkts_cntrs.append('rvec_%s_tx_pkts' % i)
                self.recv_cntrs.append('rvec_%s_tx_busy' % i)
                self.rxq_cntrs.append('rxq_%s_pkts' % i)
                self.rxq_pkts_cntrs.append('rxq_%s_pkts' % i)
                self.rxq_cntrs.append('rxq_%s_bytes' % i)
                self.txq_cntrs.append('txq_%s_pkts' % i)
                self.txq_pkts_cntrs.append('txq_%s_pkts' % i)
                self.txq_cntrs.append('txq_%s_bytes' % i)
                #if int(i) > max_index:
                #    max_index = int(i)
            #self.num_q = max_index + 1
            self.num_q = len(queue_index)
        else:
            msg = 'Cannot find the number of RX queue in NIC'
            raise NtiGeneralError(msg)


class UnitIP(Test):
    """Test class for sending IP packets"""
    # Information applicable to all subclasses
    _gen_info = """
    sending IP packets.
    """

    def __init__(self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='udp', iperr=False,
                 l4err=False, dst_mac_type="tgt", src_mac_type="src",
                 vlan=False, vlan_id=100,
                 group=None, name="", summary=None):
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

        # How many packets to send
        self.num_pkts = 10

        # The packets to send
        self.pkts = None

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

        self.iperf_s_pid = None
        self.iperf_c_pid = None
        self.tcpdump_dst_pid = None
        self.tcpdump_src_pid = None
        self.nc_pid = None

        self.num_queue = None

        # Dictionary of ethtool Counters we expect to increment
        self.expect_et_cntr = {}

        # There are counters that we don't care about their increment after
        # the test. So we add them here so that they don't cause errors.
        for dont_care_cntr in UnitIP_dont_care_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0

        # There are counters that we expect to have an exact increment after
        # the test.
        if self.promisc:
            # checksum related counters
            if self.iperr or self.l4err:
                # any checksum error in promisc/non-promisc mode
                self.expect_et_cntr["hw_rx_csum_err"] = self.num_pkts
                self.expect_et_cntr["dev_rx_errors"] = self.num_pkts
                self.expect_et_cntr["mac.rx_pkts"] = self.num_pkts
            else:
                if self.l4_type == 'udp' or self.l4_type == 'tcp':
                    # hw_rx_csum_complete only increases when receiving IP error, not affected by UDP/TCP errors
                    self.expect_et_cntr["hw_rx_csum_complete"] = self.num_pkts
                    self.expect_et_cntr["mac.rx_pkts"] = self.num_pkts
                    self.expect_et_cntr["dev_rx_errors"] = self.num_pkts
                    self.expect_et_cntr["mac.rx_pkts"] = self.num_pkts
                    #self.expect_et_cntr["rx_pkts"] = self.num_pkts

                if self.dst_mac_type == 'mc' and self.src_mac_type == 'src':
                    self.expect_et_cntr["dev_rx_mc_pkts"] = self.num_pkts
                if self.dst_mac_type == 'bc' and self.src_mac_type == 'src':
                    self.expect_et_cntr["dev_rx_bc_pkts"] = self.num_pkts
        else:
            if self.dst_mac_type == 'tgt' and self.src_mac_type == 'src':
                if self.iperr or self.l4err:
                    # any checksum error in promisc/non-promisc mode
                    self.expect_et_cntr["hw_rx_csum_err"] = 0
                    self.expect_et_cntr["mac.rx_pkts"] = self.num_pkts
                    self.expect_et_cntr["mac.rx_unicast_pkts"] = self.num_pkts
                    self.expect_et_cntr["mac.rx_frames_received_ok"] = self.num_pkts
                    self.expect_et_cntr["mac.rx_octets"] = 0
                    self.expect_et_cntr["mac.rx_pkts_65_to_127_octets"] = self.num_pkts
                    self.expect_et_cntr["hw_rx_csum_complete"] = 0 #self.num_pkts
                    if self.iperr:
                        # NIC-397, only increment on IP header error
                        self.expect_et_cntr["dev_rx_errors"] = self.num_pkts
                    else:
                        self.expect_et_cntr["dev_rx_errors"] = 0 # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp_udperr

                elif self.l4_type == 'udp' or self.l4_type == 'tcp':
                    # w/o any error, csum_ok only increases when receiving
                    # TCP/UDP
                    self.expect_et_cntr["dev_rx_errors"] = 0 #self.num_pkts
                    self.expect_et_cntr["hw_rx_csum_complete"] = 0 #self.num_pkts
                    self.expect_et_cntr["mac.rx_unicast_pkts"] = self.num_pkts
                    self.expect_et_cntr["mac.rx_octets"] = 0
                    if self.l4_type == 'tcp':
                        self.expect_et_cntr["mac.tx_pkts_64_octets"] = self.num_pkts # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_tcp
                        self.expect_et_cntr["mac.rx_pkts"] = self.num_pkts
                        self.expect_et_cntr["mac.rx_pkts_65_to_127_octets"] = self.num_pkts # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_tcp, incremented un-unexpectedly (val=10)
                    else:
                        self.expect_et_cntr["mac.tx_pkts_64_octets"] = 0
                        UnitIP_dont_care_cntrs.append("mac.tx_octets") # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp, incremented un-unexpectedly (val=690)
                        UnitIP_dont_care_cntrs.append("mac.rx_frames_received_ok") # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp
                        UnitIP_dont_care_cntrs.append("mac.tx_unicast_pkts") # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp, incremented un-unexpectedly (val=6)
                        UnitIP_dont_care_cntrs.append("mac.rx_pkts") # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp, has un-expected value (val=11 exp=10)
                        #UnitIP_dont_care_cntrs.append("mac.tx_pkts_65_to_127_octets") # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp, incremented un-unexpectedly (val=6)
                        self.expect_et_cntr["mac.rx_pkts_65_to_127_octets"] = self.num_pkts # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp, incremented un-unexpectedly (val=10)
                        UnitIP_dont_care_cntrs.append("mac.tx_frames_transmitted_ok") # nfpflownic.unit_no_fw_ld.csum_rx_ipv4_udp, incremented un-unexpectedly (val=6)

            if self.dst_mac_type == 'diff' or self.src_mac_type != 'src':
                self.expect_et_cntr["dev_rx_discards"] = self.num_pkts
            if self.dst_mac_type == 'mc' and self.src_mac_type == 'src':
                self.expect_et_cntr["dev_rx_mc_pkts"] = self.num_pkts
                self.expect_et_cntr["hw_rx_csum_complete"] = self.num_pkts
            if self.dst_mac_type == 'bc' and self.src_mac_type == 'src':
                self.expect_et_cntr["dev_rx_bc_pkts"] = self.num_pkts
                self.expect_et_cntr["hw_rx_csum_complete"] = self.num_pkts

        return

    def gen_pkts(self):
        """
        Generate packets in scapy format for replay
        """
        if self.l4_type == 'udp':
            pkt = UDP(sport=3000, dport=4000)/self.name
        elif self.l4_type == 'tcp':
            pkt = TCP(sport=3000, dport=4000)/self.name
        else:
            pkt = ICMP(type="echo-reply")/self.name
        if self.ipv4:
            if self.ipv4_opt:
                pkt = IP(src=self.src_ip, dst=self.dst_ip,
                         options=[IPOption_NOP()])/pkt
            else:
                pkt = IP(src=self.src_ip, dst=self.dst_ip)/pkt
        else:
            ipv6_base = IPv6(src=self.src_ip, dst=self.dst_ip)
            if self.ipv6_hbh:
                ipv6_base = ipv6_base/IPv6ExtHdrHopByHop()
            if self.ipv6_rt:
                ipv6_base = ipv6_base/IPv6ExtHdrRouting()
            pkt = ipv6_base/pkt

        if self.vlan:
            pkt = Dot1Q(vlan=self.vlan_id)/pkt

        if self.dst_mac_type == 'diff':
            dst_mac = "00:aa:bb:cc:12:23"
        elif self.dst_mac_type == 'mc':
            dst_mac = "01:ab:78:56:34:12"
        elif self.dst_mac_type == 'bc':
            dst_mac = "ff:ff:ff:ff:ff:ff"
        elif self.dst_mac_type == 'tgt':
            dst_mac = self.dst_mac
        else:
            dst_mac = self.dst_mac

        if self.src_mac_type == 'diff':
            src_mac = "00:aa:bb:cc:12:23"
        elif self.src_mac_type == 'mc':
            src_mac = "01:ab:78:56:34:12"
        elif self.src_mac_type == 'bc':
            src_mac = "ff:ff:ff:ff:ff:ff"
        elif self.src_mac_type == 'src':
            src_mac = self.src_mac
        else:
            src_mac = self.src_mac

        pkt = Ether(src=src_mac, dst=dst_mac)/pkt

        if self.iperr and self.ipv4:
            # no checksum in IPv6
            pkt[IP].chksum = 1234

        if self.l4err:
            if self.l4_type == 'udp':
                pkt[UDP].chksum = 4321
            elif self.l4_type == 'tcp':
                pkt[TCP].chksum = 4321
        return pkt

    def gen_pcap(self):
        """
        Create and copy PCAP file to src
        """
        _, local_pcap = mkstemp()
        src_tmpdir = self.src.make_temp_dir()
        fname = self.src.host + '_' + self.name + ".pcap"
        send_pcap = os.path.join(src_tmpdir, fname)

        self.pkts = self.gen_pkts()
        wrpcap(local_pcap, self.pkts)
        self.src.cp_to(local_pcap, send_pcap)
        os.remove(local_pcap)

        return src_tmpdir, send_pcap

    def check_result(self, if_stat_diff):
        """
        Check the result
        """
        # dump the stats to the log
        LOG_sec("Interface stats difference")
        LOG(if_stat_diff.pp())
        LOG_endsec()

        # Subclasses need to tell us which counters to check
        if len(self.expect_et_cntr) == 0:
            raise Exception("No counters specified")

        if self.dst_mac_type == 'mc' or self.dst_mac_type == 'bc':
            res, comment = if_stat_diff.ethtool.check(self.expect_et_cntr,
                                                      strict=False, all=True)
        else:
            res, comment = if_stat_diff.ethtool.check(self.expect_et_cntr,
                                                      strict=True, all=True)
        if not res:
            return NrtResult(name=self.name, testtype=self.__class__.__name__,
                             passed=False, comment=comment)

        # all checked out.
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=True)

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

    def send_packets(self, send_pcap):
        """
        Send packets by using TCPReplay

        """
        pcapre = TCPReplay(self.src, self.src_ifn, send_pcap,
                           loop=self.num_pkts, pps=10)
        attempt, sent = pcapre.run()
        if attempt == -1 or sent == -1:
            return False
        else:
            return True

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets and check the result

        """
        # get stats of dst interface
        dst_netifs = self.dst.netifs[dst_if]
        before_cntrs = dst_netifs.stats()
        # Create and run a test. Send 10 packets at 10pps
        tcpreplay_passed = self.send_packets(send_pcap)
        if not tcpreplay_passed:
            self.dst.cmd("ifconfig %s -allmulti" % self.dst_ifn)
            return NrtResult(name=self.name, testtype=self.__class__.__name__,
                             passed=False, comment="tcpreplay failed")

        if tmpdir:
            self.src.rm_dir(tmpdir)

        after_cntrs = dst_netifs.stats()
        diff_cntrs = after_cntrs - before_cntrs

        self.dst.cmd("ifconfig %s -allmulti" % self.dst_ifn)
        # clean the block:
        if self.ipv4==True:
            self.src.cmd('iptables -F')
        else:
            self.src.cmd('ip6tables -F')
        return self.check_result(diff_cntrs)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        # enable checksum offload options
        self.dst.cmd("ethtool -K %s rx on" % self.dst_ifn)

        # enable promiscuous mode
        if self.promisc:
            self.dst.cmd("ip link set dev %s promisc on" % self.dst_ifn)
        else:
            self.dst.cmd("ip link set dev %s promisc off" % self.dst_ifn)

        # check promisc mode
        self.dst.cmd("ip link show %s" % self.dst_ifn)
        self.dst.cmd("ifconfig %s" % self.dst_ifn)
        self.dst.cmd("ifconfig %s allmulti" % self.dst_ifn)

        if self.ipv4==True:
            self.src.cmd('iptables -F')
            self.src.cmd('iptables -A INPUT -s %s -j DROP' % (self.dst_ip))
            self.dst.cmd('arp -s %s %s' % (self.src_ip, self.src_mac))
        else:
            self.src.cmd('ip6tables -F')
            self.src.cmd('ip6tables -A INPUT -s %s -j DROP' % (self.dst_ip))

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

        cmd = 'ethtool -S %s' % self.dst_ifn
        _, out = self.dst.cmd(cmd)
        re_num_queue = '\s*rxq_(\d+)_pkts:\s'
        queue_index = re.findall(re_num_queue, out)
        temp_MQ = NFPFlowMultiQueue(queue_index)
        for dont_care_cntr in temp_MQ.recv_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0
        for dont_care_cntr in temp_MQ.rxq_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0
        for dont_care_cntr in temp_MQ.txq_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0

    def run(self):

        """Run the test
        @return:  A result object"""

        self.get_intf_info()

        tmpdir, r_in = self.gen_pcap()

        self.interface_cfg()

        return self.send_pckts_and_check_result(self.src_ifn, self.dst_ifn,
                                                r_in, tmpdir)


##############################################################################
# IPv4 test
##############################################################################
class UnitIPv4(UnitIP):
    """Wrapper class for sending IPv4 packets"""

    summary = "IPv4 pkts"

    info = UnitIP._gen_info

    def __init__(self, src, dst, ipv4_opt=False, l4_type='udp',
                 iperr=False, l4err=False, promisc=False, group=None,
                 dst_mac_type="tgt", src_mac_type="src",
                 name="ipv4", summary=None):
        UnitIP.__init__(self, src, dst, ipv4=True, ipv4_opt=ipv4_opt,
                        l4_type=l4_type, iperr=iperr,
                        l4err=l4err, group=group,
                        dst_mac_type=dst_mac_type, src_mac_type=src_mac_type,
                        name=name, summary=summary)

        return


##############################################################################
# IPv6 test
##############################################################################
class UnitIPv6(UnitIP):
    """Wrapper class for sending IPv6 packets"""

    summary = "IPv6 pkts"

    info = UnitIP._gen_info

    def __init__(self, src, dst, ipv6_rt=False, ipv6_hbh=False, l4_type='udp',
                 l4err=False, promisc=False, group=None,
                 dst_mac_type="tgt", src_mac_type="src",
                 name="ipv6", summary=None):
        UnitIP.__init__(self, src, dst, ipv4=False, ipv6_rt=ipv6_rt,
                        ipv6_hbh=ipv6_hbh, l4_type=l4_type,
                        l4err=l4err, group=group,
                        dst_mac_type=dst_mac_type, src_mac_type=src_mac_type,
                        name=name, summary=summary)

        return


##############################################################################
# Send and compare IP packets test
##############################################################################
class UnitComparePacket(UnitIP, Pcap_Cmp_BaseTest):
    """Send and compare IP packets test"""

    summary = "Send and compare IP packets"

    info = """
    This test send a number of Ethernet frames from Vnic to host.
    Host compare the received frame and the expected frame.
    """ + UnitIP._gen_info

    def __init__(self, src, dst, ipv4=True, ipv4_opt=False, ipv6_rt=False,
                 ipv6_hbh=False, l4_type='tcp', iperr=False,
                 l4err=False, promisc=False, group=None,
                 dst_mac_type="tgt", src_mac_type="src", num_pkts=1,
                 src_mtu=1500, dst_mtu=1500, vlan_offload=False, vlan=False,
                 force_rss=False, jumbo_frame=False, name="ip", summary=None):
        UnitIP.__init__(self, src, dst, ipv4=ipv4, ipv4_opt=ipv4_opt,
                        ipv6_rt=ipv6_rt, ipv6_hbh=ipv6_hbh, l4_type=l4_type,
                        iperr=iperr, l4err=l4err, promisc=promisc,
                        group=group, dst_mac_type=dst_mac_type,
                        src_mac_type=src_mac_type, vlan=vlan,
                        name=name, summary=summary)

        # redefine the number of packets to send
        self.num_pkts = num_pkts

        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu
        self.vlan_offload = vlan_offload
        self.force_rss = force_rss
        self.jumbo_frame = jumbo_frame

        self.expt_pkts = None
        self.src_pcmp = None
        self.dst_pcmp = None
        self.dst_tmpdir = None
        self.dst_recv_pcap = None
        self.dst_expt_pcap = None
        return

    def gen_pkts(self):
        """Generate packets in scapy format for replay

        @return Packets
        """
        pkt = UnitIP.gen_pkts(self)

        if self.vlan_offload and self.vlan:
            if self.ipv4:
                expt_pkt = Ether(src=pkt[Ether].src,
                                 dst=pkt[Ether].dst)/pkt[IP]
            else:
                expt_pkt = Ether(src=pkt[Ether].src,
                                 dst=pkt[Ether].dst)/pkt[IPv6]
        else:
            expt_pkt = pkt

        if self.jumbo_frame:
            # Ethernet frame with large pay-load is needed.
            # To compose a Ethernet frame given the length of payload, we
            # repeat string 'netronome_nfpflownic' (length is 20B) in
            # the payload and stuff 'A' at the end.

            min_mtu = (self.src_mtu if self.src_mtu < self.dst_mtu else
                       self.dst_mtu)
            ip_len = len(pkt[IP]) if self.ipv4 else len(pkt[IPv6])
            header_size = ip_len - len(pkt[Raw])
            if min_mtu > ip_len:
                pay_load_size = min_mtu - header_size
                base_str = 'netronome_nfpflownic'
                stuff_str = 'A'
                repeating = pay_load_size / len(base_str)
                stuffing = pay_load_size % len(base_str)
                payload_str = base_str * repeating + stuff_str*stuffing
                pkt[Raw].load = payload_str
                expt_pkt[Raw].load = payload_str

        self.expt_pkts = expt_pkt

        return pkt

    def gen_pcap(self):
        """
        Create and copy PCAP files to src
        """
        _, local_pcap = mkstemp()
        src_tmpdir = self.src.make_temp_dir()
        fname = self.src.host + '_' + self.name + ".pcap"
        send_pcap = os.path.join(src_tmpdir, fname)

        self.pkts = self.gen_pkts()
        wrpcap(local_pcap, self.pkts)
        self.src.cp_to(local_pcap, send_pcap)

        _, local_pcap_expt = mkstemp()
        wrpcap(local_pcap_expt, self.expt_pkts)

        # define received pcap file and expected pckt file in dst
        self.dst_tmpdir = self.dst.make_temp_dir()
        dst_rcv_p_name = "recv_"+self.src.host + '_' + self.name + ".pcap"
        dst_exp_p_name = "expt_"+self.src.host + '_' + self.name + ".pcap"
        self.dst_recv_pcap = os.path.join(self.dst_tmpdir, dst_rcv_p_name)
        self.dst_expt_pcap = os.path.join(self.dst_tmpdir, dst_exp_p_name)
        self.dst.cp_to(local_pcap_expt, self.dst_expt_pcap)

        os.remove(local_pcap)
        os.remove(local_pcap_expt)

        # copy pcmp.py to dst and src
        local_pcmp = 'lib/pcmp.py'
        self.src_pcmp = os.path.join(src_tmpdir, 'pcmp.py')
        self.dst_pcmp = os.path.join(self.dst_tmpdir, 'pcmp.py')
        self.src.cp_to(local_pcmp, self.src_pcmp)
        self.dst.cp_to(local_pcmp, self.dst_pcmp)
        self.src.cmd('chmod +x %s' % self.src_pcmp)
        self.dst.cmd('chmod +x %s' % self.dst_pcmp)

        return src_tmpdir, send_pcap

    def clean_up(self, tmpdir):
        """
        Remove temporary directory and files
        """
        if tmpdir:
            self.src.rm_dir(tmpdir)
        if self.dst_tmpdir:
            self.dst.rm_dir(self.dst_tmpdir)

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets (using tshark) and check the result (compare the received
        packets with the ecpeted packets).
        """
        try:
            passed, msg = self.send_and_recv_pkts(self.src,
                                                  self.dst,
                                                  send_pcap,
                                                  self.dst_recv_pcap,
                                                  self.dst_expt_pcap,
                                                  src_if, dst_if,
                                                  self.src_mac,
                                                  self.dst_mac,
                                                  1,
                                                  src_port=3000,
                                                  dst_port=4000)
        except:
            passed = False
            msg = 'Exception caught in send_pckts_and_check_result'
        finally:
            self.clean_up(tmpdir)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=passed, comment=msg)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        # enable promiscuous mode
        if self.promisc:
            self.dst.cmd("ip link set dev %s promisc on" % self.dst_ifn)
        else:
            self.dst.cmd("ip link set dev %s promisc off" % self.dst_ifn)

        # check promisc mode
        self.dst.cmd("ip link show %s" % self.dst_ifn)
        self.dst.cmd("ifconfig %s" % self.dst_ifn)
        # enable/disable rx VLAN offload options
        if self.vlan_offload:
            vlan_offload_status = 'on'
        else:
            vlan_offload_status = 'off'
        self.dst.cmd("ethtool -K %s rxvlan %s" % (self.dst_ifn,
                                                  vlan_offload_status))

        # configure RSS
        protocol = "%s%s" % (self.l4_type, "4" if self.ipv4 else "6")
        if self.force_rss:
            self.dst.cmd("ethtool -N %s rx-flow-hash %s sdfn"
                         % (self.dst_ifn, protocol))



##############################################################################
# Jumbo frame packet comparison test
##############################################################################
class JumboPacket(UnitComparePacket):
    """Test class for Jumbo frame packet comparison test"""

    summary = "Send and compare jumbo frame packets"

    info = """
    This test send a number of Ethernet frames with large payload size
    from dst to src.
    src compare the received frame and the expected frame.
    """ + UnitIP._gen_info

    def __init__(self, src, dst, group=None, src_mtu=9000, dst_mtu=9000,
                 force_rss=False, jumbo_frame=True, name="JumboPacket",
                 summary=None):
        UnitComparePacket.__init__(self, src, dst, ipv4=True, ipv4_opt=False,
                                   ipv6_rt=False, ipv6_hbh=False,
                                   l4_type='udp', iperr=False, l4err=False,
                                   promisc=False, group=group,
                                   dst_mac_type="tgt", src_mac_type="src",
                                   num_pkts=1, src_mtu=src_mtu,
                                   dst_mtu=dst_mtu, force_rss=force_rss,
                                   jumbo_frame=jumbo_frame, name=name,
                                   summary=summary)
        self.mtu_cfg_obj = NFPFlowNICMTU()

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

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters and MTU values
        """
        UnitComparePacket.interface_cfg(self)
        self.cfg_mtu()

    def cfg_mtu(self):
        """
        Get the current MTU settings, and change them to the given values.

        """
        src_cur_mtu = self.mtu_cfg_obj.get_mtu(self.src, self.src_ifn)
        dst_cur_mtu = self.mtu_cfg_obj.get_mtu(self.dst, self.dst_ifn)

        if dst_cur_mtu != self.dst_mtu:
            self.mtu_cfg_obj.set_mtu(self.dst, self.dst_ifn, self.dst_mtu)

        if src_cur_mtu != self.src_mtu:
            self.mtu_cfg_obj.set_mtu(self.src, self.src_ifn, self.src_mtu)

    def clean_up(self, tmpdir):
        """
        Remove temporary directory and files, and reset mtu on interfaces
        """
        UnitComparePacket.clean_up(self, tmpdir)
        default_reset_mtu = 1500
        self.mtu_cfg_obj.set_mtu(self.dst, self.dst_ifn, default_reset_mtu)
        self.mtu_cfg_obj.set_mtu(self.src, self.src_ifn, default_reset_mtu)

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets, check the result, and reset MTU to default value

        """
        res = UnitComparePacket.send_pckts_and_check_result(self, src_if,
                                                            dst_if, send_pcap,
                                                            tmpdir)

        return res


##############################################################################
# RXVLAN stripping test
##############################################################################
class RxVlan(UnitComparePacket):
    """wrapper class for RXVLAN stripping test"""

    summary = "Send and compare IP packets "

    info = """
    This test send a number of Ethernet frames with VALN tag from Vnic to host.
    Host compare the received frame and the expected frame.
    """ + UnitIP._gen_info

    def __init__(self, src, dst, group=None, vlan_offload=False, vlan=False,
                 name="ip", summary=None):
        UnitComparePacket.__init__(self, src, dst, ipv4=True, ipv4_opt=False,
                                   ipv6_rt=False, ipv6_hbh=False,
                                   l4_type='udp', iperr=False, l4err=False,
                                   promisc=False, group=group,
                                   dst_mac_type="tgt", src_mac_type="src",
                                   num_pkts=1, src_mtu=1500, dst_mtu=1500,
                                   vlan_offload=vlan_offload, vlan=vlan,
                                   jumbo_frame=False,
                                   name=name, summary=summary)

        self.dst_vlan_ifn = '%s.%s' % (self.dst_ifn, self.vlan_id)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        try:
            UnitComparePacket.interface_cfg(self)
            self.dst.vconfig_add(self.dst_ifn, self.vlan_id)
            self.dst.cmd('ifconfig %s up' % self.dst_vlan_ifn)
        except:
            self.clean_up(None)
            msg = 'Exception caught in interface_cfg'
            raise NtiGeneralError(msg)


    def gen_pkts(self):
        """Generate packets in scapy format for replay

        @return Packets
        """
        pkt = UnitIP.gen_pkts(self)

        if self.vlan:
            # remove vlan tag in pkt
            if self.ipv4:
                expt_pkt = Ether(src=pkt[Ether].src,
                                 dst=pkt[Ether].dst)/pkt[IP]
            else:
                expt_pkt = Ether(src=pkt[Ether].src,
                                 dst=pkt[Ether].dst)/pkt[IPv6]
        else:
            expt_pkt = pkt

        self.expt_pkts = expt_pkt

        return pkt

    def clean_up(self, tmpdir):
        """
        Remove temporary directory and files, and remove vlan interface
        """
        UnitComparePacket.clean_up(self, tmpdir)
        self.dst.vconfig_rem(self.dst_ifn, self.vlan_id, fail=False)

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets and check the result

        """
        if self.vlan:
            dst_interface = self.dst_vlan_ifn
        else:
            dst_interface = dst_if
        self.dst.cmd('ifconfig %s' % dst_interface)
        res = UnitComparePacket.send_pckts_and_check_result(self, src_if,
                                                            dst_interface,
                                                            send_pcap, tmpdir)
        return res

##############################################################################
# RXVLAN rx_pkts test
##############################################################################
class RxVlan_rx_byte(RxVlan):
    """wrapper class for RXVLAN stripping test"""

    summary = "Send IP packets and check rx_byte counters"

    info = """
    This test send a number of Ethernet frames with VALN tag from host to vNIC
    with and without RXVLAN offload. Test passes if rx_byte with RXVLAN
    offload off is 4B larger than rx_byte with RXVALN offload on.
    .
    """ + UnitIP._gen_info

    def __init__(self, src, dst, group=None, name="RxVlan_rx_pkts",
                 summary=None):
        RxVlan.__init__(self, src, dst, group=group, vlan_offload=True,
                        vlan=True, name=name, summary=summary)

        self.dst_vlan_ifn = '%s.%s' % (self.dst_ifn, self.vlan_id)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        try:
            UnitComparePacket.interface_cfg(self)
            self.dst.vconfig_add(self.dst_ifn, self.vlan_id)
            self.dst.cmd('ifconfig %s up' % self.dst_vlan_ifn)
        except:
            self.clean_up(None)
            msg = 'Exception caught in interface_cfg'
            raise NtiGeneralError(msg)


    def gen_pkts(self):
        """Generate packets in scapy format for replay

        @return Packets
        """
        pkt = UnitIP.gen_pkts(self)

        if self.vlan:
            # remove vlan tag in pkt
            if self.ipv4:
                expt_pkt = Ether(src=pkt[Ether].src,
                                 dst=pkt[Ether].dst)/pkt[IP]
            else:
                expt_pkt = Ether(src=pkt[Ether].src,
                                 dst=pkt[Ether].dst)/pkt[IPv6]
        else:
            expt_pkt = pkt

        self.expt_pkts = expt_pkt

        return pkt

    def clean_up(self, tmpdir):
        """
        Remove temporary directory and files, and remove vlan interface
        """
        UnitComparePacket.clean_up(self, tmpdir)
        self.dst.vconfig_rem(self.dst_ifn, self.vlan_id, fail=False)

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets and check the result

        """
        passed = True
        comment = ''
        if self.vlan:
            dst_interface = self.dst_vlan_ifn
        else:
            dst_interface = dst_if
        try:
            self.dst.cmd('ifconfig %s' % dst_interface)
            self.dst.cmd('ethtool -K %s rxvlan off' % dst_if)
            pcapre = TCPReplay(self.src, src_if, send_pcap,
                               loop=1, pps=10)
            cmd = 'cat /sys/class/net/%s/statistics/rx_bytes' % dst_if
            _, rx_byte_before = self.dst.cmd(cmd)
            attempt, sent = pcapre.run()
            _, rx_byte_after = self.dst.cmd(cmd)
            rx_byte_rxvlan_off = int(rx_byte_after) - int(rx_byte_before)
            if attempt == -1 or sent == -1:
                passed = False
                comment += 'Failed to tcpreplay pckts with rxvlan off'
            self.dst.cmd('ethtool -K %s rxvlan on' % dst_if)
            _, rx_byte_before = self.dst.cmd(cmd)
            attempt, sent = pcapre.run()
            _, rx_byte_after = self.dst.cmd(cmd)
            rx_byte_rxvlan_on = int(rx_byte_after) - int(rx_byte_before)
            if attempt == -1 or sent == -1:
                passed = False
                comment += 'Failed to tcpreplay pckts with rxvlan on'
            rx_byte_difference = rx_byte_rxvlan_off - rx_byte_rxvlan_on
            if rx_byte_difference != 4:
                passed = False
                comment += 'rx_bytes with rxvlan off is %d, rx_bytes with ' \
                           'rxvlan on is %d, the difference is not 4B' % (rx_byte_rxvlan_off, rx_byte_rxvlan_on)
            res = NrtResult(name=self.name, testtype=self.__class__.__name__,
                            passed=passed, comment=comment)
        except:
            res = NrtResult(name=self.name, testtype=self.__class__.__name__,
                            passed=False, comment='Exception caught in send_'
                                                  'pckts_and_check_result')
        finally:
            self.clean_up(tmpdir)
            return res

##############################################################################
# UnitPing test
##############################################################################
class UnitPing(Ping):
    """sub-class for ping tests for Jumbo frames and MTU changes"""

    summary = "MTU ping test"

    info = """
    This test sets the MTU on DUT and host (endpoint). And the host (endpoint)
    pings DUT with the given size.
    """

    def __init__(self, src, dst,
                 src_mtu=1500, dst_mtu=1500, ping_drop=False,
                 clean=False, count=1, ping_size=None, interval=1, noloss=False,
                 group=None, name="unitping", summary=None):

        Ping.__init__(self, src, dst, clean=clean, count=count, size=ping_size,
                      interval=interval, noloss=noloss, wait=2, group=group,
                      name=name, summary=summary)

        self.src = None
        self.src_ifn = None
        self.dst = None
        self.dst_ifn = None
        if src[0]:
            # src and dst maybe None if called without config file for list
            self.src = src[0]
            self.src_addr = src[1]
            self.src_ifn = src[2]
            self.src_addr_v6 = src[3]
            self.dst = dst[0]
            self.dst_addr = dst[1]
            self.dst_ifn = dst[2]
            self.dst_addr_v6 = dst[3]

        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu

        self.ping_drop = ping_drop

        self.mtu_cfg_obj = NFPFlowNICMTU()

        return

    def run(self):
        """
        First set MTU on DUT and host (endpoint), then run the 'run' method of
        the testinfra.ping class to do the pinging
        """

        self.dst.cmd("ip link set dev %s promisc off" % self.dst_ifn)
        self.src.cmd("ip link set dev %s promisc off" % self.src_ifn)
        src_cur_mtu = self.mtu_cfg_obj.get_mtu(self.src, self.src_ifn)
        dst_cur_mtu = self.mtu_cfg_obj.get_mtu(self.dst, self.dst_ifn)

        if src_cur_mtu == None or dst_cur_mtu == None:
            return NrtResult(name=self.name, testtype=self.__class__.__name__,
                             passed=False, comment="Fail to get MTU value")

        mtu_changed = False
        if dst_cur_mtu != self.dst_mtu:
            try:
                self.mtu_cfg_obj.set_mtu(self.dst, self.dst_ifn, self.dst_mtu)
                mtu_changed = True
            except:
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=False,
                                 comment="Fail to set dst MTU value")
        if src_cur_mtu != self.src_mtu:
            try:
                self.mtu_cfg_obj.set_mtu(self.src, self.src_ifn, self.src_mtu)
                mtu_changed = True
            except:
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=False,
                                 comment="Fail to set src MTU value")

        if mtu_changed:
            # After the MTU of an interface is changed, this interface
            # (espcially VNIC) may be unpingable for a short period of time,
            # even if ifconfig shows it is UP. Thus, we try to ping it
            # repeatedly using the default ping size (56 byte) until it
            # becomes pingable.
            try:
                src_if = self.src.netifs[self.src_ifn]
                dst_if = self.dst.netifs[self.dst_ifn]

                src_mac = src_if.mac
                dst_mac = dst_if.mac
                src_ip = src_if.ip
                dst_ip = dst_if.ip
                #self.src.cmd('arp -s %s %s' % (dst_ip, dst_mac))
                #self.dst.cmd('arp -s %s %s' % (src_ip, src_mac))
                temp_ping_size = self.size
                self.size = 40
                timed_poll(30, self.is_intf_pingable, delay=1)
            except NtiTimeoutError:
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=False,
                                 comment="Fail to ping (timed_poll with "
                                         "default ping size) dst")

            # Interface with changed MTU is now pingable, reassign ping_size
            self.size = temp_ping_size

        # disable fragmented packets
        self.interval = str(self.interval) + ' -M do'
        res = Ping.run(self)

        if self.ping_drop:
            # We expect that ping packets should be dropped, and the
            # returned result of the ping test should be failed
            if res.passed:
                # Ping test passes. Thus return the actual result as failed
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__, passed=False,
                                 comment="Ping packets are not dropped when "
                                         "ping packet size is larger than "
                                         "DUT's MTU")
            else:
                # Ping test fails as expected.
                # When the number of packets received is zero, and all ping
                # packets are all dropped, the ping-drop test passes.
                pckt_loss_str = '\d+ packets transmitted, 0 received,' \
                                '\s*(?:[\+\d]+ errors,\s*)*100% packet ' \
                                'loss, time \d+ms'
                pckt_no_trans_str = '0 packets transmitted, 0 received,' \
                                    '\s*\+\d+ errors'
                if re.findall(pckt_loss_str, res.details) or \
                        re.findall(pckt_no_trans_str, res.details):
                    return NrtResult(name=self.name,
                                     testtype=self.__class__.__name__,
                                     passed=True)
                else:
                    return NrtResult(name=self.name,
                                     testtype=self.__class__.__name__,
                                     passed=False,
                                     comment="Output of ping does not match "
                                             "the expected packet-drop output "
                                             "string")
        else:
            # We expect that ping packets should be received
            if res.passed:
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__, passed=True)
            else:
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=res.passed,
                                 comment="" if res.passed else res.comment)

    def is_intf_pingable(self):
        """
        The ping method used in timed_poll. Return True when the interface is
        pingable.
        """
        res = Ping.run(self)
        if res.passed:
            return True
        else:
            return False


##############################################################################
# statistic rx_error test
##############################################################################
class Stats_rx_err_cnt(UnitIP):
    """
    Test class for sending IPv4 packets with payload larger than MTU size, so
    that counter dev_rx_errors increases.
    """

    summary = "Sending IPv4 packets and check dev_rx_errors counter"

    info = UnitIP._gen_info

    def __init__(self, src, dst, ipv4_opt=False, l4_type='udp',
                 iperr=False, l4err=False, promisc=False,
                 src_mtu=3000, dst_mtu=1500, payload_size=1501,
                 group=None, dst_mac_type="tgt", src_mac_type="src",
                 name="Stats_rx_err_cnt", summary=None):
        UnitIP.__init__(self, src, dst, ipv4=True, ipv4_opt=ipv4_opt,
                        l4_type=l4_type, iperr=iperr,
                        l4err=l4err, promisc=promisc, group=group,
                        dst_mac_type=dst_mac_type, src_mac_type=src_mac_type,
                        name=name, summary=summary)
        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu
        self.payload_size = payload_size
        self.mtu_cfg_obj = NFPFlowNICMTU()
        # We only check dev_rx_errors counter in this test
        UnitIP_dont_care_cntrs.append("hw_rx_csum_ok")
        UnitIP_dont_care_cntrs.append("hw_rx_csum_err")
        # Dictionary of ethtool Counters we expect to increment
        self.expect_et_cntr = {}
        for dont_care_cntr in UnitIP_dont_care_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0

        return

    def gen_pkts(self):
        """Generate packets in scapy format for replay

        @return Packets
        """
        pkt = UnitIP.gen_pkts(self)

        # Ethernet frame with specify pay-load size is needed.
        # To compose a Ethernet frame given the length of payload, we
        # repeat string 'netronome_nfpflownic' (length is 20B) in
        # the payload and stuff 'A' at the end.
        # len(pkt[IP]) is the l2 payload size, which should be no larger than
        # MTU size. 

        ip_len = len(pkt[IP]) if self.ipv4 else len(pkt[IPv6])
        header_size = ip_len - len(pkt[Raw])
        raw_size = self.payload_size - header_size
        base_str = 'netronome_nfpflownic'
        stuff_str = 'A'
        repeating = raw_size / len(base_str)
        stuffing = raw_size % len(base_str)
        payload_str = base_str * repeating + stuff_str*stuffing
        pkt[Raw].load = payload_str
        return pkt

    def cfg_mtu(self):
        """
        Get the current MTU settings, and change them to the given values.

        """
        src_cur_mtu = self.mtu_cfg_obj.get_mtu(self.src, self.src_ifn)
        dst_cur_mtu = self.mtu_cfg_obj.get_mtu(self.dst, self.dst_ifn)

        if dst_cur_mtu != self.dst_mtu:
            self.mtu_cfg_obj.set_mtu(self.dst, self.dst_ifn, self.dst_mtu)

        if src_cur_mtu != self.src_mtu:
            self.mtu_cfg_obj.set_mtu(self.src, self.src_ifn, self.src_mtu)

    def clean_up(self):
        """
        Remove temporary directory and files, and reset mtu on interfaces
        """
        default_reset_mtu = 1500
        self.mtu_cfg_obj.set_mtu(self.dst, self.dst_ifn, default_reset_mtu)
        self.mtu_cfg_obj.set_mtu(self.src, self.src_ifn, default_reset_mtu)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters and MTU values
        """
        self.cfg_mtu()
        UnitIP.interface_cfg(self)

    def check_result(self, if_stat_diff):
        """
        Check the result
        """
        res = UnitIP.check_result(self, if_stat_diff)
        self.clean_up()
        return res

class LinkState(Test):
    """Test class for link state monitoring"""
    # Information applicable to all subclasses
    _gen_info = """
    Link state monitoring.
    """

    def __init__(self, src, dst, group=None, name="", summary=None):
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
        return

    def run(self):
        """
        Modifying register and check if link state has been updated correctly.
        """

        passed = True
        comment = ''
        sd_family = None
        sd_family_lane = None
        port_id = 0
        #Get the port index (0~7) by looking up MAC in nfp-hwinfo
        src_if = self.src.netifs[self.src_ifn]
        src_mac = src_if.mac
        _, out = self.src.cmd('nfp-hwinfo | grep mac')
        re_str = 'eth(\d+).mac=%s' % src_mac
        port_id_list = re.findall(re_str, out)
        print "port_id_list:%s" % port_id_list
        if port_id_list:
            port_id = int(port_id_list[0])
        else:
            raise NtiError("Cannot find the port_id using MAC")
        _, out = self.src.cmd('nfp-media')
        #Assuming that when we use breakout cable, we use it in all ports
        re_no_boc_str = 'phy0=\d+G'
        re_boc_str = 'phy0=\d+x\d+G'
        with_boc = None
        if re.findall(re_no_boc_str, out):
            with_boc = False
        elif re.findall(re_boc_str, out):
            with_boc = True
        else:
            raise NtiError("Cannot find the breakout cable setup using nfp-media")
        # Look up chip model in nfp-hwinfo and determine "SerDes family,
        # SerDes family land" (NIC-52)
        hydrogen_str = 'AMDA0081'
        lithium_str = 'AMDA0096'
        beryllium_str = 'AMDA0097'
        carbon_str = 'AMDA0099'
        chip_cmd = 'nfp-hwinfo | grep -o "AMDA.*$"'
        _, chip_model = self.src.cmd(chip_cmd)
        if hydrogen_str in chip_model:
            sd_family = 0
            sd_family_lane = port_id
        elif lithium_str in chip_model:
            sd_family = port_id
            sd_family_lane = 0
        elif carbon_str in chip_model:
            sd_family = port_id
            sd_family_lane = 0
        elif beryllium_str in chip_model:
            if with_boc:
                sd_family = port_id / 4
                sd_family_lane = port_id % 4
            else:
                sd_family = port_id
                sd_family_lane = 0
        else:
            raise NtiError("Cannot find supported chip model in nfp-hwinfo")

        ip_cmd = 'ip addr show dev %s' % self.src_ifn
        self.src.cmd(ip_cmd)
        cmd = 'nfp-serdes -n 0 8 %d %d  LANEPCSPSTATE_RX 0x1' % (sd_family,
                                                                 sd_family_lane)
        self.src.cmd(cmd)
        try:
            timed_poll(30, self.is_link_state_correct, "down", delay=1)
        except NtiTimeoutError:
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=False,
                             comment="The expected NO-CARRIER string is not "
                                     "found in the output of ip addr show cmd "
                                     "after the PHY is powered down")
        cmd = 'nfp-serdes -n 0 8 %d %d  LANEPCSPSTATE_RX 0x10' % \
              (sd_family, sd_family_lane)
        self.src.cmd(cmd)
        try:
            timed_poll(30, self.is_link_state_correct, "up", delay=1)
        except NtiTimeoutError:
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=False,
                             comment="NO-CARRIER string is found in the "
                                     "output of ip addr show cmd after the "
                                     "PHY is powered up")
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=passed, comment=comment)

    def is_link_state_correct(self, action):
        """
        Return True if NO-CARRIER shows in action=="down", or no NO-CARRIER
        shows in action=="up"
        """
        ip_cmd = 'ip addr show dev %s' % self.src_ifn
        _, out = self.src.cmd(ip_cmd)
        if action == 'up':
            if not 'NO-CARRIER' in out:
                return True
        elif action == 'down':
            if 'NO-CARRIER' in out:
                return True
        return False


class DstMACFltr(CommonTest):
    """Test class for destination MAC address filtering"""
    _gen_info = """
    Destination MAC address filtering
    """

    def __init__(self, src, dst, group=None, name="", summary=None):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        CommonTest.__init__(self, src, dst, group, name, summary)

        if not src[0]:
            return

        self.uniqe_pkts = 100
        # Number of repetitions of every packet.  To avoid packet noise breaking
        # the test we repeat the pcap @rep_pkts times and complain only if we see
        # at lease @rep_pkts packets comming through.
        # @rep_pkts can't be lower than 2, shoudn't be lower than 4
        self.rep_pkts = 5
        self.tmp_mac = "60:11:22:33:44:55"

        # src and dst maybe None if called without config file for list
        _, self.tmp_pcap = mkstemp()
        return

    def send_packets(self):
        """
        Send packets by using TCPReplay
        """
        pcapre = TCPReplay(self.src, self.src_ifn, self.tmp_pcap,
                           loop=self.rep_pkts, pps=10000)
        attempt, sent = pcapre.run()
        if attempt == -1 or sent == -1:
            return False
        else:
            return True

    def prep_pcap(self, avoid, start):
        pkts = PacketList()

        dst_mac = ""
        new_mac = start

        for i in range(0, self.uniqe_pkts):
            while new_mac == dst_mac or new_mac == avoid:
                idx = random.randrange(0, 12)
                idx += idx / 2
                # Don't change the nibble with multicast bits
                if idx != 1:
                    str_list = list(new_mac)
                    str_list[idx] = hex(random.randrange(0, 15)).split('x')[1]
                    new_mac = "".join(str_list)

            dst_mac = new_mac
            pkt = Ether(src=self.src_if.mac, dst=dst_mac)/IP(src=self.src_if.ip,
                                                             dst=self.dst_if.ip)
            pkts.append(pkt)

        wrpcap(self.tmp_pcap, pkts)
        self.src.mv_to(self.tmp_pcap, self.tmp_pcap)


    def execute(self):
        """
        Send a few packets and see if they are filtered by the NFP based on
        destination MAC address.
        """

        # Simply check if there is connectivity
        self.src.cmd('ping -i0.2 -c 10 %s' % self.dst_if.ip)

        old_dst_stats = self.dst.netifs[self.dst_ifn].stats()

        # Generate traffic with random DST MAC addrs
        self.prep_pcap(avoid=self.dst_if.mac, start=self.tmp_mac)
        if not self.send_packets():
            raise NtiGeneralError("Couldn't send packets")

        new_dst_stats = self.dst.netifs[self.dst_ifn].stats()

        diff = new_dst_stats - old_dst_stats
        discards = diff.ethtool['dev_rx_discards']
        if diff.ifconfig['rx_pkts'] + diff.ifconfig['rx_err'] > self.rep_pkts - 1:
            raise NtiGeneralError("Filtering failed (pass 1) (got %d)" %
                               (diff.ifconfig['rx_pkts'] + diff.ifconfig['rx_err']))

        # Change the MAC address on DUT
        self.dst.cmd("ip link set dev %s down; " \
                     "ip link set dev %s addr %s; " \
                     "ip link set dev %s up" %
                     (self.dst_ifn, self.dst_ifn, self.tmp_mac, self.dst_ifn))
        self.src.cmd("ip ne fl dev %s" % self.src_ifn)

        # Simply check if there is connectivity
        self.src.cmd('ping -i0.2 -c 10 %s' % self.dst_if.ip)

        old_dst_stats = self.dst.netifs[self.dst_ifn].stats()

        # Generate traffic with random DST MAC addrs
        self.prep_pcap(avoid=self.tmp_mac, start=self.dst_if.mac)
        if not self.send_packets():
            raise NtiGeneralError("Couldn't send packets")

        new_dst_stats = self.dst.netifs[self.dst_ifn].stats()

        diff = new_dst_stats - old_dst_stats
        discards += diff.ethtool['dev_rx_discards']
        if diff.ifconfig['rx_pkts'] + diff.ifconfig['rx_err'] > self.rep_pkts - 1:
            raise NtiGeneralError("Filtering failed (pass 2) (got %d)" %
                                   (diff.ifconfig['rx_pkts'] + diff.ifconfig['rx_err']))

        if discards != self.uniqe_pkts * self.rep_pkts * 2:
            raise NtiGeneralError("Filtered packets not reported as discards (exp %d, got %d)" %
                               (self.uniqe_pkts * self.rep_pkts * 2,
                                new_dst_stats.ethtool['dev_rx_discards']))


    def cleanup(self):
        # Restore the MAC address on DUT
        self.dst.cmd("ip link set dev %s down; " \
                     "ip link set dev %s addr %s; " \
                     "ip link set dev %s up" %
                     (self.dst_ifn, self.dst_ifn, self.dst_if.mac, self.dst_ifn))
        self.src.cmd("ip ne fl dev %s" % self.src_ifn)

        cmd = "rm -rf " + self.tmp_pcap
        self.src.cmd(cmd, fail=False)


class RSStest_same_l4_tuple(Test):
    """Test class for RSS test"""
    # Information applicable to all subclasses
    _gen_info = """
    sending IP packets to test RSS functions.
    """
    def __init__(self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='tcp',
                 group=None, name="", summary=None):
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
        self.num_rx_queue = 1

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

        if dst[4]:
            self.rss_keys = dst[4]
        else:
            self.rss_keys = None
        self.port_id = None

        # These will be set in the run() method
        self.src_mac = None
        self.src_ip = None
        self.dst_mac = None
        self.dst_ip = None

        # How many times to send the pcap file repeatedly
        self.num_pkts = 1

        # The packets to send
        self.pkts = None

        # The expected received packets of each rx queue
        self.rx_q_exp = None

        # ipv4 indicates IPv4 or IPv6
        # True -> IPv4; False-> IPv6
        self.ipv4 = ipv4
        # l4_type indicates the type of payload
        # 'udp'-> UDP; 'tcp'-> TCP; other -> ICMP;
        self.l4_type = l4_type
        # promisc indicates whether VNIC is set in promiscuous mode
        self.promisc = promisc
        # ipv4_opt indicates whether IPv4 option (NOP) is enabled
        self.ipv4_opt = ipv4_opt
        # ipv6_rt: true if IPv6 extension (header routing) is enabled
        self.ipv6_rt = ipv6_rt
        # ipv6_hbh: true if IPv6 extension (HopByHop) is enabled
        self.ipv6_hbh = ipv6_hbh

        self.total_pckts = 5000

        # Dictionary of ethtool Counters we expect to increment
        self.expect_et_cntr = {}

        # There are counters that we don't care about their increment after
        # the test. So we add them here so that they don't cause errors.
        for dont_care_cntr in UnitIP_dont_care_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0
        self.rxq_list = None
        self.txq_list = None

    def run(self):

        """Run the test
        @return:  A result object"""

        self.get_intf_info()

        self.interface_cfg()

        tmpdir, r_in = self.gen_pcap()

        return self.send_pckts_and_check_result(self.src_ifn, self.dst_ifn,
                                                r_in, tmpdir)

    def get_intf_number(self):
        # using nfp-hwinfo to get the index of the interface

        #Get the port index (0~7) by looking up MAC in nfp-hwinfo
        dst_if = self.dst.netifs[self.dst_ifn]
        dst_mac = dst_if.mac
        _, out = self.dst.cmd('nfp-hwinfo | grep mac')
        re_str = 'eth(\d+).mac=%s' % dst_mac
        port_id_list = re.findall(re_str, out)
        if port_id_list:
            self.port_id = int(port_id_list[0])
            self.rss_key = self.rss_keys[self.port_id]
        else:
            raise NtiError("Cannot find the port_id using MAC" + dst_mac)

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
        self.get_intf_number()

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

        cmd = 'ethtool -S %s' % self.dst_ifn
        _, out = self.dst.cmd(cmd)
        re_num_queue = '\s*rxq_(\d+)_pkts:\s'
        queue_index = re.findall(re_num_queue, out)
        temp_MQ = NFPFlowMultiQueue(queue_index)

        self.num_rx_queue = temp_MQ.num_q
        # Future work: for now, we only check recv_#_rx_pkts, will also check
        # rxq_#_pkts counter when they are ready.
        self.rxq_list = temp_MQ.recv_rx_pkts_cntrs
        self.txq_list = temp_MQ.recv_tx_pkts_cntrs
        for dont_care_cntr in temp_MQ.recv_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0
        for dont_care_cntr in temp_MQ.txq_cntrs:
            self.expect_et_cntr[dont_care_cntr] = 0


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

    def gen_pkts(self):
        """
        Generate packets in scapy format for replay
        """
        pkts = PacketList()

        # all pckts have the same ip addr & port tuple, but different
        # payload string. Half of them have ip option headers.
        for i in range(0, self.total_pckts):
            payload_str = self.name + '_' + str(i)
            if self.l4_type == 'udp':
                pkt = UDP(sport=3000, dport=4000)/payload_str
            else:
                pkt = TCP(sport=3000, dport=4000)/payload_str
            if self.ipv4:
                # half of IPV4 packets have IP option header
                if i % 2:
                    pkt = IP(src=self.src_ip, dst=self.dst_ip,
                             options=[IPOption_NOP()])/pkt
                else:
                    pkt = IP(src=self.src_ip, dst=self.dst_ip)/pkt
            else:
                # half of IPV6 packets have IPv6 option header
                ipv6_base = IPv6(src=self.src_ip, dst=self.dst_ip)
                #if i % 2:
                #    ipv6_base = ipv6_base/IPv6ExtHdrHopByHop()
                #    ipv6_base = ipv6_base/IPv6ExtHdrHopByHop()
                pkt = ipv6_base/pkt

            pkt = Ether(src=self.src_mac, dst=self.dst_mac)/pkt
            pkts.append(pkt)
        return pkts

    def cal_rss_rxq(self, pkt, rss_table, ipv4, l4_type):
        """
        Re-calculate the rss value of each packets
        referecne:
        http://download.microsoft.com/download/5/D/6/5D6EAF2B-7DDF-476B-93DC-7CF0072878E6/NDIS_RSS.doc
        Verified by using data:
        https://msdn.microsoft.com/en-us/library/windows/hardware/ff571021(v=vs.85).aspx
        """
        sk = int(self.rss_key, 16)
        k_len = (len(self.rss_key) - 2) * 4
        if ipv4:
            ip_version = IP
            # number of left_shift for the source IP address
            # (ip_length + port_length * 2)
            s_shift = 64
            # hash input length (ip_length * 2 + port_length * 2)
            ip_input_len = 96
            socket_type = socket.AF_INET
        else:
            ip_version = IPv6
            # number of left_shift for the source IPv6 address
            # (ipv6_length + port_length * 2)
            s_shift = 160
            # hash input length (ipv6_length * 2 + port_length * 2)
            ip_input_len = 288
            socket_type = socket.AF_INET6

        if l4_type == 'tcp':
            l4_prot = TCP
        elif l4_type == 'udp':
            l4_prot = UDP
        else:
            raise NtiGeneralError('We only support tcp/udp in RSS tests')

        if ip_version in pkt and l4_prot in pkt:
            s_ip = pkt[ip_version].src
            d_ip = pkt[ip_version].dst
            s_port = pkt[l4_prot].sport
            d_port = pkt[l4_prot].dport
            s_ip_input = int(hexlify(socket.inet_pton(socket_type, s_ip)), 16)
            d_ip_input = int(hexlify(socket.inet_pton(socket_type, d_ip)), 16)

            ip_hash_input = (s_ip_input << s_shift) + (d_ip_input << 32) + \
                            (int(s_port) << 16) + int(d_port)
            result = 0
            for i in range (0, ip_input_len):
                right_shift = ip_input_len - i - 1
                left_shifted_key = sk << i
                l_most_32 = left_shifted_key >> (k_len - 32)
                if ((ip_hash_input >> right_shift) & 1):
                    result ^= l_most_32
            final_result = result & 0xFFFFFFFF
            rss_table_index = final_result % len(rss_table)
            rss_expt_q = rss_table[rss_table_index]
            return rss_expt_q

    def rss_q_expt(self, pkts):
        """
        calculate the expected rx packets in RSS rx queues
        """
        rss_table = []
        _, output = self.dst.cmd('ethtool -x %s' % self.dst_ifn)
        lines = output.splitlines()
        re_table_line = '(\d{1,3}):\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})' \
                        '\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})\s+(\d{1,2})' \
                        '\s+(\d{1,2})'
        for line in lines:
            table_line_values = re.findall(re_table_line, line)
            if table_line_values:
                for i in range(1, 9):
                    rss_table.append(int(table_line_values[0][i]))
        rss_expt_q_table = []
        for i in range(0, self.num_rx_queue):
            rss_expt_q_table.append(0)
        for pkt in pkts:
            rss_expt_q = self.cal_rss_rxq(pkt, rss_table, self.ipv4,
                                          self.l4_type)
            rss_expt_q_table[rss_expt_q] += 1
        return rss_expt_q_table

    def gen_pcap(self):
        """
        Create and copy PCAP file to src
        """
        _, local_pcap = mkstemp()
        src_tmpdir = self.src.make_temp_dir()
        fname = "send.pcap"
        send_pcap = os.path.join(src_tmpdir, fname)

        self.pkts = self.gen_pkts()
        self.rx_q_exp = self.rss_q_expt(self.pkts)
        wrpcap(local_pcap, self.pkts)
        self.pkts = PacketList()
        self.src.cp_to(local_pcap, send_pcap)
        os.remove(local_pcap)

        return src_tmpdir, send_pcap

    def interface_cfg(self):
        """
        Configure interfaces, including RSS parameters
        """
        # Add cfg later
        if self.ipv4:
            if self.l4_type == 'udp':
                protocol = 'udp4'
            else:
                protocol = 'tcp4'
        else:
            if self.l4_type == 'udp':
                protocol = 'udp6'
            else:
                protocol = 'tcp6'
        self.dst.cmd("ethtool -N %s rx-flow-hash %s sdfn" % (self.dst_ifn,
                                                             protocol))
        return

    def send_packets(self, send_pcap):
        """
        Send packets by using TCPReplay

        """
        pcapre = TCPReplay(self.src, self.src_ifn, send_pcap,
                           loop=self.num_pkts, pps=10000)
        attempt, sent = pcapre.run()
        if attempt == -1 or sent == -1:
            return False
        else:
            return True

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets and check the result

        """
        # get stats of dst interface
        dst_netifs = self.dst.netifs[dst_if]
        before_cntrs = dst_netifs.stats()
        # Create and run a test. Send 10 packets at 10pps
        tcpreplay_passed = self.send_packets(send_pcap)
        if not tcpreplay_passed:
            return NrtResult(name=self.name, testtype=self.__class__.__name__,
                             passed=False, comment="tcpreplay failed")

        try:
            timed_poll(10, self.are_cntrs_correct, dst_netifs, before_cntrs,
                       delay=1)
        except NtiTimeoutError:
            return NrtResult(name=self.name,
                             testtype=self.__class__.__name__,
                             passed=False, comment="ethtool counters "
                                                   "have unexpected increase")
        # Preserve pcap if test failed
        if tmpdir:
            self.src.rm_dir(tmpdir)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=True, comment="")

    def are_cntrs_correct(self, dst_netifs, before_cntrs):
        """
        Return True if all ethtool counters match the expceted value
        """
        after_cntrs = dst_netifs.stats()
        diff_cntrs = after_cntrs - before_cntrs

        result = self.check_result(diff_cntrs)

        return result.passed


    def check_result(self, if_stat_diff):
        """
        Check the result
        """
        # dump the stats to the log
        LOG_sec("Interface stats difference")
        LOG(if_stat_diff.pp())
        LOG_endsec()

        passed = True
        comment = ''
        passed = True
        total_recv_pkts = 0
        for i in range(0, self.num_rx_queue):
            cntr_name = 'rvec_%s_rx_pkts' % i
            total_recv_pkts += if_stat_diff.ethtool[cntr_name]

        # find the extra packets that was not sent by RSS tests
        recv_gap = total_recv_pkts - self.total_pckts
        if recv_gap < 0:
            passed = False
            comment += 'The total received packets over all rx queue (%d) ' \
                       'is less than TCPreplay packets (%d); ' \
                       % (total_recv_pkts, self.total_pckts)

        LOG_sec('difference between expected rx pckt and exact rx pckts')
        LOG('%s, %s, %s, %s, %s;' % (0, 'rvec_0_rx_pkts',
                                     if_stat_diff.ethtool['rvec_0_rx_pkts'],
                                     self.rx_q_exp[0],
                                     (if_stat_diff.ethtool['rvec_0_rx_pkts'] -
                                      self.rx_q_exp[0])))
        if if_stat_diff.ethtool['rvec_0_rx_pkts'] < self.rx_q_exp[0]:
            # There maybe some icmp packets that also go to rx queue 0, thus,
            # we should expect no less than calculated RSS rx 0 pckts
            # (self.rx_q_exp[0])
            passed = False
            comment += 'rvec_0_rx_pkts received %s pckts (we expect no less ' \
                       'than %s pckts go this queue); ' % \
                       (if_stat_diff.ethtool['rvec_0_rx_pkts'],
                        self.rx_q_exp[0])
        for i in range(1, self.num_rx_queue):
            cntr_name = 'rvec_%s_rx_pkts' % i
            LOG('%s, %s, %s, %s, %s;' % (i, cntr_name,
                                         if_stat_diff.ethtool[cntr_name],
                                         self.rx_q_exp[i],
                                         (if_stat_diff.ethtool[cntr_name] -
                                          self.rx_q_exp[i])))
            if if_stat_diff.ethtool[cntr_name] < self.rx_q_exp[i] or \
               if_stat_diff.ethtool[cntr_name] > self.rx_q_exp[i] + recv_gap:
                # For every rx queue (except rx_q 0), the actual rx pckts
                # should match the calculated rx pckts
                passed = False
                comment += '%s received %s pckts (we expect %s pckts go ' \
                           'this queue); ' % (cntr_name,
                                              if_stat_diff.ethtool[cntr_name],
                                              self.rx_q_exp[i])
        LOG_endsec()

        if not passed:
            LOG_sec("The following counters have unexpected increase")
            LOG(comment)
            comment = 'RX queue counters have unexpected increase'
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=passed, comment=comment)

class RSStest_diff_l4_tuple(RSStest_same_l4_tuple):
    """Test class for RSS test"""
    # Information applicable to all subclasses
    _gen_info = """
    sending IP packets to test RSS functions.
    """
    def __init__(self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='udp',
                 varies_src_addr=True, varies_dst_addr=True,
                 varies_src_port=True, varies_dst_port=True,
                 vlan_tag=False,
                 group=None, name="", summary='sending IP packets to test '
                                              'RSS functions'):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        RSStest_same_l4_tuple.__init__(self, src, dst, promisc=promisc,
                                       ipv4=ipv4,
                                       ipv4_opt=ipv4_opt,
                                       ipv6_rt=ipv6_rt, ipv6_hbh=ipv6_hbh,
                                       l4_type=l4_type,
                                       group=group, name=name, summary=summary)
        # How many times to send the pcap file repeatedly
        self.num_pkts = 1
        self.total_pckts = 5000
        self.varies_src_addr = varies_src_addr
        self.varies_dst_addr = varies_dst_addr
        self.varies_src_port = varies_src_port
        self.varies_dst_port = varies_dst_port
        self.vlan_tag = vlan_tag
        self.vlan_id = 10

    def gen_pkts(self):
        """
        Generate packets in scapy format for replay
        """
        random.seed(1)

        pkts = PacketList()

        # all pckts have different and pseudo random ip addr & port tuple
        # Half of them have ip option headers.
        for i in range(0, self.total_pckts):
            payload_str = self.name + '_' + str(i)
            if self.varies_src_port:
                sport = random.randrange(1, 65535)
            else:
                sport = 3000
            if self.varies_dst_port:
                dport = random.randrange(1, 65535)
            else:
                dport = 4000

            if self.l4_type == 'udp':
                pkt = UDP(sport=sport, dport=dport)/payload_str
            else:
                pkt = TCP(sport=sport, dport=dport)/payload_str
            if self.ipv4:
                # half of IPV4 packets have IP option header
                if self.varies_src_addr:
                    src_ip = str(random.randrange(1, 255)) + "."
                    src_ip += str(random.randrange(1, 255)) + "."
                    src_ip += str(random.randrange(1, 255)) + "."
                    src_ip += str(random.randrange(1, 255))
                else:
                    src_ip = self.src_ip

                if self.varies_dst_addr:
                    dst_ip = str(random.randrange(1, 255)) + "."
                    dst_ip += str(random.randrange(1, 255)) + "."
                    dst_ip += str(random.randrange(1, 255)) + "."
                    dst_ip += str(random.randrange(1, 255))
                else:
                    dst_ip = self.dst_ip

                if i % 2:
                    pkt = IP(src=src_ip, dst=dst_ip,
                             options=[IPOption_NOP()])/pkt
                else:
                    pkt = IP(src=src_ip, dst=dst_ip)/pkt
            else:
                # half of IPV6 packets have IPv6 option header
                if self.varies_src_addr:
                    src_ip = '%x' % random.randrange(0, 65535) + ":"
                    src_ip += '%x' % random.randrange(0, 65535) + ":"
                    src_ip += '%x' % random.randrange(0, 65535) + ":"
                    src_ip += '%x' % random.randrange(0, 65535) + ":"
                    src_ip += '%x' % random.randrange(0, 65535) + ":"
                    src_ip += '%x' % random.randrange(0, 65535) + ":"
                    src_ip += '%x' % random.randrange(0, 65535) + ":"
                    src_ip += '%x' % random.randrange(0, 65535)
                else:
                    src_ip = self.src_ip

                if self.varies_dst_addr:
                    dst_ip = '%x' % random.randrange(0, 65535) + ":"
                    dst_ip += '%x' % random.randrange(0, 65535) + ":"
                    dst_ip += '%x' % random.randrange(0, 65535) + ":"
                    dst_ip += '%x' % random.randrange(0, 65535) + ":"
                    dst_ip += '%x' % random.randrange(0, 65535) + ":"
                    dst_ip += '%x' % random.randrange(0, 65535) + ":"
                    dst_ip += '%x' % random.randrange(0, 65535) + ":"
                    dst_ip += '%x' % random.randrange(0, 65535)
                else:
                    dst_ip = self.dst_ip

                ipv6_base = IPv6(src=src_ip, dst=dst_ip)
                #if i % 2:
                #    ipv6_base = ipv6_base/IPv6ExtHdrHopByHop()
                # but there is no ME code support yet, details at SB-99
                pkt = ipv6_base/pkt

            if self.vlan_tag:
                pkt = Dot1Q(vlan=self.vlan_id)/pkt

            pkt = Ether(src=self.src_mac, dst=self.dst_mac)/pkt
            pkts.append(pkt)
        return pkts

    def interface_cfg(self):
        """
        Configure interfaces, including RSS parameters
        """
        # Add cfg later
        if self.ipv4:
            if self.l4_type == 'udp':
                protocol = 'udp4'
            else:
                protocol = 'tcp4'
        else:
            if self.l4_type == 'udp':
                protocol = 'udp6'
            else:
                protocol = 'tcp6'
        self.dst.cmd("ethtool -N %s rx-flow-hash %s sdfn" % (self.dst_ifn,
                                                             protocol))
        return

class RSStest_diff_l4_tuple_modify_table(RSStest_diff_l4_tuple):
    """Test class for RSS test modifying indirection table"""
    # Information applicable to all subclasses
    _gen_info = """
    sending IP packets to test RSS functions with modified indirection table.
    """
    def __init__(self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='udp',
                 varies_src_addr=True, varies_dst_addr=True,
                 varies_src_port=True, varies_dst_port=True,
                 group=None, name="", summary='sending IP packets to test RSS '
                                              'functions with modified '
                                              'indirection table.'):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        RSStest_diff_l4_tuple.__init__(self, src, dst, promisc=promisc,
                                       ipv4=ipv4,
                                       ipv4_opt=ipv4_opt,
                                       ipv6_rt=ipv6_rt, ipv6_hbh=ipv6_hbh,
                                       l4_type=l4_type,
                                       varies_src_addr=varies_src_addr,
                                       varies_dst_addr=varies_dst_addr,
                                       varies_src_port=varies_src_port,
                                       varies_dst_port=varies_dst_port,
                                       group=group, name=name, summary=summary)

    def interface_cfg(self):
        """
        Configure interfaces, including RSS parameters
        """
        RSStest_diff_l4_tuple.interface_cfg(self)
        self.dst.cmd("ethtool -x %s" % self.dst_ifn)
        # we expect only #1 rx queue receives all packets
        self.dst.cmd("ethtool -X %s weight 0 1" % self.dst_ifn)
        self.dst.cmd("ethtool -x %s" % self.dst_ifn)
        return

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets and check the result

        """
        try:
            ret = RSStest_diff_l4_tuple.send_pckts_and_check_result(self,
                                                                    src_if,
                                                                    dst_if,
                                                                    send_pcap,
                                                                    tmpdir)
        except:
            ret = NrtResult(name=self.name, testtype=self.__class__.__name__,
                            passed=False, comment='test failed in the send_'
                                                  'pckts_and_check_result '
                                                  'method')
        finally:
            self.dst.cmd("ethtool -X %s equal %s" % (self.dst_ifn,
                                                     self.num_rx_queue))
            self.dst.cmd("ethtool -x %s" % self.dst_ifn)
            return ret



class Stats_per_queue_cntr(RSStest_diff_l4_tuple):
    """Test class for testing per_queue counters"""
    # We use the RSStest_diff_l4_tuple as the super class, as we want to send
    # traffic to all queues, and check the recv_* counters match the r/txq_*
    # counters
    _gen_info = """
    sending IP packets to test per_queue counters.
    """
    def __init__(self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='tcp',
                 group=None, name="", summary=None):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        RSStest_diff_l4_tuple.__init__(self, src, dst, promisc=promisc,
                                       ipv4=ipv4,
                                       ipv4_opt=ipv4_opt,
                                       ipv6_rt=ipv6_rt, ipv6_hbh=ipv6_hbh,
                                       l4_type=l4_type,
                                       varies_src_addr=True,
                                       varies_dst_addr=True,
                                       varies_src_port=True,
                                       varies_dst_port=True,
                                       group=group, name=name, summary=summary)
        self.recv_rx_list = None
        self.recv_tx_list = None
        self.dut_tmpdir = None
        self.dut_pcap = None
        self.total_pckts = 1000

    def gen_pcap(self):
        """
        Create and copy PCAP file to src
        """
        _, local_pcap = mkstemp()
        src_tmpdir = self.src.make_temp_dir()
        self.dut_tmpdir = self.dst.make_temp_dir()
        fname = "send.pcap"
        endpoint_pcap = os.path.join(src_tmpdir, fname)
        self.dut_pcap = os.path.join(self.dut_tmpdir, fname)

        self.pkts = self.gen_pkts()
        wrpcap(local_pcap, self.pkts)
        self.pkts = PacketList()
        self.src.cp_to(local_pcap, endpoint_pcap)
        self.dst.cp_to(local_pcap, self.dut_pcap)
        os.remove(local_pcap)

        return src_tmpdir, endpoint_pcap

    def send_packets(self, send_pcap):
        """
        Send packets by using TCPReplay

        """
        ret = RSStest_diff_l4_tuple.send_packets(self, send_pcap)
        pcapre = TCPReplay(self.dst, self.dst_ifn, self.dut_pcap,
                           loop=self.num_pkts, pps=10000)
        for i in range(0, self.num_rx_queue):
            attempt, sent = pcapre.run()
            if attempt == -1 or sent == -1 or not ret:
                return False
        #else:
        #    return True
        return True
        #self.src.cmd('iperf')

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

        cmd = 'ethtool -S %s' % self.dst_ifn
        _, out = self.dst.cmd(cmd)
        re_num_queue = '\s*rxq_(\d+)_pkts:\s'
        queue_index = re.findall(re_num_queue, out)
        temp_MQ = NFPFlowMultiQueue(queue_index)

        self.num_rx_queue = temp_MQ.num_q
        self.rxq_list = temp_MQ.rxq_pkts_cntrs
        self.txq_list = temp_MQ.txq_pkts_cntrs
        self.recv_rx_list = temp_MQ.recv_rx_pkts_cntrs
        self.recv_tx_list = temp_MQ.recv_tx_pkts_cntrs

    def check_result(self, if_stat_diff):
        """
        Check the result
        """
        # dump the stats to the log
        LOG_sec("Interface stats difference")
        LOG(if_stat_diff.pp())
        LOG_endsec()

        passed = True
        comment = ''
        for rxq_name in self.rxq_list:
            re_index = 'rxq_(\d+)_pkts'
            q_index = re.findall(re_index, rxq_name)[0]
            recv_rxq_name = 'rvec_%s_rx_pkts' % q_index
            if if_stat_diff.ethtool[rxq_name] != if_stat_diff.ethtool[recv_rxq_name]:
                passed = False
                comment += '%s and %s do not match' % (rxq_name, recv_rxq_name)
        for txq_name in self.txq_list:
            re_index = 'txq_(\d+)_pkts'
            q_index = re.findall(re_index, txq_name)[0]
            recv_txq_name = 'rvec_%s_tx_pkts' % q_index
            if if_stat_diff.ethtool[txq_name] != if_stat_diff.ethtool[recv_txq_name]:
                passed = False
                comment += '%s and %s do not match; ' % (txq_name, recv_txq_name)
        if not passed:
            LOG_sec("The following counters have unexpected increase")
            LOG(comment)
            LOG_endsec()
            comment = 'per queue counters do not match'
        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=passed, comment=comment)

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets and check the result

        """
        res = RSStest_diff_l4_tuple.send_pckts_and_check_result(self, src_if,
                                                                dst_if,
                                                                send_pcap,
                                                                tmpdir)


        # Preserve pcap if test failed
        if self.dut_tmpdir and res.passed:
            self.dst.rm_dir(self.dut_tmpdir)

        return res


class Kmod_perf(Test):
    """Test class for driver loading test"""
    # Information applicable to all subclasses
    _gen_info = """
    Measuring the time to load driver and firmware in kernel mode
    """
    def __init__(self, src, dst, target_time=1.0,
                 group=None, name="", summary=None):
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

        # the required loading time (in min)
        self.target_time = target_time
        self.real_time = None


    def run(self):

        """Run the test
        @return:  A result object"""

        passed = True

        try:

            self.get_eth_dict()
            self.src.cmd('rmmod nfp_net')
            self.get_eth_dict()
            cmd = "time modprobe nfp_net nfp_reset=1 num_rings=32"
            _, (out, err) = self.src.cmd(cmd, include_stderr=True)
            real_time_str = 'real\s+([\d.]+)m([\d.]+)s'
            re_find = re.findall(real_time_str, err)
            if re_find:
                load_minutes = float(re_find[0][0])
                load_seconds = float(re_find[0][1])
                self.real_time = (load_minutes * 60.0) + load_seconds
            self.get_eth_dict()
            timed_poll(10, self.is_eth_listed, self.src_ifn, delay=1)
            cmd = 'ip addr flush dev eth5; ifconfig %s inet6 add %s; ' \
                  'ifconfig %s %s up;' % (self.src_ifn, self.src_addr_v6,
                                          self.src_ifn, self.src_addr)
            self.src.cmd(cmd)
        except:
            raise NtiGeneralError(msg="Fail to re-load driver and fw in DUT")

        try:
            src_if = self.src.netifs[self.src_ifn]
            dst_if = self.dst.netifs[self.dst_ifn]

            self.src.cmd('ping -c 1 %s' % dst_if.ip)
            self.dst.cmd('ping -c 1 %s' % src_if.ip)

        except:
            raise NtiGeneralError(msg="Fail to ping after driver reloaded")

        if self.real_time > self.target_time:
            passed = False

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=passed, comment='The loading time '
                                                'is %s sec(s)' % self.real_time)


    def get_eth_dict(self):
        """
        To get the dictionary of eth interfaces which have MAC addresses
        An example of the output of cmd 'ifconfig -a | grep -r HWaddr':
        eth0      Link encap:Ethernet  HWaddr 00:30:67:aa:7e:7a
        eth1      Link encap:Ethernet  HWaddr 52:51:61:89:b8:81
        """
        cmd = 'ifconfig -a | grep HWaddr'
        _, out = self.src.cmd(cmd)
        lines = out.splitlines()
        eth_dict = {}
        for line in lines:
            line_re = '\w+ +Link encap:Ethernet +HWaddr +' \
                      '([0-9a-f]{2}:){5}[0-9a-f]{2}'
            if re.match(line_re, line):
                name, _, _, _, hw_addr = line.split()
                eth_dict[name] = hw_addr
            else:
                raise NtiGeneralError(msg="Unexpected ifconfig output "
                                          "in get_eth_dict")
        return eth_dict

    def is_eth_listed(self, eth):
        """
        return True if the 'eth' interface is listed in ifconfig
        """

        eth_dict = self.get_eth_dict()
        if eth in eth_dict:
            return True
        else:
            return False

class RSStest_diff_part_l4_tuple(RSStest_diff_l4_tuple):
    """Test class for RSS test"""
    # Information applicable to all subclasses
    _gen_info = """
    sending IP packets to test RSS functions.
    """
    def __init__(self, src, dst, promisc=False, ipv4=False, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='udp',
                 varies_src_addr=True, varies_dst_addr=False,
                 varies_src_byte_index=0, varies_dst_byte_index=0,
                 vlan_tag=False, group=None, name="",
                 summary='sending IP packets to test RSS functions'):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        RSStest_diff_l4_tuple.__init__(self, src, dst, promisc=promisc,
                                       ipv4=ipv4,
                                       ipv4_opt=ipv4_opt,
                                       ipv6_rt=ipv6_rt, ipv6_hbh=ipv6_hbh,
                                       l4_type=l4_type,
                                       varies_src_addr=varies_src_addr,
                                       varies_dst_addr=varies_dst_addr,
                                       varies_src_port=False,
                                       varies_dst_port=False,
                                       vlan_tag=vlan_tag,
                                       group=group, name=name, summary=summary)
        # How many times to send the pcap file repeatedly
        self.varies_src_byte_index = varies_src_byte_index
        self.varies_dst_byte_index = varies_dst_byte_index

    def gen_pkts(self):
        """
        Generate packets in scapy format for replay
        """
        random.seed(1)

        pkts = PacketList()

        # all pckts have different and pseudo random ip addr & port tuple
        # Half of them have ip option headers.
        for i in range(0, self.total_pckts):
            payload_str = self.name + '_' + str(i)
            sport = 3000
            dport = 4000

            if self.l4_type == 'udp':
                pkt = UDP(sport=sport, dport=dport)/payload_str
            else:
                pkt = TCP(sport=sport, dport=dport)/payload_str

            ipv6_octet_1 = random.randrange(0, 65535)
            ipv6_octet_2 = random.randrange(0, 65535)
            # half of IPV6 packets have IPv6 option header
            if self.varies_src_addr:
                if self.varies_src_byte_index == 0:
                    src_ip = '0:0:0:0:0:0:%x:%x' % (ipv6_octet_1, ipv6_octet_2)
                elif self.varies_src_byte_index == 2:
                    src_ip = '0:0:0:0:%x:%x:0:0' % (ipv6_octet_1, ipv6_octet_2)
                elif self.varies_src_byte_index == 4:
                    src_ip = '0:0:%x:%x:0:0:0:0' % (ipv6_octet_1, ipv6_octet_2)
                elif self.varies_src_byte_index == 6:
                    src_ip = '%x:%x:0:0:0:0:0:0' % (ipv6_octet_1, ipv6_octet_2)
                else:
                    src_ip = '%x:%x:0:0:0:0:0:0' % (ipv6_octet_1, ipv6_octet_2)
            else:
                src_ip = self.src_ip

            if self.varies_dst_addr:
                if self.varies_dst_byte_index == 0:
                    dst_ip = '0:0:0:0:0:0:%x:%x' % (ipv6_octet_1, ipv6_octet_2)
                elif self.varies_dst_byte_index == 2:
                    dst_ip = '0:0:0:0:%x:%x:0:0' % (ipv6_octet_1, ipv6_octet_2)
                elif self.varies_dst_byte_index == 4:
                    dst_ip = '0:0:0:0:%x:%x:0:0' % (ipv6_octet_1, ipv6_octet_2)
                elif self.varies_dst_byte_index == 6:
                    dst_ip = '0:0:%x:%x:0:0:0:0' % (ipv6_octet_1, ipv6_octet_2)
                elif self.varies_dst_byte_index == 8:
                    dst_ip = '%x:%x:0:0:0:0:0:0' % (ipv6_octet_1, ipv6_octet_2)
                else:
                    dst_ip = '%x:%x:0:0:0:0:0:0' % (ipv6_octet_1, ipv6_octet_2)
            else:
                dst_ip = self.dst_ip


            ipv6_base = IPv6(src=src_ip, dst=dst_ip)
            #if i % 2:
            #    ipv6_base = ipv6_base/IPv6ExtHdrHopByHop()
            # but there is no ME code support yet, details at SB-99
            pkt = ipv6_base/pkt

            if self.vlan_tag:
                pkt = Dot1Q(vlan=self.vlan_id)/pkt

            pkt = Ether(src=self.src_mac, dst=self.dst_mac)/pkt
            pkts.append(pkt)
        return pkts


class NFPFlowNICContentCheck(Test):
    """
    The test class to send a large file and check if the received file has
    the same content as the sent one.
    """

    # Information applicable to all subclasses
    _gen_info = """

    """

    def __init__(self, src, dst, ipv4=True, l4_type='tcp',
                 src_mtu=1500, dst_mtu=1500,
                 group=None, name="", summary=None):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        Test.__init__(self, group, name, summary)

        self.src = None
        self.src_intf = None
        self.dut = None
        self.dut_intf = None

        if src[0]:
            self.src = src[0]
            self.src_intf = src[2]
            self.dst = dst[0]
            self.dst_intf = dst[2]
            self.src_addr_v6 = src[3]
            self.dst_addr_v6 = dst[3]
            self.src_nc_bin = src[5]

        # These will be set in the run() method
        self.dst_ip = None
        self.tmp_src_dir = None
        self.tmp_dst_dir = None
        self.tmp_file = None
        self.recv_tmp_file = None
        self.hash = None
        self.file_size = None
        self.recv_file_size = None

        self.ipv4 = ipv4
        self.l4_type = l4_type
        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu

        self.iperf_s_pid = None
        self.iperf_c_pid = None
        self.tcpdump_dst_pid = None
        self.tcpdump_src_pid = None
        self.nc_pid = None

        return

    def run(self):
        """Run the test
        @return:  A result object"""

        # Refresh intf objects.
        self.src.refresh()
        self.dst.refresh()

        # Get address.
        dst_if = self.dst.netifs[self.dst_intf]
        self.dst_ip = dst_if.ip
        if self.ipv4:
            self.dst_ip = dst_if.ip
        else:
            self.dst_ip = self.get_ipv6(self.dst, self.dst_intf,
                                        self.dst_addr_v6)

        self.interface_cfg()
        #  Generate the appropriately sized file.
        #  NC the file from the dut to the endpoint.
        #  Using md5hash and cmp, verify the files are the same on both ends.
        self.tmp_src_dir = self.src.make_temp_dir()
        self.tmp_dst_dir = self.dst.make_temp_dir()
        try:
            buf_size = 0
            mb = 1024 * 1024  # One megabyte.
            # 2 MB file size.
            file_size = 2 * mb
            _, self.tmp_file = mkstemp()
            _, self.recv_tmp_file = mkstemp()
            with open(self.tmp_file, 'w', buf_size) as f:
                while os.stat(self.tmp_file).st_size < file_size:
                    f.write(str(random.random()) + '\n')

            # Using md5, obtain hash.
            md5hash = hashlib.md5()
            with open(self.tmp_file) as f:
                for line in f:
                    md5hash.update(line)
            self.hash = md5hash.hexdigest()

            self.file_size = os.stat(self.tmp_file).st_size

            # Copy tmp file to dut.
            self.src.cp_to(self.tmp_file, self.tmp_src_dir)

            self.transfer_file()

            # Take md5 hash of destination file and compare with local.
            cmd = ("python -c \"import sys; import hashlib; "
                   "md5hash = hashlib.md5(); "
                   "[md5hash.update(line) for line in sys.stdin]; "
                   "print md5hash.hexdigest()\" < %s" %
                   os.path.join(self.tmp_dst_dir,
                                ntpath.basename(self.tmp_file)))

            _, dst_hash = self.dst.cmd(cmd)
            dst_hash = dst_hash.strip('\n')

            if cmp(self.hash, dst_hash):
                comment = ("Hashes (local hash: %s) (dst_hash: %s) are "
                           "different!" % (self.hash, dst_hash))
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=False, comment=comment)

            self.dst.cp_from(os.path.join(self.tmp_dst_dir,
                                          ntpath.basename(self.tmp_file)),
                             self.recv_tmp_file)

            self.recv_file_size = os.stat(self.recv_tmp_file).st_size

            if self.recv_file_size != self.file_size:
                comment = ("File sizes (local size: %s) (dst_size: %s) are "
                           "different!" % (self.file_size, self.recv_file_size))
                return NrtResult(name=self.name,
                                 testtype=self.__class__.__name__,
                                 passed=False, comment=comment)

        finally:
            self.dst.killall_w_pid(self.nc_pid, signal='-9')

            # check netcat server err (for debugging) after netcat client ends
            self.dst.cmd('cat %s' % os.path.join(self.tmp_dst_dir,
                                             'nc_server_err.txt'), fail=False)
            # Remove all tmp created files.
            LOG_sec("Cleaning up tmp directories on remote hosts.")
            self.src.rm_dir(self.tmp_src_dir)
            self.dst.rm_dir(self.tmp_dst_dir)
            LOG_endsec()

            LOG_sec("Cleaning up local tmp files.")
            if os.path.isfile(self.tmp_file):
                os.remove(self.tmp_file)
            LOG_endsec()
            if not self.ipv4:
                self.dst.cmd("ifconfig %s -allmulti" % self.dst_intf)
            self.src.cmd('cat /proc/sys/net/ipv4/tcp_tso_win_divisor')
            self.src.cmd('echo 3 > /proc/sys/net/ipv4/tcp_tso_win_divisor')

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=True, comment="")

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        self.src.cmd('ethtool -K %s tso on' % self.src_intf)
        self.src.cmd('sysctl -w net.ipv4.tcp_min_tso_segs=2')
        self.src.cmd('ifconfig %s mtu %s' % (self.src_intf, self.src_mtu))
        self.dst.cmd('ifconfig %s mtu %s' % (self.dst_intf, self.dst_mtu))
        self.src.cmd('cat /proc/sys/net/ipv4/tcp_tso_win_divisor')
        self.src.cmd('echo 1 > /proc/sys/net/ipv4/tcp_tso_win_divisor')
        if not self.ipv4:
            self.dst.cmd("ifconfig %s allmulti" % self.dst_intf)
        return

    def transfer_file(self):
        """
        Tranfering the file
        """
        if self.ipv4:
            ipv4_str = ''
        else:
            ipv4_str = '-6'
        if self.l4_type=='udp':
            raise NtiGeneralError('We only support TCP in '
                                  'the content-check test')

        timed_poll(30, self.run_nc, ipv4_str)

        # Verify it was sent, then check the counter.
        timed_poll(30, self.dst.exists_host,
                   os.path.join(self.tmp_dst_dir,
                                ntpath.basename(self.tmp_file)),
                   delay=1)

        self.dst.killall_w_pid(self.nc_pid, signal='-9')

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

    def run_nc(self, ipv4_str):
        """
        Run netcat cmd, return True when nc client returns no-error.
        """
        nc_cmd = 'nc %s -l -p 5000 2> %s 1> %s' % \
                 (ipv4_str,
                  os.path.join(self.tmp_dst_dir, 'nc_server_err.txt'),
                  os.path.join(self.tmp_dst_dir,
                               ntpath.basename(self.tmp_file)))
        nc_pid_file = os.path.join(self.tmp_dst_dir, 'nc_tmp_pid.txt')
        ret, _ = self.dst.cmd_bg_pid_file(nc_cmd, nc_pid_file, background=True)
        self.nc_pid = ret[1]
        timed_poll(30, self.dst.exists_host,
                   os.path.join(self.tmp_dst_dir,
                                ntpath.basename(self.tmp_file)), delay=1)

        # netcat file from dut to endpoint.
        self.src.cmd('ls -lart %s' %
                     os.path.join(self.tmp_src_dir,
                                  ntpath.basename(self.tmp_file)))
        # check netcat server err (for debugging) before netcat client starts
        self.dst.cmd('cat %s' % os.path.join(self.tmp_dst_dir,
                                             'nc_server_err.txt'), fail=False)

        dst_netifs = self.dst.netifs[self.dst_intf]
        src_netifs = self.src.netifs[self.src_intf]
        before_dst_cntrs = dst_netifs.stats()
        before_src_cntrs = src_netifs.stats()

        nc_cmd = '%s %s 5000 %s %s' \
                 % (self.src_nc_bin, self.dst_ip,
                    os.path.join(self.tmp_src_dir,
                                 ntpath.basename(self.tmp_file)), ipv4_str)
        try:
            self.src.cmd(nc_cmd)
        except:
            self.dst.killall_w_pid(self.nc_pid, signal='-9')
            return False

        after_dst_cntrs = dst_netifs.stats()
        after_src_cntrs = src_netifs.stats()
        diff_dst_cntrs = after_dst_cntrs - before_dst_cntrs
        diff_src_cntrs = after_src_cntrs - before_src_cntrs

        self.dst.killall_w_pid(self.nc_pid, signal='-9')

        if diff_src_cntrs.ethtool['tx_lso']:
            return True
        else:
            raise NtiGeneralError(msg='ethtool counters did not increase as '
                                      'expected: tx_lso = %s' %
                                      diff_src_cntrs.ethtool['tx_lso'])


class McPing(Test):
    """Test class for link state monitoring"""
    # Information applicable to all subclasses
    _gen_info = """
    Multicast ping from NFP
    """

    def __init__(self, src, dst, ipv4=True, group=None, name="", summary=None):
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
        self.ipv4 = ipv4
        self.ping_number = 5
        self.mc_ping_addr = '239.1.1.123'

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
        return

    def run(self):
        """
        Ping mc address from NFP and check rx_packet on endpoint.
        """
        passed = True
        comment = ''

        _, out = self.dst.cmd('ifconfig %s | grep \"RX packets\"' % self.
                              dst_ifn)
        rx_re = 'RX packets:(\d+)\s'

        rx_before = int(re.findall(rx_re, out)[0])

        self.src.cmd('ping -c %s -I %s %s' % (self.ping_number, self.src_ifn,
                                              self.mc_ping_addr), fail=False)

        _, out = self.dst.cmd('ifconfig %s | grep \"RX packets\"' % self.
                              dst_ifn)
        rx_after = int(re.findall(rx_re, out)[0])

        if (rx_after - rx_before) <= 0:
            passed = False
            comment = 'The dst received %s packets' % (rx_after - rx_before)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=passed, comment=comment)


class Rx_Drop_test(UnitIP):
    """Test class for dropping packets by changing MTU during iperf"""
    # Information applicable to all subclasses
    _gen_info = """
    receiving and dropping packets (wrong DST MAC address packets).
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
        UnitIP.__init__(
            self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
            ipv6_rt=False, ipv6_hbh=False, l4_type='tcp', iperr=False,
            l4err=False, dst_mac_type="diff", src_mac_type="src",
            vlan=False, vlan_id=100, group=group, name=name,
            summary=summary)

        self.num_pkts = 1000000
        self.iperf_time = 5
        self.iperf_server_arg_str = ''
        self.iperf_client_arg_str = ''

    def send_packets(self, send_pcap):
        """
        Send packets by using TCPReplay

        """
        # adding the -t flag in tcpreplay for max throughput
        intf_with_flag = '%s -t -q' % self.src_ifn
        pcapre = TCPReplay(self.src, intf_with_flag, send_pcap,
                           loop=self.num_pkts)
        attempt, sent = pcapre.run()
        if attempt == -1 or sent == -1:
            return False
        else:
            return True

    def check_result(self, if_stat_diff):
        """
        Check if the interface is still functional by running iperf
        """
        passed = True
        msg = ''
        try:
            ret = self.is_pingable()
            if not ret:
                passed = False
                msg = 'Ping after rx_drop_pkts_tcpreplay failed'
        except:
            passed = False
            msg = 'Exception during ping after rx_drop_pkts_tcpreplay failed'
        finally:
            return NrtResult(name=self.name, testtype=self.__class__.__name__,
                             passed=passed, comment=msg)

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
