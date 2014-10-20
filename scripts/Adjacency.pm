#use strict;
#use warnings;
#use warnings FATAL => 'all';

$DisableStupidTest=0;
$DisableOffbyOneTest=0;




### Constants: link types
$RR = 1;
$STR= 2;
$TR = 3;
$Unknown =4;
$Hidden =5;

@linkstrings = ( "<unused>", "RR", "STR", "TR","UNKNOWN", "HIDDEN");
# make string2link num mapping
for($i=0;$i<@linkstrings;$i++)
{
	$linkstrings2index{$linkstrings[$i]}=$i;
}
%OppositeTypes= ( 
# X => Y :: throw an error is we add tag X to a router that already has a tag matching /Y/
		"China" => "NoOpposite",
		"STUPID" => "NoOpposite",
		"Layer2Flap" => "NoOpposite",
		"LAYER2" => "NoOpposite",
		"LAZY" => "NoOpposite",
		"X" => "NoOpposite",
		"U" => "NoOpposite",
		"M" => "NoOpposite",
		"C" => "NoOpposite",
		"MPLS" => "NoOpposite",
		"Filtered" => "NoOpposite",
		"DropsRR" => "NoOpposite",
		"Flapping" => "NoOpposite",
		"HA" => "^N\$",
		"A" => "B|B-OR-N|N",
		"B" => "A|A-OR-N|N",
		"A-OR-N" => "B\$",
		"B-OR-N" => "A\$",
		"N" => "(A|B)\$"
		);
%TypePrecedence = (
		# X => Y :: X has precedence over things that match /Y/
		"China" => "NOTHING",
		"STUPID" => "NOTHING",
		"Layer2Flap" => "NOTHING",
		"LAYER2" => "NOTHING",
		"LAZY" => "NOTHING",
		"X" => "NOTHING",
		"U" => "NOTHING",
		"M" => "NOTHING",
		"C" => "NOTHING",
		"MPLS" => "NOTHING",
		"Filtered" => "NOTHING",
		"DropsRR" => "NOTHING",
		"Flapping" => "NOTHING",
		"HA" => "^(A|B)\$",
		"A" => "DropsRR|A-OR-N",
		"B" => "DropsRR|B-OR-N",
		"N" => "(A|B)-OR-N",
		"A-OR-N" => "",
		"B-OR-N" => ""
		);
# function map between different router transition types
%doRR = 
(
	"HA" => { # some how, a transition from HiddenA to HiddenA just isn't very funny :-(
		"HA" => \&doRR_HA_to_HA,
		"B" => \&doRR_HA_to_B,
		"A" => \&doRR_HA_to_A,
		"N" => \&doRR_HA_to_N,
		"A|B|N" => \&doRR_HA_to_U ,
		"A|N" => \&doRR_HA_to_U,
		"B|N" => \&doRR_HA_to_U,
		},
	"A" => { 
		"HA" => \&doRR_A_to_HA,
		"B" => \&doRR_A_to_B,
		"A" => \&doRR_A_to_A,
		"N" => \&doRR_A_to_N,
		"A|B|N" => \&doRR_A_to_U ,
		"A|N" => \&doRR_A_to_U,
		"B|N" => \&doRR_A_to_U,
		},
	"B" => { 
		"HA" => \&doRR_B_to_HA,
		"B" => \&doRR_B_to_B,
		"A" => \&doRR_B_to_A,
		"N" => \&doRR_B_to_N,
		"A|B|N" => \&doRR_B_to_U,
		"A|N"  => \&doRR_B_to_U,
		"B|N"  => \&doRR_B_to_U
		},
	"N" => { 
		"HA" => \&doRR_N_to_HA,
		"B" => \&doRR_N_to_B,
		"A" => \&doRR_N_to_A,
		"N" => \&doRR_N_to_N,
		"A|B|N" => \&doRR_N_to_U,
		"A|N" => \&doRR_N_to_U,
		"B|N" => \&doRR_N_to_U,
		},
	"A|B|N" =>{
		"A|B|N" => \&doRR_U_to_U,
		"A|N" => \&doRR_U_to_U,
		"B|N" => \&doRR_U_to_U,
		# the other permuations should never happen!
		# but sigh, thanks to Level3, they do
		"HA" => \&doRR_U_to_HA,
		"B" => \&doRR_U_to_B,
		"A" => \&doRR_U_to_A,
		"N" => \&doRR_U_to_N,
		},
	"A|N" => {
		"HA" => \&doRR_U_to_HA,
		  "A" => \&doRR_U_to_A,
		  "B" => \&doRR_U_to_B,
		  "N" => \&doRR_U_to_N,
		  "A|B|N" => \&doRR_U_to_U,
		  "A|N" => \&doRR_U_to_U,
		  "B|N" => \&doRR_U_to_U
		},
	"B|N" => {
		  "HA" => \&doRR_U_to_HA,
		  "A" => \&doRR_U_to_A,
		  "B" => \&doRR_U_to_B,
		  "N" => \&doRR_U_to_N,
		  "A|B|N" => \&doRR_U_to_U,
		  "A|N" => \&doRR_U_to_U,
		  "B|N" => \&doRR_U_to_U
		}
);

###################################################################################################################
# Subroutines
##########################################################################################
sub doRR_A_to_B
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	my $srouter = $data{$ttl-1}->{$prev_iteration}->{"name"}; 
	my $tmp = $ip2router{$data{$ttl}->{$iteration}->{"rr"}->[-2]};
	if($tmp && hasMark($tmp, "Flapping"))
	{
		print STDERR "doRR_A_to_B(): doing flapping router hack: attaching on to $tmp instead of $srouter\n" if($Verbose);
		$srouter = $tmp;	 	# only do if flapping, else breaks all kinds of alias resolution
	}
	addInterface($data{$ttl}->{$iteration}->{"rr"}->[-2], $srouter);
	addInterface($data{$ttl}->{$iteration}->{"rr"}->[-1],
			$data{$ttl}->{$iteration}->{"name"});
	addLink($srouter,
			$data{$ttl}->{$iteration}->{"rr"}->[-2],
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $RR);
	markRouter($srouter,"A"," Rule #".__LINE__);
	markRouter($data{$ttl}->{$iteration}->{"name"},"B"," Rule #".__LINE__);
}

