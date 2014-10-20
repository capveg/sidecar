#!/usr/bin/perl -w

# ./dlv2adj.pl model.dlv [...]
# 	input a model from dlv and output an adjacency file

# Output Format:
#       Router "routername" <if1> <if2> <if3>...
#       Link "routername":if1 "routername":if2  "type"  
# Example:
#       Router R1 128.8.126.1 128.8.126.139
#       Router R2 128.8.6.129 128.8.0.14
#       Link R1:128.8.126.139 -> R2:128.8.6.129

#use strict;
#use warnings;
#use warnings FATAL => 'all';
if( !defined $ENV{"HOME"})
{
	$ENV{"HOME"}=".";	# stoopid hack to shut up complaints in condor
				# b/c it doesn't set $HOME
}
use lib "$ENV{'HOME'}/swork/sidecar/scripts";
use lib "/fs/sidecar/scripts";
use Adjacency;          # slurp all of the subroutines up from module
                        # kills readbility, allows reuse of code...
# horrible! never writing in perl again
use vars qw(%ip2router );

$routercount=1;
$quiet=0;

if($ARGV[0] eq "-q")
{
	$quiet=1;
	shift @ARGV;
}
if((@ARGV>=2)&&($ARGV[0] eq "-o"))
{
	$outfilebase=$ARGV[1];
	shift @ARGV;
	shift @ARGV;
}


