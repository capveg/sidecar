#!/bin/sh

scripts=$HOME/swork/sidecar/scripts
rdir=$scripts/regression.tests

abortonerror=1

cd $rdir

rm -f *.out *.log *.diff

if [ "X$1" = "X-n" ]; then
	abortonerror=0
fi

for p in `ls -d *.test` ; do
	echo Running regression $p
	$scripts/data2adjacency.pl -v $p/* > $p.out 2> $p.log
	diff -bwi $p.out $p.good > $p.diff
	if [ $? != 0 ]; then
		echo regression $p failed
        	head $p.diff
		test $abortonerror == 1 && exit 1
	fi
	$scripts/find-bad-aliases.pl -b $p.out 
	if [ $? != 0 ]; then
		echo Bad aliases found in $p.out
		test $abortonerror == 1 && exit 1
	fi
done
	#if [ `$script/cmpAdjacency.pl $p.out $p.good` ]; then
