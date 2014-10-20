
base=tgz2adjacency
tarballs = tgzlist
.PHONY: alltarballs

#all:
#	 condor_submit tgz2adjacency.cmd

alltarballs:
	cat $(tarballs) | xargs --max-args=200 ./condor_tgz2adjacency 

clean:
	rm -f $(base).log $(base).stdout $(base).stderr data-*
