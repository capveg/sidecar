#!/bin/bash
set -x

# sleeptime == time to wait after fast_wget finishes, before killing passenger
sleeptime=10
# number of concurrent websites to visit
threads=50
Outdir=data.all
file=stoplist.24

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

killall yum
sudo rpm -i *.rpm
# make sure an old copy isn't still running
killall -q ruby
killall -q srinterpreter
/usr/bin/killall -q srinterpreter
killall -q /usr/bin/perl

# make sure we clean up on exit
trap "{ killall -q srinterpreter ruby /usr/bin/perl ; echo Got signal: exiting `hostname`; }" SIGINT SIGTERM SIGHUP

test -f $file.gz && gunzip $file.gz
mkdir $Outdir
ulimit -c unlimited
./gtar_daemon.pl $Outdir $file &
cd $Outdir
LD_LIBRARY_PATH=.:..:
export LD_LIBRARY_PATH
PATH=$PATH:.:..
export PATH
../srinterpreter -ud ../informed_probe.sru -useStopList ../$file && sleep $sleeptime
cd ..
while `test -d $Outdir`; do
	sleep 10
	echo Trying to rm $Outdir `date`
	rmdir $Outdir
done
# sendmail if anything died badly
if [ $? -gt 128 ]; then
	echo Error:: `hostname`
	netstat -an
	./alertmail.py
	# just in case, cleanup
	killall ruby
	killall /usr/bin/perl 
	exit 1 
fi
	

echo Done:: `hostname` 
