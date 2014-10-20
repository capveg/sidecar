### Run from condorSolve.rb 
# we don't need to be told when we're done.
notification = NEVER
# uncomment if your program wasn't compiled using condor_compile
universe = vanilla
# name of executable to submit
executable = /fs/sidecar/condor/condorSolve.rb
# where to dump stdout from your program
output = $(OutputDir)/$(Base).stdout
# where to dump stderr from your program
error = $(OutputDir)/$(Base).stderr
# logfile for condor
log = /tmp/capveg/logdir/$(Base).log
# arguments to pass program
# arguments = /fs/sidecar/condor/data-pepper.planetlab.cs.umd.edu-urls.plab-15-3-1-2007.tar.gz
# arguments are given before queueing.
# set requirement
arguments = $(InputString)
# set environment variables for program
environment = SCRIPTS=/fs/sidecar/scripts;SIDECARDIR=/fs/sidecar;PATH=/bin:/usr/bin:/usr/local/bin:/fs/sidecar/scripts
# directory to change to before running program
#InitialDir = $(OutputDir)
should_transfer_files = YES
when_to_transfer_output = ON_EXIT

# this is where the script will add lines like the below (commented out)
queue
