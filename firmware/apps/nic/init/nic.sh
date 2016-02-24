#!/bin/bash

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

if [ $# -lt 2 ]
then
    FWFILE=./ng-nfd_nic.fw
else
    FWFILE=$2
fi

if [ -z $NFP ]
then
    NFP=0
fi


on_err () {
	echo "Error on line $1: err($2)"
	exit 1
}

trap 'on_err $LINENO $?' ERR


Usage() {
        echo
        echo -e "\t ****** Error: $1 ****** "
        echo "Usage: $0 start | stop | restart [mefw] >"
        echo -e "\tstart   : Load ME fw and load driver"
        echo -e "\tstop    : Unload drivers and ME fw"
        echo -e "\trestart : stop & start"
        echo
        exit 1
}

case "$1" in
    start)
        echo -n " - Remove net_dev and load nfp driver with reset..."
        (rmmod nfp_netvf || true) 2>/dev/null
        (rmmod nfp_net || true) 2>/dev/null
        (rmmod nfp || true) 2>/dev/null
        sleep 1
        if [ -f ./nfp.ko ]
        then
            insmod ./nfp.ko nfp_reset=1
        else
            modprobe nfp nfp_reset=1
        fi
        echo "done"

        echo "Starting FW:"

        # Load firmware
        echo -n " - Loading and starting FW..."
        nfp-nffw load -n $NFP $FWFILE
        echo "done"

        # Load driver
        echo -n " - Loading nfp driver..."
        (rmmod nfp || true) 2>/dev/null
        sleep 1
        # load vxlan if not loaded (needed by nfp_net
        modprobe vxlan
        if [ -f ./nfp_net.ko ]
        then
            insmod ./nfp_net.ko
        else
            modprobe nfp_net
        fi
        echo "done"

        echo ""
        ;;

    reload|restart)
        $0 stop
        sleep 2
        $0 start $2
        ;;

    stop)
        echo "Stopping FW:"

        echo -n " - Remove net_dev and load nfp driver with reset..."
        (rmmod nfp_netvf || true) 2>/dev/null
        (rmmod nfp_net || true) 2>/dev/null
        (rmmod nfp || true) 2>/dev/null
        sleep 1
        if [ -f ./nfp.ko ]
        then
            insmod ./nfp.ko nfp_reset=1
        else
            modprobe nfp nfp_reset=1
        fi
        echo "done"

        echo ""
        ;;
    *)
        Usage "Invalid option"
esac
exit 0
