#!/bin/sh

acroread=0
useNeato=-1
unknown=-skipUnknown
pdfs=""

if [ $1 = '-a'  ] ; then
	acroread=1
	shift
fi

if [ $1 = '-neato'  ] ; then
	useNeato=1
	shift
fi
if [ $1 = '-noNeato'  ] ; then
	useNeato=0
	shift
fi

if [ $# -lt 1 ] ; then
	echo "Error: usage $0 [-a] [-neato|-noNeato] foo.adj [... ]"
	exit 1
fi

for f in $@ ; do 
	SCRIPTS=$HOME/swork/sidecar/scripts


	sip=`echo $f| perl -p -e 's/\.adj$//'`

	if [ "X$sip" = "X" ]; then 
		sip=$f
	fi

	if [ $useNeato == "-1" ] ; then
		nDataFiles=`grep -i source $f | sort -u | wc -l`

		if [ $nDataFiles -gt 1 ] ; then
			useNeato=1
		else
			useNeato=0
		fi
	fi

	if [ $useNeato == 1 ] ; then
		adj2graphviz=$SCRIPTS/adjacency2neato.pl
		graphviz=neato
	else
		adj2graphviz=$SCRIPTS/adjacency2dot.pl
		graphviz=dot
	fi
	$adj2graphviz $unknown < $f > ${sip}.dot
	if [ $? != 0 ] ; then
		echo $adj2graphviz failed >&2
		exit 1
	fi
	$graphviz -Tps -o ${sip}.ps ${sip}.dot
	if [ $? != 0 ] ; then
		echo dot failed >&2
		exit 1
	fi
	rm -f ${sip}.pdf
	epstopdf ${sip}.ps
	echo Created ${sip}.pdf
	pdfs="${sip}.pdf $pdfs"
done

if [ $acroread = 1 -a -s ${sip}.pdf ] ; then 
	exec acroread $pdfs
fi
