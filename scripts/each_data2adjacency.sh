#!/bin/sh

scripts=$HOME/swork/sidecar/scripts

for p in $@;  do
out=`basename $p`
#$scripts/data2adjacency.pl $p > adj.$out 2> log.$out
$scripts/data2adjacency.pl $p >$out.adj 2> $out.log
done
