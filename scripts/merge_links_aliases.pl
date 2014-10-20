#!/usr/bin/perl -w

# usage: $0 foo.tr-adj-no-aliases foo.aliases > foo.adj


use lib $ENV{"HOME"}."/swork/sidecar/scripts";
use Adjacency;

%label2const = 
   (
   	"RR" => $RR,
	"TR" => $TR,
	"STR" => $STR,
	"HIDDEN" => $Hidden,
	"UNKNOWN" => $Unknown,
	);


$trace="<stdin";
$ttl=-1;
$iteration=-1;
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

$linecount=0;

open F, $ARGV[0] or die "$file : open :$!";
while(<F>)
{
	$linecount++;
	chomp;
	if(/^(Router|Endhost|NAT|HIDDEN|Source)/)
	{
		#Router Router6_MPLS nAlly=2 206.196.177.49 205.171.203.88
		@line = split;
		$router = undef;
		#$routerline = $line[1];
		#@r = split /\_/,$routerline;
		# we need a name for this router
		# first, try to find the first ip address that is already assigned a name
		for($i=3; $i<@line;$i++)
		{
			if(exists $ip2router{$line[$i]})
			{
				# found it
				$router=$ip2router{$line[$i]};
				last;
			}
		}
		# create unique name for router, if we didn't just find 
		$router = newRouter($line[0]) unless($router);
		
		for($i=3;$i<@line;$i++)
		{
			addInterface($line[$i],$router);  # add each of router's interefaces
		}
		# Don't carry over the type information; it's probably all wrong anyway
		#for($i=1;$i<@r;$i++)
		#{
		#	markRouter($router,$r[$i],"merge $router $i");	# mark router with each of it's attributes
		#}
		next;
	}
	if(/^Link/)
	{
		# Link  Router10:205.171.8.222 -- Router11:205.171.251.14 : RR
		@line = split;
		($srouter,$sip) = split /:/, $line[1];
		($drouter,$dip) = split /:/, $line[3];
		if(!defined($srouter) || !defined($sip) || 
			!defined($drouter) || !defined($dip) || !defined($line[5]))
		{
			print STDERR "Bad line $ARGV[0]:$linecount :: '$_'\n";
			next;
		}


		# make a new name for router
		$srouter = $ip2router{$sip} || newRouter(&name2type($srouter));	
		# make a new name for router
		$drouter = $ip2router{$dip} || newRouter(&name2type($drouter));
		# note: addLink calls addInterface for each pair, to ensure correctness
		die "Bad line parse '$_' :: $line[5] + $label2const{$line[5]})\n" unless $label2const{$line[5]};
		addLink($srouter,$sip,$drouter,$dip,$label2const{$line[5]});

		next;
	}
	die "Unknown line $_ \n";
}

open F, $ARGV[1] or die "$file : open :$!";	# aliases file
while(<F>)
{
	chomp;
	@line=split;
	$router=undef;
	foreach $ip (@line)
	{
		$router=$ip2router{$ip};
		last if(defined($router));		# grab the first defined router
	}
	next unless(defined($router));			# tried to add an alias for IPs not in the adj
	foreach $ip (@line)
	{
		if(defined($ip2router{$ip}))		# if ip used in this adj file
		{
			addInterface($ip,$router);	# assign it to the first we found
		}
	}
}


&markSameRouters();		# agregate all routers and merge things as necess
&dumpRouterList();		# print




##################################
sub name2type
{
	my($router)=@_;
	if($router =~/^R/)
	{
		return "ROUTER";
	}elsif($router=~/^E/)
	{
		return "ENDHOST";
	}
	elsif($router=~/^H/)
	{
		return "HIDDEN";
	}
	elsif($router=~/^N/)
	{
		return "NAT";
	}
	else
	{
		die "name2type :: unknown router type $router\n";
	}
}
