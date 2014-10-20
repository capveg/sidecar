#!/usr/bin/perl -w



if((@ARGV>=1)&&($ARGV[0] eq "-v"))
{
	$Verbose=1;
	shift @ARGV;
}
if((@ARGV>=1)&&($ARGV[0] eq "-"))
{
	shift @ARGV;
	push @ARGV,<>;
}

print STDERR "In verbose mode\n" if($Verbose);

$routercount=1;

foreach $file (@ARGV)
{
	my %links;
	open IN, $file or die "open $file:$!";

	@filen = split /[-:,]+/,&basename($file);
	$src_ip=$filen[1];
	$links{0}->{$src_ip}++;		# hack in source hop

	while(<IN>)
	{
		next unless(/RECV/);
		next if(/RR,/);		# ignore 
		@line=split;
		#- RECV TTL 1 it=1 from    128.208.4.100 (255)   ROUTER   rtt=0.000305 s t=1147905262.069736 Macro
		$ttl=$line[3];
		$ip=$line[6];
		$links{$ttl}->{$ip}++;
	}
	foreach $ttl ( sort { $a <=> $b} keys %links)
	{
		$nIPs=0;
		$routertype="R";
		#$routertype="S" if($ttl==0); # causes problems; not worth it
		foreach $ip ( keys %{$links{$ttl}})
		{
			$nIPs++;
			next unless(exists $links{$ttl+1});
			foreach $dst (keys %{$links{$ttl+1}})
			{
				#Link  R10_B:198.32.8.81 -- R1_B:198.32.8.80 : RR
				$allLinks{"Link $routertype".&ip2router($ip).":$ip -- R".&ip2router($dst).":$dst : TR"}++;
			}
		}
		print STDERR "$file ttl=$ttl has TR route change\n" if($nIPs>1);
	}

}

foreach $router (keys %ip2routername)
{
	print "Router R$ip2routername{$router} nAlly=1 $router\n";
}
foreach $link (keys %allLinks)
{
	print "$link\n";
}


sub basename
{
	my ($foo)=@_;
	$foo= `basename $foo`;
	chomp $foo;
	return $foo;
}

sub ip2router
{
	my ($ip)=@_;
	return $ip2routername{$ip} if(exists $ip2routername{$ip});
	$ip2routername{$ip}=$routercount++;
	return $ip2routername{$ip};
}
