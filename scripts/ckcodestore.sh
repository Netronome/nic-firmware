#!/bin/sh

# Copyright (c) 2017 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

report() {
    # $1 = firmware name
    # $2 = # of instructions
    # $3 = last count file name
    if [ -f $3 ] && grep -q $1 $3 ; then
        OCNT=`grep "^$1 " $3 | awk '{print $2}'`
        if [ $OCNT -gt $2 ] ; then
            printf "%-30s %d instructions (-%d since last check)\n" $1 $2 $(($OCNT - $2))
        else
            printf "%-30s %d instructions (+%d since last check)\n" $1 $2 $(($2 - $OCNT))
        fi
    else
        printf "%-30s %d instructions\n" $1 $2
    fi
}

report_all() {
    # $1 = last count file name
    # $2 = list file name
    MAX=0
    for d in firmware/build/nic_AMDA*
    do
        [ ! -d $d ] && continue
        FWN=`basename $d`
        F=$d/$2
        NI=`grep '^\.[0-9]' $F | tail -1 | sed -e 's/\.\([0-9][0-9]*\).*/\1/'`
        NI=`expr $NI \\+ 1`
        report $FWN $NI $1
        if [ $NI -gt $MAX ] ; then
            MAX=$NI
        fi
    done
    echo "--"
    report Maximum $MAX $1
}

report_all firmware/build/cknic_datapath_icount-last.txt datapath.list > /tmp/cknic_datapath-report.$$
printf "\ndatapath.list code store report:\n\n"
cat /tmp/cknic_datapath-report.$$

if [ $# -gt 0 -a "$1" = "-s" ] ; then
    mv /tmp/cknic_datapath-report.$$ firmware/build/cknic_datapath_icount-last.txt
else
    if [ $# -gt 0 -a "$1" = "-c" ] ; then
        rm -f firmware/build/cknic_datapath_icount-last.txt
    fi
    rm -f /tmp/cknic_datapath-report.$$
fi
printf "===============================\n"

report_all firmware/build/cknic_app_master_icount-last.txt nfd_app_master/nfd_app_master.list> /tmp/cknic_app_master-report.$$
printf "\nnfd_app_master.list code store report:\n\n"
cat /tmp/cknic_app_master-report.$$

if [ $# -gt 0 -a "$1" = "-s" ] ; then
    mv /tmp/cknic_app_master-report.$$ firmware/build/cknic_app_master_icount-last.txt
else
    if [ $# -gt 0 -a "$1" = "-c" ] ; then
        rm -f firmware/build/cknic_app_master_icount-last.txt
    fi
    rm -f /tmp/cknic_app_master-report.$$
fi
printf "===============================\n"
