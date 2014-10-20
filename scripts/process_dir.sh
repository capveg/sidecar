#!/bin/sh

# given a directory foo, create foo.processed with all of the tgz files in foo (recursivley)
# run through tgz2adjacency.pl, and then run *.good through unionModels.pl and *.good + *.hints through
# unionModels.pl

base=$HOME/swork/sidecar
scripts=$base/scripts
scratch=/scratch1/capveg
# /scratch1 works much better :-)

if [ $# -ne 1 ] ; then
	echo Usage: $0 datadir >&2
	exit 1
fi

# remove trailing slash if there
datadir=`echo $1| sed -e 's/\/$//'`


if [ ! -d $datadir ] ; then
	echo Data dir $datadir does not exists -  exiting
	exit 1
fi

outdir=$datadir.processed
olddir=`pwd`
mkdir -p $outdir

find $datadir -type f -name \*.gz > $outdir/tgzlist
cd $outdir
spawn -s -f $base/hosts.rogues.good -p $outdir/tgzlist -- "ssh -o StrictHostKeyChecking=no %%H 'cd $outdir && hostname && tgz2adjacency.sh -d $scratch %%P'"


ls | grep .good | unionModels.pl all-good -
ls | egrep '.(good|hints)' | unionModels.pl all-hints -


	
