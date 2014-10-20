#!/bin/sh
set -x
ulimit -c unlimited
rm -f fast_wget.log passenger.log
sudo /etc/init.d/syslog start
./fast_wget -t urls.plab > fast_wget.log && sudo killall -USR1 passenger &
sudo valgrind --leak-check=full ./passenger -p 80
# sendmail that this thing died
test $? -gt 128 && ./alertmail.py


# just in case
killall fast_wget
