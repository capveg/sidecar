#!/bin/sh

cat $@ | grep -v Link | perl -an -e 'chomp @F; shift @F; shift @F; shift @F; foreach $i (@F){ print "$i\n";}'|   sort -u
