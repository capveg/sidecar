#!/bin/sh

# solves using pesolver and DLV input. 

scripts=$HOME/swork/sidecar/scripts
rdir=$scripts/regression.tests
pesolver=$HOME/swork/sidecar/solver/pesolver

if [ -z $SIDECARDIR ]; then
        SIDECARDIR=$HOME/swork/sidecar
fi

abortonerror=1

makemaps()
{
	for map in $1.good-dlv $1-C*.adj ; do 
		echo calling adjacency2map.sh $map
		adjacency2map.sh $map
	done
	exit 1
}

cd $rdir

rm -f *.out *.log *.diff *.dlv *.model *.adj

if [ "X$1" = "X-n" ]; then
	abortonerror=0
fi

for p in $* ; do
#for p in `ls -d *.test` ; do
	if [ ! -f $p.good-dlv ] ; then
		echo SKIPPING $p :: no $p.good-dlv
		continue
	fi
	echo Running regression $p
	$scripts/data2dlv.pl $p/data-*[0-9] > data/$p-tmp.dlv
	if [ $? != 0 ] ; then
		echo $scripts/data2dlv.pl failed >&2
		exit 1
	fi
	$scripts/pesolve.pl $p data/$p-tmp.dlv
	if [ $? != 0 ] ; then
		echo $pesolver/processDLV.pl failed >&2
		exit 1
	fi
	$scripts/dlv2adj.pl $p.model > /dev/null
	if [ $? != 0 ] ; then
		echo $scripts/dlv2adj.sh failed >&2
		exit 1
	fi
	for adj in $p*.adj; do
                echo "Working on $adj."
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
		# break	
	done
done