##########################################################################################
sub doRR_A_to_N
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# NO rr  interfaces to add, add a traceroute one
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"A"," Rule #".__LINE__);
	markRouter($data{$ttl}->{$iteration}->{"name"},"N"," Rule #".__LINE__);
}
##########################################################################################
sub doRR_A_to_A
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	my $srouter = $data{$ttl-1}->{$prev_iteration}->{"name"};
	my $tmp = $ip2router{$data{$ttl}->{$iteration}->{"rr"}->[-1]};
	if($tmp && hasMark($tmp, "Flapping"))
	{
		print STDERR "doRR_A_to_A(): doing flapping router hack: attaching on to $tmp instead of $srouter\n" if($Verbose);
		$srouter = $tmp;	 	# only do if flapping, else breaks all kinds of alias resolution
	}
	addInterface($data{$ttl}->{$iteration}->{"rr"}->[-1], $srouter);
	addLink($srouter,
			$data{$ttl}->{$iteration}->{"rr"}->[-1],
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $RR);
	markRouter($srouter,"A"," Rule #".__LINE__);
	markRouter($data{$ttl}->{$iteration}->{"name"},"A"," Rule #".__LINE__);
}
##########################################################################################
sub doRR_A_to_U
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# NO rr  interfaces to add, add a traceroute one
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"A"," Rule #".__LINE__);
	# don't mark second router - it's unknown
}
##########################################################################################
sub doRR_N_to_B
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	addInterface($data{$ttl}->{$iteration}->{"rr"}->[-1],
	                        $data{$ttl}->{$iteration}->{"name"});
	# nothing to add but smart TR link
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"N"," Rule #".__LINE__);
	markRouter($data{$ttl}->{$iteration}->{"name"},"B"," Rule #".__LINE__);
}
##########################################################################################
sub doRR_N_to_A
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# nothing to add but smart TR link
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"N");
	markRouter($data{$ttl}->{$iteration}->{"name"},"A");
}
##########################################################################################
sub doRR_N_to_N
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# nothing to add but smart TR link
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"N");
	markRouter($data{$ttl}->{$iteration}->{"name"},"N");
}
##########################################################################################
sub doRR_N_to_U
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# nothing to add but smart TR link
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"N");
	# don't mark second router - it's unknown
}
##########################################################################################
sub doRR_B_to_B
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	addInterface($data{$ttl}->{$iteration}->{"rr"}->[-1],
	                        $data{$ttl}->{$iteration}->{"name"});
	# add link from prev[-1] to curr inhop
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"rr"}->[-1],
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $RR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"B");
	markRouter($data{$ttl}->{$iteration}->{"name"},"B");
}
##########################################################################################
sub doRR_B_to_HA
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# found a hidden router!
	# lookup by ip or assign name if new
	$hidden = $ip2router{$data{$ttl}->{$iteration}->{"rr"}->[-1]} || newRouter("HIDDEN");	
	$hiddenip = $data{$ttl}->{$iteration}->{"rr"}->[-1];

	# link from B router to hidden router
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"rr"}->[-1],
			$hidden,
			$hiddenip,$RR);
	# link from hidden router to A router
	addLink($hidden,
			$hiddenip,
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $RR);

	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"B");
	markRouter($data{$ttl}->{$iteration}->{"name"},"HA");
}
##########################################################################################
sub doRR_B_to_A
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"rr"}->[-1],
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $RR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"B");
	markRouter($data{$ttl}->{$iteration}->{"name"},"A");
}
##########################################################################################
sub doRR_B_to_N
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"rr"}->[-1],
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $RR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"B");
	markRouter($data{$ttl}->{$iteration}->{"name"},"N");
}
##########################################################################################
sub doRR_B_to_U
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"rr"}->[-1],
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $RR);
	markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"B");
	# don't mark second router, it's unknown
}
##########################################################################################
sub doRR_U_to_U
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	# don't mark either router, their unknown
}
##########################################################################################
sub doRR_U_to_A
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# add the link
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl}->{$iteration}->{"name"},"A");
}
##########################################################################################
sub doRR_U_to_N
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# add the link
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl}->{$iteration}->{"name"},"N");
}
##########################################################################################
sub doRR_U_to_B
{
	my ($ttl,$iteration,$prev_iteration) = @_ or die "Wrong number of args in doRR()\n";
	# add the Interface for the B side
	addInterface($data{$ttl}->{$iteration}->{"rr"}->[-1],
		$data{$ttl}->{$iteration}->{"name"});
	# add the link
	addLink($data{$ttl-1}->{$prev_iteration}->{"name"},
			$data{$ttl-1}->{$prev_iteration}->{"inhop"},
			$data{$ttl}->{$iteration}->{"name"},
			$data{$ttl}->{$iteration}->{"inhop"}, $STR);
	markRouter($data{$ttl}->{$iteration}->{"name"},"B");
}
##########################################################################################
sub doRR_HA_to_HA
{ 
	die "Found a HA to HA transition: world view might be broken\n";
}
sub doRR_A_to_HA
{ 
	die "Found a A to HA transition: world view might be broken\n";
}
sub doRR_N_to_HA
{ 
	die "Found a N to HA transition: world view might be broken\n";
}
sub doRR_U_to_HA
{ 
	die "Found a U to HA transition: world view might be broken\n";
}
##########################################################################################
# doRR_HA_to_* is just A_to_*

