#!/bin/bash

killall buildbot-worker

SLAVES=4
for i in `seq 1 $SLAVES`; do
  buildbot-worker create-worker --umask=022 ./corenic-slave-$i localhost:9989 corenic-slave-$i qwe123
  echo "bbslave <bbslave@netronome.com>" > corenic-slave-$i/info/admin
  echo "CoreNIC Builder $i" > corenic-slave-$i/info/host
  buildbot-worker start corenic-slave-$i
done

SLAVES=1
for i in `seq 1 $SLAVES`; do
  buildbot-worker create-worker --umask=022 ./nfp-slave-$i localhost:9989 nfp-slave-$i qwe123
  echo "bbslave <bbslave@netronome.com>" > nfp-slave-$i/info/admin
  echo "NFP Unit Test Builder $i" > nfp-slave-$i/info/host
  buildbot-worker start nfp-slave-$i
done
