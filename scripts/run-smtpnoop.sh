#!/bin/bash
set -x

# sleeptime == time to wait after fast_wget finishes, before killing passenger
sleeptime=10
# number of concurrent websites to visit
threads=50
Outdir=data.all

rpm -q perl-Time-HiRes || sudo rpm --install -f perl-Time-HiRes-1.55-2.i386.rpm
rpm -q perl-Event || sudo rpm --install -f perl-Event-1.06-1.1.fc2.rf.i386.rpm 

getpid() {
	ps auxww | grep "$1" | grep -v grep | awk '{print $2}'| head -1
}

# make sure an old copy isn't still running
killall -q passenger
killall -q smtpnoop.pl 
killall -q /usr/bin/perl

# make sure we clean up on exit
trap "{ killall -q passenger smtpnoop.pl /usr/bin/perl ; echo Got signal: exiting `hostname`; }" SIGINT SIGTERM

ulimit -c unlimited
rm -f smtpnoop.log passenger.log
./gtar_daemon.pl $Outdir smtplist &
./smtpnoop.pl smtplist 10 30 10 > smtpnoop.log && sleep $sleeptime && sudo killall -USR1 passenger &
# wait on passenger
sudo ./passenger $pass_opts -d $Outdir -p 25 > passenger.log 
# sendmail if anything died badly
if [ $? -gt 128 ]; then
	echo Error:: `hostname`
	netstat -an
	./alertmail-aschulm.py
	# just in case, cleanup
	killall smtpnoop.pl  
	killall /usr/bin/perl 
	exit 1 
fi
	

echo Done:: `hostname` 
