#!/usr/bin/perl -w

# nspring's ally format is:
#	<router id> <ip>
#	<router id> <ip>
#	... 
#	
#	such that all ips with same router id are aliases (sorted)
# this script converts them to "<ip> <ip> <ip> <ip>" format, like iplane

$outputAsPairs=0;

if(@ARGV>0 && $ARGV[0] eq "-pairs")
{
	$outputAsPairs=1;
	shift @ARGV;
}

@aliases=();
$lastrid=-1;

while(<>)
{
	($rid,$ip)= split;
	if($rid == $lastrid)
	{
		push @aliases,$ip;
	}
	else
	{
		if($lastrid != -1)
		{
			&outputAliases(@aliases);
			@aliases = ($ip);
			$lastrid=$rid;
		}
		else
		{
			push @aliases,$ip;
			$lastrid=$rid;
		}
	}
}

&outputAliases(@aliases);

sub outputAliases
{
	my (@aliases)=@_;
	if($outputAsPairs==0)
	{
		print join " ",@aliases, "\n";
	}
	else	# then do out aliases in a different format
	{
		for($i=0;$i<@aliases;$i++)
		{
			for($j=$i+1;$j<@aliases;$j++)
			{
				print "$aliases[$i] $aliases[$j]\n";
			}
		}
	}
}
