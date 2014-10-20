#!/bin/bash
set -x

Outdir=data.all

# emergency sanity check
if [ $USER = "umd_sidecar" ]; then
	echo DO NOT RUN THIS SCRIPT FROM THE UMD_SIDECAR SLICE - use ./run.sh >&2
	exit 1
fi

# make sure an old copy isn't still running
killall -q passenger

# make sure we clean up on exit
trap "{ killall -USR1 -q passenger ; echo Got signal: exiting `hostname`; }" SIGINT SIGTERM

rm -f passenger.log

rm -rf $Outdir

./gtar_daemon.pl $Outdir codeen &

sudo ./passenger $pass_opts -d $Outdir -p 3128 > passenger.log 


# sendmail if anything died badly
if [ $? -gt 128 ]; then
	echo Codeen Error:: `hostname`
	./alertmail.py
	# just in case, cleanup
	exit 1 
fi
	

echo Done:: `hostname` 
