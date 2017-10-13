% Agilio Core NIC Release Notes

#Revision History

|Date        |Revision |Author          |Description                           |
|------------|:-------:|----------------|--------------------------------------|
| 2016-12-14 |   0.1   |P. Cascón       | Initial version                      |
| 2017-02-13 |   0.2   |D. Gunawardena  | Added note on TFTP constraints       |
| 2017-04-07 |   0.3   |D. Gunawardena  | Added notes on performance testing.  |
|            |         |                | Changed board names to AMDA names.   |

#Highlights

1. Performance improvement.

2. Support added for 8x10G platform and the 4x10G+1x40G platforms.

3. Added support for 2x25G platform

#Currently supported platform list:
  * nic_AMDA0099-0001_2x25 - 2x25G
  * nic_AMDA0099-0001_2x10 - 2x10G
  * nic_AMDA0097-0001_8x10 - 8x10G
  * nic_AMDA0097-0001_4x10_1x40 - 4x10G + 1x40G
  * nic_AMDA0097-0001_2x40 - 2x40G
  * nic_AMDA0096-0001_2x10 - 2x10G
  * nic_AMDA0081-0001_4x10 - 4x10G
  * nic_AMDA0081-0001_1x40 - 1x40G



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

#Performance testing guidelines

Specific performance measurements can be influenced by a large number of factors within the system, the network, and/or the application, therefore performance measurements must not be used as an acceptance test for determining whether a Netronome Agilio card is operating properly.  Netronome reserves the right to reject return requests for cards that do not meet arbitrary performance requirements.

##Performance testing best practices

###DO (recommendations) 

* Test with Agilio NICs of the same type back to back, ideally in 40G
mode (or the fastest support PHY speed)
* Use fast, multi core servers e.g Dell R730 10 cores+, latest BIOS
  updates
* Use netperf – multiple threads and pin IRQs to CPU cores
* Use 1460 byte MTU or 9 KByte jumbo frame sizes
* Run performance test direct from host OS
* Do unidirectional test to measure maxium single direction throughput
* Do bi-directional test to measure aggregate bandwidth saturation
* Pin interrupts to cores, stopping the irqbalance service, and
  forcing netperf to use cores not used by other VMs can generate much
  more consistent results
* Run performance test for at least 60s
* Use TCP for performance testing
* Monitor CPU utilisation on test client/server - should not be 100%
  [indicates host CPU is bottleneck] but also should not be very low
  [indicates test may not be using all the cores - check command line
  paramters of performance tool]
* Run multiple performance runs and measure the average and standard
  deviation of the performance results
* Check network statistics to see if packets are being dropped or
  lost.

###DO NOT (recommendations)
* Run performance test with packet sizes smaller than MTU size
* Run performance tests in a VM
* Run single threaded performance tests
* Run very short <60s performance test runs
* Use UDP for performance testing (lack of flow control results in
  drops)

##Example script/instructions for performance testing 
Example configuration:

 DUT A Agilio 40G NIC (client – 10.3.111.3); DUT B Agilio 40G NIC (server –
10.3.111.4)

On server B:

B> netserver

On client A:

On the client side, run multiple netperf threads (TCP stream) for 60
seconds:

A> export THREADS=10

A> service irqbalance stop

A> for i in `seq 1 $THREADS`; do netperf -H 10.3.111.4 -t TCP_STREAM
-l 60 -c -P0 & done;

Look at results reported on server A. Remember to re-enable IRQ
balancing service once done (service irqbalance start).
