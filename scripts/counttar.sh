#!/bin/sh


for p in $@ ; do
	echo $p `tar tzvf $p | awk '{count=count+$3} END{print count}'`
done

