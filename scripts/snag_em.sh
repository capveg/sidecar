#!/bin/sh
slice=umd_sidecar
HOSTS=$HOME/swork/sidecar/HOSTS
sshopts="-o BatchMode=yes -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=$HOME/swork/sidecar/plab.known_hosts"

if [ $# = 0 ] ; then
	echo USAGE: $0 host >&2
	exit 1
fi
host=$1
dir=$2


test -d $host || mkdir $host
cd $host
#rsync --rsh=ssh --delete-after -av umd_sidecar@${host}:data-\* .
if [ "X$dir" = "X" ] ; then
	ssh $sshopts ${slice}@${host} tar -cf - --remove-files  'data-*' |tar -xvf - 
else
	slice=princeton_codeen
	ssh $sshopts ${slice}@${host} "cd $dir && tar -cf - --remove-files  data-*" |tar -xvf - 
fi
cd ..
