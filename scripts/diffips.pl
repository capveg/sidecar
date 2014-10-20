#!/usr/bin/perl -w

open F1, "$ARGV[0]" or die "open : $ARGV[0]: $!";

while(<F1>)
{
	chomp;
	$ip1{$_}=1;
}
open F2, "$ARGV[1]" or die "open : $ARGV[1]: $!";

while(<F2>)
{
	chomp;
	$ip2{$_}=1;
}

foreach $ip (keys %ip1)
{
	if (exists $ip2{$ip})
	{
		delete $ip2{$ip};
	}
	else
	{
		print "- $ip\n";
	}
}

foreach $ip (keys %ip2)
{
	print "+ $ip\n";
}
