#!/usr/bin/perl -w


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
			$routerline = $line[1];
			$router = undef;
			@r = split /\_/,$routerline;
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
			for($i=1;$i<@r;$i++)
			{
				markRouter($router,$r[$i],"merge $router $i");	# mark router with each of it's attributes
			}
			next;
		}
		if(/^Link/)
		{
			# Link  Router10:205.171.8.222 -- Router11:205.171.251.14 : RR
			@line = split;
			($srouter,$sip) = split /:/, $line[1];
			($drouter,$dip) = split /:/, $line[3];
			# make a new name for router
			$srouter = $ip2router{$sip} || newRouter(&name2type($srouter));	
			# make a new name for router
			$drouter = $ip2router{$dip} || newRouter(&name2type($drouter));
			# note: addLink calls addInterface for each pair, to ensure correctness
			addLink($srouter,$sip,$drouter,$dip,$label2const{$line[5]});

			next;
		}
		die "Unknown line $_ \n";
	}
}

&markSameRouters();
&dumpRouterList();


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