foreach $file (@ARGV)	# foreach file
{
	open F,$file or die "Couldn't open :$file:$!";
	$modelcount=0;
	while(<F>)	# foreach model in a file
	{	
		next if /^%/; # skip comments.
		$modelcount++;
		%ip2router=();
		%routers=();
		%links=();
		%types=();
		%aliases=();
		%edgetype=();
		%other=();
		if(/(Best model|Current model \[maybe not optimal\]): \{/)
		{
			$model = $_;
			$cost=<F>;
			@facts=split /\s+/, $model;
		}
		else
		{
			@facts = ( $_ );
			push @facts,<F>;	 # a really horrible way of doing this
						 # FIX ME PLS!!
			$cost="unknown";
		}
		foreach $fact (@facts)	# foreach fact in a model
		{
			next if($fact =~ /^(Best|model:|Current|model|\[maybe|not|optimal\]:)$/);
			$fact=~tr/{}//d;	# remove any curly braces
			$fact=~s/,$//;		# remove trailing comma
			next if($fact =~ /^\s*$/);	# ignore empty facts
			next if($fact =~ /^%/); # skip comments.
			# next unless ($fact=~/other/ || $fact=~/type/ || $fact=~/alias/ || $fact=~/link/);
			# next if ($fact =~ /:-/); #skip rules.
			if($fact =~/^type\(/)
			{
				&handleType($fact);
				next;
			} 
			elsif($fact =~/^link\(/)
			{
				&handleLink($fact);
				next;
			}
			elsif($fact =~/^other\(/)
			{
				&handleOther($fact);
				next;
			}
			elsif($fact =~/^alias\(/)
			{
				&handleAlias($fact);
				next;
			}
			elsif($fact =~/^(-alias|badAlias|offbyone|samePrefix|layer2switch|badNotAlias|badLink)\(/)
			{
				# don't need to track not alias errors in adjfile
				next;
			}
			die "Unknown fact '$fact':$!";
		}
		
		&makeRouterList();
		if(!defined($outfilebase))
		{
			$outfile = &makeoutfile($file,$modelcount,$cost);
		}
		else
		{
			$outfile=$outfilebase;
			if($modelcount>1)
			{
				$outfile=~s/\.adj$/-$modelcount.adj/;
			}
		}
		print "Outputing $file:$modelcount to $outfile\n" unless($quiet);
		open OUT, ">$outfile" or die "Unable to open $outfile: $!";
		&dumpRouterList(\*OUT);		# from Adjacency.pm
	}
}


sub handleType
{
	my ($ip,$type);
	my $fact = shift @_;
	die "Bad fact $fact:$!" unless($fact=~/type\(([ip\d_]+),(\w)\)/);
	$ip = $1;
	$type = $2;
	$type=~tr/a-z/A-Z/;
	$ip =~ tr/_ip/./d;
	$types{$ip}->{$type}=1;
	$ip2router{$ip}="NEED";
}

sub handleOther
{
	my ($ip,$other);
	my $fact = shift @_;
	die "Bad fact '$fact':$!" unless($fact=~/other\(([ip\d_]+),(\w+)\)/);
	$ip = $1;
	$other = $2;
	$other=~tr/a-z/A-Z/;
	$ip =~ tr/_ip/./d;
	$other{$ip}->{$other}=1;
	$ip2router{$ip}="NEED";
}

sub handleLink
{
	my ($ip1,$ip2,$type);
	my $fact = shift @_;
	die "Bad fact $fact:$!" unless($fact=~/link\(([ip\d_\.]+),([ip\d_\.]+),([\w\d]+)\)/);
	$ip1 = $1;
	$ip2 = $2;
	$ip1 =~ tr/_ip/./d;
	$ip2 =~ tr/_ip/./d;
	$ip2router{$ip1}="NEED";
	$ip2router{$ip2}="NEED";
	$type= $3;
	$links{"$ip1 -- $ip2"}=$type
		unless((exists $links{"$ip1 -- $ip2"}) &&
			(&linkXbetterthenY($links{"$ip1 -- $ip2"},$type)));
}

sub handleAlias
{
	my ($ip1,$ip2);
	my $fact = shift @_;
	die "Bad fact $fact:$!" unless($fact=~/alias\(([ip\d_\.]+),([ip\d_\.]+),\w+\)/);
	$ip1 = $1;
	$ip2 = $2;
	$ip1 =~ tr/_ip/./d;
	$ip2 =~ tr/_ip/./d;
	$ip2router{$ip1}="NEED";
	$ip2router{$ip2}="NEED";
	push @{$aliases{$ip1}},$ip2;
	push @{$aliases{$ip2}},$ip1;
}

sub makeRouterList
{
	my %newlinks;
	foreach $ip ( keys %ip2router)
	{
		next unless($ip2router{$ip} eq "NEED");
		$router = "$routercount";
		$routercount++;
		&markinterfaces($ip,$router);

	}
	&remakerouternames();
	# fixup links
	foreach $link ( keys %links)
	{
		@line = split /\s+/,$link;	# $link = "$sip -- $dip" =$type
		$ip1=$line[0];
		$ip2=$line[2];
		$r1=$ip2router{$ip1};
		$r2=$ip2router{$ip2};
		$type=$links{$link};
		die "No link value defined for $link" unless(defined($links{$link}));
		#delete $links{$link};
		$newlinks{"$r1:$ip1 -- $r2:$ip2"}=$type;
		$edgetype{"$r1:$r2"}=$type 
			unless((exists $edgetype{"$r1:$r2"}) && 
				(&linkXbetterthenY($edgetype{"$r1:$r2"},$type)));
		#$edgetype{"$r2:$r1"}=$type 
		#	unless((exists $edgetype{"$r2:$r1"}) && 
		#		(&linkXbetterthenY($edgetype{"$r2:$r1"},$type)));
	}
	%links=%newlinks;
}

sub markinterfaces
{
	my ($ip,$router) = @_;
	return if($ip2router{$ip} eq $router);
	die "$ip set to $ip2router{$ip} not $router:$!" 
			if($ip2router{$ip} ne "NEED");
	$ip2router{$ip}=$router;
	push @{$routers{$router}},$ip;
	foreach $nip ( @{$aliases{$ip}})
	{
		&markinterfaces($nip,$router);
	}
}

sub makeoutfile
{ 
	my ($file,$modelcount,$cost) = @_;
	$file=~s/\.[^.]+$//;
	if($cost ne "unknown")
	{
		@line=split /\s+/, $cost; #"Cost ([Weight:Level]): <[0:1]>"
		$cost = $line[2]; #"<[0:1]>"
		$cost =~ tr/0-9:][<>/0-9:,/d;
	}
	return "$file-C=$cost-$modelcount.adj";
}

sub remakerouternames
{
	my ($router,$neorouter,%neorouters,$o,$key);

	foreach $router (keys %routers)
	{
		my ($ip,%otherlist,%typelist);
		my $rtype = "R";
		foreach $ip ( @{$routers{$router}})
		{
			foreach $key ( keys %{$other{$ip}})
			{ 
				$otherlist{$key}=1;
			}
			foreach $key ( keys %{$types{$ip}})
			{
				$typelist{$key}=1;
			}
		}
		$rtype= "H" if(exists $otherlist{"HIDDEN"});
		$rtype= "E" if(exists $otherlist{"ENDHOST"});
		$rtype= "N" if(exists $otherlist{"NAT"});
		$rtype= "S" if(exists $otherlist{"SOURCE"});

		$o= join "_", keys %typelist;
		$neorouter="$rtype$router";
		$neorouter.="_$o" if($o ne"");
		$o = join "_", grep {!/^(SOURCE|ENDHOST|NAT|HIDDEN)/} keys %otherlist;
		$neorouter .= "_$o" if($o ne "");
		# now swap the new name into place
		foreach $ip (@{$routers{$router}})
		{
			$ip2router{$ip}=$neorouter;
		}
		$neorouters{$neorouter}=$routers{$router};
	}
	%routers=%neorouters;	# save the changes
}
