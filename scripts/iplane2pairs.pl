#!/usr/bin/perl -w

# iplane's ally format is:
#	<ip><ip><ip><ip><ip> 
#	<ip><ip><ip> 
#	... 
#	
# this script converts them to "<ip> <ip>\n" format, like output of adjacency2pairs

@aliases=();

while(<>)
{
	@aliases=split;
	for($i=0;$i<@aliases;$i++)
	{
		for($j=$i+1;$j<@aliases;$j++)
		{
			print "$aliases[$i] $aliases[$j]\n";
		}
	}
}
