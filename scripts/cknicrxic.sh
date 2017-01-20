#!/bin/sh

report() {
	# $1 = firmware name
	# $2 = # of instructions
	if [ -f ../deb/tmp/ns-agilio-core-nic/firmware/nfp-nic/firmware/build/nic_rx_icount-last.txt ] && grep -q $1 ../deb/tmp/ns-agilio-core-nic/firmware/nfp-nic/firmware/build/nic_rx_icount-last.txt ; then
		OCNT=`grep "^$1 " ../deb/tmp/ns-agilio-core-nic/firmware/nfp-nic/firmware/build/nic_rx_icount-last.txt | awk '{print $2}'`
		if [ $OCNT -gt $2 ] ; then
			printf "%-30s %d instructions (-%d)\n" $1 $2 $(($OCNT - $2))
		else
			printf "%-30s %d instructions (+%d)\n" $1 $2 $(($2 - $OCNT))
		fi
	else
		printf "%-30s %d instructions\n" $1 $2
	fi
}

report_all() {
	MAX=0
	for d in ../deb/tmp/ns-agilio-core-nic/firmware/nfp-nic/firmware/build/ns_nic*
	do
		[ ! -d $d ] && continue
		FWN=`basename $d`
		F=$d/nic_rx/nic_rx.list
		NI=`grep '^\.[0-9]' $F | tail -1 | sed -e 's/\.\([0-9][0-9]*\).*/\1/'`
		NI=`expr $NI \\+ 1`
		report $FWN $NI
		if [ $NI -gt $MAX ] ; then
			MAX=$NI
		fi
	done
	echo "--"
	report Maximum $MAX
}

report_all > /tmp/cknic_rxic-report.$$
printf "nic_rx.list\n"
cat /tmp/cknic_rxic-report.$$

if [ $# -gt 0 -a "$1" = "-s" ] ; then
	mv /tmp/cknic_rxic-report.$$ ../deb/tmp/ns-agilio-core-nic/firmware/nfp-nic/firmware/build/nic_rx_icount-last.txt
else
	if [ $# -gt 0 -a "$1" = "-c" ] ; then
		rm -f ../deb/tmp/ns-agilio-core-nic/firmware/nfp-nic/firmware/build/nic_rx_icount-last.txt
	fi
	rm -f /tmp/cknic_rxic-report.$$
fi