sub doRR_HA_to_B { return doRR_A_to_B(@_); }
sub doRR_HA_to_A { return doRR_A_to_A(@_); }
sub doRR_HA_to_N { return doRR_A_to_N(@_); }
sub doRR_HA_to_U { return doRR_A_to_U(@_); }
##########################################################################################
# Rule: DROP Detect
#	IF there are no RR packets for a given ttl,
#	AND all TR packets got through, assume it DropsRR
#	ELSE, it could be just busy, dropping some packets
sub lookForDroppingRouters	# look for routers that drop RR packets
{

	my ($ttl,$iteration,$rrcount,$trcount);
	for($ttl=1;$ttl<$rrDistance[0];$ttl++)		# assume all $rrDistances are the same
	{
		$rrcount=$trcount=0;
		# only test this for RR packets
		for($iteration=0;$iteration<$Iterations;$iteration++)
		{
			next unless( exists($data{$ttl}) && exists($data{$ttl}->{$iteration}));
			if( $data{$ttl}->{$iteration}->{"gotRR"}>0)
			{
				$rrcount++;
			}
			else
			{
				$trcount++;
			}
		}
		if(($rrcount==0)&&($trcount>=($Iterations/2)))
		{	# found a router that drops RR; mark all instances (could be buggy)
			for($iteration=0;$iteration<$Iterations;$iteration++)
			{
				next unless( exists($data{$ttl}) && exists($data{$ttl}->{$iteration}));
				&markRouter($data{$ttl}->{$iteration}->{"name"},"DropsRR"," Rule #".__LINE__);
			}
		}
	}
}
##########################################################################################
sub parseline
{
	my ($ttl,$iteration,$ip,@line,$index,$i,$n);
	@line=@_;
	my @tmp;
	$ip = $line[6];
	$ttl= $line[3];
	$iteration=$line[4];
	$iteration=~s/it\??=//;				# it?=1 --> 1
	return if(exists $data{$ttl}->{$iteration});	# don't override existing probe data
							# this is needed if we have a TraceRoute packet
							# repeated in phase=2 for the same ttl,iteration
	# $foo{"rr"} =[];		# init the rr list as empty
	my %ref;
	$ref{"rr"} =[];		# init the rr list as empty
	$MaxTTL=$ttl if($ttl>$MaxTTL);			# track the max ttl
	$ref{"inhop"}=$ip;
	$ref{"type"}=$line[8];
	$ref{"RRholes"}=0;	# the number of known non-RR supporting routers upstream
	$foundEndHost=1 if($ref{"type"} eq "ENDHOST");
	$ref{"ptype"}=$line[-1];	# mark the probe type
	$ref{"ptype"}=~s/\?//;	# remove ambiguity; just assume it's right
	if(!$ref{"ptype"}=~/(Macro|Pollo|Payload|TraceRoute)/)
	{
		#line could end like:: 'hop 7 66.218.91.137 ,  Macro Non-time exceeded message: ICMP type=12 code=0 : ABORT! ICMP_PARAMETERPROB at index 21'
		$ref{"ptype"}=undef;
		$ref{"ptype"}="Macro" if(grep( $_ eq "Marco,", @line[12..$#line]));
		$ref{"ptype"}="Pollo" if(grep( $_ eq "Pollo,", @line[12..$#line]));
		$ref{"ptype"}="TraceRoute" if(grep( $_ eq "TraceRoute,", @line[12..$#line]));
		$ref{"ptype"}="Payload" if(grep( $_ eq "Payload,", @line[12..$#line]));
		return 1 unless($ref{"ptype"});
	}
	$ref{"beenClassified"}=0;
	# parse RR lines, if present
	@tmp = grep /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, @line[12..$#line];	# hack in the array context
	$ref{"rr"} = \@tmp;
	#if((scalar(@line)>12) and ($line[12] eq "RR,"))
	#{
	#		$index=0;
	#		$ref{"gotRR"}=1;
	#		$ref{"RRtype"}="A|B|N";
	#		$ref{"delta"}=-1;
	#		for($i=15;$i<@line;$i+=4)
	#		{
	#			$ref{"rr"}->[$index++]=$line[$i];
	#		}
	#	} 
	if(grep( $_ eq "RR,", @line))
	{
			$ref{"gotRR"}=1;
			$ref{"RRtype"}="A|B|N";
			$ref{"delta"}=-1;
	}
	else
 	{
		$ref{"RRtype"}="None";
		$ref{"gotRR"}=0;
	}
	if(grep( /MPLS/, @line))
	{
		my @tmp = grep( /MPLS/, @line);
		$ref{"hasMPLS"}=1;
		$ref{"mpls"}=$tmp[0];
		$ref{"mpls"}=~s/,/ /g;	# remove commas
	}
	else
	{
		$ref{"hasMPLS"}=0;
	}
    $data{$ttl}->{$iteration} = \%ref;
    return 0;
}
#######################################################################################################
##sub updateRRtypeGuesses
##{
##	my ($ttl, $iteration, $n);
##	($ttl)=@_;
##	for(;$ttl<$MaxTTL;$ttl++)
##	{
##		next unless(exists $data{$ttl});
##		for($iteration=0;$iteration<$Iterations;$iteration+=2)
##		{
##			next unless(exists $data{$ttl}->{$iteration});
##			# attempt to GUESS RRtype; this will be overridden later if we have better info
##			# it's important to guess b/c we can't make all inferences later if we have missing data
##			# add the # of RR entries plus the number of holes to find out the expected number of entries
##			$n = scalar(@{$data{$ttl}->{$iteration}->{"rr"}}) + $data{$ttl}->{$iteration}->{"RRholes"};
##			if($n==9)
##			{
##				# could be too far to tell, or could be just at limit : Need to check later
##				$data{$ttl}->{$iteration}->{"RRtype"} = "?";
##			}
##			elsif($n == ($ttl-1))
##			{
##				# note that this also sets ttl=1 to A even though $n==0, which is probably correct 
##				$data{$ttl}->{$iteration}->{"RRtype"} = "A-OR-N";
##			}
##			elsif($n == $ttl)
##			{
##				$data{$ttl}->{$iteration}->{"RRtype"} = "B";
##			}
##			elsif($n == 0)
##			{
##				$data{$ttl}->{$iteration}->{"RRtype"} = "Unimplemented";
##			} 
##			else
##			{
##				# really just don't know; probably a flakey router somewhere upstream
##				$data{$ttl}->{$iteration}->{"RRtype"} = "?";
##			}
##			print STDERR "Probe $trace ttl=$ttl it=$iteration guessed to be ",$data{$ttl}->{$iteration}->{"RRtype"},"\n"
##				if($Verbose);
##		}
##	}
##}
#################################################################################################################
sub addNewHole	 # mark all of the routers from $ttl to $MaxTTL that they should expect one less RR entry
{
	my ($ttl, $iteration, $n);
	($ttl) =@_;
	for(;$ttl<$MaxTTL;$ttl++)
	{
		next unless(exists $data{$ttl});
		for($iteration=0;$iteration<$Iterations;$iteration+=2)
		{
			next unless(exists $data{$ttl}->{$iteration});
			$data{$ttl}->{$iteration}->{"RRholes"}++;
		}
	}
}



###############################################################################################
 sub ensureReachability
{
  # ns tried to make SourceRouterName and source_ip not globals.
    my ($lastReachableRouter, $lastReachableRouterIp) = @_;
    my ($ttl,$iteration);
	# now step through and add "unknown" links for any unreachable router
	# $lastReachableRouter=$SourceRouterName;
	# $lastReachableRouterIp=$source_ip;
	for($ttl=1;$ttl<=$MaxTTL;$ttl++)
	{
		next unless(exists $data{$ttl});
		for($iteration=0;$iteration<$Iterations;$iteration++)
		{
			next unless(exists $data{$ttl}->{$iteration});
			if(exists $Reachable{$data{$ttl}->{$iteration}->{"name"}})
			{
				$lastReachableRouter=$data{$ttl}->{$iteration}->{"name"};
				$lastReachableRouterIp=$data{$ttl}->{$iteration}->{"inhop"};
				next;
			}
			&addLink($lastReachableRouter,$lastReachableRouterIp,
				$data{$ttl}->{$iteration}->{"name"},
				$data{$ttl}->{$iteration}->{"inhop"},$Unknown);
			$Reachable{$data{$ttl}->{$iteration}->{"name"}}=1;
		}
	}
}
###############################################################################################
sub do_traceroute_probe
{
	my ($ttl,$iteration) = @_;
	$count=0;
	# only compare even with even, and odd with odd
	for($j=($iteration%2);$j<$Iterations;$j+=2)
	{
		next if(!exists($data{$ttl-1}) || !exists($data{$ttl-1}->{$j}));
		$count++;
		# if the last hop was also a TR packet, just match the in interfaces
		if($data{$ttl-1}->{$j}->{"ptype"} eq "TraceRoute")
		{
			&addLink($data{$ttl-1}->{$j}->{"name"},
				$data{$ttl-1}->{$j}->{"inhop"},
				$data{$ttl}->{$iteration}->{"name"},
				$data{$ttl}->{$iteration}->{"inhop"},$TR);
			next;
		}
		# else, last hop was RRtype=A, so we just add a TR link
		# note that we can't ensure that the last RR record of the
		# last probe came here, so just use $TR links
		&addLink($data{$ttl-1}->{$j}->{"name"},
				$data{$ttl-1}->{$j}->{"inhop"},
				$data{$ttl}->{$iteration}->{"name"},
				$data{$ttl}->{$iteration}->{"inhop"},$TR);

	}
}
###############################################################################################
sub newRouter
{
	my ($type) =@_;
	my $name;
	if($type =~ /ROUTER/i)
	{
		$routercounter++;
		$name= "R$routercounter";
	} 
	elsif($type =~ /HIDDEN/i)
	{
		$hiddencounter++;
		$name= "H$hiddencounter";
	}
	elsif($type =~ /NAT/i)
	{
		$natcounter++;
		$name= "NAT$natcounter";
	}
	elsif($type =~ /SOURCE/i)
	{
		$sourcehostcounter++;
		$name= "S$sourcehostcounter";
	}
	elsif($type =~ /ENDHOST/i)
	{
		$endhostcounter++;
		$name= "E$endhostcounter";
	}
	else
	{
		die "Unknown router type '$type': $trace\n";
	}
	$routers{$name}=();		# init an empty list
	return $name;
}

######################################################################################################

# Usage:
# 	addInterface(ip,router)	 -- add ip to router's list of if's
sub addInterface
{
	my ($ip,$router)= @_;
# unnecessary - ns	$ip = shift @_ || die "Need to specify an ip";
# unnecessary - ns	$router = shift @_ || die "Need to specify a router name";
	if(!exists $routers{$router})
	{
		@{$routers{$router}}=($ip);
		print STDERR "Adding interface $ip to $router (first interface)\n" if($Verbose);
	}elsif(!grep($_ eq $ip,@{$routers{$router}})) 	# only add if not already added
	{
		push @{$routers{$router}}, $ip;	# add to list
		print STDERR "Adding interface $ip to $router\n" if($Verbose);
    }
	if(!exists $ip2router{$ip})
	{
		$ip2router{$ip}=$router;
	}
	
	return $router;
}

#########################################################################################################


sub addLink
{
	my ($srouter,$sip,$drouter,$dip,$type) = @_;
    my ($key, $edgename1, $edgename2);
	die "addLink() needs a type parameter" unless ($type);
	$key= "$srouter:$sip -- $drouter:$dip";
	$edgename1="$srouter:$drouter";
	$edgename2="$drouter:$srouter";

	$Reachable{$drouter}=1 if($Reachable{$srouter});	# track reachability
	&addInterface($sip,$srouter);				# sanity check
	&addInterface($dip,$drouter);		
	
	# if link doesn't exist, or we get a more accurate type
	if((!exists $edgetype{$edgename1}) or ($edgetype{$edgename1} > $type))
	{
		$links{$key}=$type;
		$edgetype{$edgename1}=$edgetype{$edgename2}=$type;
		print STDERR "Adding link $key of type $type\n" if($Verbose);
	}
}

###########################################################################################################
sub MIN
{	
  # only a tiny improvement.

  $_[0] < $_[1] ? $_[0] : $_[1];

	# my ($a,$b) = @_;
	# if($a < $b)
	# {
		# return $a;
	# } else
	# { 
		# return $b;
	# }
}

###########################################################################################################
sub markSameRouters
{
	my (%map, %tmpip2router,%tmprouters,%tmplinks,$router,$dest);
	my ($if,$otherif, $otherrouter);
	# make equivalence map
#	foreach $router (keys %routers )
#	{
#		if(!exists $map{$router})
#		{	#make the router name a function of it's types
#			$map{$router}=&makeRouterName($router);
#		}
#		else
#		{	# else, verify these two routers have the same types
#			&typesCompare($router,$map{$router});
#		}
#		next if($router =~/^(NAT|E)/);		# don't remap NAT's onto Endhosts (they share ips)
#		foreach $if ( @{$routers{$router}})
#		{
#			if($ip2router{$if} ne $router)
#			{
#				$map{$ip2router{$if}}=$map{$router};	# mark as equivalent
#			}
#		}
#
#	}
	foreach $router (keys %routers )
	{
		# attempt to find a router to map ourselves on to
		$dest=undef;
		foreach $if ( @{$routers{$router}})
		{
			if(exists $tmpip2router{$if})
			{
				$dest=$tmpip2router{$if};	# grab the first one
				last;
			}
		}
		if($dest)
		{
			&typesCompare($router,$dest);		# if we found someone, type Check
		}
		else
		{
			$dest = $router;			# if we found no one, map to ourselves
		}
		$map{$router}=$dest;		# record the mapping
		# mark it for future routers
		foreach $if ( @{$routers{$router}})
		{
			if(exists $tmpip2router{$if})
			{
				if($dest ne $tmpip2router{$if})	# we just spanned two sets
				{

					$otherrouter = $tmpip2router{$if};
					# re-mark all of their interfaces
					foreach $otherif (@{$routers{$otherrouter}})
					{
						$tmpip2router{$otherif}=$dest;
					}
					# and re-map them to our dest
					$map{$otherrouter}=$dest;
				}
			}
			$tmpip2router{$if}=$dest;
		}
		
	}
	# re-name and re-map %routers
	foreach $router (keys %routers)
	{
		$map{$router}=&makeRouterName($map{$router});					# rename with types
		@{$tmprouters{$map{$router}}}=() if(!exists $tmprouters{$map{$router}});	# initialize
		foreach $if ( @{$routers{$router}})
		{
			if (!grep($_ eq $if,@{$tmprouters{$map{$router}}}))
			#if(!grep /^$if$/, @{$tmprouters{$map{$router}}})		# add it if it doesn't exist
			{
				push @{$tmprouters{$map{$router}}},$if;
			}
		}
	}
	# re-map %edgetype
	foreach $key (keys %edgetype)
	{
		($r1,$r2)=split /:/,$key;
		# update only if edge doesn't exist or if we have a better edge
		if((!exists $tmpedgetype{$map{$r1}.":".$map{$r2}})||(
			$tmpedgetype{$map{$r1}.":".$map{$r2}} > $edgetype{$key}))
		{
			$tmpedgetype{$map{$r1}.":".$map{$r2}} = $edgetype{$key};
		}
	}
	# re-map %links
	foreach $link (keys %links)
	{
		@line = split /[\s:]/,$link;
		$key= "$map{$line[0]}:$line[1] $line[2] $map{$line[3]}:$line[4]";
		$tmplinks{$key}=$links{$link};
	}
	# replace %routers with %tmprouters
	%routers=%tmprouters;
	# replace %edgetype with %tmpedgetype
	%edgetype=%tmpedgetype;
	# replace %links with %tmplinks
	%links = %tmplinks;
}
##########################################################################################################
sub parseArgs
{
	while((scalar(@ARGV) > 0) and ($ARGV[0] =~ /^-/))
	{
		if($ARGV[0] eq "-a")
		{
			@files = <STDIN>;
			chomp @files;
			push @ARGV, @files;			# slurp traces from stdin
		}
		elsif($ARGV[0] eq "-v")
		{
			$Verbose=1;
		}
		else 
		{
			die "Unknown arg '$ARGV[0]' -- usage: data2adjacency.pl [-v] [-a] source_ip [traces..]\n";
		}
		shift @ARGV;
	}
}

############################################################################################################
sub  previous_hop_was_nat
{
	my ($ttl,$iteration) = @_;
	for($j=0;$j<$Iterations;$j++)
	{
		next unless(exists($data{$ttl-1}->{$j}));
		return 1 if($data{$ttl-1}->{$j}->{"type"} eq "NAT");
	}
	return 0;
}
############################################################################################################
sub markRouter
{
	my ($router, $type, $mesg) = @_;
	my ($routerlist);

	$mesg = "" unless($mesg);		# fill it in as blank if not supplied

	die "Bad router name $router\n" unless(exists $routers{$router});
	if(!exists($routerType{$router}))
	{
		print STDERR "Marking $router as $type $mesg\n" if($Verbose);
		$routerType{$router}->{$type}=1;
	}
	return 1 if(exists $routerType{$router}->{$type});	# already marked
	foreach $key (keys %{$routerType{$router}})
	{
		die "Weirdness in markRouter string for $router $mesg\n" unless(exists $routerType{$router}->{$key});
		return 1 if($type =~ /$TypePrecedence{$key}/); # existing type has precedence
		if($key =~ /$TypePrecedence{$type}/) # new type has precdence
		{
			print STDERR "Marking $router as $type: was ",$key," $mesg\n" if($Verbose);
			delete $routerType{$router}->{$key};
			$routerType{$router}->{$type}=1;	# update 
			next;
		}
		if(($key =~ $OppositeTypes{$type})&&(!&hasMark($router,"MPLS")))
		{
			if(exists $routers{$router})
			{
				$routerlist = join(" ",@{$routers{$router}});
			}
			else
			{
				$routerlist = "";
			}
			#print STDERR "$trace\n";
			#print STDERR "$ttl $iteration\n";
			warn "Tried to mark router $router ($routerlist) as $type when it is already ", $key, " : $trace $ttl $iteration $mesg\n";
			return 0;		# failed to mark router
		}
	}
	print STDERR "Marking $router as $type $mesg\n" if($Verbose);
	$routerType{$router}->{$type}=1;;	
	return 1;


}
#############################################################################################################
sub hasMark
{
	my ($router, $type) = @_;
	my ($i);
	die "Bad router name $router\n" unless(exists $routers{$router});
	return 0 unless(exists $routerType{$router});
	return 1 if(exists $routerType{$router}->{$type});
	return 0;
}
#############################################################################################################
sub parseSendingLine
{
	my (@line, $safettl,$iteration);
	my ($str) = @_;
	@line = split /\s+/,$str;
	$iteration= $line[3];			# train=0
	return if($line[3]=~m/probe=/);		# we have gone into phase=2
	$iteration=~ s/train=//;
	$safettl = $line[5];			# safettl=11
	$safettl =~ s/safettl=//;
	$rrDistance[$iteration]=MIN($safettl,10);
}

#############################################################################################################
#
sub comparePath			# compare the paths of 2 probes; return 1 if they follow the same path
{
	# step through each hop in the RR path
	# if one varies, mark it as flapping
	#my ($ttl,$iteration,$prev_iteration) = @_;
	my ($probeA,$probeB) = @_;
	my ($min,$i,$j);

    my $thisiteration = \@{$probeA->{"rr"}};
    my $lastiteration = \@{$probeB->{"rr"}};
    my $thisiteration_i;
	# $min = MIN(scalar(@{$data{$ttl}->{$iteration}->{"rr"}}),
		#	scalar(@{$data{$ttl-1}->{$prev_iteration}->{"rr"}}));

	$min = &MIN(scalar(@{$thisiteration}), scalar(@{$lastiteration}));
	for($i=0;$i<$min;$i++)
	{
      $thisiteration_i = $thisiteration->[$i];
      next if($thisiteration_i  eq		# skip if RR's match
			$lastiteration->[$i]);
		# make up a name for this router real quick if we haven't seen it before
		if(!exists($ip2router{$thisiteration_i}))
		{
			$ip2router{$thisiteration_i} = &newRouter("ROUTER");
			&addInterface($thisiteration_i,
				$ip2router{$thisiteration_i});
		}
		# This mark for flapping marks the wrong router if the flap happened right before
		#	a typeB router
		&markRouter($ip2router{$thisiteration_i},"Flapping"," Rule #".__LINE__);
		return 0;		# come back to salvage more info  FIXME
	}
	return 1;
}

#############################################################################################################
sub makeRouterName	# make the router name a function of it's types
{
	my ($router) = @_;
	my ($type,$name);
	$name = $router;
	foreach $type (keys %{$routerType{$router}})
	{
		$name .="_$type";
	}
	return $name;
}
############################################################################################################
sub typesCompare
{
	my ($router,$otherrouter) = @_;
	my (@types,$type1,$type2);
	@types = split /\_/,$otherrouter;
	shift @types;		# get rid of router name
	# make sure there are no opposites
	foreach $type1 ( keys %{$routerType{$router}})
	{
		foreach $type2 ( @types)
		{
			next unless($OppositeTypes{$type1} =~ $type2);
			print STDERR "WARN: trying to merge $router with $otherrouter, but have $type1 and $type2\n";
		}
	}
}
############################################################################################################
sub specialRRProcessing
{
	# make a list of hidden routers between where we left off and where we are now
	my ($ttl,$iteration) = @_;
	my ($i,$j);
	print STDERR "Doing Special Procesing on $trace: $ttl : $iteration :: couldn't find prev RR packet\n" if($Verbose);
	$lastHop=$SourceRouterName;
	$lastHopIp=$source_ip;
	if($data{$ttl}->{$iteration}->{"RRtype"} =~ /(A|\?)/)
	{
		for($i=0;$i<scalar(@{$data{$ttl}->{$iteration}->{"rr"}});$i++)
		{	# foreach RR entry
			if(!exists $ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]})
			{
				$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]} = newRouter("HIDDEN");
				addInterface($data{$ttl}->{$iteration}->{"rr"}->[$i],
						$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]});
				addLink($lastHop,
						$lastHopIp,
						$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]},
						$data{$ttl}->{$iteration}->{"rr"}->[$i],$Hidden);
			}
			$lastHop=$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]};
			$lastHopIp=$data{$ttl}->{$iteration}->{"rr"}->[$i];
		}
		addLink($lastHop,$lastHopIp,
				$data{$ttl}->{$iteration}->{"name"},
				$data{$ttl}->{$iteration}->{"inhop"},$RR);
	}
	elsif($data{$ttl}->{$iteration}->{"RRtype"} eq "B")
	{
		for($i=0;$i<scalar(@{$data{$ttl}->{$iteration}->{"rr"}})-1;$i++)
		{	# foreach RR entry
			if(!exists $ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]})
			{
				$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]} = newRouter("HIDDEN");
				addInterface($data{$ttl}->{$iteration}->{"rr"}->[$i],
						$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]});
				addLink($lastHop,
						$lastHopIp,
						$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]},
						$data{$ttl}->{$iteration}->{"rr"}->[$i],$Hidden);
			}
			$lastHop=$ip2router{$data{$ttl}->{$iteration}->{"rr"}->[$i]};
			$lastHopIp=$data{$ttl}->{$iteration}->{"rr"}->[$i];
		}
		addLink($lastHop,$lastHopIp,
				$data{$ttl}->{$iteration}->{"name"},
				$data{$ttl}->{$iteration}->{"rr"}->[-1],$RR);
	}
	else
	{
		print STDERR "Unable to do special processing for probe ttl=$ttl it=$iteration from $trace\n" if($Verbose);
	}
}
#######################################################################################################################
sub addAllLinks
{
	# hack in the link between source and ttl=1, this is really an Implicit RR link
	for($iteration=0;$iteration<$Iterations;$iteration++)
	{
		next unless(exists $data{"1"} && exists $data{"1"}->{$iteration});
		addLink($data{"0"}->{$iteration}->{"name"},
				$data{"0"}->{$iteration}->{"inhop"},
				$data{"1"}->{$iteration}->{"name"},
				$data{"1"}->{$iteration}->{"inhop"},$RR);
		last;
	}
	for($ttl=2;$ttl<=$MaxTTL;$ttl++)
	{
		if(!exists($data{$ttl}))
		{
			# all probes for this iteration must have been dropped: weird/unlucky/maybe evil router
			$nDroppedProbe+=$Iterations;
			print STDERR "File $trace has no probes for ttl=$ttl!!\n" if($Verbose);
			next;
		}
		for($iteration=0;$iteration<$Iterations;$iteration++)
		{
			if(!exists($data{$ttl}->{$iteration}))
			{
				# this probe must have dropped
				$nDroppedProbe++;
				print STDERR "File $trace has no probe for ttl=$ttl iteration=$iteration\n" if($Verbose);
				next;
			}
			if($data{$ttl}->{$iteration}->{"gotRR"} ==0)
			{
				# we only get traceroute information out of this one
				do_traceroute_probe($ttl,$iteration);
				next;			# skip to next probe
			}
			$foundRRconnection=0;
			#### 
			# Add RR links relative to all of the probes from the last hop
			# 	on ptype=(Macro|Pollo|Payload) get here
			#	IMPORTANT: only compare even iterations with other event iterations
			#		and odd with odd, so we duck weird problems like RRtype=stupid
			for($j=0;$j<$Iterations;$j++)
			{
				# skip the test against the last hop probe if it doesn't exist
				next if((!exists($data{$ttl-1}))||(!exists($data{$ttl-1}->{$j})));
				# skip the test against the last hop probe unless it has RR
				next unless($data{$ttl-1}->{$j}->{"gotRR"});
				next unless($data{$ttl-1}->{$j}->{"beenClassified"}==1);	
				next unless(&comparePath($data{$ttl}->{$iteration},$data{$ttl-1}->{$j}));	# skip if didn't take same path
				$foundRRconnection=1;
				# call doRR_X_to_Y as appropriate
				$srctype = $data{$ttl-1}->{$j}->{"RRtype"};
				$dsttype = $data{$ttl}->{$iteration}->{"RRtype"};
				print STDERR "doRR($srctype)($dsttype) for ttl=$ttl it=$iteration prev_it=$j ::\n" if($Verbose);
				$doRR{$srctype}->{$dsttype}($ttl,$iteration,$j);
			}
			# if we didn't find a 1 hop previous RR probe to attach to, do some magic to find some probe k hops in past and fill in
			&specialRRProcessing($ttl,$iteration) unless($foundRRconnection);

		}
	}
}
#############################################################################################################################
sub classifyRouters
{
  # needs to be 'local' and not 'my' b/c subroutines assume these vars are defined
  local ($ttl, $iteration, $prev_iteration, $next_iteration,$router, $count);

	# for each probe, assign name, and calc the delta relative to the previous one that took the same path
	# IF $delta=2, then mark curr to B and prev to A
  ## print STDERR join ",", sort keys %data, "\n"; 
  foreach $ttl ( sort  {$a <=> $b}  keys %data ) 
  {
    next if !$ttl;
    ## print STDERR $ttl, "---\n";
	# for($ttl=1;$ttl<=$MaxTTL;$ttl++) 
		# next unless(exists $data{$ttl});		# skip non-existent
    # this sort not necessary for correctness, but for consistency.
    foreach $iteration ( sort { $a <=> $b } keys %{$data{$ttl}} ) 
    { 
	    		$router=undef; 		# start from scratch
		# for($iteration=0;$iteration<$Iterations;$iteration++) 
			# next unless(exists $data{$ttl}->{$iteration});		# skip non-existent
			# look up router's name based on probe source
			$router = $ip2router{$data{$ttl}->{$iteration}->{"inhop"}};
			# assign the router a name if this is the first time we've seen it
			if((! $router) or ($ttl>1 and &previous_hop_was_nat($ttl,$iteration)))
			{
				# this router gets a new name if we've never seen it before
				# or if it is behind a NAT
				$router = &newRouter($data{$ttl}->{$iteration}->{"type"});
				# add the inhop interface; BTW: can't move this to addAllLinks() b/c it is needed ensure unique routers
				&addInterface($data{$ttl}->{$iteration}->{"inhop"},$router);
				&markRouter($router,"MPLS") if($data{$ttl}->{$iteration}->{"hasMPLS"}==1);
				&markRouter($router,"China") if(exists $data{$ttl}->{$iteration}->{"china"});
			}
			$data{$ttl}->{$iteration}->{"name"}=$router;
			next unless($data{$ttl}->{$iteration}->{"gotRR"});	# skip non-RR probes
			
			for($prev_iteration=0;$prev_iteration<$Iterations;$prev_iteration++)
			{
				next unless(exists $data{$ttl-1}->{$prev_iteration});	# skip non-existent
				next unless($data{$ttl-1}->{$prev_iteration}->{"gotRR"});	# skip non-RR probes
				if($data{$ttl-1}->{$prev_iteration}->{"inhop"} eq $data{$ttl}->{$iteration}->{"inhop"})
				{
					my $pttl=$ttl-1;
					print STDERR "WARN: probes for ttl=$ttl it=$iteration and ttl=$pttl it=$prev_iteration come from same ip in $trace\n";
					return 0;
				}
				next unless(&comparePath($data{$ttl}->{$iteration},$data{$ttl-1}->{$prev_iteration}));       # skip if didn't take same path
				next if($data{$ttl}->{$iteration}->{"beenClassified"}==1);	# already done
				# getting here means curr and prev probes exist and have RR and took same paths
				$delta = scalar(@{$data{$ttl}->{$iteration}->{"rr"}}) - scalar(@{$data{$ttl-1}->{$prev_iteration}->{"rr"}});
				$data{$ttl}->{$iteration}->{"delta"}=$delta;
				if(($delta == 2)||($ttl ==1 && $delta==1))		# if $delta == 2 or first hop is +1 (the source->hop1 RR is implicit)
				{
					# then we know absolutely that curr is a B and prev is an A
					&markRouter($router,"B"," Rule #1") or return 0;
					$data{$ttl}->{$iteration}->{"RRtype"}="B";
					$data{$ttl}->{$iteration}->{"beenClassified"}=1;
					&markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"A"," Rule #1") or return 0;
					$data{$ttl-1}->{$prev_iteration}->{"RRtype"}="A";
					$data{$ttl-1}->{$prev_iteration}->{"beenClassified"}=1;
				} 
				elsif ($delta == 0)
				{
					if(scalar(@{$data{$ttl}->{$iteration}->{"rr"}})<9)
					{
						# then we are A-or-N
						&markRouter($router,"A-OR-N"," Rule #3") or return 0;
						$data{$ttl}->{$iteration}->{"RRtype"}="A|N";
						# and prev is N-OR-B
						if($data{$ttl-1}->{$prev_iteration}->{"beenClassified"} ==0)
						{
							&markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"B-OR-N", " Rule #3") or return 0;
							$data{$ttl-1}->{$prev_iteration}->{"RRtype"}="B|N";
						}
					}
					else
					{
						# RR array is full, will not learn about these routers in this trace
						$data{$ttl}->{$iteration}->{"beenClassified"}=1;
					}
				}
				elsif(($delta == 1 )||($delta == -1))
				{
					# has to do more processing below
				}
				else
				{
					# grr!! !*&(*#!# Level3
					warn "Unknown delta value $delta for probe ttl=$ttl it=$iteration prev=$prev_iteration from trace $trace: skipping";
					&markRouter($router,"X");
					$data{$ttl}->{$iteration}->{"beenClassified"}=1;
					$data{$ttl-1}->{$prev_iteration}->{"RRtype"}="A|B|N";	
					return 0;
				}
			}

		}
	}
  #pass 2 to look for layer2 flapping and stupid routers
  foreach $ttl ( sort  {$a <=> $b}  keys %data ) 
  {
    next if !$ttl;
    foreach $iteration ( sort { $a <=> $b } keys %{$data{$ttl}} ) 
    { 
			# look for layer2 flapping
			$next_iteration=($iteration+2)%$Iterations;
			if( exists $data{$ttl}->{$next_iteration} &&
				scalar(@{$data{$ttl}->{$iteration}->{"rr"}}) == scalar(@{$data{$ttl}->{$next_iteration}->{"rr"}}) &&
				&comparePath($data{$ttl}->{$iteration},$data{$ttl}->{$next_iteration}) &&
				$data{$ttl}->{$iteration}->{"inhop"} ne $data{$ttl}->{$next_iteration}->{"inhop"})
			{
				# two probes with the same TTL took identical RR paths, but ended up at diff places: Layer2 switch!
				&markRouter($data{$ttl}->{$iteration}->{"name"},"Layer2Flap");
				&markRouter($data{$ttl}->{$next_iteration}->{"name"},"Layer2Flap");
				print STDERR "WARN: skipping $trace b/c there is a layer2 flap at ttl=$ttl between it=$iteration and it=$next_iteration\n";
				return 0;  # FIXME: don't need to throw away; just not add links relative to me!
			}
    }
    return 0 if(&doStupidTest($ttl));	# currently abort the trace if things are stupid
  }
	# now that everything has been labeled, go through and try to resolve dependencies
	$count=1;
	do
	{
		$has_changed=0;
		print STDERR "Inference Loop $count\n" if($Verbose);
		$count++;
		for($ttl=1;$ttl<=$MaxTTL;$ttl++)
		{
			next unless(exists $data{$ttl});		# skip non-existent
			for($iteration=0;$iteration<$Iterations;$iteration++)
			{
				next unless(exists $data{$ttl}->{$iteration});		# skip non-existent
				next unless($data{$ttl}->{$iteration}->{"gotRR"});	# skip non-RR probes
				next if($data{$ttl}->{$iteration}->{"beenClassified"}==1);	# skip already classified routers
				# look up router's name based on probe source
				$router = $data{$ttl}->{$iteration}->{"name"};
				# some logic rules
				if(hasMark($router,"B-OR-N"))
				{
					if( hasMark($router,"A-OR-N"))
					{
						# then logically, we must be N
						markRouter($router,"N", " Rule L1") or return 0;
						$data{$ttl}->{$iteration}->{"RRtype"}="N";
						$data{$ttl}->{$iteration}->{"beenClassified"}=1;
						$has_changed=1;
						next;
					}
				}
				# part two of the off-by-one rule
				# IF we are off-by-one
				#	if nRR>0 and off-by-one and [ nRR=1 or the last guy is also not off-by-one]
				if((scalar(@{$data{$ttl}->{$iteration}->{"rr"}})>0) &&
					&off_by_one($data{$ttl}->{$iteration}->{"inhop"},$data{$ttl}->{$iteration}->{"rr"}->[-1]) &&
					((scalar(@{$data{$ttl}->{$iteration}->{"rr"}}) == 1) || 
						!&off_by_one($data{$ttl}->{$iteration}->{"inhop"},$data{$ttl}->{$iteration}->{"rr"}->[-2])))
				{
					# THEN we are !B
					if(hasMark($router,"B-OR-N"))	# if we know B OR N
					{
						# then N
						markRouter($router,"N", " Rule L1") or return 0;
						$data{$ttl}->{$iteration}->{"RRtype"}="N";
						$data{$ttl}->{$iteration}->{"beenClassified"}=1;
						$has_changed=1;
						next;
					}
					elsif($data{$ttl}->{$iteration}->{"RRtype"} eq "A|B|N")
					{
						markRouter($router,"A-OR-N", " Rule #".__LINE__) or return 0;
						$data{$ttl}->{$iteration}->{"RRtype"}="A|N";
						$has_changed=1;
					}
					elsif(hasMark($router,"B"))
					{
						print STDERR "WARN: A valid Type B router has interfaces off-by-one: $ttl $iteration $trace\n";
						return 0;
					}
				}
				for($prev_iteration=0;$prev_iteration<$Iterations;$prev_iteration++)
				{
					next unless(exists $data{$ttl-1}->{$prev_iteration});	# skip non-existent
					next unless($data{$ttl-1}->{$prev_iteration}->{"gotRR"});	# skip non-RR probes
					next unless(&comparePath($data{$ttl}->{$iteration},$data{$ttl-1}->{$prev_iteration}));       # skip if didn't take same path
					# getting here means curr and prev probes exist and have RR and took same paths
					if($data{$ttl}->{$iteration}->{"delta"} == 1)
					{
						if($data{$ttl-1}->{$prev_iteration}->{"beenClassified"}==1)
						{
							if($data{$ttl-1}->{$prev_iteration}->{"RRtype"} eq "A")
							{
								# if we are +1 and prev is A, then we are A or N
								$has_changed=1 unless(
										hasMark($data{$ttl}->{$iteration}->{"name"},"A-OR-N") ||
										hasMark($data{$ttl}->{$iteration}->{"name"},"A")  ||
										hasMark($data{$ttl}->{$iteration}->{"name"},"HA")  ||
										hasMark($data{$ttl}->{$iteration}->{"name"},"N"));
								markRouter($data{$ttl}->{$iteration}->{"name"},"A-OR-N"," Rule #4") or return 0;
								$data{$ttl}->{$iteration}->{"RRtype"}="A|N";
							} 
							elsif($data{$ttl-1}->{$prev_iteration}->{"RRtype"} eq "HA")
							{
								# we are definite A if we follow a Hidden A
								$has_changed=1 unless(
										hasMark($data{$ttl}->{$iteration}->{"name"},"A-OR-N") ||
										hasMark($data{$ttl}->{$iteration}->{"name"},"A")  ||
										hasMark($data{$ttl}->{$iteration}->{"name"},"HA")  ||
										hasMark($data{$ttl}->{$iteration}->{"name"},"N"));
								markRouter($data{$ttl}->{$iteration}->{"name"},"A"," Rule #".__LINE__) or return 0;
								$data{$ttl}->{$iteration}->{"RRtype"}="A";

							}
							else
							{
								# if we are +1 and prev is N or B, then we are B: unless off-by-one rule applies
								# off-by-one rule: if we are +1 from last hop and not also +1 from last hop's outgoing
								if(!&off_by_one($data{$ttl}->{$iteration}->{"inhop"},$data{$ttl}->{$iteration}->{"rr"}->[-1])||
									&off_by_one($data{$ttl}->{$iteration}->{"inhop"},$data{$ttl}->{$iteration}->{"rr"}->[-2]))
								{
									markRouter($data{$ttl}->{$iteration}->{"name"},"B"," Rule #5") or return 0;
									$data{$ttl}->{$iteration}->{"RRtype"}="B";
									$data{$ttl}->{$iteration}->{"beenClassified"}=1;
									# and previous probe is B or N
									markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"B-OR-N","Rule #".__LINE__) or return 0;
									$has_changed=1;
									next;
								}
								else
								{
									markRouter($data{$ttl}->{$iteration}->{"name"},"HA"," Rule #off-by-one") or return 0;
									$data{$ttl}->{$iteration}->{"RRtype"}="HA";
									$data{$ttl}->{$iteration}->{"beenClassified"}=1;
									# and hidden router; deal with in the doRR_HA_to_*
									$has_changed=1;
									next;
								}
							}
						} 
						else		# previous probe is unclassified
						{
							# don't think we can tell anything else on this pass
						}
					} 
					elsif($data{$ttl}->{$iteration}->{"delta"} == 0)
					{
						if($data{$ttl-1}->{$prev_iteration}->{"delta"}==0)	# if two +0's in a row
						{
							# then we are A-OR-N
							$has_changed=1 unless(
									hasMark($data{$ttl}->{$iteration}->{"name"},"A-OR-N") ||
									hasMark($data{$ttl}->{$iteration}->{"name"},"A")  ||
									hasMark($data{$ttl}->{$iteration}->{"name"},"N"));
							markRouter($data{$ttl}->{$iteration}->{"name"},"A-OR-N"," Rule #6") or return 0;
							$data{$ttl}->{$iteration}->{"RRtype"}="A|N";
							# and they are definitely N
							markRouter($data{$ttl-1}->{$prev_iteration}->{"name"},"N"," Rule #6") or return 0;
							$data{$ttl-1}->{$prev_iteration}->{"RRtype"}="N";
						}


					} 
					elsif($data{$ttl}->{$iteration}->{"delta"} == -1)
					{
						# there is a hole behind this probe; do nothing and hope it gets classified in next loop
					}
					else
					{
						warn "Unknown delta value $delta for probe $ttl $iteration from trace $trace";
						return 0;
					}
				}
				next unless(($ttl<$MaxTTL)&&($data{$ttl}->{$iteration}->{"beenClassified"}==0));		# don't do the forward inferences if we are at end of trace or done
				for($next_iteration=0;$next_iteration<$Iterations;$next_iteration++)
				{
					next unless(exists $data{$ttl+1}->{$next_iteration});	# skip non-existent
					next unless($data{$ttl+1}->{$next_iteration}->{"gotRR"});	# skip non-RR probes
					next unless(&comparePath($ttl+1,$next_iteration,$iteration));	# skip if didn't take same path
					
					# if next hop is +1 and is also not B
					if($data{$ttl+1}->{$next_iteration}->{"RRtype"}!~ /B/)
					{
						if($data{$ttl+1}->{$next_iteration}->{"delta"} ==1)
						{
							# then we are A
							markRouter($router,"A"," Rule #7") or return 0;
							$data{$ttl}->{$iteration}->{"RRtype"}="A";
							$data{$ttl}->{$iteration}->{"beenClassified"}=1;
							$has_changed=1;
							next;
						}
#						else
#						{
#							markRouter($router,"N"," Rule #8") or return 0;
#							$data{$ttl}->{$iteration}->{"RRtype"}="N";
#							$data{$ttl}->{$iteration}->{"beenClassified"}=1;
#							$has_changed=1;
#							next;
#						}
					}
				}
			}
		}
	}while($has_changed);
	return 1;
}

