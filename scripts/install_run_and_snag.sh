#!/bin/sh

user=umd_sidecar
srcdir=$HOME/swork/sidecar
srctar=sidecar.tgz
knownhosts=$srcdir/plab.known_hosts
sshopts="-o BatchMode=yes -o ServerAliveInterval=80 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$HOME/swork/sidecar/plab.known_hosts"
# ServerAliveInterval=80 --> 15*$ServerAliveInterval or 1200 s or 20 minute timeout


if [ $#  -lt 2 ] ; then
	echo Usage: $0 host command >&2
	exit 1
fi

host=$1
# get rid of hostname off cmdline
shift


if [ ! -f $srcdir/$srctar ] ; then
	echo $srctar not found in $srcdir
	exit 1
fi

echo "Removing *everything*, untarring, and running command ,$@,"
cat $srcdir/$srctar | ssh $sshopts  $user@${host} "sudo rm -rf *; tar xzvf - ; $@ &"


test -d $host || mkdir $host
cd $host
#grab data file from remote, put it in local directory
ssh -n $sshopts ${user}@${host} tar -cf - --remove-files  'data-*' |tar -xvf - 
cd ..
