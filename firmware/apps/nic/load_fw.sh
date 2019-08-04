#!/bin/bash

# Copyright (c) 2016 Netronome Systems, Inc. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

shorten_path() {
    basepath=$(pwd)
    fullpath=$(cd $1; pwd)
    echo ".`echo $fullpath | sed "s|$basepath||"`"
}

on_err () {
	echo "Error on line $1: err($2)"
	exit 1
}

trap 'on_err $LINENO $?' ERR

# Work out where the BSP is installed.
TMP=`which nfp-cpp`
if [ -n "$TMP" ]
then
    TMP=`dirname $TMP`
    NFP_BSP_DIR=`dirname $TMP`
else
    NFP_BSP_DIR=${NFP_SDK_DIR:-/opt/netronome}
    export PATH=${NFP_BSP_DIR}/bin:$PATH
    export LD_LIBRARY_PATH=${NFP_BSP_DIR}/lib:$LD_LIBRARY_PATH
fi

if [ ! -z $TEST ]; then
    CONFIG_DIR=${CONFIG_DIR:-$(dirname $0)/../../${TEST}/scripts}
    CONFIG_DIR=${CONFIG_DIR}
    UIO_DIR=${UIO_DIR:-${CONFIG_DIR}/../../${TEST}/dpdk}
    NETDEV_DIR=${NETDEV_DIR:-${CONFIG_DIR}/../../${TEST}/netdev}
else
    CONFIG_DIR=${CONFIG_DIR:-$(dirname $0)}
    CONFIG_DIR=$(shorten_path ${CONFIG_DIR})
    UIO_DIR=${UIO_DIR:-${CONFIG_DIR}/../dpdk}
    NETDEV_DIR=${NETDEV_DIR:-${CONFIG_DIR}/../netdev}
fi

LOAD_NETDEV=${LOAD_NETDEV:-}
INITIALISE_MAC=${INITIALISE_MAC:-}
BASE_SRC_MAC=${BASE_MAC:-"00:15:4d:00:00:"}
BASE_DST_MAC=${BASE_MAC:-"00:15:4d:10:00:"}
USE_SRC_MAC=${USE_SRC_MAC:-1}
USE_DST_MAC=${USE_DST_MAC:-0}
NUM_PCI1_VF=${NUM_PCI1_VF:-0}
BSP_DRIVERS=${BSP_DRIVERS:-0}
DEVICE=

# look for starfighter (19ee:6000) else look for hydrogen card (19ee:4000)
if lspci -d 19ee:6000 | grep Netronome > /dev/null 2>&1
then
    PCI0_ID=`setpci -v -d 19ee:6000 ECAP_DSN+5.B  | grep "= 10" | \
        cut -f 1 -d " " | sed -e "s/^0000://" -e "s/:00.0$//"`
    PCI1_ID=`setpci -v -d 19ee:6000 ECAP_DSN+5.B  | grep "= 11" | \
        cut -f 1 -d " " | sed -e "s/^0000://" -e "s/:00.0$//"`
    DEVICE=SF
elif lspci -d 19ee:4000 | grep Netronome > /dev/null 2>&1
then
    PCI0_ID=`setpci -v -d 19ee:4000 ECAP_DSN+5.B  | grep "= 10" | \
         cut -f 1 -d " " | sed -e "s/^0000://" -e "s/:00.0$//"`
    DEVICE=HYDROGEN
else
    echo "Can't find the NFP on the PCI bus"
fi
PF0_SYS="/sys/bus/pci/devices/0000:${PCI0_ID}:00.0"
PF1_SYS="/sys/bus/pci/devices/0000:${PCI1_ID}:00.0"

Usage() {
    echo -e "Usage: $0 <num VFs> <path_to_fw> [options]"
    echo -e ""
    echo -e "Options"
    echo -e "\t-M\t\tInitialise MAC, Using SRC MAC set (00:15:4d:00:00:)"
    echo -e "\t-N\t\tLoad nfp_netvf (default nfp_uio)"
    echo -e "\t-v\t\tNumber PCIe1 VFs (default ${NUM_PCI1_VF})"
    echo -e "\t-B\t\tLoad drivers installed by BSP"
    echo -e "\t-D\t\tUsing DST MAC set (00:15:4d:10:00:) "
    echo
    exit 1
}

