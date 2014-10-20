#!/usr/bin/perl -w
# first pass on generating rpt times


$maxiteration =-1;
$maxttl = -1;

$payload = 9334;	# FIXME
$flapping=0;

while(<>)
{
	last if(/TRANSITION/);
	next unless(/RECV/);
	chomp;
	@line = split;
	$ttl = $line[3];
	$iteration = $line[4];
	$iteration =~ s/iteration\?*=//;
	$time = $line[11];
	$time =~ s/time=//;
	$type = $line[@line-1];
	$times[$iteration][$ttl]->{$type}=$time;
	$times[$iteration][$ttl]->{"ip-$type"}=$line[6];
	$times[$iteration][$ttl]->{"payload"}=$payload;
	if(/NOP/)
	{
		$times[$iteration][$ttl]->{"rr"}=1;
	}
	else
	{
		$times[$iteration][$ttl]->{"rr"}=0;
	}
	$maxttl = $ttl if($ttl>$maxttl);
	$maxiteration = $iteration if($iteration>$maxiteration);
}

for($ttl=1;$ttl<=$maxttl;$ttl++)
{
	for($iteration=0;$iteration<=$maxiteration;$iteration++)
	{
		if((defined $times[$iteration][$ttl]->{"Macro"}) 
			and (defined $times[$iteration][$ttl]->{"Pollo"}))
		{
			$delta = ($times[$iteration][$ttl]->{"Pollo"})-($times[$iteration][$ttl]->{"Macro"});
			if($times[$iteration][$ttl]->{"rr"}==1)
			{
				$count = $times[$iteration][$ttl]->{"payload"} +80 * ($maxttl-$ttl);
			}
			else
			{
				$count = $times[$iteration][$ttl]->{"payload"} +40 * ($maxttl-$ttl);
			}
			$bw = $count/$delta;
			if($times[$iteration][$ttl]->{"ip-Macro"} eq $times[$iteration][$ttl]->{"ip-Pollo"})
			{
				printf "ttl $ttl\titeration $iteration\tip=%20s\t\tdelta=$delta bytes=$count \t\tbw $bw B/s %s %s\n",
					$times[$iteration][$ttl]->{"ip-Macro"}, 
						$times[$iteration][$ttl]->{"rr"}?"RR":"-",
						$flapping?"FLAPPING":"";
			}
			else
			{
				printf "ttl $ttl\titeration $iteration\tip= FLAP (%20s!=%20s)\t\tdelta=$delta bytes=$count \t\tbw $bw B/s\n",
						$times[$iteration][$ttl]->{"ip-Macro"},$times[$iteration][$ttl]->{"ip-Pollo"};
				$flapping=1;
			}
			next;	# skip to next entry
		}
		printf "ttl $ttl\titeration $iteration\tip=%20s\t\t", $times[$iteration][$ttl]->{"ip"}?$times[$iteration][$ttl]->{"ip"}:"unknown";
		print " no Macro " unless(defined $times[$iteration][$ttl]->{"Macro"});
		print " no Pollo " unless(defined $times[$iteration][$ttl]->{"Pollo"});
		print "\n";
	}
}

