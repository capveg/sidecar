#!/usr/bin/perl -w

$index=0;
$ccdf=0;

$minDelta=0.0001;

if(@ARGV>0 && $ARGV[0] eq "-c")
{
	$ccdf=1;
	shift @ARGV;
}
if(@ARGV>0 && $ARGV[0] eq "-k")
{
	$index=$ARGV[1];
	shift @ARGV;
	shift @ARGV;
}

while(<>)
{
	chomp;
	@line=split;
	push @data,$line[$index];
}

@sorteddata = sort { $a <=> $b} @data;

if($ccdf)
{
	print "0 1\n";
	$last=1;
	for($i=1;$i<=scalar(@data);$i++)
	{
		$p = 1-($i/scalar(@data));
		if(($last-$p)>$minDelta)
		{
			print $sorteddata[$i-1]," ",$p,"\n";
			$last=$p;
		}
	}
} 
else 
{
	print "0 0\n";
	$last=0;
	for($i=1;$i<=scalar(@data);$i++)
	{
		$p = $i/scalar(@data);
		if(($p-$last)>$minDelta)
		{
			print $sorteddata[$i-1]," ",$p,"\n";
			$last=$p;
		}
	}
}
