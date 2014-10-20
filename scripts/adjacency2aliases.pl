#!/usr/bin/perl -w


foreach $file ( @ARGV)
{
	open F, $file or warn "file open: $file:$!";
	while(<F>)
	{
		next if(/Link/);
		chomp;
		# $_ = "Router R12_A nAlly=2 140.142.155.15 128.208.4.100"
		@line = split;
		for($i=3;$i<@line;$i++)
		{
			for($j=($i+1);$j<@line;$j++)
			{
				if(($line[$i] cmp $line[$j])<0)
				{
					print "$line[$i] $line[$j]\n";
				}
				else
				{
					print "$line[$j] $line[$i]\n";
				}
			}
		}
	}
}
