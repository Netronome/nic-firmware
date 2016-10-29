##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
Iperf test classes for the NFPFlowNIC Software Group.
"""

import os
import re
import time
import random
import string
from scapy.packet import bind_layers
from netro.testinfra import Test, LOG_sec, LOG, LOG_endsec
from scapy.all import TCP, UDP, IP, Ether, wrpcap, IPv6, ICMP, \
    IPOption_NOP, IPv6ExtHdrRouting, IPv6ExtHdrHopByHop, Dot1Q, Raw, rdpcap, \
    PacketList, load_contrib, GRE, ICMPv6ND_RS
from vxlan import VXLAN
from netro.testinfra.utilities import timed_poll
from tempfile import mkstemp
from netro.testinfra.nrt_result import NrtResult
from netro.testinfra.nti_exceptions import NtiGeneralError
from iperf_unit import Csum_Tx, LSO_iperf
from unit import RSStest_same_l4_tuple, RSStest_diff_l4_tuple, \
    RSStest_diff_l4_tuple_modify_table, RSStest_diff_part_l4_tuple, UnitIP, \
    NFPFlowNICMTU

from netro.testinfra.nti_exceptions import NtiTimeoutError, NtiGeneralError
from netro.tests.tcpreplay import TCPReplay
from expect_cntr_list import RingSize_ethtool_tx_cntr, RingSize_ethtool_rx_cntr


def get_new_mac():
    return '54:%s:%s:%s:%s:%s' % (hex(random.randrange(0, 255))[2:],
                                  hex(random.randrange(0, 255))[2:],
                                  hex(random.randrange(0, 255))[2:],
                                  hex(random.randrange(0, 255))[2:],
                                  hex(random.randrange(0, 255))[2:])

def get_vxlan_dport(src_ip, dst_ip):
    my_ip_key = src_ip + dst_ip
    port_hash = hash(my_ip_key) % 100
    dport = 4789 + port_hash
    bind_layers(UDP, VXLAN, dport=dport)
    return dport


class RSStest_diff_inner_tuple(RSStest_diff_l4_tuple):
    """Test class for RSS test"""
    # Information applicable to all subclasses
    _gen_info = """
    sending IP packets to test RSS functions.
    """
    def __init__(self, src, dst, promisc=False, outer_ipv4=True,
                 outer_ipv4_opt=False, outer_ipv6_rt=False,
                 outer_ipv6_hbh=False, outer_l4_type=None,
                 inner_ipv4=True, inner_ipv4_opt=False, inner_ipv6_rt=False,
                 inner_ipv6_hbh=False, inner_l4_type='udp',
                 varies_src_addr=True, varies_dst_addr=True,
                 varies_src_port=True, varies_dst_port=True,
                 tunnel_type='vxlan',
                 outer_vlan_tag=False, inner_vlan_tag=False,
                 group=None, name="", summary='sending tunnel IP packets to '
                                              'test RSS functions'):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        RSStest_diff_l4_tuple.__init__(self, src, dst, promisc=promisc,
                                       ipv4=outer_ipv4,
                                       ipv4_opt=outer_ipv4_opt,
                                       ipv6_rt=outer_ipv6_rt,
                                       ipv6_hbh=outer_ipv6_hbh,
                                       l4_type=outer_l4_type,
                                       varies_src_addr=varies_src_addr,
                                       varies_dst_addr=varies_dst_addr,
                                       varies_src_port=varies_src_port,
                                       varies_dst_port=varies_dst_port,
                                       vlan_tag=outer_vlan_tag,
                                       group=group, name=name, summary=summary)
        self.inner_ipv4 = inner_ipv4
        self.inner_ipv4_opt = inner_ipv4_opt
        self.inner_ipv6_rt = inner_ipv6_rt
        self.inner_ipv6_hbh = inner_ipv6_hbh
        self.inner_l4_type = inner_l4_type
        self.tunnel_type = tunnel_type
        self.inner_vlan_tag = inner_vlan_tag
        self.inner_vlan_id = 20

        self.vxlan_id = 42
        if src[0]:
            self.vxlan_dport = get_vxlan_dport(self.src_addr, self.dst_addr)
        self.dst_vxlan_intf = 'vxlan_%s' % self.dst_ifn
        self.src_vxlan_intf = 'vxlan_%s' % self.src_ifn
        self.vxlan_mc = '239.1.1.1'
        self.src_inner_hwaddr = None
        self.dst_inner_hwaddr = None
        self.src_inner_addr = None
        self.dst_inner_addr = None
        self.src_inner_addr6 = None
        self.dst_inner_addr6 = None

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
                sport = 5000
            if self.varies_dst_port:
                dport = random.randrange(1, 65535)
            else:
                dport = 6000

            if self.inner_l4_type == 'udp':
                pkt = UDP(sport=sport, dport=dport)/payload_str
            else:
                pkt = TCP(sport=sport, dport=dport)/payload_str
            if self.inner_ipv4:
                # half of IPV4 packets have IP option header
                if self.varies_src_addr:
                    src_ip = str(random.randrange(1, 255)) + "."
                    src_ip += str(random.randrange(1, 255)) + "."
                    src_ip += str(random.randrange(1, 255)) + "."
                    src_ip += str(random.randrange(1, 255))
                else:
                    src_ip = self.src_inner_addr

                if self.varies_dst_addr:
                    dst_ip = str(random.randrange(1, 255)) + "."
                    dst_ip += str(random.randrange(1, 255)) + "."
                    dst_ip += str(random.randrange(1, 255)) + "."
                    dst_ip += str(random.randrange(1, 255))
                else:
                    dst_ip = self.dst_inner_addr

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
                    src_ip = self.src_inner_addr6

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
                    dst_ip = self.dst_inner_addr6

                ipv6_base = IPv6(src=src_ip, dst=dst_ip)
                #if i % 2:
                #    ipv6_base = ipv6_base/IPv6ExtHdrHopByHop()
                # but there is no ME code support yet, details at SB-99
                pkt = ipv6_base/pkt

            if self.inner_vlan_tag:
                pkt = Dot1Q(vlan=self.inner_vlan_id)/pkt

            pkt = Ether(src=self.src_inner_hwaddr,
                        dst=self.dst_inner_hwaddr)/pkt
            if self.tunnel_type == 'vxlan':
                pkt = VXLAN(vni=self.vxlan_id)/pkt
                if self.l4_type == 'udp':
                    pkt = UDP(sport=3000, dport=self.vxlan_dport)/pkt
                else:
                    raise NtiGeneralError(msg='Only UDP is supported as '
                                              'outer header in vxlan '
                                              'tunnel tests.')
            elif self.tunnel_type == 'nvgre':
                pkt = GRE(proto=0x6558, key_present=1, key=0x1234)/pkt
                # For NVGRE there is no outer L4 and so the outer UDP/TCP
                # should not be there. Thus, one should add nvgre rx tests in
                # unit_tests.py with 'l4_type=None', or use the default value
                if self.l4_type:
                    raise NtiGeneralError(msg='There should be neither TCP nor '
                                              'UDP in NVGRE outer header')
            if self.ipv4:
                pkt = IP(src=self.src_ip, dst=self.dst_ip)/pkt
            else:
                pkt = IPv6(src=self.src_ip, dst=self.dst_ip)/pkt
            if self.vlan_tag:
                pkt = Dot1Q(vlan=self.vlan_id)/pkt
            pkt = Ether(src=self.src_mac, dst=self.dst_mac)/pkt
            pkts.append(pkt)
        return pkts

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
            if self.tunnel_type == 'vxlan':
                innner_pkt = pkt[VXLAN][Ether]
            elif self.tunnel_type == 'nvgre':
                innner_pkt = pkt[GRE][Ether]
            else:
                raise NtiGeneralError(msg='Only support VXLAN and NVGRE')
            rss_expt_q = self.cal_rss_rxq(innner_pkt, rss_table,
                                          self.inner_ipv4,
                                          self.inner_l4_type)
            rss_expt_q_table[rss_expt_q] += 1
        return rss_expt_q_table


    def interface_cfg(self):
        """
        Configure interfaces, including RSS parameters
        """
        random.seed(os.getpid())
        self.src_inner_hwaddr = get_new_mac()
        self.dst_inner_hwaddr = get_new_mac()

        src_if = self.src.netifs[self.src_ifn]
        dst_if = self.dst.netifs[self.dst_ifn]
        src_ip6 = self.get_ipv6(self.src, self.src_ifn, self.src_addr_v6)
        dst_ip6 = self.get_ipv6(self.dst, self.dst_ifn, self.dst_addr_v6)
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

        self.src_inner_addr = new_src_ipv4
        self.dst_inner_addr = new_dst_ipv4
        self.src_inner_addr6 = new_src_ipv6
        self.dst_inner_addr6 = new_dst_ipv6

        # Add cfg later
        if self.inner_ipv4:
            if self.inner_l4_type == 'udp':
                protocol = 'udp4'
            else:
                protocol = 'tcp4'
        else:
            if self.inner_l4_type == 'udp':
                protocol = 'udp6'
            else:
                protocol = 'tcp6'
        self.dst.cmd("ethtool -N %s rx-flow-hash %s sdfn" % (self.dst_ifn,
                                                             protocol))

        if self.tunnel_type == 'vxlan':
            self.dst.cmd("ip link delete %s" % self.dst_vxlan_intf, fail=False)
            cmd = 'ip link add %s type vxlan id %d group %s dev %s ' \
                  'dstport %s' % (self.dst_vxlan_intf, self.vxlan_id,
                                  self.vxlan_mc, self.dst_ifn, self.vxlan_dport)
            self.dst.cmd(cmd)
            # The following cmd is needed for kernel 4.2
            cmd = 'ip link set up %s' % self.dst_vxlan_intf
            self.dst.cmd(cmd)
        return

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        remove vxlan interface before return the result object

        """
        res = RSStest_diff_l4_tuple.send_pckts_and_check_result(self, src_if,
                                                                dst_if,
                                                                send_pcap,
                                                                tmpdir)
        if self.tunnel_type == 'vxlan':
            self.dst.cmd("ip link delete %s" % self.dst_vxlan_intf, fail=False)

        return res


