#!/usr/bin/perl -w

# diff-aliases.pl [-noIntersect] base <-iplane|-pairs|-adj> foo <-iplane|-pairs|-adj> bar
# foreach alias 
#	if only in foo, then print into $base.left
#	if only in bar, then print into $base.right
# 	if in both, then print into $base.both
#  ignore aliases that reference IPs that are not in the other file
# supports alias formats of -iplane, -pairs (from adjacency2aliases.pl), and -adj (direct from adj files)

$IntersectionOnly=1;
die "Shit is horribly broken with makeAlly()" unless (&makeAlly("128.8.128.1","172.16.0.38") eq &makeAlly("172.16.0.38","128.8.128.1"));

sub usage
{
	print STDERR join "\n",@_ if(@_>0);
	print STDERR "\n\ndiff-aliases.pl base <-iplane|-pairs|-adj> foo <-iplane|-pairs|-adj> bar\n";
	exit 1;
}

$outname= shift || usage("Need more args");
$outname=~s/.adj//;
open LEFT, "> $outname.left" or die "open to write >$outname.left:$!";
open LEFT_IP, "> $outname.left_ip" or die "open to write >$outname.left:$!";
open RIGHT, "> $outname.right" or die "open to write >$outname.right:$!";
open RIGHT_IP, "> $outname.right_ip" or die "open to write >$outname.right:$!";
open BOTH, "> $outname.both" or die "open to write >$outname.both:$!";

if($ARGV[0] =~ /^-noIntersect/)
{
	$IntersectionOnly=0;
	shift @ARGV;
}

$leftType = shift || usage("Need more args");
$leftFile = shift || usage("Need more args");
$rightType = shift || usage("Need more args");
$rightFile = shift || usage("Need more args");

########################################################################################
## Main
########################################################################################

($left,$left_ips) = &readAliases($leftType,$leftFile);
($right,$right_ips) = &readAliases($rightType,$rightFile);




foreach $alias (keys %{$left})
{
	if(exists $right->{$alias})
	{
		print BOTH "$alias\n";
		delete $right->{$alias};
	}
	else
	{
		$skip=0;
		($ip1,$ip2) = split /\s+/,$alias;
		if($IntersectionOnly)
		{
		if(!exists $right_ips->{$ip1})
		{
			$left_only{$ip1}=1;
			$skip=1;
		}
		if(!exists $right_ips->{$ip2})
		{
			$left_only{$ip2}=1;
			$skip=1;
		}
		next if($skip);		# ignore aliases with unseen ips
		}
		print LEFT "$alias\n";
	}
}

foreach $alias (keys %{$right})
{
	$skip=0;
	($ip1,$ip2) = split /\s+/,$alias;
	if(!exists $left_ips->{$ip1})
	{
		$right_only{$ip1}=1;
		$skip=1;
	}
	if(!exists $left_ips->{$ip2})
	{
		$right_only{$ip2}=1;
		$skip=1;
	}
	next if($skip);		# ignore aliases with unseen ips
	print RIGHT "$alias\n";
}

# print IPs that were ignored b/c they were only in one or the other
foreach $ip (keys %right_only)
{
	print RIGHT_IP "$ip\n";
}
foreach $ip (keys %left_only)
{
	print LEFT_IP "$ip\n";
}

########################################################################################
## Subroutines
########################################################################################



sub readAliases
{
	my ($type,$file) = @_;
	if($type eq "-iplane")
	{
		return &readIplaneAliases($file);
	}
	elsif($type eq "-pairs")
	{
		return &readPairsAliases($file);
	}
	elsif($type eq "-adj")
	{
		return &readAdjAliases($file);
	}
	else
	{
		usage("Bad type $type\n");
	}
}


# set the alias in some sort of canonical order
sub makeAlly
{ 
	my ($ipA,$ipB) = @_;
	$ipA=~s/\s+//g;
	$ipB=~s/\s+//g;
	if(($ipA cmp $ipB)<0)	# keep a lexical order
	{
		$tmp=$ipA;
		$ipA=$ipB;
		$ipB=$tmp;
	}
	return "$ipA $ipB";
}

sub readAdjAliases
{ 
	my ($file) =@_;
	my (%aliases,%ips, $ally);
	# read known aliases
	open F, $file or die "open $file: $!";
	while(<F>)
	{
		next if(/Link/);
		chomp;
		@line =split;
		# Endhost E100387_B_U nAlly=3 222.203.80.1 222.202.208.1 222.16.81.29
		for($i=3;$i<@line;$i++)
		{
			$ips{$line[$i]}=1;		# record which ips are used
			for($j=($i+1);$j<@line;$j++)
			{

				$ally=&makeAlly($line[$i],$line[$j]);	
				$aliases{$ally}=1;
			}
		}
	}
	return \%aliases,\%ips;
}

sub readIplaneAliases
{ 
	my ($file) =@_;
	my (%aliases,%ips, $ally);
	# read known aliases
	open F, $file or die "open $file: $!";
	while(<F>)
	{
		@line =split;
		# 128.8.128.1 128.8.126.1 128.8.127.1
		for($i=0;$i<@line;$i++)
		{
			$ips{$line[$i]}=1;		# record which ips are used
			for($j=$i+1;$j<@line;$j++)
			{

				$ally=&makeAlly($line[$i],$line[$j]);	
				$aliases{$ally}=1;
			}
		}
	}
	return \%aliases,\%ips;
}

sub readPairsAliases
{ 
	my ($file) =@_;
	my (%aliases,%ips, $ally);
	my ($ip1,$ip2);
	# read known aliases
	open F, $file or die "open $file: $!";
	while(<F>)
	{
		@line =split;
		# 128.8.128.1 128.8.126.1
		# 128.8.128.1 128.8.127.1
		if(!/(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)/)
		{
			print STDERR "Invalid ally line in $ARGV[0] :: '$_'\n";
			next;
		}
		$ip1=$1;
		$ip2=$2;
		$ips{$ip1}=$ips{$ip2}=1;
		$ally=&makeAlly($ip1,$ip2);	
		$aliases{$ally}=1;
	}
	return \%aliases,\%ips;
}
