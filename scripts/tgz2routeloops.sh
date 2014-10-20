#!/bin/sh

scratch=./scratch
hops=10

test -d $scratch || mkdir $scratch

for f in $@; do 
	echo ------------------- $f
	tar xzf $f -C $scratch
	find $scratch -type f | xargs grep -l '==109' | tee $scratch/files
	cat $scratch/files | xargs tail -v -n $hops | tee -a routeloops
	find $scratch -type f | xargs rm
done
