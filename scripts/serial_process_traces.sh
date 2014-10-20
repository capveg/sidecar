#!/bin/sh

if [ $# -ne 1 ]; then
	echo Usage: $0 '<modelname>' >&2
	exit 1
fi

for dir in  `cat dirnames `; do
	find $dir -name \*.model | xargs rm -f
	find $dir -name \*.adj | xargs rm -f
	find $dir -name \*.dlv | xargs rm -f
	echo $dir cleaned
done

date
cat datafiles | data2dlv2adjacency.pl -
date
cat modellist | unionModels.pl $1 -
date
echo Running conflict-debug2dlv.pl $1.conflict-debug
conflict-debug2dlv.pl $1.conflict-debug
date
echo Running badtraces_by_src.pl $1.badtraces \> $1.badtraces.by_src
badtraces_by_src.pl $1.badtraces > $1.badtraces.by_src
date
echo Calculating Good Ips
dlv2adj.pl $1.good
adjacency2ip.sh $1-C=unknown-1.adj > $1-C=unknown-1.ips
date
