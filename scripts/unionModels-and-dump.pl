#!/usr/bin/perl -w
# 	./unionModels.pl <base-output-name> [-v ] [-] [file1 [file2 [...]]

$outputbase = shift @ARGV or die "Usage: ./unionModels.pl <base-output-name> [-v ] [-] [file1.model [file2.model [...]]\n";


# link type consts
$RR = 1;
$STR= 2;
$TR = 3;
$Unknown =4;
$Hidden =5;

$MinLinkQuality=$STR;		# a link is a conflict only if it is  better quality then TR, Unknown or Hidden link
$LowMem=0;
$TransitiveAliases=1;

use List::Util qw[min max];

# stoopid hack to make perl not complain about unused vars
$RR=$RR;
$STR=$STR;
$TR=$TR;
$Unknown=$Unknown;
$Hidden=$Hidden;

if((@ARGV>=1)&&($ARGV[0] eq "-lowmem"))
{
	print STDERR "Using lowmem verison\n";
	$LowMem=1;
	shift @ARGV;
}
if((@ARGV>=1)&&($ARGV[0] eq "-t"))
{
	$TransitiveAliases=0;
	shift @ARGV;
}
if((@ARGV>=1)&&($ARGV[0] eq "-v"))
{
	$Verbose=1;
	shift @ARGV;
}
if((@ARGV>=1)&&($ARGV[0] eq "-"))
{
	shift @ARGV;
	push @ARGV,<>;
}

print STDERR "Using $outputbase as the output base\n";
open GOOD, ">$outputbase.good" or die "Couldn't open >$outputbase.good : $!";
open CONFLICT, ">$outputbase.conflicts" or die "Couldn't open >$outputbase.conflicts : $!";
open CONFACTS, ">$outputbase.conflict-facts" or die "Couldn't open >$outputbase.conflict-facts : $!";
open FACTSDB, ">$outputbase.all-facts" or die "Couldn't open >$outputbase.all-facts : $!";
open CONBUG, ">$outputbase.conflict-debug" or die "Couldn't open >$outputbase.conflict-debug : $!";
open BADTRACES, ">$outputbase.badtraces" or die "Couldn't open >$outputbase.badtraces : $!";

%badtraces = ();


