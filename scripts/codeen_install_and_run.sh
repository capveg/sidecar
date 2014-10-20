#!/bin/sh

user=princeton_codeen
srcdir=$HOME/swork/sidecar
outdir=umd_sidecar
srctar=sidecar.tgz
knownhosts=$srcdir/plab.known_hosts
sshopts="-o BatchMode=yes -o ServerAliveInterval=80 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$HOME/swork/sidecar/plab.known_hosts"
# ServerAliveInterval=80 --> 15*$ServerAliveInterval or 1200 s or 20 minute timeout


if [ $#  -ne 1 ] ; then
	echo Usage: $0 host >&2
	exit 1
fi

host=$1
# get rid of hostname off cmdline
shift



if [ ! -f $srcdir/$srctar ] ; then
	echo $srctar not found in $srcdir
	exit 1
fi

echo "Removing *everything*, untarring, and running command ./codeen_sidecar.run.sh"
cat $srcdir/$srctar | ssh $sshopts  $user@${host} "mkdir $outdir; cd $outdir &&  tar xzvf - && ./codeen_sidecar.run.sh "