############################################################################
sub dumpRouterList
{
	my $out;
	$out = shift @_ || \*STDOUT;

	foreach $router (sort keys %routers)
	{
		if($router =~/^R/)
		{
			print $out "Router $router ";
		} 
		elsif($router =~/^E/)
		{
			print $out "Endhost $router ";
		} 
		elsif($router =~/^H/)
		{
			print $out "HIDDEN $router ";
		} 
		elsif($router =~/^NAT/)
		{
			print $out "NAT $router ";
		} 
		elsif($router =~/^S/)
		{
			print $out "Source $router ";
		} 
		else
		{
			die "unknown router label '$router'\n";
		}
		$nAlly=scalar(@{$routers{$router}});
		print $out "nAlly=$nAlly";

		foreach $if (reverse sort @{$routers{$router}})
		{
			print $out " $if";
		}
		print $out "\n";
	}

	foreach $link (sort keys %links)
	{
		# $link is of the form "$srouter:$sip -- $drouter:$dip", and $links{$link} specifies the type
		@line=split /\s+/,$link;
		($srouter,$sip)=split /:/,$line[0];
		($drouter,$dip)=split /:/,$line[2];
		$sip=$dip;		# tell perl not to complain about these; here for clarity
		$edgename="$srouter:$drouter";
		if($links{$link}=~/^\d+/)
		{
			$linktype=$linkstrings[$links{$link}];
		}
		else
		{
			$linktype=$links{$link};
			$linktype=~tr/a-z/A-Z/; # capitalize
		}

		# only print this link if this is the best way we know to connect the two routers
		print $out "Link  $link : ",$linktype,"\n" unless(exists$edgetype{$edgename} && &linkXbetterthenY($edgetype{$edgename},$links{$link}));
	}
}
########################################################################
sub linkXbetterthenY
{
	my ($l1,$l2) =@_;
	my $tmp;
	if($l1!~/^\d+/)         # if not numeric, lookup
	{
		$l1=~tr/a-z/A-Z/;       # map to upper case
			$tmp=$linkstrings2index{$l1} or die "unknown link type $l1";
		$l1=$tmp;
	}
	if($l2!~/^\d+/)         # if not numeric, lookup
	{
		$l2=~tr/a-z/A-Z/;       # map to upper case
			$tmp=$linkstrings2index{$l2} or die "unknown link type $l2";
		$l2=$tmp;
	}
	return $l1<$l2;
}

