#!/usr/bin/perl -w
# 	Daemon sits and lurks, and watches given directory and makes a gtar of files
#	that show up in it, deleting and compressing as it goes


$SRCDIR=shift or usage("Need to specify argument\n");
$datatag = shift || "untagged";


$sleepTime=5;		# sleep for 5 seconds in between checking the directory
$done=0;
$verbose="";		# $verbose = "-v" for verbose mode
$tar="tar";
$delete="--remove-files";
$gzip="gzip";

# gets rid of annoying "unused variable" stuff
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) ;

$SIG{USR1}=\&handle_usr1;		# sets signal handler
$SIG{CHLD}=\&mywait;			# set child handler

sub mywait
{
	wait;
	$SIG{CHLD} = \&mywait;
}

$lastfileName="";
$hostname=`hostname`;
chomp $hostname;

while(!$done)
{
	sleep($sleepTime);
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$outfileName = sprintf "tmp-data-%s-$datatag-%d-%d-%d-%d.tar", $hostname, $hour,$mday,$mon+1,$year+1900;
	$mode = (-f $outfileName)?"--append":"--create";
	#print "$tar $mode $delete $verbose --file $outfileName --directory $SRCDIR .\n";
	if(! -d $SRCDIR)
	{
		print STDERR "Exiting... $SRCDIR doesn't (nolonger?) exists\n";
		$done=1;
		last;
	}
	$status=system("$tar $mode $delete $verbose --file $outfileName --directory $SRCDIR .");
	if($status)
	{
		print STDERR "Got status=$status; cleaning up and aborting:: ";
		$done=1;
		last;
	}

	if(($lastfileName)and ($outfileName ne $lastfileName))	
	{	# move the lastfile from tmp-data to data so it can be snagged
		$dest = $lastfileName;
		$dest =~ s/tmp-//;
		`mv $lastfileName $dest`;
		&forkAndCompress($dest);
	}
	$lastfileName=$outfileName;
}

$dest = $outfileName;
$dest =~ s/tmp-//;
`mv $outfileName $dest`;
exec("$gzip $dest");




#####################################################################
sub usage
{
	my ($errmsg) = @_;

	print STDERR "$errmsg\n" if($errmsg);
	print STDERR "Usage:\n\ngtar_daemon.pl <source dir> [datatag]\n";
	exit(1);
}

#####################################################################

sub forkAndCompress
{
	my ($file,$pid);

	$pid=fork();
	return if($pid!=0); 	# parent
	$file = shift @_;
	exec("$gzip $file") == 0 or die "system $gzip $file: failed : $!";
	exit(1);
}


#####################################################################
sub handle_usr1
{
	$done=1;
}
