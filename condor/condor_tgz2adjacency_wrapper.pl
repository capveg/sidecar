#!/usr/bin/perl -w

# Take the same input as tgz2adjacency.pl (just a single tgzfile) and
# schedule it as a condor job

$tgzfile = shift or die "usage $0 /full/path/to/tgzfile.tar.tgz";
$base = `basename $tgzfile`;
