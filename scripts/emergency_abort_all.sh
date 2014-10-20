#!/bin/sh

dir=$HOME/swork/sidecar

outdir=emergency.$$

mkdir $outdir
cd $outdir
exec $dir/scripts/spawn -f $dir/HOSTS -- -l umd_sidecar killall passenger fast_get /usr/bin/perl
