#!/bin/sh
#set -x

SCRATCH=./scratch
TIMEOUT=300
BIGTIMEOUT=600
useDir=0
cleanup=1
tracespergroup=1

if [ $# -ge 1 -a $1 = '-c' ]; then
	echo "No cleanup"
	cleanup=0
	shift 
fi
if [ $# -ge 2 -a $1 = '-n' ]; then
	tracespergroup=$2
	shift 2
fi

if [ $# -ge 2 -a $1 = '-d' ]; then
	SCRATCH=$2
	shift 2
fi

#test -d $SCRATCH || mkdir $SCRATCH

if [ ! -d $SCRATCH ] ; then
	mkdir $SCRATCH
	echo using scratch dir $SCRATCH
fi

if [ ! -d $SCRATCH ] ; then
	echo No scratch dir $SCRATCH found: failing
	exit 1
fi

if [ $cleanup == 1 ]; then
	echo Will cleanup after
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
	if [ $useDir -eq 1 ]; then 
		mkdir $name
		adjfile="$name/$name.adj"
		logfile="$name/$name.log"
		ipfile="$name/$name.ip"
		modelfile="$name/$name.union"
		statfile="$name/$name.stat"
	else
		adjfile="$name.adj"
		logfile="$name.log"
		ipfile="$name.ip"
		modelfile="$name.union"
		statfile="$name.stat"
	fi
	test -e $file || continue
	test -s $modelfile.good && continue
	mkdir -p $TMP
	echo Extracting $file :: `date`
	tar xzf $file -C $TMP
	if [ $tracespergroup == 1 ] ; then
		base="data-"
	else
		base="traces."
		find $TMP -name data-\* | split -l $tracespergroup - $TMP/traces.
	fi
	# process everything file by file
	for p in `find $TMP -name $base\*`; do
		echo processing $p :: $tracespergroup traces/group
		if [ $tracespergroup == 1 ] ; then
			$scripts/data2dlv.pl $p 2>&1 > $p.dlv | tee -a $logfile 
		else
			cat $p | $scripts/data2dlv.pl - 2>&1 > $p.dlv | tee -a $logfile 
		fi
		/usr/bin/time $scripts/timer $TIMEOUT $scripts/test-facts.sh $p.dlv 2>&1 > $p.model  | tee -a $logfile 
	done
	echo Union models :: `date`
	find $TMP -name $base\*.model | $scripts/unionModels.pl $modelfile -
	# doesn't work unless datafile=foo and modelfile=foo.model
	if [ $tracespergroup == 1 ] ; then
		echo conflict-debug2dlv.pl :: `date`
		$scripts/conflict-debug2dlv.pl -d $SCRATCH $modelfile.conflict-debug
	fi
	echo Calc stats :: `date`
	find $TMP -name data-\* | $scripts/data2stats.pl > $ipfile 2> $statfile
	if [ $cleanup == 1  ] ; then
		echo Cleaning `date`
		rm -rf $TMP
	fi 
done

#sleep 120	# Good call on removing this Fritz ;-)
