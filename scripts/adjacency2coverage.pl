#!/usr/bin/perl -w

$IgnoreUnknownLinks=1;


$dir = $ENV{"HOME"}."/swork/sidecar";

$Verbose=0;
if((@ARGV>=1)&&($ARGV[0] eq "-v"))
{
	$Verbose=1;
	shift @ARGV;
}

if(@ARGV == 0)
{
	push @ARGV, <>;
	chomp @ARGV;
}


#############
# Step 1: Slurp up files

foreach $file (@ARGV)
{
	open F, $file or die "$file : open :$!";
	while(<F>)
	{
		chomp;
		if(/^(Router|Endhost|NAT|HIDDEN|Source)/)
		{
			#Router Router6_MPLS nAlly=2 206.196.177.49 205.171.203.88
			@line = split;
			$router = $line[1];

			for($i=3;$i<@line;$i++)
			{
				$routers{$router}->{$line[$i]}=1;  # add each of router's interefaces
			}
			next;
		}
		elsif(/^Link/)
		{
			next if((/UNKNOWN/)&& $IgnoreUnknownLinks==1);
# Link  Router10:205.171.8.222 -- Router11:205.171.251.14 : RR
			@line = split;
			$type=$line[5];
			($srouter,$sip) = split /:/, $line[1];
			($drouter,$dip) = split /:/, $line[3];
			$sip=$dip;
			$adj{$srouter}->{$drouter}=1;
			$adj{$drouter}->{$srouter}=1;
			if(($type eq "RR") ||($type eq "STR"))	# was this link close enough for RR?
			{	
				$closeRouter{$srouter}=1;
				$closeRouter{$drouter}=1;
			}
			next;
		}
		die "Unknown line $_ \n";
	}
}

#############
# Step 2: read all the planetlab nodes from file
#	we do this instead of just using the nodes marked Source
#	b/c there used to be a bug where all nodes that were sources and endhosts
#	might have been arbitrarily marked one or the other... 
#	that bug might still exist

open F, "$dir/HOSTS.ip" or die "Open: $dir/HOSTS.ip: $!";

map { chomp; $plab{$_}=1} <F>;	# put each ip into hash


#############
# Step 3: step through each router and flood if it is in %plab

foreach $router ( keys %routers )
{
	$should_flood=0;
	foreach $if ( keys %{$routers{$router}})
	{
		$should_flood=1 if(exists $plab{$if});
	}
	flood($router) if($should_flood);
}

$nRR=scalar(keys %reachable);
$nClose=scalar(keys %closeRouter);
$total=scalar(keys %routers);

if($total>0)
{
	print "COVERAGE: total $total: by flooding: $nRR ",100*$nRR/$total,"; by IP routing $nClose ",100*$nClose/$total,"\n";
}
else
{
	print "COVERAGE: the file was empty !\n";
}


###############################################################
sub flood
{
	%visited=();		# zero this out
	print STDERR "Flooding from $router\n" if($Verbose);
	doFlood($router,9);
}


sub doFlood
{
	my ($router,$count)=@_;
	my ($target);
	return if(exists $visited{$router} && ($visited{$router}>$count));
	$reachable{$router}=1;
	$visited{$router}=$count;
	return if($count<=0);
	foreach $target ( keys %{$adj{$router}})
	{
		doFlood($target,$count-1) unless($visited{$target});
	}
}



