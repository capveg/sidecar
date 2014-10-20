#!/usr/bin/perl -w

$file = shift @ARGV || die "Usage: $0 [-ccdf] foo.adj\n";
$ccdf=0;

if($file eq "-ccdf")
{
	$file = shift @ARGV || die "Usage: $0 [-ccdf] foo.adj\n";
	$ccdf=1;
}



open ADJ, "$file" or die "open : $file:$!";
while(<ADJ>)
{
	next unless(/Link/);
	@line=split;
	# Link  R10_B:198.32.8.81 -- R1_B:198.32.8.80 : RR
	next if($line[5] eq "UNKNOWN");
	($srouter,$sip) = split /:/,$line[1];
	($drouter,$dip) = split /:/,$line[3];
	$sip=$dip=0;		# shut up -w
	$degree{$srouter}++ unless ($srouter =~/^(S)/);	# skip sources
	$degree{$drouter}++ unless ($drouter =~/^(S)/);	# skip sources
}


$nRouters=scalar(keys %degree);
$routerCount=0;
if($ccdf)
{
	# print CCDF
	foreach $router ( sort { $degree{$a} <=> $degree{$b}} keys %degree)
	{
		#print 100-(100*$routerCount/$nRouters)," $routerCount $degree{$router}\n";
		print " $degree{$router} ",100-(100*$routerCount/$nRouters)," $routerCount $router\n";
		$routerCount++;
	}
}
else
{
	# print CDF
	foreach $router ( sort { $degree{$a} <=> $degree{$b}} keys %degree)
	{
		#print 100*($routerCount/$nRouters)," $routerCount $degree{$router}\n";
		print " $degree{$router} ",100*($routerCount/$nRouters)," $routerCount $router\n";
		$routerCount++;
	}
}

