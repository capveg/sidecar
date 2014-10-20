#!/bin/sh

# given a directory foo, create foo.processed with all of the tgz files in foo (recursivley)
# run through tgz2adjacency.pl, and then run *.good through unionModels.pl and *.good + *.hints through
# unionModels.pl

base=$HOME/swork/sidecar
scripts=$base/scripts
spawn=$scripts/spawn
scratch=/scratch1/capveg
# /scratch1 works much better :-)

if [ $# -ne 1 ] ; then
	echo Usage: $0 datadir >&2
	exit 1
fi

# remove trailing slash if there
datadir=`echo $1| sed -e 's/\/$//'`


if [ ! -d $datadir ] ; then
	echo Data dir $datadir does not exist -  exiting
	exit 1
fi

outdir=$datadir.processed
olddir=`pwd`
mkdir -p $outdir

find $datadir -type f -name \*.tar.gz > $outdir/tgzlist
cd $outdir
$spawn -s 200 -p $outdir/tgzlist -- "ruby /fs/sidecar/condor/condor_submit_and_wait %%P"

#find . -type f -name \*.good | unionModels.pl all-good -
#find . -type f -name '*.(good|hints)' | unionModels.pl all-hints -


	
