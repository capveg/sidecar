#!/usr/bin/perl -w
$simplified=0;

if(@ARGV>=1 && $ARGV[0] eq "-s")
{
	$simplified=1;
	shift @ARGV;
}

while(<>)
{
	my %r;
	next if(/Link/);
	@line=split;
	@name= split /_/,$line[1];

	shift @name;
	$type=join "_",@name;
	$routercount++ unless($type =~/^\s*$/);
	if(!$simplified)
	{
		$types{$type}++;
	}
	else
	{
		# try to break down what the diff types are "intelligently"
		for($i=0;$i<@name;$i++)
		{
			$r{$name[$i]}++;
		}
		if($r{"A"} && $r{"B"})
		{
			$types{"A_B"}++;
		}
		else
		{
			$types{"A"}++ if ($r{"A"});
			$types{"B"}++ if ($r{"B"});
		}
		# something is unknown only if not classified elsewhere
		$types{"U"}++ if($r{"U"} && !($r{"A"} || $r{"B"}|| $r{"C"}));
		if($r{"N"})
		{
			if($r{"A"})
			{
				$types{"A_N"}++;
			}
			elsif($r{"B"})
			{
				$types{"B_N"}++;
			}
			elsif($r{"C"})
			{
				$types{"C_N"}++;
			}
			else
			{	
				$types{"N"}++;
			}
		}
		
		foreach $key (keys %r)	# everything else just gets counted
		{
			next if($key =~/^(A|B|U|N)$/);
			$types{$key}++;
		}
	}
}

foreach $key ( sort { $types{$b} <=> $types{$a}} keys %types)
{
	printf "%30s		: 	$types{$key} 	%3.2f %%\n",$key,100*$types{$key}/$routercount;
}
print "--------------------\nTotal : $routercount\n";
