#!/usr/bin/perl -w 
#	./createDLVbase.pl [-a] [-v] source_ip [datafiles... ]
# Parse the output files from passenger, and print a dlv friendly list of facts:
#
# This tells the start and end host for a particular probe_id.
# trace(traceID,starthost,endhost).
# 138.96.250.222:46318-134.76.81.241:80 - Sending train=0 type=DATA safettl=11 nProbes=11 payload=-1 RR=1 rto=1500000(1) time=1147905365.770698
# creates
# probe(1,ip138_96_250_222,ip134_76_81_241)
#
# traceroute info from a particular probe
# tr(traceID, probe_ttl, icmp_source)
#               probe ids are globally unique
# - RECV TTL 1 it=1 from   138.96.248.250 (255)   ROUTER   rtt=0.000431 s t=1147905365.882119 Macro
# creates:
# tr(1, 1, ip138__96_248_250)
#                                                                   
# record route info from a probe
# rr(traceID,icmp_source,probe_ttl,index,ip)
#               Indexes start at *one* (not Zero)
# - RECV TTL 3 it=0 from    193.51.180.33 (253)   ROUTER   rtt=0.005743 s t=1147905365.789415 RR, hop 1 193.51.181.137 , hop 2 193.51.180.34 ,  Macro
# creates
# rr(1,ip193_51_180_33,2,1,ip193_51_181_137)
# rr(1,ip193_51_180_33,2,2,ip193_51_180_34)
#
# traceID is unique to a particular trace.
# I'm using "trace" here to mean one particular run of
# trace route AND record route. For a particular start and
# end host, all data from one iteration of a traceroute 
# and a record route is tagged with the same probe id, 
# which is unique to that probe.
#


use strict;
#use warnings;
#use warnings FATAL => 'all';
# will need to be changed...
#use lib "$ENV{"HOME"}"."/swork/sidecar/scripts";
use lib $ENV{"HOME"}."/projects/typeRec/sidecar/scripts";
use Adjacency;		# slurp all of the subroutines up from module
			# kills readbility, allows reuse of code...

use vars qw($Verbose $Quiet $Iterations $MaxTTL %data $trace %Reachable %ip2router $foundEndHost $SourceRouterName $source_ip $dest_ip @rrDistance);
$Verbose=0;
$Quiet=0;
$Iterations=6;

# makes an IP address into an identifier which conforms to DLV syntax.
sub makeDLVaddress
{
    my $ip = shift or die "Bad args for makeDLVaddress\n";
    $ip =~ s/\./_/g;
    $ip = "ip$ip";
    return $ip;
}

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

        # use the trace number as the trace ID.
        my $traceID = "0";
        # print out the source and dest addresses for this trace.:

        # now we do a record route trace.
	my $linecounter=0;
        my $err=0;
        my $rrTrace = 0; # 1 if the current trace is traceroute, 0 if it is record route.
	while(<IN>)
	{
		$linecounter++;
                # Here we parse the sending line: we get the source and dest IP addresses
                # and decide if we need a new trace ID. Also, this line tells us if
                # the following trace is rr or tr.
                if (/Sending.* RR=(\d)/) {
                    $rrTrace = $1;
                    if ($rrTrace == 1) {
                        $totaltraces++;
                        $traceID = $totaltraces;
                    }
                    my @line=split /\s+/,$_;
                    my @filen=split /-/, $line[0];
                    $source_ip=$filen[0];
                    $source_ip=~s/:\d+//;
                    $dest_ip = $filen[1];
                    $dest_ip =~s/:\d+//;
                    if((!$source_ip)||(!$dest_ip))
                    {
                        print STDERR "WARN: could not parse source or dest ip in : $trace\n";
                        last;
                    }
                    my $prettySourceIP = &makeDLVaddress($source_ip);
                    my $prettyDestIP = &makeDLVaddress($dest_ip);
                    print "trace($traceID,$prettySourceIP,$prettyDestIP).\n";
                }
		next unless(/RECV/);	# skip non-data msgs
			chomp;
		@line=split;
		if($line[5] ne "from")
		{
			print STDERR "Bad line $trace:$linecounter '$_'\n";
			next;
		}
                # line[6] should be the IP address sending the info
                my $prettyTimeoutAddress = &makeDLVaddress($line[6]);
                # line[3] should be the TTL count.
                if ($rrTrace == 1) {
                    # observeRR(ID,IP1,TTL,IP2,HOP).
                    while (/hop (\d+) (\S+) ,/g) {
                        my $prettyHopAddress = &makeDLVaddress($2);
                        print "rr($traceID,$prettyTimeoutAddress,$line[3],$1,$prettyHopAddress).\n";
                    }
                } else { 
                    # observeTR(ID,IP,TTL).
                    print "tr($traceID,$line[3],$prettyTimeoutAddress).\n";
                }
	}
	next if($err);
}


# end main


