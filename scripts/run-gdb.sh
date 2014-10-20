#!/bin/sh
set -x
ulimit -c unlimited
rm -f fast_wget.log passenger.log
sudo /etc/init.d/syslog start
./fast_wget > fast_wget.log && sudo killall -USR1 passenger &
sudo gdb -x gdb-passenger-run ./passenger 
# sendmail that if passenger died
test $? -gt 128 && ./alertmail.py


# just in case
killall fast_wget