start() {

    if [ "$LOAD_NETDEV" == "1" ];then
        DRIVER_PATH=$NETDEV_DIR
        DRIVER="nfp_netvf"
        UNUSED_DRIVER="nfp_uio"
    else
        DRIVER_PATH=$UIO_DIR
        DRIVER="nfp_uio"
        UNUSED_DRIVER="nfp_netvf"
    fi

    echo "Starting FW:"
    # Load firmware
    echo -n " - Loading and starting FW..."
    nfp-nffw load ${FW}
    echo "done"

    if [ "$LOAD_NETDEV"!="1" ];then
    echo -n " - Create hugeTLB FS if needed..."
    # Make sure that nr_hugepages is not 0. The original script assumed 2MB
    # huge pages and allocated 1024 (2GB worth). Let's allocate 2GB worth but
    # read the system default huge page size from /proc/meminfo instead.
    HUGEPAGESIZE="`awk '/^Hugepagesize:/ {print $2$3}' /proc/meminfo`"
    test -n "$HUGEPAGESIZE" || {
        echo 'Failed to determine the default huge page size.' >&2
        exit 1
    }
    let NR_HUGEPAGES=1024*2048/${HUGEPAGESIZE%kB} || exit
    NR_HUGEPAGES_FNAME="/sys/kernel/mm/hugepages/hugepages-$HUGEPAGESIZE/nr_hugepages"
    if [ "`cat $NR_HUGEPAGES_FNAME`" -eq 0 ]; then
        echo "$NR_HUGEPAGES" >"$NR_HUGEPAGES_FNAME"
    fi
    # Now ensure that hugetlbfs is mounted somewhere.
    if ! grep -wq hugetlbfs /proc/mounts; then
        mkdir -p /mnt/hugetlbfs
        mount -t hugetlbfs none /mnt/hugetlbfs
    fi
    echo "done"
    fi

    # Load firmware
    echo -n " - Loading UIO and ${DRIVER} modules..."
    modprobe uio
    if [ "$BSP_DRIVERS" == "1" ]
    then
        modprobe ${DRIVER}
    else
        insmod ${DRIVER_PATH}/${DRIVER}.ko
    fi
    # insmod ${DRIVER_PATH}/${DRIVER}.ko
    # Register vendor/product ID for nfp_uio in particular...
    echo "19ee 6003" > /sys/bus/pci/drivers/${DRIVER}/new_id || :
    echo "done"

    echo -n " - Emumerating $NUM_PCI0_VF VFs for PCI0..."
    echo $NUM_PCI0_VF > ${PF0_SYS}/sriov_numvfs
    sleep 0.5
    echo "done"

    echo -n " - Make sure VFs bound to ${DRIVER}..."
    for ((i=0;i<$NUM_PCI0_VF;i++));do
        (echo -n "0000:${PCI0_ID}:08.${i}" > \
            /sys/bus/pci/drivers/${UNUSED_DRIVER}/unbind || true) 2>/dev/null
        (echo -n "0000:${PCI0_ID}:08.${i}" > \
            /sys/bus/pci/drivers/${DRIVER}/bind || true) 2>/dev/null
    done
    sleep 0.5
    echo "done"

    if [ $NUM_PCI1_VF -gt 0 ]; then
    echo -n " - Emumerating $NUM_PCI1_VF VFs for PCI1..."
    echo $NUM_PCI1_VF > ${PF1_SYS}/sriov_numvfs
    sleep 0.5
    echo "done"

    echo -n " - Make sure VFs bound to ${DRIVER}..."
    for ((i=0;i<$NUM_PCI1_VF;i++));do
        (echo -n "0000:${PCI1_ID}:08.${i}" > \
            /sys/bus/pci/drivers/${UNUSED_DRIVER}/unbind || true) 2>/dev/null
        (echo -n "0000:${PCI1_ID}:08.${i}" > \
            /sys/bus/pci/drivers/${DRIVER}/bind || true) 2>/dev/null
    done
    sleep 0.5
    echo "done"
    fi

    # NBI MAC init
    if [[ "$INITIALISE_MAC" == "1" && $DEVICE == "SF" ]];then
    echo -n " - Init MAC for SF..."
    nfp-macinit \
        -0 ${CONFIG_DIR}/sf1-2x40GE.json \
        -p ${NFP_BSP_DIR}/share/nbi/nfp_nbi_phy_tuning_AMDA0058R1.json -m0 \
        &> /dev/null || exit 1
    nfp -m mac -e set port rx 0 0 enable &> /dev/null || exit 1
    nfp -m mac -e set port rx 0 4 enable &> /dev/null || exit 1
    echo "done"
    elif [[ "$INITIALISE_MAC" == "1" && $DEVICE == "HYDROGEN" ]];then
    echo -n " - Init MAC for HYDROGEN..."
    nfp-macinit \
        -0 ${CONFIG_DIR}/hy-1x40GE.json \
        -p ${NFP_BSP_DIR}/share/nbi/nfp_nbi_phy_tuning_AMDA0081R1.json -m0 \
        &> /dev/null || exit 1
    nfp -m mac -e set port rx 0 0 enable &> /dev/null || exit 1
    echo "done"
    fi

    # Set MAC and netdev name
    if [ "$USE_SRC_MAC" == "1" ]; then
    BASE_MAC=$BASE_SRC_MAC
    fi
    if [ "$USE_DST_MAC" == "1" ]; then
    BASE_MAC=$BASE_DST_MAC
    fi
    if [ "$LOAD_NETDEV" == "1" ];then
    echo -n " - Configure MAC addr and name..."
    sleep 0.5
    VF=0
    ls /sys/bus/pci/devices/0000\:${PCI0_ID}*/net | grep -o eth[[:digit:]]* | \
    while read eth
    do
        MAC=`printf "%s%02x" $BASE_MAC $VF`
        eval "ip l s dev $eth address $MAC"
        eval "ip link set dev $eth name vf${VF}"
        let VF++
    done
    echo "done"
    fi

    echo ""
}

