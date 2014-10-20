#!/bin/sh

if [ "X$1" == '-q' ] ;  then
	shift 
	quiet=1
fi

if [ -z $quiet ]  ; then
	exec head -1 $@ | perl -p -e 's/, /.\n/g' | grep -v Cost | grep -v Best
else
	exec perl -p -e 's/, /\n/g' $@
fi
