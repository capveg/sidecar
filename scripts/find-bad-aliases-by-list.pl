#!/usr/bin/perl -w

##############
# does a uniq across aliases, then prints the counts
#	different from find-bad-aliases.pl b/c 
#	the counts from find-bad-aliases.pl are local
#	and here they are global without merging
#
#


$badaliases = $ENV{"HOME"}."/swork/sidecar/scripts/bad-aliases";
$goodaliases = $ENV{"HOME"}."/swork/sidecar/scripts/good-aliases";

# read badaliases file into hash
open BAD, $badaliases or die "open $badaliases :$!";
while(<BAD>)
{
	chomp;
	@line = split;
	$badaliases{"$line[0] $line[1]"}=1;
	$badaliases{"$line[1] $line[0]"}=1;
}
# read goodaliases file into hash
open GOOD, $goodaliases or die "open $goodaliases :$!";
while(<GOOD>)
{
	chomp;
	@line = split;
	$goodaliases{"$line[0] $line[1]"}=1;
	$goodaliases{"$line[1] $line[0]"}=1;
}

$Quiet=0;
if((@ARGV>0)&&($ARGV[0] eq "-q"))
{
	$Quiet=1;
	shift @ARGV;
}

if(@ARGV == 0 )
{
	@files=<>;
	chomp @files;
	push @ARGV, @files;
}

if(@ARGV==0)
{
	print STDERR "find-bad-aliases.pl file.adj [...]\n";
	die "usage";
}


foreach $file (@ARGV)
{
	$badcount=$goodcount=0;
	open F, $file or die "open $file: $!";
	while(<F>)
	{
		next if(/Link/);
		chomp;
		@line=split;
		#$_="11.2.4.5 1.35.5.6
		&testaliases(($line[0],$line[1]));
	}
	print "TOTAL: $file   bad $badcount good $goodcount total $total falseP ",100*$badcount/($badcount+$goodcount),"\n";
}



sub testaliases
{
	my @aliases = @_;
	my $ip;

	while(scalar(@aliases)>1)
	{
		$ip = shift @aliases;
		foreach $alias ( @aliases)
		{
			$total++;
			if(exists $badaliases{"$ip $alias"})
			{
				print "BAD alias: $ip $alias :: $file\n" unless($Quiet);
				$badcount++;
			}
			elsif(exists $goodaliases{"$ip $alias"})
			{
				print "GOOD alias: $ip $alias :: $file\n" unless($Quiet);
				$goodcount++;
			}
		}
	}
}
