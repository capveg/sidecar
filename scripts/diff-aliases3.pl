#!/usr/bin/perl -w

# diff-aliases.pl3 base <-iplane|-pairs|-adj> foo <-iplane|-pairs|-adj> bar <-iplane|-pairs|-adj> baz
# foreach alias 
#	if only in foo, then print into $base.left
#	if only in bar, then print into $base.middle
#	if only in baz, then print into $base.right
# 	if in all, then print into $base.all
#		etc...
#  ignore aliases that reference IPs that are not in the other files
#  except output all aliases into the raw file
# supports alias formats of -iplane, -pairs (from adjacency2aliases.pl), and -adj (direct from adj files)

sub usage
{
	print STDERR join "\n",@_ if(@_>0);
	print STDERR "\n\ndiff-aliases3.pl base <-iplane|-pairs|-adj> foo <-iplane|-pairs|-adj> bar <-iplane|-pairs|-adj> baz\n";
	exit 1;
}

$outname= shift || usage("Need more args");
$outname=~s/.adj//;
open LEFT, "> $outname.left" or die "open to write >$outname.left:$!";
open LEFT_IP, "> $outname.left_ip" or die "open to write >$outname.left_ip:$!";
open RIGHT, "> $outname.right" or die "open to write >$outname.right:$!";
open RIGHT_IP, "> $outname.right_ip" or die "open to write >$outname.right_ip:$!";
open MIDDLE, "> $outname.middle" or die "open to write >$outname.middle:$!";
open MIDDLE_IP, "> $outname.middle_ip" or die "open to write >$outname.middle_ip:$!";


open LEFTMIDDLE, "> $outname.left+middle" or die "open to write >$outname.left+middle:$!";
open LEFTMIDDLE_IP, "> $outname.left+middle_ip" or die "open to write >$outname.left+middle_ip:$!";
open LEFTRIGHT, "> $outname.left+right" or die "open to write >$outname.left+right:$!";
open LEFTRIGHT_IP, "> $outname.left+right_ip" or die "open to write >$outname.left+right_ip:$!";
open MIDDLERIGHT, "> $outname.middle+right" or die "open to write >$outname.middle+right:$!";
open MIDDLERIGHT_IP, "> $outname.middle+right_ip" or die "open to write >$outname.middle+right_ip:$!";

open ALL, "> $outname.all" or die "open to write >$outname.all:$!";
open ALL_IP, "> $outname.all_ip" or die "open to write >$outname.all_ip:$!";
open RAW, "> $outname.raw" or die "open to write >$outname.raw:$!";

$leftType = shift || usage("Need more args");
$leftFile = shift || usage("Need more args");
$middleType = shift || usage("Need more args");
$middleFile = shift || usage("Need more args");
$rightType = shift || usage("Need more args");
$rightFile = shift || usage("Need more args");

########################################################################################
## Main
########################################################################################

%aliases=();
%ips=();

$LEFT=1;
$MIDDLE=2;
$RIGHT=4;

$LEFT_MIDDLE=$LEFT+$MIDDLE;
$MIDDLE_RIGHT=$RIGHT+$MIDDLE;
$LEFT_RIGHT=$RIGHT+$LEFT;
$ALL=$LEFT+$MIDDLE+$RIGHT;

# yes, side effects; sue me
&readAliases($leftType,$leftFile,$LEFT);
&readAliases($middleType,$middleFile,$MIDDLE);
&readAliases($rightType,$rightFile,$RIGHT);




foreach $alias (keys %aliases)
{
	print RAW "$alias $aliases{$alias}\n";
	($ip1,$ip2) = split /\s+/,$alias;
	&classifyIP($ip1);
	&classifyIP($ip2);
	if(($ips{$ip1}==$ALL)&&($ips{$ip2}==$ALL))
	{
		# both Ips exist; now just print whereever
		if($aliases{$alias} == $ALL)
		{
			print ALL "$alias\n";
		}
		elsif($aliases{$alias} == $LEFT_MIDDLE)
		{
			print LEFTMIDDLE "$alias\n";
		}
		elsif($aliases{$alias} == $MIDDLE_RIGHT)
		{
			print MIDDLERIGHT "$alias\n";
		}
		elsif($aliases{$alias} == $LEFT_RIGHT)
		{
			print LEFTRIGHT "$alias\n";
		}
		elsif($aliases{$alias} == $LEFT)
		{
			print LEFT "$alias\n";
		}
		elsif($aliases{$alias} == $MIDDLE)
		{
			print MIDDLE "$alias\n";
		}
		elsif($aliases{$alias} == $RIGHT)
		{
			print RIGHT "$alias\n";
		}
		else
		{
			die "unknown tag $aliases{$alias} for alias $alias";
		}
	}
}


########################################################################################
## Subroutines
########################################################################################

sub classifyIP
{
	my ($ip)=@_;
	if($ips{$ip} == $ALL)
	{
		print ALL_IP "$ip\n";
	}
	elsif($ips{$ip} == $LEFT_MIDDLE)
	{
		print LEFTMIDDLE_IP "$ip\n";
	}
	elsif($ips{$ip} == $MIDDLE_RIGHT)
	{
		print MIDDLERIGHT_IP "$ip\n";
	}
	elsif($ips{$ip} == $LEFT_RIGHT)
	{
		print LEFTRIGHT_IP "$ip\n";
	}
	elsif($ips{$ip} == $LEFT)
	{
		print LEFT_IP "$ip\n";
	}
	elsif($ips{$ip} == $MIDDLE)
	{
		print MIDDLE_IP "$ip\n";
	}
	elsif($ips{$ip} == $RIGHT)
	{
		print RIGHT_IP "$ip\n";
	}
	else
	{
		die "unknown tag $ips{$ip} for alias $ip";
	}
}


sub readAliases
{
	my ($type,$file,$tag) = @_;
	if($type eq "-iplane")
	{
		return &readIplaneAliases($file,$tag);
	}
	elsif($type eq "-pairs")
	{
		return &readPairsAliases($file,$tag);
	}
	elsif($type eq "-adj")
	{
		return &readAdjAliases($file,$tag);
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
	my ($file,$tag) =@_;
	my ($ally);
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
			$ips{$line[$i]}|=$tag;		# record which ips are used
			for($j=($i+1);$j<@line;$j++)
			{

				$ally=&makeAlly($line[$i],$line[$j]);	
				$aliases{$ally}|=$tag;
			}
		}
	}
}

sub readIplaneAliases
{ 
	my ($file,$tag) =@_;
	my ($ally);
	# read known aliases
	open F, $file or die "open $file: $!";
	while(<F>)
	{
		@line =split;
		# 128.8.128.1 128.8.126.1 128.8.127.1
		for($i=0;$i<@line;$i++)
		{
			$ips{$line[$i]}|=$tag;		# record which ips are used
			for($j=$i+1;$j<@line;$j++)
			{

				$ally=&makeAlly($line[$i],$line[$j]);	
				$aliases{$ally}|=$tag;
			}
		}
	}
}

sub readPairsAliases
{ 
	my ($file,$tag) =@_;
	my ($ally);
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
		$ips{$ip1}|=$tag;
		$ips{$ip2}|=$tag;
		$ally=&makeAlly($ip1,$ip2);	
		$aliases{$ally}|=$tag;
	}
}
