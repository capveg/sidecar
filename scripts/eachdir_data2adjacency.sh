#!/bin/sh

scripts=$HOME/swork/sidecar/scripts

for p in `find . -type d -name \*.`; do 
out=`basename $p`
find $p \( -type f -or -type l \) -name data-\*| $scripts/data2adjacency.pl -a > adj.$out 2> log.$out
find $p \( -type f -or -type l \) -name data-\*| $scripts/data2stats.pl  > ip.$out 2> stat.$out
done
