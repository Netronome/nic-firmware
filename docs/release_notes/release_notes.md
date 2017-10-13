% Agilio Core NIC Release Notes

#Revision History

|Date        |Revision |Author          |Description                           |
|------------|:-------:|----------------|--------------------------------------|
| 2016-12-14 |   0.1   |P. Cascón       | Initial version                      |
| 2017-02-13 |   0.2   |D. Gunawardena  | Added note on TFTP constraints       |
| 2017-10-10 |   0.3   |V. Vasu         | Added Agilio CoreNIC features        |

#Features

  * Support standard Linux networking tools with netdev interfaces associated
    with each of the physical interfaces of the card.
  * Support Large Segmentation Offload (LSO).
  * Support RX and TX checksum offload for L3 (IPv4) and L4 (TCP and UDP over
    IPv4/v6). Also for inner headers on VXLAN tunnels.
  * Support configuration of NIC virtual functions (VFs), up to 48 VFs.
  * SR-IOV interfaces directly into VMs.
  * Support the ability to use a netdev on Netronome VFs in the host or guest to
    feed traffic to them based on MAC addresses and or VLAN tags.
  * Provide a stateless load balancer to achieve hash-based load balancing
    across queues via RSS.
  * Support RSS for L3 (IPv4) and L4 (TCP and UDP over IPv4/v6). Also for inner
    headers on VXLAN tunnels.
  * Support DPDK (PF and VF PMD) in version 17.05 and higher.

#Currently supported platform list:
  * Hydrogen 1x40
  * Hydrogen 4x10
  * Lithium 2x10
  * Beryllium 2x40
  * Beryllium 4x10+1x40
  * Beryllium 8x10
  * Carbon 2x10
  * Carbon 2x25

#TFTP constraints

   The firmware assumes that any TFTP server used for TFTP boot of the
NIC conforms to RFC 894 - A Standard for the Transmission of IP
Datagrams over Ethernet Networks States:

> The minimum length of the data field of a packet sent over an
Ethernet is 46 octets. If necessary, the data field should be padded
(with octets of zero) to meet the Ethernet minimum frame size. This
padding is not part of the IP packet and is not included in the total
length field of the IP header."

   Failure for the TFTP server to conform to RFC 894 will result in TFTP
boot failure owing to incorrect checksum computation for the UDP
frames.
