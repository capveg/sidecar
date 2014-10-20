#!/bin/sh
for p in 5 4 3 2 1 ; do 
	echo "##################################### TTL=$p"
	./artrat -t $p -O greeble.cs.umd.edu -p 8080
done
