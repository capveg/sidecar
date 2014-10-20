#!/bin/sh

SCRIPTS=$HOME/swork/sidecar/scripts

if [ $# -lt 2 ] ; then
    echo "Error: usage $0 <file1.adj> <file2.adj>"
    exit 1
fi

$SCRIPTS/adjSubsetCmp.pl $1 $2
$SCRIPTS/adjSubsetCmp.pl $2 $1

