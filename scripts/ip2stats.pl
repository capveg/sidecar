#!/usr/bin/perl -w

# read a list of ip files generated from data2stats.pl, and output statistics about them in aggregate

@files=();

if(@ARGV==0)
{
	@files=<>;
	chomp @files;
}

push @files,@ARGV;

foreach $file (@files)
{
	open F, $file or die "open: $file: $! ";
	while(<F>)
	{
		($ip,$type) = split;
		if(!exists $list{$ip}|| $type eq "B")
		{
			$list{$ip}=$type;
		}
		else
		{
			# if found both, then become B
			if($type ne $list{$ip})
			{
				$list{$ip}="B";
			}
		}

	}
}

# done parseing, now do stats

$nRR=$nTR=$total=0;

foreach $ip ( keys %list)
{
	$total++;
	$nRR++ if($list{$ip} eq "R");
	$nTR++ if($list{$ip} eq "T");
	print "$ip\n";
}

print STDERR "TOTALS: total $total nRR $nRR nTR $nTR\n";


