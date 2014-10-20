
# we don't need to be told when we're done.
notification = NEVER
# uncomment if your program wasn't compiled using condor_compile
universe = vanilla
# name of executable to submit
executable = /fs/sidecar/scripts/tgz2adjacency.sh
# where to dump stdout from your program
output = tgz2adjacency-$(Process).stdout
# where to dump stderr from your program
error = tgz2adjacency-$(Process).stderr
# logfile for condor
log = tgz2adjacency.log
# arguments to pass program
# arguments = /fs/sidecar/condor/data-pepper.planetlab.cs.umd.edu-urls.plab-15-3-1-2007.tar.gz
# arguments are given before queueing.
# set requirement
Requirements = Machine != "lamppc24.umiacs.umd.edu"
# set environment variables for program
environment = SCRIPTS=/fs/sidecar/scripts;SIDECARDIR=/fs/sidecar
# directory to change to before running program
InitialDir = /fs/sidecar/condor
should_transfer_files = YES
when_to_transfer_output = ON_EXIT

# this is where the script will add lines like the below (commented out)
# arguments = /fs/sidecar/condor/data-pepper.planetlab.cs.umd.edu-urls.plab-15-3-1-2007.tar.gz
# queue
