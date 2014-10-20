#!/usr/bin/perl -w

# uncomment for debuging
#$debug=1;
use Socket;

$ignoreUnknownLinks=0;
$resolveIPs=0;
$IpCacheFile = "$ENV{'HOME'}/.ipcache";


@prefixes=();

if(@ARGV>=1 && $ARGV[0] eq "-debug")
{
	$debug=1;
	shift @ARGV;
}

while(@ARGV>=2 && $ARGV[0] eq "-prefix")
{
	print STDERR "Adding $ARGV[1] to selection criteria\n";
	usage("Bad prefix format '$ARGV[1]'\n") unless($ARGV[1] =~/\d+\/\d+/);
	$ignoreUnknownLinks=1;	# implied
	$resolveIPs=1;	# implied
	push @prefixes,$ARGV[1];
	shift @ARGV;
	shift @ARGV;
}

if($debug)
{
	$resolveIPs=1;
}

$left = shift or usage();
$right = shift or usage();

$diffcount=0;


&readIpCache() if($resolveIPs);



# read in files
%leftadj = &parseAdj($left);
%rightadj = &parseAdj($right);

%newips=();

# print transtions from the left file to the right


# foreach ip in the left aliases list, test if exists in the right list
foreach $ip ( keys %{$leftadj{"aliases"}})
{
	if(!exists $rightadj{"ips"}->{$ip})
	{
		$newips{$ip}=1;
		next;
	}
	foreach $dip ( keys %{$leftadj{"aliases"}->{$ip}})
	{
		if(!exists $rightadj{"ips"}->{$dip})
		{
			$newips{$dip}=1;	# dip didn't show up in other trace at all
			next;
		}
		#next if ($ip eq $dip);
		if(exists $rightadj{"aliases"}->{$ip}->{$dip})
		{
			delete $rightadj{"aliases"}->{$ip}->{$dip};
			$dns1=$resolveIPs?&ip2hostname($ip):"";
			$dns2=$resolveIPs?&ip2hostname($dip):"";
			print "common ALIAS $ip $dip	$dns1 	$dns2\n" if($debug);
		}
		else
		{
			$dns1=$resolveIPs?&ip2hostname($ip):"";
			$dns2=$resolveIPs?&ip2hostname($dip):"";
			print "REMOVING ALIAS $ip $dip	$dns1	$dns2\n";
			$diffcount++;
		}
	}
}


foreach $ip ( keys %{$leftadj{"links"}})
{
	if(!exists $rightadj{"ips"}->{$ip})
	{
		$newips{$ip}=1;
		next;
	}
	foreach $dip ( keys %{$leftadj{"links"}->{$ip}})
	{
		if(!exists $rightadj{"ips"}->{$dip})
		{
			$newips{$dip}=1;	# dip didn't show up in other trace at all
			next;
		}
		if((exists $rightadj{"links"}->{$ip}) && (exists $rightadj{"links"}->{$ip}->{$dip}))
		{
			$dns1=$resolveIPs?&ip2hostname($ip):"";
			$dns2=$resolveIPs?&ip2hostname($dip):"";
			print "common LINK $ip $dip $leftadj{'links'}->{$ip}->{$dip}/$rightadj{'links'}->{$ip}->{$dip}	$dns1	$dns2\n" if($debug);
			delete $rightadj{"links"}->{$ip}->{$dip};
		}
		else
		{
			$dns1=$resolveIPs?&ip2hostname($ip):"";
			$dns2=$resolveIPs?&ip2hostname($dip):"";
			print "REMOVING LINK $ip $dip $leftadj{'links'}->{$ip}->{$dip}	$dns1	$dns2\n";
			$diffcount++;
		}
	}
}
# now list the ips that were not common seperately
foreach $ip (keys %newips)
{
	$dns=$resolveIPs?&ip2hostname($ip):"";
	print "REMOVING IP $ip	$dns\n";
	$diffcount++;
}
%newips=();

# anything that is still in the $righadj is an addition

foreach $ip ( keys %{$rightadj{"aliases"}})
{
	if(!exists $leftadj{"ips"}->{$ip})
	{
		$newips{$ip}=1;
		next;
	}
	foreach $dip ( keys %{$rightadj{"aliases"}->{$ip}})
	{
		if(!exists $leftadj{"ips"}->{$dip})
		{
			$newips{$dip}=1;	# dip didn't show up in other trace at all
			next;
		}
		$dns1=$resolveIPs?&ip2hostname($ip):"";
		$dns2=$resolveIPs?&ip2hostname($dip):"";
		print "ADDING ALIAS $ip $dip	$dns1	$dns2\n";
		$diffcount++;
	}
}

foreach $ip ( keys %{$rightadj{"links"}})
{
	if(!exists $leftadj{"links"}->{$ip})
	{
		$newips{$ip}=1;
		next;
	}
	foreach $dip ( keys %{$rightadj{"links"}->{$ip}})
	{
		if(!exists $leftadj{"links"}->{$dip})
		{
			$newips{$dip}=1;	# dip didn't show up in other trace at all
			next;
		}
		$dns1=$resolveIPs?&ip2hostname($ip):"";
		$dns2=$resolveIPs?&ip2hostname($dip):"";
		print "ADDING LINK $ip $dip $rightadj{'links'}->{$ip}->{$dip}	$dns1	$dns2\n";
		$diffcount++;
	}
}
# now list the ips that were not common seperately
foreach $ip (keys %newips)
{
	$dns=$resolveIPs?&ip2hostname($ip):"";
	print "ADDING IP $ip	$dns\n";
	$diffcount++;
}

&writeIpCache() if($resolveIPs);

exit $diffcount;


############################################################################
sub usage
{
	print STDERR "usage:: diffadj.pl [-debug] [-prefix 198.32/16 [...]] left.adj right.adj\n";
	exit(1);
}
############################################################################
sub parseAdj
{
	my $file = shift @_;
	my %data = ();
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
				$data{"ips"}->{$ip}=1;
				$interesting=1 if(&interestingIP($ip));
			}
			next unless($interesting);
			foreach $ip (@line[3..$#line])
			{
				$data{"ips"}->{$ip}=1;
				foreach $dip(@line[3..$#line])
				{
					$data{"ips"}->{$dip}=1;
					$data{"aliases"}->{$dip}->{$ip}=1;
					$data{"aliases"}->{$ip}->{$dip}=1;
				}
			}
			next;
		}
		if(/^Link/)
		{
			next if(/UNKNOWN/ && $ignoreUnknownLinks);
			@line=split;
			($srouter,$sip)=split /:/, $line[1];
			($drouter,$dip)=split /:/, $line[3];
			$data{"ips"}->{$sip}=1;
			$data{"ips"}->{$dip}=1;
			next unless(&interestingIP($sip) || &interestingIP($dip));
			$data{"links"}->{$sip}->{$dip}=$line[5];
			$data{"links"}->{$dip}->{$sip}=$line[5];
			next;
		}

		die "Unhandled line in $file:$linecount ::  '$_'";
	}
	return %data;
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

