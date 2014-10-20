#!/usr/bin/perl -w

$f1 = shift or &usage();
$f2 = shift or &usage();

$d1 = parseFile($f1);
$d2 = parseFile($f2);


























#################################################################################################
sub parseFile
{
	my ($file) = @_;
	my $ref;
	open F, $file or die " open: $f: $!";
	while(<F>)
	{
		chomp;
		if(!/Link/)
		{
			#$_ = "Router R4_DropsRR nAlly=1 4.68.105.30 4.68.105.123"
			@line = split;
			@r = split /\_/,$line[1];
			$router = $line[1];
			for($i=3;$i<scalar(@line);$i)
			{
				die "duplicate entry for $line[$i]: $router and ",$ref->{"ip2router"}->{$line[$i]},"\n" 
					if(exists $ref->{"ip2router"}->{$line[$i]});
				$ref->{"ip2router"}->{$line[$i]}=$router;
				$ref->{"routers"}->{$router}->{"ifs"}->{$line[$i]}=1;
			}
			for($i=1;$i<scalar(@r);$i++)
			{
				$ref->{"routers"}->{$router}->{"types"}->{$r[$i]}=1;
			}
		}
		else
		{
			#$_ "


		}

	}
	return $ref;
}