class RSStest_diff_inner_tuple_multi_tunnels(RSStest_diff_l4_tuple):
    """Test class for RSS test"""
    # Information applicable to all subclasses
    _gen_info = """
    sending IP packets to test RSS functions.
    """
    def __init__(self, src, dst, promisc=False, outer_ipv4=True,
                 outer_ipv4_opt=False, outer_ipv6_rt=False,
                 outer_ipv6_hbh=False, outer_l4_type=None,
                 inner_ipv4=True, inner_ipv4_opt=False, inner_ipv6_rt=False,
                 inner_ipv6_hbh=False, inner_l4_type='udp',
                 varies_src_addr=True, varies_dst_addr=True,
                 varies_src_port=True, varies_dst_port=True,
                 tunnel_type='vxlan',
                 outer_vlan_tag=False, inner_vlan_tag=False,
                 group=None, name="", summary='sending tunnel IP packets to '
                                              'test RSS functions'):
        """
        @src:        A tuple of System and interface name from which to send
        @dst:        A tuple of System and interface name which should receive
        @group:      Test group this test belongs to
        @name:       Name for this test instance
        @summary:    Optional one line summary for the test
        """
        RSStest_diff_l4_tuple.__init__(self, src, dst, promisc=promisc,
                                       ipv4=outer_ipv4,
                                       ipv4_opt=outer_ipv4_opt,
                                       ipv6_rt=outer_ipv6_rt,
                                       ipv6_hbh=outer_ipv6_hbh,
                                       l4_type=outer_l4_type,
                                       varies_src_addr=varies_src_addr,
                                       varies_dst_addr=varies_dst_addr,
                                       varies_src_port=varies_src_port,
                                       varies_dst_port=varies_dst_port,
                                       vlan_tag=outer_vlan_tag,
                                       group=group, name=name, summary=summary)
        self.inner_ipv4 = inner_ipv4
        self.inner_ipv4_opt = inner_ipv4_opt
        self.inner_ipv6_rt = inner_ipv6_rt
        self.inner_ipv6_hbh = inner_ipv6_hbh
        self.inner_l4_type = inner_l4_type
        self.tunnel_type = tunnel_type
        self.inner_vlan_tag = inner_vlan_tag
        self.inner_vlan_id = 20

        self.vxlan_id = None
        self.vxlan_mc = None
        self.dst_vxlan_intf = None
        self.src_vxlan_intf = None
        self.dst_vxlan_dport = None
        self.src_vxlan_dport = None
        self.src_inner_hwaddr = None
        self.dst_inner_hwaddr = None
        self.src_inner_addr = None
        self.dst_inner_addr = None
        self.src_inner_addr6 = None
        self.dst_inner_addr6 = None
        self.tunnel_number = 4
        if src[0]:
            self.vxlan_dport = get_vxlan_dport(self.src_addr, self.dst_addr)


    def get_ipv46_addr(self, channel):
        index = channel + 1
        src_if = self.src.netifs[self.src_ifn]
        dst_if = self.dst.netifs[self.dst_ifn]
        src_ip6 = self.get_ipv6(self.src, self.src_ifn, self.src_addr_v6)
        dst_ip6 = self.get_ipv6(self.dst, self.dst_ifn, self.dst_addr_v6)
        ipv4_re_str = '(\d{1,3}).(\d{1,3}.\d{1,3}.\d{1,3})'
        src_ipv4_octl = re.findall(ipv4_re_str, src_if.ip)
        if src_ipv4_octl:
            new_octl = (int(src_ipv4_octl[0][0]) + (10 * index)) % 255
            new_src_ipv4 = '%s.%s' % (new_octl, src_ipv4_octl[0][1])
        else:
            raise NtiGeneralError('Failed to create ipv4 for tunnel intf')
        dst_ipv4_octl = re.findall(ipv4_re_str, dst_if.ip)
        if dst_ipv4_octl:
            new_octl = (int(dst_ipv4_octl[0][0]) + (10 * index)) % 255
            new_dst_ipv4 = '%s.%s' % (new_octl, dst_ipv4_octl[0][1])
        else:
            raise NtiGeneralError('Failed to create ipv4 for tunnel intf')

        ipv6_re_str = '(^[a-f\d]{1,4})'
        src_ipv6_octl = re.findall(ipv6_re_str, src_ip6)
        if src_ipv6_octl:
            new_octl = (int(src_ipv6_octl[0], 16) + (100 * index)) % 65536
            octl_str = '%s' % hex(new_octl)
            new_src_ipv6 = re.sub(ipv6_re_str, octl_str[2:], src_ip6)
        else:
            raise NtiGeneralError('Failed to create ipv6 for tunnel intf')

        dst_ipv6_octl = re.findall(ipv6_re_str, dst_ip6)
        if dst_ipv6_octl:
            new_octl = (int(dst_ipv6_octl[0], 16) + (100 * index)) % 65536
            octl_str = '%s' % hex(new_octl)
            new_dst_ipv6 = re.sub(ipv6_re_str, octl_str[2:], dst_ip6)
        else:
            raise NtiGeneralError('Failed to create ipv6 for tunnel intf')

        return new_src_ipv4, new_dst_ipv4, new_src_ipv6, new_dst_ipv6

    def interface_cfg(self):
        """
        Configure interfaces, including RSS parameters
        """
        random.seed(os.getpid())
        self.vxlan_id = [42]
        self.vxlan_mc = ['239.1.1.1']
        self.dst_vxlan_intf = ['vxlan_0_%s' % self.dst_ifn]
        self.src_vxlan_intf = ['vxlan_0_%s' % self.src_ifn]
        self.dst_vxlan_dport = ['%s' % self.vxlan_dport]
        self.src_vxlan_dport = ['%s' % self.vxlan_dport]
        self.src_inner_hwaddr = [get_new_mac()]
        self.dst_inner_hwaddr = [get_new_mac()]
        new_src_ipv4, new_dst_ipv4, new_src_ipv6, new_dst_ipv6 = \
            self.get_ipv46_addr(0)
        self.src_inner_addr = [new_src_ipv4]
        self.dst_inner_addr = [new_dst_ipv4]
        self.src_inner_addr6 = [new_src_ipv6]
        self.dst_inner_addr6 = [new_dst_ipv6]
        self.tunnel_number = 4
        for i in range(1, self.tunnel_number):
            self.vxlan_id.append(42 + i)
            self.vxlan_mc.append('239.%s1.1.1' % i)
            self.dst_vxlan_intf.append('vxlan_%s_%s' % (i, self.dst_ifn))
            self.src_vxlan_intf.append('vxlan_%s_%s' % (i, self.src_ifn))
            self.dst_vxlan_dport.append('%s' % (self.vxlan_dport + i))
            self.src_vxlan_dport.append('%s' % (self.vxlan_dport + i))
            self.src_inner_hwaddr.append(get_new_mac())
            self.dst_inner_hwaddr.append(get_new_mac())
            new_src_ipv4, new_dst_ipv4, new_src_ipv6, new_dst_ipv6 = \
                self.get_ipv46_addr(i)
            self.src_inner_addr.append(new_src_ipv4)
            self.dst_inner_addr.append(new_dst_ipv4)
            self.src_inner_addr6.append(new_src_ipv6)
            self.dst_inner_addr6.append(new_dst_ipv6)

        # Add cfg later
        if self.inner_ipv4:
            if self.inner_l4_type == 'udp':
                protocol = 'udp4'
            else:
                protocol = 'tcp4'
        else:
            if self.inner_l4_type == 'udp':
                protocol = 'udp6'
            else:
                protocol = 'tcp6'
        self.dst.cmd("ethtool -N %s rx-flow-hash %s sdfn" % (self.dst_ifn,
                                                             protocol))

        # allmulti is needed by now to allow multicast,
        # will remove it after SB-186

        self.dst.cmd('ifconfig %s allmulti' % self.dst_ifn)

        if self.tunnel_type == 'vxlan':
            for i in range(0, self.tunnel_number):
                self.dst.cmd("ip link delete %s" % self.dst_vxlan_intf[i],
                             fail=False)
                self.src.cmd("ip link delete %s" % self.src_vxlan_intf[i],
                             fail=False)
                cmd = 'ip link add %s type vxlan id %d group %s dev %s ' \
                      'dstport %s' % \
                      (self.src_vxlan_intf[i], self.vxlan_id[i],
                       self.vxlan_mc[i], self.src_ifn, self.src_vxlan_dport[i])
                self.src.cmd(cmd)
                cmd = 'ip link add %s type vxlan id %d group %s dev %s ' \
                      'dstport %s' % \
                      (self.dst_vxlan_intf[i], self.vxlan_id[i],
                       self.vxlan_mc[i], self.dst_ifn, self.dst_vxlan_dport[i])
                self.dst.cmd(cmd)
                cmd = 'ip link set %s address %s' % (self.src_vxlan_intf[i],
                                                     self.src_inner_hwaddr[i])
                self.src.cmd(cmd)
                cmd = 'ip link set %s address %s' % (self.dst_vxlan_intf[i],
                                                     self.dst_inner_hwaddr[i])
                self.dst.cmd(cmd)

                if self.ipv4:
                    cmd = 'ip address add %s/24 dev %s' % \
                          (self.src_inner_addr[i], self.src_vxlan_intf[i])
                    self.src.cmd(cmd)
                    cmd = 'ip address add %s/24 dev %s' % \
                          (self.dst_inner_addr[i], self.dst_vxlan_intf[i])
                    self.dst.cmd(cmd)
                else:
                    cmd = 'ip -6 address add %s/64 dev %s' % \
                          (self.src_inner_addr6[i], self.src_vxlan_intf[i])
                    self.src.cmd(cmd)
                    cmd = 'ip -6 address add %s/64 dev %s' % \
                          (self.dst_inner_addr6[i], self.dst_vxlan_intf[i])
                    self.dst.cmd(cmd)

                cmd = 'ip link set up %s' % self.src_vxlan_intf[i]
                self.src.cmd(cmd)
                cmd = 'ip link set up %s' % self.dst_vxlan_intf[i]
                self.dst.cmd(cmd)

            for i in range(0, self.tunnel_number):
                # we ping the tunnel address first as to not begging
                # sending multicast traffic
                time.sleep(10)
                if self.ipv4:
                    cmd = 'ping -c 1 -I %s -i 1 %s -w 4' % \
                          (self.src_vxlan_intf[i], self.dst_inner_addr[i])
                    self.src.cmd(cmd)
                    cmd = 'ping -c 1 -I %s -i 1 %s -w 4' % \
                          (self.dst_vxlan_intf[i], self.src_inner_addr[i])
                    self.dst.cmd(cmd)
                else:
                    cmd = 'ping6 -c 1 -I %s -i 1 %s -w 4' % \
                          (self.src_vxlan_intf[i], self.dst_inner_addr6[i])
                    self.src.cmd(cmd)
                    cmd = 'ping6 -c 1 -I %s -i 1 %s -w 4' % \
                          (self.dst_vxlan_intf[i], self.src_inner_addr6[i])
                    self.dst.cmd(cmd)

            cmd = 'ifconfig -a'
            self.src.cmd(cmd)
            cmd = 'ifconfig -a'
            self.dst.cmd(cmd)
        return

    def send_packets(self, send_pcap):
        """
        Send packets by using TCPReplay

        """
        passed = True
        self.dst.cmd('ethtool -S %s | grep hw_rx_csum_inner_ok' % self.dst_ifn)
        for i in range(0, self.tunnel_number):
            pcapre = TCPReplay(self.src, self.src_vxlan_intf[i], send_pcap,
                               loop=self.num_pkts, pps=10000)
            attempt, sent = pcapre.run()
            if attempt == -1 or sent == -1:
                passed = False
            self.dst.cmd('ethtool -S %s | grep hw_rx_csum_inner_ok' %
                         self.dst_ifn)

        return passed

    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        remove vxlan interface before return the result object

        """
        # updating the total packets for RSS expected recv pckts calculation
        for i in range(0, self.num_rx_queue):
            self.rx_q_exp[i] *= self.tunnel_number

        res = RSStest_diff_l4_tuple.send_pckts_and_check_result(self, src_if,
                                                                dst_if,
                                                                send_pcap,
                                                                tmpdir)

        # will remove it after SB-186
        self.dst.cmd('ifconfig %s -allmulti' % self.dst_ifn)
        if self.tunnel_type == 'vxlan':
            for i in range(0, self.tunnel_number):
                self.src.cmd("ip link delete %s" % self.src_vxlan_intf[i],
                             fail=False)
                self.dst.cmd("ip link delete %s" % self.dst_vxlan_intf[i],
                             fail=False)

        return res

##############################################################################
# Iperf test
##############################################################################
class TunnelTest(Test):
    """Tunnel test"""

    # Information applicable to all subclasses
    _gen_info = """
    Using Tunnel to send packets
    """

    def __init__(self, src, dst, promisc=False, ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='udp', iperr=False,
                 l4err=False, dst_mac_type="tgt", src_mac_type="src",
                 vlan=False, vlan_id=100, num_pkts=1, iperf_time=1,
                 src_mtu=1500, dst_mtu=1500, tunnel_type='vxlan',
                 group=None, name="iperf", summary=None):
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
        self.tunnel_type = tunnel_type

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

        self.vxlan_id = 42
        self.dst_vxlan_intf = 'vxlan_%s' % self.dst_ifn
        self.src_vxlan_intf = 'vxlan_%s' % self.src_ifn
        self.vxlan_mc = '239.1.1.1'
        self.src_inner_hwaddr = None
        self.dst_inner_hwaddr = None
        self.src_inner_addr = None
        self.dst_inner_addr = None
        self.src_inner_addr6 = None
        self.dst_inner_addr6 = None
        if src[0]:
            self.vxlan_dport = get_vxlan_dport(self.src_addr, self.dst_addr)

        return

    def run(self):

        """Run the test
        @return:  A result object"""

        rc_passed = True
        rc_comment = ''

        try:
            self.set_up_tunnel(self.tunnel_type)
            self.src.refresh()
            self.dst.refresh()
            src_vxlan_if = self.src.netifs[self.src_vxlan_intf]
            dst_vxlan_if = self.dst.netifs[self.dst_vxlan_intf]
            self.src_inner_mac = src_vxlan_if.mac
            self.dst_inner_mac = dst_vxlan_if.mac
            self.src_inner_ip = src_vxlan_if.ip
            self.dst_inner_ip = dst_vxlan_if.ip

            cmd = 'ping -c 1 -w 2 %s' % self.src_inner_ip
            self.dst.cmd(cmd)
            cmd = 'ping -c 1 -w 2 %s' % self.dst_inner_ip
            self.src.cmd(cmd)
        finally:
            cmd = 'ip link delete %s' % self.src_vxlan_intf
            self.src.cmd(cmd, fail=False)
            cmd = 'ip link delete %s' % self.dst_vxlan_intf
            self.dst.cmd(cmd, fail=False)

        return NrtResult(name=self.name, testtype=self.__class__.__name__,
                         passed=rc_passed, comment=rc_comment)

    def set_up_tunnel(self, tunnel_type):

        if tunnel_type == 'vxlan':

            random.seed(os.getpid())
            self.src_inner_hwaddr = get_new_mac()
            self.dst_inner_hwaddr = get_new_mac()

            src_if = self.src.netifs[self.src_ifn]
            dst_if = self.dst.netifs[self.dst_ifn]
            src_ip6 = self.get_ipv6(self.src, self.src_ifn, self.src_addr_v6)
            dst_ip6 = self.get_ipv6(self.dst, self.dst_ifn, self.dst_addr_v6)
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

            self.src_inner_addr = new_src_ipv4 + '/24'
            self.dst_inner_addr = new_dst_ipv4 + '/24'
            self.src_inner_addr6 = new_src_ipv6 + '/64'
            self.dst_inner_addr6 = new_dst_ipv6 + '/64'

            cmd = 'ip link delete %s' % self.src_vxlan_intf
            self.src.cmd(cmd, fail=False)
            cmd = 'ip link delete %s' % self.dst_vxlan_intf
            self.dst.cmd(cmd, fail=False)
            cmd = 'ip link add %s type vxlan id %d group %s dev %s ' \
                  'dstport %s' % \
                  (self.src_vxlan_intf, self.vxlan_id, self.vxlan_mc,
                   self.src_ifn, self.vxlan_dport)
            self.src.cmd(cmd)
            cmd = 'ip link add %s type vxlan id %d group %s dev %s ' \
                  'dstport %s' % \
                  (self.dst_vxlan_intf, self.vxlan_id, self.vxlan_mc,
                   self.dst_ifn, self.vxlan_dport)
            self.dst.cmd(cmd)
            cmd = 'ip link set %s address %s' % (self.src_vxlan_intf,
                                                 self.src_inner_hwaddr)
            self.src.cmd(cmd)
            cmd = 'ip link set %s address %s' % (self.dst_vxlan_intf,
                                                 self.dst_inner_hwaddr)
            self.dst.cmd(cmd)
            cmd = 'ip address add %s dev %s' % (self.src_inner_addr,
                                                self.src_vxlan_intf)
            self.src.cmd(cmd)
            cmd = 'ip address add %s dev %s' % (self.dst_inner_addr,
                                                self.dst_vxlan_intf)
            self.dst.cmd(cmd)
            cmd = 'ip link set up %s' % self.src_vxlan_intf
            self.src.cmd(cmd)
            cmd = 'ip link set up %s' % self.dst_vxlan_intf
            self.dst.cmd(cmd)
            cmd = 'ifconfig -a'
            self.src.cmd(cmd)
            cmd = 'ifconfig -a'
            self.dst.cmd(cmd)

##############################################################################
# TX checksum offload test via tunnel
##############################################################################
class Csum_Tx_tunnel(Csum_Tx):
    """Test class for TX checksum offload test"""

    summary = "Tunnel TX checksum offload test"

    info = """
    This test send a number of packets from DUT to Host A using Iperf.
    Host receives packets and verifies them.
    """

    def __init__(self, src, dst, ipv4=True, l4_type='udp', group=None,
                 num_pkts=1, txcsum_offload=True, tunnel_type='vxlan',
                 name="ip", summary=None):

        Csum_Tx.__init__(self, src, dst, ipv4=ipv4, l4_type=l4_type,
                         num_pkts=num_pkts, vlan_offload=False, vlan=False,
                         txcsum_offload=txcsum_offload,
                         group=group, name=name, summary=summary
                         )

        self.tunnel_type = tunnel_type

        self.vxlan_id = 42
        self.dst_vxlan_intf = 'vxlan_%s' % self.dst_ifn
        self.src_vxlan_intf = 'vxlan_%s' % self.src_ifn
        self.vxlan_mc = '239.1.1.1'
        self.src_inner_hwaddr = None
        self.dst_inner_hwaddr = None
        self.src_inner_addr = None
        self.dst_inner_addr = None
        self.src_inner_addr6 = None
        self.dst_inner_addr6 = None
        self.src_inner_mac = None
        self.dst_inner_mac = None
        self.src_inner_ip = None
        self.dst_inner_ip = None
        if src[0]:
            self.vxlan_dport = get_vxlan_dport(self.src_addr, self.dst_addr)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        if self.tunnel_type == 'vxlan':
            self.vxlan_cfg()
        self.dst.cmd("ethtool -K %s rx off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s gso off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s gro off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s lro off" % self.dst_ifn)
        if not self.ipv4:
            self.dst.cmd("ifconfig %s allmulti" % self.dst_ifn)
            self.src.cmd("ifconfig %s allmulti" % self.src_ifn)

        if self.txcsum_offload:
            txcsum_status = 'on'
        else:
            txcsum_status = 'off'
        self.src.cmd("ethtool -K %s tx %s" % (self.src_ifn, txcsum_status))
        self.dst.cmd("ethtool -K %s rx on" % self.dst_ifn)

        self.src.cmd("ethtool -k %s" % self.src_ifn)
        self.dst.cmd("ethtool -k %s" % self.dst_ifn)

    def vxlan_cfg(self):
        """
        Create and configure vlan interfaces
        """
        random.seed(os.getpid())
        self.src_inner_hwaddr = get_new_mac()
        self.dst_inner_hwaddr = get_new_mac()

        src_if = self.src.netifs[self.src_ifn]
        dst_if = self.dst.netifs[self.dst_ifn]
        src_ip6 = self.get_ipv6(self.src, self.src_ifn, self.src_addr_v6)
        dst_ip6 = self.get_ipv6(self.dst, self.dst_ifn, self.dst_addr_v6)
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

        self.src_inner_addr = new_src_ipv4 + '/24'
        self.dst_inner_addr = new_dst_ipv4 + '/24'
        self.src_inner_addr6 = new_src_ipv6 + '/64'
        self.dst_inner_addr6 = new_dst_ipv6 + '/64'

        cmd = 'ip link delete %s' % self.src_vxlan_intf
        self.src.cmd(cmd, fail=False)
        cmd = 'ip link delete %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd, fail=False)
        cmd = 'ip link add %s type vxlan id %d group %s dev %s dstport %s' % \
              (self.src_vxlan_intf, self.vxlan_id, self.vxlan_mc,
               self.src_ifn, self.vxlan_dport)
        self.src.cmd(cmd)
        cmd = 'ip link add %s type vxlan id %d group %s dev %s dstport %s' % \
              (self.dst_vxlan_intf, self.vxlan_id, self.vxlan_mc,
               self.dst_ifn, self.vxlan_dport)
        self.dst.cmd(cmd)
        cmd = 'ip link set %s address %s' % (self.src_vxlan_intf,
                                             self.src_inner_hwaddr)
        self.src.cmd(cmd)
        cmd = 'ip link set %s address %s' % (self.dst_vxlan_intf,
                                             self.dst_inner_hwaddr)
        self.dst.cmd(cmd)
        if self.ipv4:
            cmd = 'ip address add %s dev %s' % (self.src_inner_addr,
                                                self.src_vxlan_intf)
            self.src.cmd(cmd)
            cmd = 'ip address add %s dev %s' % (self.dst_inner_addr,
                                                self.dst_vxlan_intf)
            self.dst.cmd(cmd)
        else:
            cmd = 'ip -6 address add %s dev %s' % (self.src_inner_addr6,
                                                   self.src_vxlan_intf)
            self.src.cmd(cmd)
            cmd = 'ip -6 address add %s dev %s' % (self.dst_inner_addr6,
                                                   self.dst_vxlan_intf)
            self.dst.cmd(cmd)
        cmd = 'ip link set up %s' % self.src_vxlan_intf
        self.src.cmd(cmd)
        cmd = 'ip link set up %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd)

        self.src.refresh()
        self.dst.refresh()
        src_vxlan_if = self.src.netifs[self.src_vxlan_intf]
        dst_vxlan_if = self.dst.netifs[self.dst_vxlan_intf]
        self.src_inner_mac = src_vxlan_if.mac
        self.dst_inner_mac = dst_vxlan_if.mac
        if self.ipv4:
            self.src_inner_ip = src_vxlan_if.ip
            self.dst_inner_ip = dst_vxlan_if.ip
        else:
            self.src_inner_ip = self.get_ipv6(self.src, self.src_vxlan_intf,
                                              self.src_inner_addr6)
            self.dst_inner_ip = self.get_ipv6(self.dst, self.dst_vxlan_intf,
                                              self.dst_inner_addr6)
        return


    def is_pingable(self):
        if self.tunnel_type == 'vxlan':
            dst_ip = self.dst_inner_ip
            src_ip = self.src_inner_ip
        else:
            dst_ip = self.dst_ip
            src_ip = self.src_ip

        if self.ipv4:
            cmd = 'ping -c 1 %s -w 4' % src_ip
        else:
            cmd = 'ping6 -c 1 %s -w 4' % src_ip
        ret_dst, _ = self.dst.cmd(cmd, fail=False)

        if self.ipv4:
            cmd = 'ping -c 1 %s -w 4' % dst_ip
        else:
            cmd = 'ping6 -c 1 %s -w 4' % dst_ip
        ret_src, _ = self.src.cmd(cmd, fail=False)

        if ret_dst or ret_src:
            return False
        else:
            return True

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
        if self.l4_type == 'udp':
            # Avoid IPv6 fragmentation
            self.iperf_client_arg_str += ' -l 800B'
            self.iperf_server_arg_str += ' -l 800B'

        self.iperf_client_arg_str += ' -t %s' % self.iperf_time

        if self.tunnel_type == 'vxlan':
            self.iperf_client_arg_str += ' -n 15K -B %s' % self.src_inner_ip
        else:
            self.iperf_client_arg_str += ' -n 15K'

        return

    def start_iperf_server(self):
        """
        Start the iperf server, using the command-line argument string
        configured in iperf_arg_str_cfg(). Use a timed_poll method to check if
        the iperf server has started properly.
        """
        if self.tunnel_type == 'vxlan':
            dst_ip = self.dst_inner_ip
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
        if self.tunnel_type == 'vxlan':
            dst_ip = self.dst_inner_ip
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
              (diff_dst_cntrs.ethtool['rx_packets'],
               diff_src_cntrs.ethtool['tx_packets'])
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

    def clean_up(self, passed=True):
        """
        Remove temporary directory and files
        """
        if self.tunnel_type == 'vxlan':
            cmd = 'ip link delete %s' % self.src_vxlan_intf
            self.src.cmd(cmd, fail=False)
            cmd = 'ip link delete %s' % self.dst_vxlan_intf
            self.dst.cmd(cmd, fail=False)
        # make sure iperf and tcpdump are stopped.
        self.dst.killall_w_pid(self.iperf_s_pid, signal="-9")
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

    def check_csum_cnt(self):

        csum_passed = True
        csum_comment = ''

        if (self.hw_tx_inner_csum != self.rx_pkts and self.txcsum_offload) or \
                (self.hw_tx_inner_csum and not self.txcsum_offload):
            csum_passed = False
            csum_comment = 'hw_tx_inner_csum (%s) != rx_pkts (%s) when ' \
                           'tx_csum offload is %s' % (self.hw_tx_inner_csum,
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
        if self.tunnel_type == 'vxlan':
            tunnel_layer = VXLAN
        else:
            tunnel_layer = None
        index = 0
        # the total expected hw_csum pkts
        self.rx_pkts = 0
        for pkt in self.rcv_pkts:
            ip_chksum = None
            l4_chksum = None
            rc_ip_chksum = None
            rc_l4_chksum = None
            outer_passed = True
            inner_passed = True

            if IP in pkt or IPv6 in pkt:
                # only check checksum of IP/IPv6 packet
                outer_passed, outer_comment = self.check_csum(pkt)
                if tunnel_layer in pkt:
                    inner_pkt = pkt[tunnel_layer][Ether]
                    if UDP in inner_pkt or TCP in inner_pkt:
                        # excludes ICMP and ICMPv6
                        self.rx_pkts += 1
                    if IP in inner_pkt or IPv6 in inner_pkt:
                        inner_passed, inner_comment = self.check_csum(inner_pkt)

            if not outer_passed:
                cr_passed = False
                cr_comment += 'Outer checksum error in pckt %d; ' % index
            if not inner_passed:
                cr_passed = False
                cr_comment += 'Inner checksum error in pckt %d; ' % index
            index += 1


        # find the stats line in iperf server output, such as the last line
        # in this xample:
        #------------------------------------------------------------
        #Server listening on UDP port 5001
        #Receiving 1470 byte datagrams
        #UDP buffer size:  208 KByte (default)
        #------------------------------------------------------------
        #[  3] local fc00:1::2 port 5001 connected with fc00:1::1 port 48836
        #[ ID] Interval       Transfer     Bandwidth        Jitter   Lost/Total
        #[  3]  0.0- 0.1 sec  15.0 KBytes  1.05 Mbits/sec   0.003 ms    0/   15
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

        csum_passed, csum_comment = self.check_csum_cnt()

        return (cr_passed and csum_passed), (cr_comment + csum_comment)

    def check_csum(self, pkt, check_zero=False):

        cr_passed = True
        cr_comment = ''
        ip_chksum = None
        rc_ip_chksum = None
        l4_chksum = None
        rc_l4_chksum = None

        if self.ipv4:
            ip_chksum = pkt[IP].chksum
            del pkt[IP].chksum
        if self.l4_type == 'udp' and UDP in pkt:
            l4_chksum = pkt[UDP].chksum
            del pkt[UDP].chksum
        elif self.l4_type == 'tcp' and TCP in pkt:
            l4_chksum = pkt[TCP].chksum
            del pkt[TCP].chksum

        rc_pkt = pkt.__class__(str(pkt))
        if self.ipv4:
            rc_ip_chksum = rc_pkt[IP].chksum
        if self.l4_type == 'udp' and UDP in pkt:
            rc_l4_chksum = rc_pkt[UDP].chksum
            if rc_l4_chksum == 0:
                rc_l4_chksum = 65535
        elif self.l4_type == 'tcp' and TCP in pkt:
            rc_l4_chksum = rc_pkt[TCP].chksum

        if ip_chksum != rc_ip_chksum:
            cr_passed = False
            cr_comment = 'Checksum error'
            LOG_sec("IP checksum error in packet:")
            if IP in pkt:
                LOG("IP_ID %d" % pkt[IP].id)
            LOG("ip_chksum, rc_ip_chksum")
            LOG('%s, %s' % (ip_chksum, rc_ip_chksum))
            LOG_endsec()

        if l4_chksum != rc_l4_chksum:
            if l4_chksum or check_zero:
                cr_passed = False
                cr_comment = 'Checksum error'
                LOG_sec("TCP/UDP checksum error in packet")
                if IP in pkt:
                    LOG("IP_ID %d" % pkt[IP].id)
                LOG("l4_chksum, rc_l4_chksum")
                LOG('%s, %s' % (l4_chksum, rc_l4_chksum))
                LOG_endsec()
        return cr_passed, cr_comment


##############################################################################
# TX checksum offload test via tunnel
##############################################################################
class LSO_tunnel(LSO_iperf):
    """Test class for TX checksum offload test"""

    summary = "Tunnel TX checksum offload test"

    info = """
    This test send a number of packets from DUT to Host A using Iperf.
    Host receives packets and verifies them.
    """

    def __init__(self, src, dst, ipv4=True, l4_type='tcp', group=None,
                 src_mtu=1500, dst_mtu=1500, num_pkts=1, txcsum_offload=True,
                 tunnel_type='vxlan', name="ip", summary=None):

        outer_ipv4 = None
        outer_l4_type = None
        if tunnel_type == 'vxlan':
            outer_ipv4 = True
            outer_l4_type = 'udp'
        else:
            raise NtiGeneralError('Currently only vxlan is supported. ')

        LSO_iperf.__init__(self, src, dst, ipv4=outer_ipv4,
                           l4_type=outer_l4_type,
                           num_pkts=num_pkts,
                           txcsum_offload=txcsum_offload,
                           group=group, name=name, summary=summary
                           )

        self.tunnel_type = tunnel_type
        self.inner_ipv4 = ipv4
        self.inner_l4_type = l4_type
        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu
        self.vxlan_id = 42
        self.dst_vxlan_intf = 'vxlan_%s' % self.dst_ifn
        self.src_vxlan_intf = 'vxlan_%s' % self.src_ifn
        self.vxlan_mc = '239.1.1.1'
        self.src_inner_hwaddr = None
        self.dst_inner_hwaddr = None
        self.src_inner_addr = None
        self.dst_inner_addr = None
        self.src_inner_addr6 = None
        self.dst_inner_addr6 = None
        self.src_inner_mac = None
        self.dst_inner_mac = None
        self.src_inner_ip = None
        self.dst_inner_ip = None
        if src[0]:
            self.vxlan_dport = get_vxlan_dport(self.src_addr, self.dst_addr)

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        self.dst.cmd("ifconfig %s mtu %s" % (self.dst_ifn, self.dst_mtu))
        self.src.cmd("ifconfig %s mtu %s" % (self.src_ifn, self.src_mtu))
        if self.tunnel_type == 'vxlan':
            self.vxlan_cfg()
        self.dst.cmd("ethtool -K %s rx off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s gso off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s gro off" % self.dst_ifn)
        self.dst.cmd("ethtool -K %s lro off" % self.dst_ifn)
        if not self.ipv4:
            self.dst.cmd("ifconfig %s allmulti" % self.dst_ifn)
            self.src.cmd("ifconfig %s allmulti" % self.src_ifn)

        if self.txcsum_offload:
            txcsum_status = 'on'
        else:
            txcsum_status = 'off'
        self.src.cmd("ethtool -K %s tx %s" % (self.src_ifn, txcsum_status))
        self.dst.cmd("ethtool -K %s rx on" % self.dst_ifn)

        self.src.cmd('ethtool -K %s tso on' % self.src_ifn)
        self.src.cmd('sysctl -w net.ipv4.tcp_min_tso_segs=2')

        self.src.cmd("ethtool -k %s" % self.src_ifn)
        self.dst.cmd("ethtool -k %s" % self.dst_ifn)
        return

    def vxlan_cfg(self):
        """
        Create and configure vlan interfaces
        """
        random.seed(os.getpid())
        self.src_inner_hwaddr = get_new_mac()
        self.dst_inner_hwaddr = get_new_mac()

        src_if = self.src.netifs[self.src_ifn]
        dst_if = self.dst.netifs[self.dst_ifn]
        src_ip6 = self.get_ipv6(self.src, self.src_ifn, self.src_addr_v6)
        dst_ip6 = self.get_ipv6(self.dst, self.dst_ifn, self.dst_addr_v6)
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

        self.src_inner_addr = new_src_ipv4 + '/24'
        self.dst_inner_addr = new_dst_ipv4 + '/24'
        self.src_inner_addr6 = new_src_ipv6 + '/64'
        self.dst_inner_addr6 = new_dst_ipv6 + '/64'

        cmd = 'ip link delete %s' % self.src_vxlan_intf
        self.src.cmd(cmd, fail=False)
        cmd = 'ip link delete %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd, fail=False)
        cmd = 'ip link add %s type vxlan id %d group %s dev %s dstport %s' % \
              (self.src_vxlan_intf, self.vxlan_id, self.vxlan_mc,
               self.src_ifn, self.vxlan_dport)
        self.src.cmd(cmd)
        cmd = 'ip link add %s type vxlan id %d group %s dev %s dstport %s' % \
              (self.dst_vxlan_intf, self.vxlan_id, self.vxlan_mc,
               self.dst_ifn, self.vxlan_dport)
        self.dst.cmd(cmd)
        cmd = 'ip link set %s address %s' % (self.src_vxlan_intf,
                                             self.src_inner_hwaddr)
        self.src.cmd(cmd)
        cmd = 'ip link set %s address %s' % (self.dst_vxlan_intf,
                                             self.dst_inner_hwaddr)
        self.dst.cmd(cmd)
        if self.inner_ipv4:
            cmd = 'ip address add %s dev %s' % (self.src_inner_addr,
                                                self.src_vxlan_intf)
            self.src.cmd(cmd)
            cmd = 'ip address add %s dev %s' % (self.dst_inner_addr,
                                                self.dst_vxlan_intf)
            self.dst.cmd(cmd)
        else:
            cmd = 'ip -6 address add %s dev %s' % (self.src_inner_addr6,
                                                   self.src_vxlan_intf)
            self.src.cmd(cmd)
            cmd = 'ip -6 address add %s dev %s' % (self.dst_inner_addr6,
                                                   self.dst_vxlan_intf)
            self.dst.cmd(cmd)
        cmd = 'ip link set up %s' % self.src_vxlan_intf
        self.src.cmd(cmd)
        cmd = 'ip link set up %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd)

        self.src.refresh()
        self.dst.refresh()
        src_vxlan_if = self.src.netifs[self.src_vxlan_intf]
        dst_vxlan_if = self.dst.netifs[self.dst_vxlan_intf]
        self.src_inner_mac = src_vxlan_if.mac
        self.dst_inner_mac = dst_vxlan_if.mac
        if self.inner_ipv4:
            self.src_inner_ip = src_vxlan_if.ip
            self.dst_inner_ip = dst_vxlan_if.ip
        else:
            self.src_inner_ip = self.get_ipv6(self.src, self.src_vxlan_intf,
                                              self.src_inner_addr6)
            self.dst_inner_ip = self.get_ipv6(self.dst, self.dst_vxlan_intf,
                                              self.dst_inner_addr6)
        return

    def is_pingable(self):
        if self.tunnel_type == 'vxlan':
            dst_ip = self.dst_inner_ip
            src_ip = self.src_inner_ip
        else:
            dst_ip = self.dst_ip
            src_ip = self.src_ip

        if self.inner_ipv4:
            cmd = 'ping -c 1 %s -w 4' % src_ip
        else:
            cmd = 'ping6 -c 1 %s -w 4' % src_ip
        ret_dst, _ = self.dst.cmd(cmd, fail=False)

        if self.inner_ipv4:
            cmd = 'ping -c 1 %s -w 4' % dst_ip
        else:
            cmd = 'ping6 -c 1 %s -w 4' % dst_ip
        ret_src, _ = self.src.cmd(cmd, fail=False)

        if ret_dst or ret_src:
            return False
        else:
            return True

    def iperf_arg_str_cfg(self):
        """
        Configure the command-line argument strings for both iperf server and
        iperf client
        """
        if not self.inner_ipv4:
            self.iperf_server_arg_str += ' -V'
            self.iperf_client_arg_str += ' -V'
        if self.inner_l4_type == 'udp':
            self.iperf_server_arg_str += ' -u'
            self.iperf_client_arg_str += ' -u'
        if self.inner_l4_type == 'udp' and not self.inner_ipv4:
            # Avoid IPv6 fragmentation
            self.iperf_client_arg_str += ' -l 1K'

        self.iperf_client_arg_str += ' -t %s' % self.iperf_time

        if self.tunnel_type == 'vxlan':
            self.iperf_client_arg_str += ' -n 320K -B %s' % self.src_inner_ip
        else:
            self.iperf_client_arg_str += ' -n 320K'

        return

    def start_iperf_server(self):
        """
        Start the iperf server, using the command-line argument string
        configured in iperf_arg_str_cfg(). Use a timed_poll method to check if
        the iperf server has started properly.
        """
        if self.tunnel_type == 'vxlan':
            dst_ip = self.dst_inner_ip
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
        if self.tunnel_type == 'vxlan':
            dst_ip = self.dst_inner_ip
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
              (diff_dst_cntrs.ethtool['rx_packets'],
               diff_src_cntrs.ethtool['tx_packets'],
               diff_src_cntrs.ethtool['tx_lso'])
        LOG(msg)
        LOG_endsec()
        if diff_src_cntrs.ethtool['tx_lso']:
            return
        else:
            raise NtiGeneralError(msg='ethtool counters did not increase as '
                                      'expected: tx_lso = %s' %
                                      diff_src_cntrs.ethtool['tx_lso'])

    def clean_up(self, passed=True):
        """
        Remove temporary directory and files
        """
        if self.tunnel_type == 'vxlan':
            cmd = 'ip link delete %s' % self.src_vxlan_intf
            self.src.cmd(cmd, fail=False)
            cmd = 'ip link delete %s' % self.dst_vxlan_intf
            self.dst.cmd(cmd, fail=False)
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
        return

    def check_result(self):
        """
        Recalculate the checksum and check if received checksums are the same
        as recalculated ones
        """

        cr_passed = True
        cr_comment = ''
        if self.tunnel_type == 'vxlan':
            tunnel_layer = VXLAN
        else:
            tunnel_layer = None
        index = 0
        for pkt in self.rcv_pkts:
            outer_passed = True
            inner_passed = True

            if IP in pkt or IPv6 in pkt:
                # only check checksum of IP/IPv6 packet=
                outer_passed, outer_comment = self.check_csum(pkt, self.ipv4,
                                                              self.l4_type)

                if tunnel_layer in pkt:
                    inner_pkt = pkt[tunnel_layer][Ether]
                    if IP in inner_pkt or IPv6 in inner_pkt:
                        inner_passed, inner_comment = self.check_csum(
                            inner_pkt, self.inner_ipv4, self.inner_l4_type)

            if not outer_passed:
                cr_passed = False
                cr_comment += 'Outer checksum error in pckt %d; ' % index
            if not inner_passed:
                cr_passed = False
                cr_comment += 'Inner checksum error in pckt %d; ' % index
            index += 1
        for pkt in self.rcv_pkts:
            inner_passed = True

            if tunnel_layer in pkt:
                inner_pkt = pkt[tunnel_layer][Ether]
                if IP in inner_pkt or IPv6 in inner_pkt:
                    inner_passed, inner_comment = self.check_csum(
                        inner_pkt, self.inner_ipv4, self.inner_l4_type)

            if not inner_passed:
                cr_passed = False
                cr_comment += 'Inner checksum error in pckt %d; ' % index
            index += 1

        if not cr_passed:
            LOG_sec("Inner checksum not correct")
            LOG(cr_comment)
            LOG_endsec()
            cr_comment = "Inner checksum not correct. "

        inner_rcv_pkts = PacketList()
        inner_snd_pkts = PacketList()
        for pkt in self.rcv_pkts:
            if tunnel_layer in pkt:
                inner_rcv_pkt = pkt[tunnel_layer][Ether]
                inner_rcv_pkts.append(inner_rcv_pkt)
        for pkt in self.snd_pkts:
            if tunnel_layer in pkt:
                inner_snd_pkt = pkt[tunnel_layer][Ether]
                inner_snd_pkts.append(inner_snd_pkt)

        LOG_sec("LSO packet check for outer layers")
        lso_passed, los_comment = LSO_iperf.check_pkts(self, self.rcv_pkts,
                                                       self.snd_pkts,
                                                       self.l4_type, self.ipv4)
        LOG_endsec()

        LOG_sec("LSO packet check for inner layers")
        inner_passed, inner_comment = LSO_iperf.check_pkts(self,
                                                           inner_rcv_pkts,
                                                           inner_snd_pkts,
                                                           self.inner_l4_type,
                                                           self.inner_ipv4)
        LOG_endsec()

        return (cr_passed and lso_passed and inner_passed), \
               (cr_comment + los_comment + inner_comment)

    def check_csum(self, raw_pkt, ipv4, l4_type, check_zero=False):

        cr_passed = True
        cr_comment = ''
        ip_chksum = None
        rc_ip_chksum = None
        l4_chksum = None
        rc_l4_chksum = None
        pkt = raw_pkt.__class__(str(raw_pkt))

        if ipv4:
            ip_chksum = pkt[IP].chksum
            del pkt[IP].chksum
        if l4_type == 'udp' and UDP in pkt:
            l4_chksum = pkt[UDP].chksum
            del pkt[UDP].chksum
        elif l4_type == 'tcp' and TCP in pkt:
            l4_chksum = pkt[TCP].chksum
            del pkt[TCP].chksum

        rc_pkt = pkt.__class__(str(pkt))
        if ipv4:
            rc_ip_chksum = rc_pkt[IP].chksum
        if l4_type == 'udp' and UDP in pkt:
            rc_l4_chksum = rc_pkt[UDP].chksum
        elif l4_type == 'tcp' and TCP in pkt:
            rc_l4_chksum = rc_pkt[TCP].chksum

        if ip_chksum != rc_ip_chksum:
            cr_passed = False
            cr_comment = 'Checksum error'
            LOG_sec("IP checksum error in packet:")
            if IP in pkt:
                LOG("IP_ID %d" % pkt[IP].id)
            LOG("ip_chksum, rc_ip_chksum")
            LOG('%s, %s' % (ip_chksum, rc_ip_chksum))
            LOG_endsec()

        if l4_chksum != rc_l4_chksum:
            if l4_chksum or check_zero:
                cr_passed = False
                cr_comment = 'Checksum error'
                LOG_sec("TCP/UDP checksum error in packet")
                if IP in pkt:
                    LOG("IP_ID %d" % pkt[IP].id)
                LOG("l4_chksum, rc_l4_chksum")
                LOG('%s, %s' % (l4_chksum, rc_l4_chksum))
                LOG_endsec()

        return cr_passed, cr_comment


##############################################################################
# IPv4 test
##############################################################################
class Csum_rx_tnl(UnitIP):
    """Wrapper class for sending IPv4 packets"""

    def __init__(self, src, dst, promisc=False, tunnel_type=None,
                 ipv4=True, ipv4_opt=False,
                 ipv6_rt=False, ipv6_hbh=False, l4_type='udp', iperr=False,
                 l4err=False, dst_mac_type="tgt", src_mac_type="src",
                 vlan=False, vlan_id=100, src_mtu=1500, dst_mtu=1500,
                 group=None, name="", summary=None):

        UnitIP.__init__(self, src, dst, ipv4=ipv4, ipv4_opt=ipv4_opt,
                        l4_type=l4_type, iperr=iperr,
                        ipv6_rt=ipv6_rt, ipv6_hbh=ipv6_hbh,
                        l4err=l4err, group=group,
                        dst_mac_type=dst_mac_type, src_mac_type=src_mac_type,
                        vlan=vlan, vlan_id=vlan_id,
                        name=name, summary=summary)

        self.tunnel_type = tunnel_type
        self.vxlan_id = 42
        if src[0]:
            self.vxlan_dport = get_vxlan_dport(self.src_addr, self.dst_addr)
        self.dst_vxlan_intf = 'vxlan_%s' % self.dst_ifn
        self.src_vxlan_intf = 'vxlan_%s' % self.src_ifn
        self.vxlan_mc = '239.1.1.1'
        self.src_inner_hwaddr = None
        self.dst_inner_hwaddr = None
        self.src_inner_addr = None
        self.dst_inner_addr = None
        self.src_inner_addr6 = None
        self.dst_inner_addr6 = None
        self.src_inner_mac = None
        self.dst_inner_mac = None
        self.src_inner_ip = None
        self.dst_inner_ip = None
        self.dst_tmp_dir = None
        self.dst_pcap_file = None
        self.src_outer_mac = None
        self.dst_outer_mac = None
        self.mtu_cfg_obj = NFPFlowNICMTU()
        self.src_mtu = src_mtu
        self.dst_mtu = dst_mtu

        # tunnel checksum related counters
        if self.tunnel_type == 'vxlan':
            if (not self.iperr) and (not self.l4err):
                if self.l4_type == 'udp' or self.l4_type == 'tcp':
                    # w/o any error, inner csum_ok only increases when
                    # receiving TCP/UDP
                    self.expect_et_cntr["hw_rx_csum_inner_ok"] = self.num_pkts
                # on vxlan tunnel check that all outer (IP and UDP) is ok
                self.expect_et_cntr["hw_rx_csum_ok"] = self.num_pkts

    def gen_pkts(self):
        """Generate packets based in UnitIP's gen_pkts()
        """

        pkt = UnitIP.gen_pkts(self)

        if self.src_mtu > (2048 + 200):
            # add a pseudo random payload of 2048B so that pkt does
            # not fit in CTM and make CSUM calculation use more than 1
            # ME code path (200B is a rough estimate of how long the
            # outer and inner headers can be)
            random.seed(1)
            payload = ''.join(random.choice(string.ascii_uppercase +\
                                            string.digits)
                              for _ in range(2048))
            pkt[Raw].load = payload

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


    def send_pckts_and_check_result(self, src_if, dst_if, send_pcap, tmpdir):
        """
        Send packets and check the result

        """
        # get stats of dst interface

        self.start_tcpdump_listening()
        return UnitIP.send_pckts_and_check_result(self, src_if, dst_if,
                                                  send_pcap, tmpdir)


    def send_packets(self, send_pcap):
        """
        Send packets by using TCPReplay

        """
        if self.tunnel_type == 'vxlan':
            src_ifn = self.src_vxlan_intf
        else:
            src_ifn = self.src_ifn

        pcapre = TCPReplay(self.src, src_ifn, send_pcap,
                           loop=self.num_pkts, pps=self.num_pkts)
        attempt, sent = pcapre.run()

        if attempt == -1 or sent == -1:
            return False
        else:
            return True

    def prepare_temp_dir(self):
        """
        prepare temporary directory and files for iperf server output and
        tcpdump output
        """
        self.dst_tmp_dir = self.dst.make_temp_dir()
        dst_pcap_fname = 'recv.pcap'
        self.dst_pcap_file = os.path.join(self.dst_tmp_dir, dst_pcap_fname)
        return

    def start_tcpdump_listening(self):
        """
        Start the tcpdump to listening to the interfaces.
        """
        self.prepare_temp_dir()
        if self.promisc:
            promisc_str = ''
        else:
            promisc_str = '-p'
        tcpd_pid_file = os.path.join(self.dst_tmp_dir, 'tcpd_tmp_pid.txt')
        cmd = "tcpdump %s -w %s -i %s  " \
              % (promisc_str, self.dst_pcap_file, self.dst_ifn, )
        ret, _ = self.dst.cmd_bg_pid_file(cmd, tcpd_pid_file, background=True)
        self.tcpdump_dst_pid = ret[1]
        timed_poll(30, self.dst.exists_host, self.dst_pcap_file, delay=1)
        return

    def interface_cfg(self):
        """
        Configure interfaces, including offload parameters
        """
        self.cfg_mtu()
        UnitIP.interface_cfg(self)

        # tunnel setup
        if self.tunnel_type == 'vxlan':

            self.vxlan_cfg()

    def vxlan_cfg(self):
        """
        Create and configure vlan interfaces
        """
        random.seed(os.getpid())
        self.src_inner_hwaddr = get_new_mac()
        self.dst_inner_hwaddr = get_new_mac()

        src_if = self.src.netifs[self.src_ifn]
        dst_if = self.dst.netifs[self.dst_ifn]
        src_ip6 = self.get_ipv6(self.src, self.src_ifn, self.src_addr_v6)
        dst_ip6 = self.get_ipv6(self.dst, self.dst_ifn, self.dst_addr_v6)
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

        self.src_inner_addr = new_src_ipv4 + '/24'
        self.dst_inner_addr = new_dst_ipv4 + '/24'
        self.src_inner_addr6 = new_src_ipv6 + '/64'
        self.dst_inner_addr6 = new_dst_ipv6 + '/64'

        cmd = 'ip link delete %s' % self.src_vxlan_intf
        self.src.cmd(cmd, fail=False)
        cmd = 'ip link add %s type vxlan id %d group %s dev %s dstport %s' % \
              (self.src_vxlan_intf, self.vxlan_id, self.vxlan_mc,
               self.src_ifn, self.vxlan_dport)
        self.src.cmd(cmd)
        cmd = 'ip link set %s address %s' % (self.src_vxlan_intf,
                                             self.src_inner_hwaddr)
        self.src.cmd(cmd)

        cmd = 'ip link delete %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd, fail=False)
        cmd = 'ip link add %s type vxlan id %d group %s dev %s dstport %s' % \
              (self.dst_vxlan_intf, self.vxlan_id, self.vxlan_mc,
               self.dst_ifn, self.vxlan_dport)
        self.dst.cmd(cmd)
        cmd = 'ip link set %s address %s' % (self.dst_vxlan_intf,
                                             self.dst_inner_hwaddr)
        self.dst.cmd(cmd)

        # The following cmd is needed for kernel 4.2
        cmd = 'ip link set up %s' % self.src_vxlan_intf
        self.src.cmd(cmd)
        cmd = 'ip link set up %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd)

        # update mac and ip info for gen_pkts (called in superclass UnitIP)
        self.src.refresh()
        self.dst.refresh()
        src_vxlan_if = self.src.netifs[self.src_vxlan_intf]
        dst_vxlan_if = self.dst.netifs[self.dst_vxlan_intf]
        self.src_outer_mac = self.src_mac
        self.dst_outer_mac = self.dst_mac
        self.src_mac = src_vxlan_if.mac
        self.dst_mac = dst_vxlan_if.mac
        if self.ipv4:
            self.src_ip = src_vxlan_if.ip
            self.dst_ip = dst_vxlan_if.ip
        else:
            self.src_ip = self.get_ipv6(self.src, self.src_vxlan_intf,
                                              self.src_inner_addr6)
            self.dst_ip = self.get_ipv6(self.dst, self.dst_vxlan_intf,
                                              self.dst_inner_addr6)

        self.dst.cmd("ifconfig %s allmulti" % self.dst_vxlan_intf)

        # flushing out ipv6 address in order to avoid vxlan pkts with
        # inner icmpv6.
        cmd = 'ip -6 address flush dev %s' % self.src_vxlan_intf
        self.src.cmd(cmd)
        cmd = 'ip -6 address flush dev %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd)
        return

    def check_result(self, if_stat_diff):
        """
        Check the result
        """
        time.sleep(1)
        self.dst.killall_w_pid(self.tcpdump_dst_pid)
        _, local_recv_pcap = mkstemp()
        self.dst.cp_from(self.dst_pcap_file, local_recv_pcap)
        rcv_pkts = rdpcap(local_recv_pcap)
        inner_rx_pkts = 0
        outer_rx_pkts = 0
        if self.tunnel_type == 'vxlan':
            tunnel_layer = VXLAN
        else:
            tunnel_layer = None

        for pkt in rcv_pkts:
            if (IP in pkt or IPv6 in pkt) and tunnel_layer in pkt \
                    and pkt[Ether].src == self.src_outer_mac:
                inner_pkt = pkt[tunnel_layer][Ether]
                if UDP in inner_pkt or TCP in inner_pkt:
                    # excludes ICMP and ICMPv6
                    inner_rx_pkts += 1
        # updating the expecting value in the cases that we do expect
        # correct csum
        if "hw_rx_csum_inner_ok" in self.expect_et_cntr and \
                self.expect_et_cntr["hw_rx_csum_inner_ok"]:
            self.expect_et_cntr["hw_rx_csum_inner_ok"] = inner_rx_pkts
        #if "hw_rx_csum_ok" in self.expect_et_cntr and \
        #        self.expect_et_cntr["hw_rx_csum_ok"]:
        #    self.expect_et_cntr["hw_rx_csum_ok"] = outer_rx_pkts
        if local_recv_pcap:
            os.remove(local_recv_pcap)
        res = UnitIP.check_result(self, if_stat_diff)
        if self.dst_tmp_dir and res.passed:
            self.dst.rm_dir(self.dst_tmp_dir)
        self.dst.cmd("ifconfig %s -allmulti" % self.dst_vxlan_intf)
        cmd = 'ip link delete %s' % self.src_vxlan_intf
        self.src.cmd(cmd, fail=False)
        cmd = 'ip link delete %s' % self.dst_vxlan_intf
        self.dst.cmd(cmd, fail=False)
        return res
