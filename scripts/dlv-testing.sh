#!/bin/sh

scripts=$HOME/swork/sidecar/scripts
#rdir=$scripts/regression.tests

abortonerror=1
skipunlesstest=1

makemaps()
{
	for map in $1.good-dlv $1-C*.adj ; do 
		echo calling adjacency2map.sh $map
		adjacency2map.sh $map
	done
	exit 1
}

#cd $rdir


if [ "X$1" = "X-f" ]; then
	echo Forcing execution even if no .good-dlv file >&2
	skipunlesstest=0
	shift
fi
if [ "X$1" = "X-n" ]; then
	abortonerror=0
	shift
fi

if [ $# = 0 ]  ; then
	tests=`ls -d *.test| perl -p -e 's/\/$//'`
else
	tests="`ls -d $@| perl -p -e 's/\/$//'`"
fi


for p in $tests ; do
	rm -f $p.out $p.log $p.diff $p.dlv $p.model $p*.adj $p*.pdf $p*.dot $p*.ps
	hints=""
	if [ ! -f $p.good-dlv -a $skipunlesstest = 1 ] ; then
		echo SKIPPING $p :: no $p.good-dlv
		continue
	fi
	if [ -f $p.hints ] ; then
		hints=$p.hints
	fi
	echo Running regression $p
	if [ -f $p/data-clique ] ; then
		$scripts/data2dlv.pl $p/data-clique > $p.dlv
	elif [ -f $p/data-sql ] ; then
		$scripts/data2dlv.pl $p/data-sql > $p.dlv
	else
		$scripts/data2dlv.pl $p/data-*[0-9] > $p.dlv
	fi
	if [ $? != 0 ] ; then
		echo $scripts/data2dlv.pl failed >&2
		exit 1
	fi
	$scripts/test-facts.sh $hints $p.dlv > $p.model
	if [ $? != 0 ] ; then
		echo $scripts/test-facts.sh failed >&2
		exit 1
	fi
	if [ ! -s $p.model ] ; then
		echo "----------  Test $p FAILED; outputed no model"
		if [ $abortonerror == 1 ] ; then
			exit 1
		else 
			continue
		fi
	fi
	$scripts/dlv2adj.pl $p.model > /dev/null
	if [ $? != 0 ] ; then
		echo $scripts/test-facts.sh failed >&2
		exit 1
	fi
	for adj in ${p}*.adj; do
		$scripts/diffadj.pl $adj $p.good-dlv > $adj.diff
		if [ $? != 0 ]; then
			echo regression $p failed
			head $adj.diff 
			test $abortonerror == 1 && makemaps $p
		fi
		$scripts/find-bad-aliases.pl -b $adj
		if [ $? != 0 ]; then
			echo Bad aliases found in $adj
			test $abortonerror == 1 && makemaps $p
		fi
# break if the first model fails: who cares about 2nd model
#	-- horrible hack
		break	
	done
done
