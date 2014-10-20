#!/bin/sh

SCRIPTS=$HOME/swork/sidecar/scripts

if [ $# -lt 1 ] ; then
	echo "Error: usage $0 <source_ip> data-file1 [data-file2 [...]]" >&2
	exit 1
fi

sip=`echo $1| cut -d- -f2 | perl -p -e 's/:\d+//'`

if [ "X$sip" = "X" ]; then 
	sip=$1
fi

$SCRIPTS/data2adjacency.pl $@ > ${sip}.adj
if [ $? != 0 ] ; then
	echo $SCRIPTS/data2adjacency.pl failed >&2
	exit 1
fi
$SCRIPTS/adjacency2dot.pl < ${sip}.adj > ${sip}.dot
if [ $? != 0 ] ; then
	echo $SCRIPTS/adjacency2dot.pl failed >&2
	exit 1
fi
dot -Tps -o ${sip}.ps ${sip}.dot
if [ $? != 0 ] ; then
	echo dot failed >&2
	exit 1
fi
rm -f ${sip}.pdf
epstopdf ${sip}.ps
echo Created ${sip}.pdf