print STDERR "\n---------- Parsing models\n";
$filecount=0;
foreach $file (@ARGV)	# foreach file
{
	open F,$file or die "Couldn't open1 :$file:$!";
	chomp $file;
	$filecount++;
	$percent = 100*$filecount/@ARGV;
	printf(STDERR "\r%8.6f done",$percent) unless($filecount%10);
	while(<F>)	# foreach model in a file
	{
		next if(/^Cost/);
		$model = $_;
		@facts=split /\s+/, $model;
		foreach $fact (@facts)	# foreach fact in a model
		{
			next if($fact eq "Best");
			next if($fact eq "model:");
			next if($fact =~ /^\d+$/);	# skip anything that is just a number
			$fact=~tr/{}//d;	# remove any curly braces
			$fact=~s/,$//;		# remove trailing comma
			next if($fact eq "");	# ignore empty facts
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
			elsif($fact =~/^-alias\(/)
			{
				&handleNotAlias($fact);
				next;
			}
			elsif($fact =~/^badNotAlias\(/)
			{
				&handleBadNotAlias($fact);
				next;
			}
			elsif($fact =~/^badAlias\(/)
			{
				&handleBadAlias($fact);
				next;
			}
			elsif($fact =~/^layer2\(/)
			{
				&handleLayer2($fact);
				next;
			}
			elsif($fact =~/^badLink\(/)
			{
				#&handleLayer2($fact);	 ignore; don't propagate bad link information up
				next;
			}
			die "Unknown fact '$fact' in $file:$!";
		}
	}
}
if($TransitiveAliases)
{
	print STDERR "\n---------- Calculating transitive alias closure\n";
	&calcTransitiveAliases();
}
print STDERR "\n---------- Calculating conflicts\n";
&createConflictList();
print STDERR "---------- Printing Good facts\n";
&printGoodList();
print STDERR "---------- Dumping Facts Databse\n";
&printFactsDB();
#print STDERR "---------- Printing conflict ips\n";
#&printConflictList();
#print STDERR "---------- Extracting conflicted facts\n";
#&extractConflictedFacts();
#print STDERR "---------- Printing Bad traces\n";
#&printBadTraces();
print STDERR "\n---------- Done\n";



####################################################################


sub handleType
{
	my ($ip,$type);
	my $fact = shift @_;
	die "Bad fact $fact:$!" unless($fact=~/type\(([ip\d_\.]+),(\w)\)/);
	$ip = $1;
	$type = $2;
	if($LowMem)
	{
		$types{$ip}->{$type}=1;
	}
	else
	{
		$types{$ip}->{$type}->{$file}=1;
	}
}

sub handleOther
{
	my ($ip,$other);
	my $fact = shift @_;
	die "Bad fact '$fact':$!" unless($fact=~/other\(([ip\d_]+),(\w+)\)/);
	$ip = $1;
	$other = $2;
	if($LowMem)
	{
		$other{$ip}->{$other}=1;
	}
	else
	{
		$other{$ip}->{$other}->{$file}=1;
	}
}

sub handleLink
{
	my ($ip1,$ip2,$type);
	my $fact = shift @_;
	die "Bad fact $fact:$!" unless($fact=~/link\(([ip\d_]+),([ip\d_]+),([\w\d]+)\)/);
	$ip1 = $1;
	$ip2 = $2;
	$type= $3;
	
	if($LowMem)
	{
		$links{$ip1}->{$ip2}->{$type}=1
			unless((exists $links{$ip1}->{$ip2}) &&
				(&bestLink($ip1,$ip2)<$type));
	}
	else
	{
		$links{$ip1}->{$ip2}->{$type}->{$file}=1
			unless((exists $links{$ip1}->{$ip2}) &&
				(&bestLink($ip1,$ip2)<$type));
	}
	#$links{$ip1}->{$ip2}<=$type));
}

sub bestLink
{
	my ($ip1,$ip2)=@_;
	my $lowest;
	($lowest)=sort {$a <=> $b} keys %{$links{$ip1}->{$ip2}};
	return $lowest;
}

sub handleBadAlias
{
	my ($ip1,$ip2);
	my $fact = shift @_;
	die "Bad fact '$fact':" unless($fact=~/badAlias\(([ip\d_]+),([ip\d_]+),(\w+)\)/);
	$ip1 = $1;
	$ip2 = $2;
	if($LowMem)
	{
		$Badaliases{$ip1}->{$ip2}=$3;
		$Badaliases{$ip2}->{$ip1}=$3;
	}
	else
	{
		$Badaliases{$ip1}->{$ip2}->{$file}=$3;
		$Badaliases{$ip2}->{$ip1}->{$file}=$3;
	}
}
sub handleBadNotAlias
{
	my ($ip1,$ip2);
	my $fact = shift @_;
	die "Bad fact '$fact':" unless($fact=~/badNotAlias\(([ip\d_]+),([ip\d_]+),(\w+)\)/);
	$ip1 = $1;
	$ip2 = $2;
	$BadNotaliases{$ip1}->{$ip2}->{$file}=$3;
	$BadNotaliases{$ip2}->{$ip1}->{$file}=$3;
}
sub handleNotAlias
{
	my ($ip1,$ip2);
	my $fact = shift @_;
	die "Bad fact '$fact':" unless($fact=~/-alias\(([ip\d_]+),([ip\d_]+),(\w+)\)/);
	$ip1 = $1;
	$ip2 = $2;
	if($LowMem)
	{
		$Notaliases{$ip1}->{$ip2}=$3;
		$Notaliases{$ip2}->{$ip1}=$3;
	}
	else
	{
		$Notaliases{$ip1}->{$ip2}->{$file}=$3;
		$Notaliases{$ip2}->{$ip1}->{$file}=$3;
	}
}
sub handleAlias
{
	my ($ip1,$ip2);
	my $fact = shift @_;
	die "Bad fact '$fact':" unless($fact=~/alias\(([ip\d_]+),([ip\d_]+),(\w+)\)/);
	$ip1 = $1;
	$ip2 = $2;
	if($LowMem)
	{
		$aliases{$ip1}->{$ip2}=$3;
		$aliases{$ip2}->{$ip1}=$3;
	}
	else
	{
		$aliases{$ip1}->{$ip2}->{$file}=$3;
		$aliases{$ip2}->{$ip1}->{$file}=$3;
	}
}

sub handleLayer2
{
	my ($ip1,$ip2);
	my $fact = shift @_;
	die "Bad fact $fact:$!" unless($fact=~/layer2switch\(([ip\d_]+),([ip\d_]+)\)/);
	$ip1 = $1;
	$ip2 = $2;
	if($LowMem)
	{
		$layer2{$ip1}->{$ip2}=1;
		$layer2{$ip2}->{$ip1}=1;
	}
	else
	{
		$layer2{$ip1}->{$ip2}->{$file}=1;
		$layer2{$ip2}->{$ip1}->{$file}=1;

	}
}

sub testConflictLink
{
# we declare facts to be in conflict if there is a link
# between two ips that are supposed to be aliases
	my ($ip1,$ip2)=@_;
	my (@files,@files2);
	my ($trace,$types);
	return 0 unless(exists $links{$ip1}->{$ip2});
	if (&bestLink($ip1,$ip2)>$MinLinkQuality)
	{
		print STDERR "Ignoring conflict caused by low quality link($ip1,$ip2,",&bestLink($ip1,$ip2),")\n";
		return;   # was next, which led to a return...
	}
	foreach $type ( keys %{$links{$ip1}->{$ip2}})
	{
		push @files,keys %{$links{$ip1}->{$ip2}->{$type}} unless($LowMem);
		foreach $trace ( keys %{$links{$ip1}->{$ip2}->{$type}} )
		{
			$badtraces{$trace}++;
		}
	}
	@files2=keys %{$aliases{$ip1}->{$ip2}} unless($LowMem);
	foreach $trace ( keys %{$aliases{$ip1}->{$ip2}})
	{
		$badtraces{$trace}++;
	}
	# delete conflicting facts
	if($LowMem)
	{
		@files=("lowmem-version--nofiles");
		@files2=@files;
	}
	print CONBUG "link($ip1,$ip2,",&bestLink($ip1,$ip2),") ",
		scalar(@files),
		" alias($ip1,$ip2) ",
		scalar(@files2),
		" (",
		join( ";",@files),
		") (",
		join( ";",@files2),
		")\n";

	delete $links{$ip1}->{$ip2};
	return 1;		# signal there was a conflict
}

sub createConflictList
{
	my ($ip1,$ip2);
	foreach $ip1 ( keys %aliases )
	{
		foreach $ip2 (keys %{$aliases{$ip1}})
		{
			if( &testConflictLink($ip1,$ip2) || &testConflictLink($ip1,$ip2))
			{
				delete $aliases{$ip1}->{$ip2};
				delete $aliases{$ip2}->{$ip1};
				$conflictedIP{$ip1}=1;
				$conflictedIP{$ip2}=1;
				#print CONFLICT "conflict IP $ip1\n";
				#print CONFLICT "conflict IP $ip2\n";
			}

		}
	}
}

sub printConflictList
{
	foreach $ip (keys %conflictedIP)
	{
		print CONFLICT "conflict IP $ip\n";
	}
}

sub printBadTraces
{
	foreach $trace (sort { $badtraces{$a} <=> $badtraces{$b} } keys %badtraces)
	{
		print BADTRACES "$trace\t\t$badtraces{$trace}\n";
	}
}


sub printFactsDB
{
	$MaxEntries=5;
	my $n;
	foreach $ip1 ( keys %aliases)
	{
		foreach $ip2 (keys %{$aliases{$ip1}})
		{
			@stuff=keys %{$aliases{$ip1}->{$ip2}};
			$str = join(" ",@stuff[0..min($MaxEntries,$#stuff)]);
			foreach $aliastype ( &calcAliasTypes($aliases{$ip1}->{$ip2}))
			{
				print FACTSDB "alias($ip1,$ip2,$aliastype).\t\t$str\n";
			}
		}
	}
	foreach $ip1 ( keys %Badaliases)
	{
		foreach $ip2 (keys %{$Badaliases{$ip1}})
		{
			#$n = scalar(keys %{$Badaliases{$ip1}->{$ip2}});
			@stuff=keys %{$Badaliases{$ip1}->{$ip2}};
			$str = join(" ",@stuff[0..min($MaxEntries,$#stuff)]);
			foreach $aliastype ( &calcAliasTypes($Badaliases{$ip1}->{$ip2}))
			{
				print FACTSDB "badAlias($ip1,$ip2,$aliastype).\t\t$str\n";
			}
		}
	}
	foreach $ip1 ( keys %Notaliases)
	{
		foreach $ip2 (keys %{$Notaliases{$ip1}})
		{
			#$n = scalar(keys %{$Notaliases{$ip1}->{$ip2}});
			@stuff=keys %{$Notaliases{$ip1}->{$ip2}};
			$str = join(@stuff[0..min($MaxEntries,$#stuff)]," ");
			foreach $aliastype ( &calcAliasTypes($Notaliases{$ip1}->{$ip2}))
			{
				print FACTSDB "-alias($ip1,$ip2,$aliastype).\t\t$str\n";
			}
		}
	}
	foreach $ip1 ( keys %BadNotaliases)
	{
		foreach $ip2 (keys %{$BadNotaliases{$ip1}})
		{
			#$n = scalar(keys %{$BadNotaliases{$ip1}->{$ip2}});
			@stuff=keys %{$BadNotaliases{$ip1}->{$ip2}};
			$str = join(" ",@stuff[0..min($MaxEntries,$#stuff)]);
			foreach $aliastype ( &calcAliasTypes($BadNotaliases{$ip1}->{$ip2}))
			{
				print FACTSDB "badNotAlias($ip1,$ip2,$aliastype).\t\t$str\n";
			}
		}
	}

	foreach $ip1 ( keys %links)
	{
		foreach $ip2 (keys %{$links{$ip1}})
		{
			#$n = scalar(keys %{$links{$ip1}->{$ip2}});
			@stuff=keys %{$links{$ip1}->{$ip2}};
			$str = join(" ",@stuff[0..min($MaxEntries,$#stuff)]);
			print FACTSDB "link($ip1,$ip2,",
				&bestLink($ip1,$ip2),
				").\t\t$str\n";
		}
	}

	foreach $ip (keys %other )
	{
		foreach $o ( keys %{$other{$ip}})
		{
			#$n=scalar(keys %{$other{$ip}->{$o}});
			@stuff=keys %{$other{$ip}};
			$str = join(" ",@stuff[0..min($MaxEntries,$#stuff)]);
			print FACTSDB "other($ip,$o).\t\t$str\n";
		}
	}
	foreach $ip (keys %types )
	{
		foreach $o ( keys %{$types{$ip}})
		{
			#$n=scalar(keys %{$types{$ip}->{$o}});
			@stuff=keys %{$types{$ip}};
			$str = join(" ",@stuff[0..min($MaxEntries,$#stuff)]);
			print FACTSDB "type($ip,",$o,").\t\t$str\n";
		}
	}
}
sub printGoodList
{
	my $n;
	foreach $ip1 ( keys %aliases)
	{
		next if($conflictedIP{$ip1});		# don't print if conflicted
		foreach $ip2 (keys %{$aliases{$ip1}})
		{
			next if($conflictedIP{$ip2});
			$n = scalar(keys %{$aliases{$ip1}->{$ip2}});
			foreach $aliastype ( &calcAliasTypes($aliases{$ip1}->{$ip2}))
			{
				print GOOD "alias($ip1,$ip2,$aliastype).\t\t$n\n";
			}
		}
	}
	foreach $ip1 ( keys %Badaliases)
	{
		next if($conflictedIP{$ip1});		# don't print if conflicted
		foreach $ip2 (keys %{$Badaliases{$ip1}})
		{
			next if($conflictedIP{$ip2});
			$n = scalar(keys %{$Badaliases{$ip1}->{$ip2}});
			foreach $aliastype ( &calcAliasTypes($Badaliases{$ip1}->{$ip2}))
			{
				print GOOD "badAlias($ip1,$ip2,$aliastype).\t\t$n\n";
			}
		}
	}
	foreach $ip1 ( keys %Notaliases)
	{
		next if($conflictedIP{$ip1});		# don't print if conflicted
		foreach $ip2 (keys %{$Notaliases{$ip1}})
		{
			next if($conflictedIP{$ip2});
			$n = scalar(keys %{$Notaliases{$ip1}->{$ip2}});
			foreach $aliastype ( &calcAliasTypes($Notaliases{$ip1}->{$ip2}))
			{
				print GOOD "-alias($ip1,$ip2,$aliastype).\t\t$n\n";
			}
		}
	}
	foreach $ip1 ( keys %BadNotaliases)
	{
		next if($conflictedIP{$ip1});		# don't print if conflicted
		foreach $ip2 (keys %{$BadNotaliases{$ip1}})
		{
			next if($conflictedIP{$ip2});
			$n = scalar(keys %{$BadNotaliases{$ip1}->{$ip2}});
			foreach $aliastype ( &calcAliasTypes($BadNotaliases{$ip1}->{$ip2}))
			{
				print GOOD "badNotAlias($ip1,$ip2,$aliastype).\t\t$n\n";
			}
		}
	}

	foreach $ip1 ( keys %links)
	{
		next if($conflictedIP{$ip1});		# don't print if conflicted
		foreach $ip2 (keys %{$links{$ip1}})
		{
			next if($conflictedIP{$ip2});
			$n = scalar(keys %{$links{$ip1}->{$ip2}});
			print GOOD "link($ip1,$ip2,",
				&bestLink($ip1,$ip2),
				").\t\t$n\n";
		}
	}

	foreach $ip (keys %other )
	{
		if($conflictedIP{$ip})
		{
			next unless($Verbose);
			foreach $o ( keys %{$other{$ip}})
			{
				print CONBUG "conflict other($ip,$o).\n";
			}
			next;
		}
		foreach $o ( keys %{$other{$ip}})
		{
			$n=scalar(keys %{$other{$ip}->{$o}});
			print GOOD "other($ip,$o).\t\t$n\n";
		}
	}
	foreach $ip (keys %types )
	{
		if($conflictedIP{$ip})
		{
			next unless($Verbose);
			print CONBUG "conflict type($ip,",$types{$ip},").\n";
			next;
		}
		foreach $o ( keys %{$types{$ip}})
		{
			$n=scalar(keys %{$types{$ip}->{$o}});
			print GOOD "type($ip,",$o,").\t\t$n\n";
		}
	}
}
sub extractConflictedFacts
{
	$filecount=0;
	foreach $file (@ARGV)	# foreach file
	{
		$file=~s/\.model/.dlv/;	 # look up the equivalent .dlv file
		open F,$file or die "Couldn't open :$file:$!";
		$filecount++;
		$percent = 100*$filecount/@ARGV;
		%conflictedIds=();
		printf(STDERR "\r%8.6f done",$percent) unless($filecount%10);
		# go through file and generate the list of conflicted IDs
		$linenumber=0;
		while(<F>)	# foreach model in a file
		{
			$linenumber++;
			next if(/^%/);	# skip comments
			@fact = split /[\(,\)]/;
			if($fact[0] =~ /(rr|alias|badAlias|badLink|potentialAlias|potentialNotAlias)/)
			{
				
				# rr(ip193_1_201_26_ip128_31_1_16_3,4,ip198_32_8_85).
				$conflictedIds{$fact[1]}=1 if($conflictedIP{$fact[2]});
				next;
			}
			elsif($fact[0] eq "tr" or $fact[0] eq "tr_only")
			{
				# tr(ip193_1_201_26_ip128_31_1_16_3,ip193_1_201_26,ip128_31_1_16,10,ip18_168_0_23,3).
				$conflictedIds{$fact[1]}=1 if($conflictedIP{$fact[5]});
				next;
			}
			elsif($fact[0] =~/(samePrefix|other|offbyone|layer2switch|type)/)
			{
				die "Misparsed fact $file:$linenumber $fact[0]:: '$_':$!" unless($fact[1]);
				if($conflictedIP{$fact[1]})
				{
					print CONFACTS ;
				}
				next;
			}
			elsif($fact[0] eq "link")
			{
				#link(ip128_30_0_250,ip128_31_1_16,4).
				if($conflictedIP{$fact[1]}|| $conflictedIP{$fact[2]})
				{
					print CONFACTS ;
				}
				next;
			}
			elsif($fact[0] =~ /(gap|potentialProbePair|probePair|trPair)/)
			{
				next;	# do nothing with these
			}
			chomp;
			die "Unknown fact '$fact[0]' from '$_':$!";
		}
		# reopen file and output anything with a conflicted ID
		open F,$file or die "Couldn't open :$file:$!";
		while(<F>)
		{
			next if(/^%/);	# skip comments
			@fact = split /[\(,\)]/;
			next if($fact[0] =~ /(badAlias|badLink|alias|potentialAlias|potentialNotAlias|samePrefix|link|other|offbyone|type|layer2switch)/);
			if($fact[0] =~ /^(rr|tr|tr_only)/)
			{
				
				# rr(ip193_1_201_26_ip128_31_1_16_3,4,ip198_32_8_85).
				print CONFACTS if($conflictedIds{$fact[1]});
				next;
			}
			elsif($fact[0] =~ /(gap|potentialProbePair|probePair|trPair)/)
			{
				print CONFACTS if($conflictedIds{$fact[1]} || $conflictedIds{$fact[2]});
				next;
			}
			chomp;
			die "Unknown fact '$_':$!";
		}
	}
}

######################
sub calcAliasTypes
{
	if($LowMem)
	{
		return @_;
	}
	else
	{
		my ($files)=@_;   #(%{$aliases{$ip1}->{$ip2}}
		my (%typesList,$file);
		foreach $file (keys %{$files})
		{
			$typesList{$files->{$file}}=1;
		}
		return keys %typesList;
	}
}

######################
sub calcTransitiveAliases {
	# from CLR, page 563; they claim this is good even if it is O(n^3)
	foreach $k (keys %aliases)
	{
		foreach $i (keys %{$aliases{$k}} )
		{ 
			foreach $j (keys %{$aliases{$k}})
			{
				if( !exists $aliases{$i}->{$j})
				{
					#if (exists $aliases{$k}->{$i} && exists $aliases{$k}->{$j}) # totalogical
					#{
						$aliases{$i}->{$j}->{"unionModels"}= "unionModels";	
						$aliases{$j}->{$i}->{"unionModels"}= "unionModels";	# should be redundant
					#}
				}
			}
		}
	}
}
