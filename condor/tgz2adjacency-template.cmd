### Run tgz2adjacency on $(InputDir)/$(InputFile) and output stuff to $(OutputDir)/$(InputFile)/ (created before this script)
# we don't need to be told when we're done.
notification = NEVER
# uncomment if your program wasn't compiled using condor_compile
universe = vanilla
# name of executable to submit
executable = /fs/sidecar/scripts/tgz2adjacency.sh
# where to dump stdout from your program
output = $(OutputDir)/$(InputFile)/stdout
# where to dump stderr from your program
error = $(OutputDir)/$(InputFile)/stderr
# logfile for condor
log = $(OutputDir)/$(InputFile)/log
# arguments to pass program
# arguments = /fs/sidecar/condor/data-pepper.planetlab.cs.umd.edu-urls.plab-15-3-1-2007.tar.gz
# arguments are given before queueing.
# set requirement
arguments = $(InputDir)/$(InputFile)
# lamppc24.umiacs.umd.edu is buggy right now
Requirements = Machine != "lamppc24.umiacs.umd.edu"
# set environment variables for program
environment = SCRIPTS=/fs/sidecar/scripts;SIDECARDIR=/fs/sidecar
# directory to change to before running program
InitialDir = $(OutputDir)
should_transfer_files = YES
when_to_transfer_output = ON_EXIT

# this is where the script will add lines like the below (commented out)
# arguments = /fs/sidecar/condor/data-pepper.planetlab.cs.umd.edu-urls.plab-15-3-1-2007.tar.gz
queue
