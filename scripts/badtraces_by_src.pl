#!/usr/bin/perl -w

# takes the foo.badtraces file from unionModels.pl and outputs fraction of bad traces by source

#./planetlab01.erin.utoronto.ca./data-142.150.3.246:37881-165.91.83.22:80-566.model              1

while(<>)
{
	chomp;
	$_=~s/\// /g;	# change / to ' '
	@line=split;
	$traces{$line[1]}+=$line[3];
	$total+=$line[3];
}

foreach $trace ( sort { $traces{$a} <=> $traces{$b} } keys %traces)
{
	printf "%s %d %f\n",$trace,$traces{$trace},100*$traces{$trace}/$total;
}
