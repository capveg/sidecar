#!/usr/bin/perl -w

# uncomment for debuging
use Socket;



@prefixes=();


while(@ARGV>=2 && $ARGV[0] eq "-prefix")
{
	print STDERR "Adding $ARGV[1] to selection criteria\n";
	usage("Bad prefix format '$ARGV[1]'\n") unless($ARGV[1] =~/\d+\/\d+/);
	push @prefixes,$ARGV[1];
	shift @ARGV;
	shift @ARGV;
}


$adjfile = shift or usage();
&parseAdj($adjfile);



############################################################################
sub usage
{
	print STDERR "usage:: adjacency2subset.pl [-prefix 198.32/16 [...]] foo.adj\n";
	exit(1);
}
############################################################################
sub parseAdj
{
	my $file = shift @_;
	my ($linecount,@line,$srouter,$sip,$drouter,$dip);
	open F, "$file" or die "open: $file : $!";
	$linecount=0;
	while(<F>)
	{
		$linecount++;
		chomp;
		next if(/^\s*$/);  # skip blank lines
		if(/^(Router|Endhost|Source|HIDDEN|NAT)/)
		{
			@line= split;
			$interesting=0;
			foreach $ip (@line[3..$#line])
			{
				$interesting=1 if(&interestingIP($ip));
			}
			if($interesting)
			{
				print "$_\n"; 
				$usedRouter{$line[1]}=1;
			}
			next;
		}
		if(/^Link/)
		{
			#next if(/UNKNOWN/ && $ignoreUnknownLinks);
			@line=split;
			($srouter,$sip)=split /:/, $line[1];
			($drouter,$dip)=split /:/, $line[3];
			if(&interestingIP($sip) || &interestingIP($dip))
			{
				print "$_\n";
				if(!exists($usedRouter{$srouter}))
				{
					$needRouter{$srouter}->{$sip}=1;
				}
				if(!exists($usedRouter{$drouter}))
				{
					$needRouter{$drouter}->{$dip}=1;
				}
			}
			next;
		}

		die "Unhandled line in $file:$linecount ::  '$_'";
	}
	foreach $router (keys %needRouter)
	{
		print "Router $router nAlly=",scalar (keys %{$needRouter{$router}});
		foreach $ip ( keys %{$needRouter{$router}})
		{
			print " $ip";
		}
		print "\n";
	}
}



############################################################################
sub interestingIP
{
	my ($ip)=@_;
	return 1 if(scalar(@prefixes) == 0);	# if no prefixes specified, interested in everything
	foreach $prefix (@prefixes)
	{
		return 1 if(&prefixMatch($prefix,$ip));
	}
	return 0;	# didn't match any of our interesting prefixes
}
############################################################################
sub prefixMatch
{
	my ($prefix,$ip)=@_;
	my ($prefixIP,$prefixMask)=split /\//,$prefix;
	my ($pInt,$ipInt);
	$pInt=&iptoInt($prefixIP);
	$ipInt=&iptoInt($ip);
	$bits = ~((2**(32-$prefixMask))-1);	# 16 --> 0xffff0000
	return (($pInt & $bits) == ($ipInt & $bits));
}
############################################################################
sub iptoInt	# "255.0.255.1" --> 0xff00ff01
{
	my ($ip)=@_;
	my ($sum,@octets);
	@octets=split /\./,$ip;
	$sum += $octets[0]*(2**24) 	if(defined $octets[0]);
	$sum += $octets[1]*(2**16) 	if(defined $octets[1]);
	$sum += $octets[2]*(2**8) 	if(defined $octets[2]);
	$sum += $octets[3] 		if(defined $octets[3]);
	return $sum;
}

######################################################################################################

sub ip2hostname
{
	my ($host) = (undef);
	my ($ip) = @_;
	if($ip eq "unknown")
	{
		$host = "unknown";
	}
	elsif(exists$ipcache{$ip})
	{
		$host = $ipcache{$ip};
	}
	else
	{
		print STDERR "Resolving $ip... ";
		$host = gethostbyaddr(inet_aton($ip),AF_INET) || "??";
		print STDERR " '$host' done.\n";
		$ipcache{$ip}=$host unless($host eq "??");
	}
	return $host;
}

#######################################################################################################
sub readIpCache
{
	%ipcache = ();
	open CACHE, "$IpCacheFile" or return;   #file not found
		while(<CACHE>)
		{
			@line=split;
			$ipcache{$line[0]}=$line[1];
		}
}
#######################################################################################################
sub writeIpCache
{
	open CACHE, ">$IpCacheFile.tmp" or die "open $IpCacheFile.tmp : $!";
	foreach $key (sort keys %ipcache)
	{
		print CACHE "$key $ipcache{$key}\n";
	}
	close CACHE;
	system("mv $IpCacheFile $IpCacheFile.old") if(-f $IpCacheFile);
	system("mv $IpCacheFile.tmp $IpCacheFile");
}

