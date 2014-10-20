#!/usr/bin/perl -w

# parse through raw data and prints some statistics about it

$dir = shift || "";

@files = <>;


foreach $file ( @files)
{
	next if($file eq "." or $file eq "..");
	open F, "$dir$file" or die "Couldn't open $dir/$file : $!";
	while(<F>)
	{
		next unless(/RECV/);
		@ips=grep /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, split;
		$traceroute{$ips[0]}++;
		for($i=1;$i<@ips;$i++)
		{
			$recordroute{$ips[$i]}++;
		}
#		@line = split;
#		#$ptype = $line[-1];	# 'TraceRoute', 'Macro', etc..
#		$ip = $line[6];
#		$traceroute{$ip}++;
#		if((scalar(@line)>12) and ($line[12] =~ "(RR|NOP),"))
#		{
#			#$recordroute{$ip}++;
#			for($i=15;$i<@line;$i+=4)
#			{
#				$recordroute{$line[$i]}++;
#			}
#		}
	}
}

$nTR= scalar(keys %traceroute);
$nRR= scalar(keys %recordroute);

$tracerouteonly=0;
$recordrouteonly=0;
$both=0;

foreach $ip (keys %traceroute)
{
	if(exists $recordroute{$ip})
	{
		$both++;
		print "$ip B\n";
		delete $recordroute{$ip};
	}
	else
	{
		$tracerouteonly++;
		print "$ip T\n";
	}
	#delete $traceroute{$ip};
}

# anything that's left is RR only
$recordrouteonly=scalar(keys %recordroute);
foreach $ip (keys %recordroute)
{
	print "$ip R\n";
}

printf STDERR "STAT: Total Unique: %d Total TR %d Total RR %d  TR only %d  RR only %s \n",
	$both+$tracerouteonly+$recordrouteonly, $nTR,$nRR, $tracerouteonly,$recordrouteonly;

