#!/usr/bin/perl -w 
#	./data2adjacency.pl [-a] [-v] source_ip [datafiles... ]
# Parse the output files from passenger, and print a formated list of connectivity:
# Format:
#	Router "routername" <if1> <if2> <if3>...
#	Link "routername":if1 "routername":if2	"type"	"time"
# Example:
#	Router R1 128.8.126.1 128.8.126.139
#	Router R2 128.8.6.129 128.8.0.14
#	Link R1:128.8.126.139 -> R2:128.8.6.129
#	
# Algorithm:
# foreach trace
#	read and parse full trace
#	foreach probe compute deltas relative to prev probes that took the same path
#		- if all deltas are not consistant, mark flaky
#	from deltas, infer RRtype
#	from RRtype, add links and interfaces
#	if missing all RR probes, but got TR probes, mark as DropsRR
# rename/mark all routers
# add hidden links to ensure connectivity
# 


use strict;
#use warnings;
#use warnings FATAL => 'all';
use lib $ENV{"HOME"}."/swork/sidecar/scripts";
use Adjacency;		# slurp all of the subroutines up from module
			# kills readbility, allows reuse of code...

use vars qw($Verbose $Quiet $Iterations $MaxTTL %data $trace %Reachable %ip2router $foundEndHost $SourceRouterName $source_ip $dest_ip @rrDistance);
$Verbose=0;
$Quiet=0;
$Iterations=6;


# no need to forward declare in perl, but here for clarity
#%ip2router = {};
#%routers = {};
#%links = {};
#%routerTypes = {};

&parseArgs();

# 0              1    2  3    4         5           6         7             8           9      10    11                 12    13 14 15           16 17 18 19            20 21 22 23            24 25
#- RECV TTL 3 it=0 from   209.124.176.12 (253)       ROUTER   rtt=0.021415 s time=1146243600.835900 RR, hop 1 140.142.155.15 , hop 2 209.124.176.23 , hop 3 209.124.178.12 ,  Macro

my ($skippedtraces, $goodtraces, $totaltraces) = (0,0,0);

foreach $trace ( @ARGV)
{
	next if($trace eq "." or $trace eq "..");
	if( ! -f $trace )
	{
		warn "$trace not a file\n";
		next;
	}
	open IN, "$trace" or die "open: $trace: $!";	# sort on TTL

	%data = (); 			# zero the data structure
	$MaxTTL=0;
	my @line=split /\s+/,<IN>;			# grab the first line of the trace to calc the source and dest address
	my @filen=split /-/, $line[0];
	$source_ip=$filen[0];
	$source_ip=~s/:\d+//;
	$dest_ip = $filen[1];
	$dest_ip =~s/:\d+//;
	if((!$source_ip)||(!$dest_ip))
	{
		print STDERR "WARN: could not parse source or dest ip in : $trace\n";
		next;
	}
	if(!exists $ip2router{$source_ip})
	{
		$SourceRouterName = newRouter("SOURCE");
	}
	else
	{
		$SourceRouterName=$ip2router{$source_ip};
	}
	$Reachable{$SourceRouterName}=1;
	addInterface($source_ip,$SourceRouterName);	# say that source_ip is an interface on the router named "$source_ip"
    my $i;
	for($i=0;$i<$Iterations;$i++)
	{
		$data{"0"}->{$i}->{"inhop"}=$source_ip;
		$data{"0"}->{$i}->{"name"}=$SourceRouterName;
		$data{"0"}->{$i}->{"rr"}=[];
		$data{"0"}->{$i}->{"RRtype"}="A";
		$data{"0"}->{$i}->{"ptype"}="Source";
		$data{"0"}->{$i}->{"gotRR"}=1;
		$data{"0"}->{$i}->{"beenClassified"}=0;
		$data{"0"}->{$i}->{"delta"}=0;
		$rrDistance[$i]=0;
	}
	my $linecounter=0;
    $foundEndHost = 0;
    my $err=0;
	while(<IN>)
	{
		$linecounter++;
		parseSendingLine($_) if(/Sending/);
		next unless(/RECV/);	# skip non-data msgs
			chomp;
		@line=split;
		if($line[5] ne "from")
		{
			print STDERR "Bad line $trace:$linecounter '$_'\n";
			next;
		}
		if(&parseline(@line))	# put data into %data structure
		{
			chomp;
			print STDERR "ERR: $trace:$linecounter :: unparsable trace: '$_'\n";
			$err=1;
			last;
		}
	}
	next if($err);
    # parseline side effect is to set foundEndHost.
	if(!$foundEndHost)		# hack in an unknown link to endhost if we didn't get a response from it
	{
		print STDERR "Did not find Endhost response for $trace; hacking it in!\n" if($Verbose);
		$MaxTTL+=2;
		my $ttl=$MaxTTL;
		my $iteration=0;
		$data{$ttl}->{$iteration}->{"inhop"}=$dest_ip;
		$data{$ttl}->{$iteration}->{"type"}="ENDHOST";
		$data{$ttl}->{$iteration}->{"rr"}=[];
		$data{$ttl}->{$iteration}->{"ptype"}="TraceRoute";
		$data{$ttl}->{$iteration}->{"name"}=newRouter($data{$ttl}->{$iteration}->{"type"});
		$data{$ttl}->{$iteration}->{"RRtype"}="None";
		$data{$ttl}->{$iteration}->{"gotRR"}=0;
		&addInterface($data{$ttl}->{$iteration}->{"inhop"},$data{$ttl}->{$iteration}->{"name"});
		&markRouter($data{$ttl}->{$iteration}->{"name"},"Filtered"," Rule #".__LINE__);
	}
	$totaltraces++;
	&chinaFireWallHack();
	if(&classifyRouters()) # are we RRtype = A,B or N?
	{
		$goodtraces++;
		print STDERR "Parsing trace $trace : nG $goodtraces nS $skippedtraces Total: $totaltraces\n" if($Verbose);
	}
	else
	{
		$skippedtraces++;
		print STDERR "SKIPPING trace $trace : error in classification: nG $goodtraces nS $skippedtraces Total: $totaltraces\n" unless($Quiet);
		next;
	}
	&addAllLinks();		   # once we know what types the routers are, setup the links
	&lookForDroppingRouters(); # mark any routers that drop RR packets
	&ensureReachability($SourceRouterName, $source_ip);	# mark any unconnected nodes with "unknown" links
}


print STDERR "STATUS nG $goodtraces nS $skippedtraces Total: $totaltraces\n" unless($Quiet);
if($goodtraces<1)
{
	print STDERR "No good traces... exiting\n";
	exit 1;
}

# do a second pass and mark all routers with the same interfaces as being the same
#	we can't do this above b/c of the way that outgoing interfaces are discovered
&markSameRouters();
&dumpRouterList();

# end main