########################################################################
sub off_by_one
{
	return 0 if($DisableOffbyOneTest);
	my ($ipA, $ipB) = @_;
	my (@A,@B);
	@A = split /\./,$ipA;
	@B = split /\./,$ipB;
	# check third byte first as it is higher entropy/faster
	return 0 if(($A[2] ne $B[2])|| ($A[1] ne $B[1]) || ($A[0] ne $B[0]));
	return 0 if(abs($A[3]-$B[3])!=1);
	return 1;
}

########################################################################
sub doStupidTest
{
	return 0 if($DisableStupidTest);
	my ($ttl, $iteration);
	($ttl)=@_;
	# check for stupid routers: if all of our RR iterations get one source, and all of our TR iterations get another
	#  *AND* the same is true for the TTL ahead of is
	# THEN we are stupid
	# If things look kinda stupid; just junk the trace
	my ($tr_ip,$rr_ip,$could_be_dumb,$prev_iteration) = (undef,undef,1);
	my $stupid_points=0;
	my $i;
	foreach $iteration ( sort { $a <=> $b } keys %{$data{$ttl}} ) 
	{
		if($data{$ttl}->{$iteration}->{"gotRR"})
		{
			for($i=1;$i<$Iterations;$i+=2)
			{
				# NOT stupid
				next unless(exists $data{$ttl}->{$i});
				return 0 if($data{$ttl}->{$iteration}->{"inhop"} eq $data{$ttl}->{$i}->{"inhop"});
			}
			for($i=1;$i<$Iterations;$i+=2)
			{
				# NOT stupid
				next unless(exists $data{$ttl+1}->{$i});
				$stupid_points++ if($data{$ttl}->{$iteration}->{"inhop"} eq $data{$ttl+1}->{$i}->{"inhop"});
			}
		}
	}
	return 0 if($stupid_points < 3);	# not stupid enough
	return 1 if($stupid_points<9);		# stupid enough to junk the trace
	# full marks!
	# now mark it as STUPID
	foreach $iteration ( sort { $a <=> $b } keys %{$data{$ttl}} ) 
	{
		next unless(exists $data{$ttl}->{$iteration});
		if($data{$ttl}->{$iteration}->{"gotRR"})
		{
			# Don't try to fix, just junk
			#$data{$ttl}->{$iteration}->{"name"}=$ip2router{$saved_tr_ip};
			#$data{$ttl}->{$iteration}->{"inhop"}=$saved_tr_ip;

			#&addInterface($tr_ip,$data{$ttl}->{$iteration}->{"name"});
			&markRouter($data{$ttl}->{$iteration}->{"name"},"STUPID");
			$data{$ttl}->{$iteration}->{"RRtype"}="B";
			$data{$ttl}->{$iteration}->{"beenClassified"}=1;
		}
		else
		{
			#&addInterface($rr_ip,$data{$ttl}->{$iteration}->{"name"});
			&markRouter($data{$ttl}->{$iteration}->{"name"},"STUPID");
		}
	}
	# FIXME :: come back later, and push down the right address along RR so we get the right
	# aliases
		
	return 1;		# really is stupid;

}

##############################################################
#	Apparently some chinese firewalls bounce RR messages from the dest instead
#	of from the router, saying dest is one hop away :-(
sub chinaFireWallHack()
{
	my ($iteration,$tr_ip);
	for($iteration=1;$iteration<$Iterations;$iteration+=2)
	{
		next unless(exists $data{1}&& exists $data{1}->{$iteration});
		$tr_ip=$data{1}->{$iteration}->{"inhop"};
	}
	return unless($tr_ip);		# can't apply hack without this
	for($iteration=0;$iteration<$Iterations;$iteration+=2)
	{
		next unless(exists $data{1}->{$iteration});
		if($dest_ip eq $data{1}->{$iteration}->{"inhop"})
		{
			$data{1}->{$iteration}->{"inhop"}=$tr_ip;
			$data{1}->{$iteration}->{"type"}="ROUTER";
			$data{1}->{$iteration}->{"china"}=1;
		}
	}

}
##############################################################
1;


