#!/usr/bin/perl -w

# only need to run this on old generated dlv files w/o unique ids
# OBSOLETE


foreach $file (@ARGV)
{
	open IN, $file or die "Couldn't open $file:$!";
	open OUT, ">$file.uniq-dlv" or die "Couldn't open $file.uniq-dlv: $!";

	@fname=split /-/,`basename $file`;

	$src = $fname[1];
	$src =~ s/:\d+$//;	# chop off port
	$src =~ tr/\./_/;
	$src="ip$src";

	$dst = $fname[2];
	$dst =~ s/:\d+$//;	# chop off port
	$dst =~ tr/\./_/;
	$dst="ip$dst";
	$prefix=$src."_".$dst;
	
	while(<IN>)
	{
		chomp;
		if(/^(rr|tr|tr_only)\((\d+),(\S+)/)
		{
			print OUT "$1(".$prefix."_$2,$3\n";
		}
		elsif(/^(probePair|trPair)\((\d+),(\d+)(\S+)/)
		{
			print OUT "$1(".$prefix."_$2,$prefix"."_$3$4\n";
		}
		else
		{
			print OUT "$_\n";
		}
	}
	print "$file done\n";
}
