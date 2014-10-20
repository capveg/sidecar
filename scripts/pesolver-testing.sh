#!/bin/sh

pesolver=$HOME/swork/sidecar/solver/pesolver
scripts=$HOME/swork/sidecar/scripts
rdir=$scripts/regression.tests

abortonerror=0

cd $rdir


rm -f *.out *.log *.diff 
rm -rf data
mkdir data

if [ "X$1" = "X-n" ]; then
	abortonerror=0
fi

for p in `ls -d *.test` ; do
	echo Running pesolver $p
	name=`echo $p | sed -e 's/\.test//'`
	$pesolver/solveDirectory.pl $name $p >& pesolver-$name.out
	$scripts/diffadj.pl $p.good data/$name.adj | tee $p.diff
	if [ $? != 0 ]; then
		echo regression $p failed
        	head $p.diff
		test $abortonerror == 1 && exit 1
	fi
	$scripts/find-bad-aliases.pl -b data/$name.adj
	if [ $? != 0 ]; then
		echo Bad aliases found in data/$name.adj
		test $abortonerror == 1 && exit 1
	fi
done
	#if [ `$script/cmpAdjacency.pl $p.out $p.good` ]; then
