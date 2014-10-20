#!/bin/sh

count=5

if [ -z $SIDECARDDIR ] ; then
	SIDECARDIR=$HOME/swork/sidecar
fi

sideping=$SIDECARDIR/sideping/sideping

$sideping -I -w -c $count $@ 80
$sideping -w -c $count $@ 80



