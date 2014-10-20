#!/usr/bin/perl -w

use sidecar;

sub debug {
	$arg=@_;
	print "PERL DEBUG '$arg'";
};

print STDERR "Testing INIT call\n";
sidecar::sidecarinit( "12344");
print STDERR "Testing debug call\n";
sidecar::registerdebug(\&debug);
