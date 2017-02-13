% Agilio Core NIC Release Notes

#Revision History

|Date        |Revision |Author          |Description                           |
|------------|:-------:|----------------|--------------------------------------|
| 2016-12-14 |   0.1   |P. Cascón       | Initial version                      |
| 2017-02-13 |   0.2   |D. Gunawardena  | Added note on TFTP constraints       |

#Highlights

1. Performance improvement.

2. Support added for Beryllium 8x10 and the 4x10+1x40 platforms.

3. Added support for Carbon 2x25

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
