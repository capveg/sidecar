#!/bin/sh
#set -x

SCRATCH=./scratch
TIMEOUT=30
useDir=0

if [ $# -ge 2 -a $1 = '-d' ]; then
	SCRATCH=$2
	shift 2
fi

#test -d $SCRATCH || mkdir $SCRATCH

if [ ! -d $SCRATCH ] ; then
	mkdir $SCRATCH
	echo using scratch dir $scratch
fi

if [ ! -d $SCRATCH ] ; then
	echo No scratch dir $scratch found: failing
	exit 1
fi

TMP=$SCRATCH/tmpdir.$HOSTNAME.$$
scripts=$HOME/swork/sidecar/scripts
if [ ! -z $SCRIPTS ] ; then
	scripts=$SCRIPTS
fi
echo Using ,$scripts, for the script dir
test -d $scripts || echo Directory ,$scripts, does not exist
test ! -d $scripts || echo Directory ,$scripts, DOES exist
test -f $scripts/timer || gcc -Wall -o $scripts/timer $scripts/timer.c

for file in $@ ; do 
	name1=`basename $file`
	name=`echo $name1| sed -e 's/\.tar\.gz//'`
	test -e $file || continue
	mkdir -p $TMP
	echo Extracting $file :: `date`
	tar xzf $file -C $TMP
	find $TMP -name data-\* | data2tr-adj.pl - > $name.tr-adj
	echo Cleaning `date`
	rm -rf $TMP
done

#sleep 120	# Good call on removing this Fritz ;-)
