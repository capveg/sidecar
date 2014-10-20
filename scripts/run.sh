#!/bin/bash
set -x

# sleeptime == time to wait after fast_wget finishes, before killing passenger
sleeptime=10
# number of concurrent websites to visit
threads=50
Outdir=data.all
file=urls.good

# emergency sanity check
if [ $USER = "princeton_codeen" ]; then
	echo DO NOT RUN THIS SCRIPT FROM THE CODEEN SLICE - use ./run-codeen.sh >&2
	exit 1
fi

#rpm -q libpcap || sudo yum -yt install libpcap

getpid() {
	ps auxww | grep "$1" | grep -v grep | awk '{print $2}'| head -1
}


if [ $# != 0 ]; then
	file=$1
fi

if [ $file = "urls.plab" ]; then
	# no safe distance when just going to plab nodes
	pass_opts="-s 0"
else
	pass_opts=""
fi

# make sure an old copy isn't still running
killall -q passenger
killall -q fast_wget
killall -q /usr/bin/perl

# make sure we clean up on exit
trap "{ killall -q passenger fast_wget /usr/bin/perl ; echo Got signal: exiting `hostname`; }" SIGINT SIGTERM

ulimit -c unlimited
rm -f fast_wget.log passenger.log
./gtar_daemon.pl $Outdir $file &
./fast_wget -n $threads -t $file > fast_wget.log && sleep $sleeptime && sudo killall -USR1 passenger &
# wait on passenger
sudo ./passenger $pass_opts -d $Outdir -p 80 > passenger.log 
# sendmail if anything died badly
if [ $? -gt 128 ]; then
	echo Error:: `hostname`
	netstat -an
	./alertmail.py
	# just in case, cleanup
	killall fast_wget  
	killall /usr/bin/perl 
	exit 1 
fi
	

echo Done:: `hostname` 
