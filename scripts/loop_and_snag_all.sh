#!/bin/sh
set -x

dir=$HOME/swork/sidecar

if [ $#  == 0 ] ; then
	echo Usage: $0 HOSTS '[dir]' >&2 
	exit 1
fi

if [ ! -f $dir/$1 ]; then
	echo $dir/$1 not found >&2 
	exit 2
fi



while `true` ; do
	$dir/scripts/spawn -s -t 1 -f $dir/$1 -- "$dir/scripts/loop_and_snag.sh %%H $2" >> loop_and_snag_all.log.$$
done

