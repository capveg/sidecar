#!/bin/sh
set -x

dir=$HOME/swork/sidecar
time=7260

if [ $# -lt 1 ] ; then
	echo Usage: $0 host '[dir]'>&2 
	exit 1
fi

host=$1
outdir=$2

while `true` ; do
	echo Snagging $host `date`
	$dir/scripts/snag_em.sh $host $outdir
	echo Sleeping $time `date`
	sleep $time
done

