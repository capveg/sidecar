#!/usr/bin/perl -w

$IgnoreUnknownLinks=1;

$INFINITY=500000;


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
			$sources{$router}=1 if(/Source/);
			next;
		}
		elsif(/^Link/)
		{
			next if((/UNKNOWN/)&& $IgnoreUnknownLinks==1);
# Link  Router10:205.171.8.222 -- Router11:205.171.251.14 : RR
			@line = split;
			($srouter,$sip) = split /:/, $line[1];
			($drouter,$dip) = split /:/, $line[3];
			$sip=$dip;
			$adj{$srouter}->{$drouter}=1;
			$adj{$drouter}->{$srouter}=1;
			next;
		}
		die "Unknown line $_ \n";
	}
}

##############
# Step 2:  init router distances to something high
foreach $router (keys %adj)
{
	$routerDist{$router}=$INFINITY;
}


#############
# Step 3: step through each router, breadthfirst search
# 	and min the distance to each router from a source

@toVisit=keys %sources;	 # init list with Sources
$distance=0;

while(@toVisit>0)
{
	foreach $router (@toVisit)
	{
		next if($routerDist{$router}<=$distance);
		$routerDist{$router}=$distance;
		foreach $next (keys %{$adj{$router}})
		{
			 $toVisitNext{$next}=1;
		}
	}
	@toVisit=keys %toVisitNext;
	$distance++;
	%toVisitNext=();
}

#############
# Step 4: calc median distance

@distances = sort { $a <=> $b } values %routerDist;
$median_distance = $distances[ int(scalar(@distances)/2)];

############
# Step 5: partion data into near group (<median) and far group (<=median)
#	skip sources and things with infinite distance

foreach $router ( keys %routerDist)
{
	next if(($routerDist{$router}==0) || ($routerDist{$router}==$INFINITY));
	$degree = scalar(keys %{$adj{$router}});
	$key = "$degree,$routerDist{$router},$router";
	push @allData,$key;
	if($routerDist{$router}<$median_distance)
	{
		push @nearData,$key;
	}
	else
	{
		push @farData,$key;
	}
}

################
# Step 6: print in six columns all data for gnuplot

$lastNearDegree=$lastNearDist=$lastFarDegree=$lastFarDist=0;

@allData = sort datumSort @allData;
@nearData = sort datumSort @nearData;
@farData = sort datumSort @farData;

## print CCDF
for($i=0;$i<@allData;$i++)
{
	if($i<@nearData)
	{
		($lastNearDegree,$lastNearDist,$nearRouter)=split /,/, $nearData[$i];
		$nearpercent=1-($i/@nearData);
		$lastNearDist=$lastNearDist;
	}
	if($i<@farData)
	{
		($lastFarDegree,$lastFarDist,$farRouter)=split /,/, $farData[$i];
		$farpercent=1-($i/@farData);
		$lastFarDist=$lastFarDist;
	}
	($allDegree,$allDist,$allRouter)=split /,/, $allData[$i];
	$allpercent=1-($i/@allData);
	print "$allDegree $allpercent $lastNearDegree $nearpercent $lastFarDegree $farpercent $allDist $allRouter $nearRouter $farRouter\n";
}

#foreach $router ( sort { $degree{$a} <=> $degree{$b}} keys %degree)
#{
#	print " $degree{$router} ",100-(100*$routerCount/$nRouters)," $routerCount $router\n";
#	$routerCount++;
#}


sub datumSort
{
	($a_degree,$a_dist,$a_router)=split /,/,$a;
	($b_degree,$b_dist,$b_router)=split /,/,$b;
	$a_router=$b_router;	# to shut up -w
	$a_dist=$b_dist;	# to shut up -w
	return $a_degree <=> $b_degree;
}
