#!/bin/sh

if [ -z $SIDECARDDIR ] ; then
	SIDECARDIR=$HOME/swork/sidecar
fi

SCRIPTS=$SIDECARDIR/scripts

if [ $# -lt 1 ] ; then
	echo "Error: usage $0 [-outprefix foo ] data-file1 [data-file2 [...]]" >&2
	exit 1
fi

sip=`basename $1`

if [ "X$1" = "X-outprefix" ]; then 
	sip=$2
	shift $@
	shift $@
fi
echo Using $sip as outfile base

echo --- "data2dlv.pl $@ > ${sip}.dlv" :: `date`

$SCRIPTS/data2dlv.pl $@ > ${sip}.dlv
if [ $? != 0 ] ; then
	echo $SCRIPTS/data2dlv.pl failed >&2
	exit 1
fi
echo --- "test-facts.sh ${sip}.dlv > ${sip}.model" :: `date`
$SCRIPTS/test-facts.sh ${sip}.dlv > ${sip}.model
if [ $? != 0 ] ; then
	echo $SCRIPTS/test-facts.sh failed >&2
	exit 1
fi
echo --- "dlv2adj.pl ${sip}.model" :: `date`
$SCRIPTS/dlv2adj.pl ${sip}.model
if [ $? != 0 ] ; then
	echo $SCRIPTS/test-facts.sh failed >&2
	exit 1
fi
for p in $sip*.adj; do 
	o=`echo $p | sed -e 's/\.adj/\.dot/'`
	q=`echo $p | sed -e 's/\.adj/\.ps/'`
	r=`echo $p | sed -e 's/\.adj/\.pdf/'`
	echo --- "adjacency2dot.pl < $p > $o" :: `date`
	$SCRIPTS/adjacency2dot.pl < $p > $o
	if [ $? != 0 ] ; then
		echo $SCRIPTS/adjacency2dot.pl failed for $p >&2
		exit 1
	fi
	echo --- "dot -Tps -o $q $o" :: `date`
	dot -Tps -o $q $o
	if [ $? != 0 ] ; then
		echo dot failed for $o >&2
		exit 1
	fi
	rm -f $r
	echo --- "epstopdf $q" :: `date`
	epstopdf $q 
	echo Created $r
done
