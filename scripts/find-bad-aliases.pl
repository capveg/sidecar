#!/usr/bin/perl -w

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
$PrintBadOnly=0;
if((@ARGV>0)&&($ARGV[0] eq "-b"))
{
	$PrintBadOnly=1;
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
	print STDERR "find-bad-aliases.pl [-b] file.adj [...]\n";
	die "usage";
}


foreach $file (@ARGV)
{
	$badcount=$goodcount=$total=0;
	open F, $file or die "open $file: $!";
	while(<F>)
	{
		next if(/Link/);
		chomp;
		@line=split;
		#$_="Router R10_A nAlly=2 62.40.124.34 188.1.18.217"
		shift @line;	# remove "Router"
		$routername = shift @line; 	# remove routername
		shift @line;	# remove nAlly=?
		&testaliases(@line);
	}
	$percent = "-";
	$percent = 100 * $badcount/($badcount+$goodcount) if(($badcount+$goodcount)>0);
	print "TOTAL: $file   bad $badcount good $goodcount total $total falseP $percent %\n" unless($PrintBadOnly);
}

exit($badcount);


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
				print "BAD alias: $routername $ip $alias :: $file\n" unless($Quiet);
				$badcount++;
			}
			elsif(exists $goodaliases{"$ip $alias"})
			{
				print "GOOD alias: $routername $ip $alias :: $file\n" unless($Quiet||$PrintBadOnly);
				$goodcount++;
			}
		}
	}
}
