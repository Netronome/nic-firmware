##
## Copyright (C) 2014-2015,  Netronome Systems, Inc.  All rights reserved.
##
"""
List of ethtool counters.
 
In tests classes such as UnitIP, the whole list of ethtool counters can be
put into 3 groups: A) counters that we expect to have an exact increment after
the test; B) counters that we expect zero increment after the test; and C)
counters that we don't care about their increment after the test. 

We define the list of the don't-care counters in this file.
The lists of the other two kinds of counters can also be defined here
if necessary.
"""

UnitIP_dont_care_cntrs = [
    "dev_tx_bytes",
    "dev_tx_bc_bytes",
    "dev_tx_mc_bytes",
    "dev_tx_pkts",
    "dev_tx_bc_pkts",
    "dev_tx_mc_pkts",
    "dev_rx_uc_bytes",
    "dev_tx_uc_bytes",
    "hw_tx_csum",
    "dev_rx_bytes",
    "dev_rx_mc_bytes",
    "dev_rx_bc_bytes",
    "dev_rx_uc_bytes",
    "dev_rx_mc_pkts",
    "dev_rx_bc_pkts",
    "dev_rx_pkts",
    "dev_rx_discards",
    #"rvec_0_rx_pkts",
    #"rvec_0_tx_pkts",
    #"rvec_0_tx_busy",
    #"rvec_1_tx_pkts",
    #"rvec_1_rx_pkts",
    #"rvec_1_tx_busy",
    #"rvec_2_tx_pkts",
    #"rvec_2_rx_pkts",
    #"rvec_2_tx_busy",
    #"rvec_3_tx_pkts",
    #"rvec_3_rx_pkts",
    #"rvec_3_tx_busy",
    #"rvec_4_tx_pkts",
    #"rvec_4_rx_pkts",
    #"rvec_4_tx_busy",
    #"rvec_5_tx_pkts",
    #"rvec_5_rx_pkts",
    #"rvec_5_tx_busy",
    #"rvec_6_tx_pkts",
    #"rvec_6_rx_pkts",
    #"rvec_6_tx_busy",
    #"rvec_7_tx_pkts",
    #"rvec_7_rx_pkts",
    #"rvec_7_tx_busy",
    #"txq_0_pkts",
    #"txq_0_bytes",
    #"txq_1_pkts",
    #"txq_1_bytes",
    #"txq_2_pkts",
    #"txq_2_bytes",
    #"txq_3_pkts",
    #"txq_3_bytes",
    #"txq_4_pkts",
    #"txq_4_bytes",
    #"txq_5_pkts",
    #"txq_5_bytes",
    #"txq_6_pkts",
    #"txq_6_bytes",
    #"txq_7_pkts",
    #"txq_7_bytes",
    #"rxq_0_pkts",
    #"rxq_0_bytes",
    #"rxq_1_pkts",
    #"rxq_1_bytes",
    #"rxq_2_pkts",
    #"rxq_2_bytes",
    #"rxq_3_pkts",
    #"rxq_3_bytes",
    #"rxq_4_pkts",
    #"rxq_4_bytes",
    #"rxq_5_pkts",
    #"rxq_5_bytes",
    #"rxq_6_pkts",
    #"rxq_6_bytes",
    #"rxq_7_pkts",
    #"rxq_7_bytes"
]

# the list of ethtool counters that we need to check in the ring size iperf
# tests
RingSize_ethtool_tx_cntr = [
    "txq_0_pkts",
    "txq_1_pkts",
    "txq_2_pkts",
    "txq_3_pkts",
    "txq_4_pkts",
    "txq_5_pkts",
    "txq_6_pkts",
    "txq_7_pkts"
]

RingSize_ethtool_rx_cntr = [
    "rxq_0_pkts",
    "rxq_1_pkts",
    "rxq_2_pkts",
    "rxq_3_pkts",
    "rxq_4_pkts",
    "rxq_5_pkts",
    "rxq_6_pkts",
    "rxq_7_pkts"
]
