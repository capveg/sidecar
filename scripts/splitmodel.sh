#!/bin/csh

exec perl -p -e 's/, /\n/g' $1 > ${1:r}.model-split