stop() {
    echo "Stopping FW:"

    echo -n " - Removing VFs..."
    echo 0 > ${PF0_SYS}/sriov_numvfs
    sleep 0.5
    echo "done"

    echo -n " - Remove net_dev and load nfp driver..."
    (rmmod nfp_netvf || true) 2>/dev/null
    (rmmod nfp_uio || true) 2>/dev/null
    (rmmod nfp_net || true) 2>/dev/null
    (rmmod nfp || true) 2>/dev/null
    sleep 1
    if [ -f ./nfp.ko ]
    then
        insmod ./nfp.ko
    else
        modprobe nfp
    fi
    echo "done"

    echo -n " - Unloading FW..."
    nfp-nffw unload
    echo "done"

    # Reset Islands to restore NBI events and packet engine work queues
    echo -n " - Reset Islands..."
    nfp-power nbi=reset nbi=on
    nfp-power fpc=reset fpc=on
    nfp-power imu=reset imu=on
    nfp-power ila=reset ila=on
    nfp-power crp=reset crp=on
    nfp-power pci_0.meg0=reset pci_0.meg0=on
    nfp-power pci_0.meg1=reset pci_0.meg1=on
    nfp-power pci_1.meg0=reset pci_1.meg0=on
    nfp-power pci_1.meg1=reset pci_1.meg1=on
    nfp-power pci_2.meg0=reset pci_2.meg0=on
    nfp-power pci_2.meg1=reset pci_2.meg1=on
    nfp-power pci_3.meg0=reset pci_3.meg0=on
    nfp-power pci_3.meg1=reset pci_3.meg1=on
    echo "done"

    echo ""
}

## Main
if [ $# -lt 2 ]; then
    Usage
fi

NUM_PCI0_VF=$1
FW=$2

if [ ! -f $FW ]; then
    echo "$FW does not exist"
    exit 1
fi

# don't pass the <num VFs> <path_to_fw> argument to getopts
shift
shift

while getopts "hMNvBD-:" opt; do
    case $opt in
        h)
            Usage
        ;;
        M)
            INITIALISE_MAC=1
        ;;
        N)
            LOAD_NETDEV=1
        ;;
        v)
            NUM_PCI1_VF=1
        ;;
        B)
            BSP_DRIVERS=1
        ;;
        D)
            USE_DST_MAC=1
            USE_SRC_MAC=0
        ;;
        \?)
            echo "Error: Invalid option -$OPTARG"
            exit 1
        ;;
    esac
done

echo ""
echo "== Loading FW For $TEST =="
echo ""
stop
start

exit 0
