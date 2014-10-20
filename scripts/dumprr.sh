#!/bin/sh

if [ $# = 0 ] ; then
	echo usage: $0 '[-t|-T]' data-file >&2
	exit 1
fi

if [ \( $# -gt 1 \) -a \( "X$1" = "X-t" \) ] ; then
# TR + RR
	shift 
	exec awk '/RECV/ {if($13 != "RR,") { print $4,$7,"TR:" } else { print $4,$7,"RR:",$16,$20,$24,$28,$32,$36,$40,$44,$48,$52 }} ' $@ | sort -n | sed -e 's/ /	/g' | uniq -c | sort -n -k 2 
elif [ \( $# -gt 1 \) -a \( "X$1" = "X-T" \) ] ; then
# TR only
	shift 
	exec awk '/RECV/ {if($13 != "RR,") { print $4,$7,"TR:" } } ' $@ | sort -n | sed -e 's/ /	/g' | uniq -c | sort -n -k 2 
else
# RR only
	exec awk '/RECV.*RR/ {print $4,$7,"RR:",$16,$20,$24,$28,$32,$36,$40,$44,$48,$52 } ' $@ | sort -n | sed -e 's/ /	/g' | uniq -c | sort -n -k 2 
fi
