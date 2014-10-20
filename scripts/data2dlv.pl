#!/usr/bin/perl -w
# Convert data files generated from passenger into .dlv facts for
#	test-facts.sh	(dlv)

# Track
#	RR info
#	TR info
#	MPLS info
#	Flaky routers (ones that don't do RR all the time)
#	China firewall hack
#	Gaps in the traceroute due to routers that drop packets
# 	anything else we can find out


#### use lib Doesn't !(*&#$ work for no %#(*&@ reason
#if(! exists $ENV{"SIDECARDIR"})
#{
#	$ENV{"SIDECARDIR"}=$ENV{"HOME"}."/swork/sidecar";
#}
#
#use lib $ENV{"SIDECARDIR"}."/scripts";
#$SIDECAR=$ENV{"SIDECAR"} || $ENV{"HOME"}."/swork/sidecar/scripts";
#require "Global-hints-data2dlv.pm";	# TEMP get rid of hints -- don't need it
#print STDERR "$SIDECAR\n";

$probeid=1;
#use lib "/fs/sidecar/scripts";
use Sys::Hostname;

#eval 'use DBI;';
#if($@)
#{
#	die "Problem loading DBI library (probably not installed) --no DB aliases\n";
#	$dumpIps2sql=0;
#}
#else
#{
#	$dumpIps2sql=1;
#}
$datasource=undef;
$datasource=$datasource;
#$dbname="capveg";
$tablename="traces";
$psql='psql';
$hostn=hostname();
if($hostn =~/\.cs\.umd\.edu/ || $hostn =~ /(drive|bluepill)/)
{
	$host="drive.cs.umd.edu";
}
else
{
	$host="drive127.cs.umd.edu";
}
#$host="drive.cs.umd.edu";
$username="capveg";
#$password="dataentrysux";
$ParanoidCheck=0;	# 0 == None, 1 == for layer2 only, 2 == all traces

%tr_probes=();
%tr_adjprobes=();
$tr_probeids=0;


%allips=();
%lazyFixed=();


@OFFBYONE_EXCEPTIONS = ( 
	"^198\.32\.8\.84", 	# Abilene router that doesn't follow the off-by-one rule
	"^216\.24\.186\."	# NLR does weird things with offbyone- denver node has   .7-->.6/.5--->.4
	);

$TTLMAX=30;

if(@ARGV>1 && $ARGV[0] eq "-p")	# get data from sql
{
	shift @ARGV;
	$ParanoidCheck=shift;
	print STDERR "Using Paranoid Level $ParanoidCheck\n";
}
if(@ARGV>0 && $ARGV[0] eq "-")
{
	shift @ARGV;
	push @ARGV,<>;
	chomp @ARGV;
}

if(@ARGV>0 && $ARGV[0] eq "-clique")	# get data from sql
{
	&parseCliqueStatement(@ARGV);
}
elsif(@ARGV>0 && $ARGV[0] eq "-sql")	# get data from sql
{
	shift @ARGV;
	&getdatafromSQL(@ARGV);
}
else
{
	&getdatafromfiles(@ARGV);
}


# print off_by_one pairs
foreach $ip ( keys %allips)
{
	$exception=&offbyone_exception($ip);
	#next if(&offbyone_exception($ip));
	@list=split /[_\.]/,$ip;
	$newip = "$list[0].$list[1].$list[2].".($list[3]+1);
	$exception|=&offbyone_exception($newip);
	if($exception==1)
	{
		$ob1_fact="offbyoneException";
	}
	else
	{
		$ob1_fact="offbyone";

	}
	if(exists $allips{$newip})
	{
		print "$ob1_fact(ip$list[0]_$list[1]_$list[2]_$list[3],ip$list[0]_$list[1]_$list[2]_",
			$list[3]+1,").\n" if(($list[3]&252)==(($list[3]+1)&252));	#if the top 6 bits match, i.e., /30
	}
	$exception=&offbyone_exception($ip);
	$newip = "$list[0].$list[1].$list[2].".($list[3]-1);
	$exception|=&offbyone_exception($newip);
	if($exception==1)
	{
		$ob1_fact="offbyoneException";
	}
	else
	{
		$ob1_fact="offbyone";

	}
	if(exists $allips{$newip})
	{
		print "$ob1_fact(ip$list[0]_$list[1]_$list[2]_$list[3],ip$list[0]_$list[1]_$list[2]_",
			$list[3]-1,").\n" if(($list[3]&252)==(($list[3]-1)&252));	#if the top 6 bits match, i.e., /30
	}
	# note that the -1 case will be caught when the other IP address comes up
}
#&ips2sql(\%allips,$datasource,$ARGV[0]) if($dumpIps2sql);
&printSamePrefixPairs();

&pullUsefulAliases();	# if($dumpIps2sql);
&applyChinaFirewallHack();
&flagFlakyRouters();
$needLazyFix=1;
$foundLazyCount=0;
while($needLazyFix==1)
{
	$needLazyFix=&fixLazyTraces();	# calling them "Lazy" and not "Stupid" incase someone reads this :-)
	$foundLazyCount++ if($needLazyFix==1);
}
if($foundLazyCount>1)
{
	print STDERR "Found multiple($foundLazyCount) lazy routers in @ARGV\n";
}

		

# print basic probe facts
foreach $probe (keys %probes)	# sort() for now, for debug; remove for eff later
#foreach $probe (sort byTTL keys %probes)	# sort() for now, for debug; remove for eff later
{
	die "bogosity in the data:$!" unless(defined($probe));
	if(!$probes{$probe})
	{
		print STDERR "Filling in count value for buggy probe pair $probe\n";
		$probes{$probe}=0;
	}
	$n = $probes{$probe};
	@line = split /,/,$probe;
	$id = $line[0]."_".$probeid;
	print "tr($id,$line[0],$line[1],$line[2],$n).\n";
	$rrindex=1;
	foreach $rr (reverse @line[3..$#line])
	{
		print "rr($id,$rrindex,$rr).\n";
		$rrindex++;
	}
	# identify type C routers here: look at ./cs-planetlab2.cs.surrey.sfu.ca./* for example
	# 142.58.191.126 and 142.58.29.110
	# if the icmp address matches the last RR address? then it's type C
	if((@line>3)&&($line[2] eq $line[$#line])&&(! exists $NotTypeC{$line[2]}))
	{
		print "type($line[2],c).\n";
	}
	else
	{
		$NotTypeC{$line[2]}=1;		# explicitly list anything that is not typeC
		# this is necesary for the 065-infinity2 test, where the path loops back
		# onto itself, and is typeC the second time(!) for God knows what reason
	}
	
	$probeids{$probe}=$id;
	$probeid++;
}
foreach $probe (sort keys %tr_probes)	# sort() for now, for debug; remove for eff later
{
	$n = $tr_probes{$probe};
	@line = split /,/,$probe;
	$id= $line[0]."_".$probeid;
	print "tr_only($id,$line[0],$line[1],$line[2],$n).\n";
	$tr_probeids{$probe}=$id;
	$probeid++;
}
# print probe pair facts: i.e., are two probes one TTL apart on the same path?
foreach $srcdst ( keys %adjprobes)
{
	foreach $ttl1 (sort { $a <=> $b} keys %{$adjprobes{$srcdst}} )
	{
		&testForLayer2($srcdst,$ttl1);		# see if these connections were affected by switches
		foreach $probe1 (keys %{$adjprobes{$srcdst}->{$ttl1}})
		{
			die "found bogosity in data $srcdst ",$ttl1,":$!" if(!defined($probeids{$probe1}));
			next if(&probeSelfLoops($probe1));
			$foundProbePair=0;
			foreach $probe2 (keys %{$adjprobes{$srcdst}->{$ttl1+1}})
			{
				die "found bogosity in data $srcdst ",$ttl1+1,":$!" if(!defined($probeids{$probe2}));
				next unless(&tookSamePath($probe1,$probe2));
				#next if($layer2{$srcdst}&& !&paranoidCheck($srcdst,$ttl1,$probe1,$probe2));
				next if(!&paranoidCheck($srcdst,$ttl1,$probe1,$probe2));
				next if(&probeSelfLoops($probe2));
				# print "potentialProbePair(probeid1,probeid2,rr_delta)"
				@p1 = split /,/,$probe1;
				@p2 = split /,/,$probe2;
				if(@p1 >= 12)	# when first probe's RR is full, treat it like a traceroute probe
				{
					print "trPair($probeids{$probe1},$probeids{$probe2}). % special hack for full RR probes : $p1[2] --> $p2[2]\n";
					next;	# move on to next probe
				}
				$d = scalar(@p2) - scalar(@p1);
				$n = scalar(@p2)-3;	# the 3 is the number of non-rr entries 
				@tmp=@p2;	# b/c splice is destructive
				# this is a hack to prevent printing too many effectively
				#	identical probePairs()
				$probepairkey=$p1[2].",".$p2[2]. join ",",splice(@tmp,-1*($d+1));
				if(!exists $printedProbePairs{$probepairkey})
				{
					print "potentialProbePair($probeids{$probe1},$probeids{$probe2},$d,$n). % $p1[2] (ttl=$p1[1]) --> $p2[2] (ttl=$p2[1]) delta=$d\n";
				}
				else
				{
					print "% skipped: there was multi-pathing before this that does not affect this probepair: $probepairkey :: probePair($probeids{$probe1},$probeids{$probe2},$d,$n).\n";
				}
				$printedProbePairs{$probepairkey}=1;
				$foundProbePair=1;
				die "found bogosity2 in data $srcdst ",$ttl1+1,":$!" if(!defined($probe2));
			}
			#&generateGap($srcdst,$probe1,$ttl1,1) unless(&nonEmptyHashRef($adjprobes{$srcdst}->{$ttl1+1}));
			&generateGap($srcdst,$probe1,$ttl1,1) unless($foundProbePair);
		}
	}
}

foreach $srcdst ( keys %tr_adjprobes)
{
	($src,$dst) = split /:/,$srcdst;
	foreach $ttl1 (sort {$a <=> $b} keys %{$tr_adjprobes{$srcdst}} )
	{
		foreach $probe1 (keys %{$tr_adjprobes{$srcdst}->{$ttl1}})
		{
			@p1 = split /,/,$probe1;
			foreach $probe2 (keys %{$tr_adjprobes{$srcdst}->{$ttl1+1}})
			{
				@p2 = split /,/,$probe2;
				# print "trPair(probeid1,probeid2)"
				
				if($p1[2] eq $p2[2])	# do not make solver handle self-loops; it makes solver very slow
				{
					print "% skipping self link trPair($tr_probeids{$probe1},$tr_probeids{$probe2}). % tr to $dst: $p1[2] --> $p2[2]\n";
					print "other($p1[2],selflink).\n";
				}
				else
				{
					print "trPair($tr_probeids{$probe1},$tr_probeids{$probe2}). % tr  from $src->$dst: $p1[2] --> $p2[2]\n";
				}
			}
		}
	}
}
$hostname =`hostname`;
chomp $hostname;
print "% Hints: $hostname\n";	# this has been replaced by the db calls above
foreach $ip (keys %iplist)
{
	next unless(exists $hints{$ip});
	foreach $hint ( @{$hints{$ip}})
	{
		print "$hint\n";
	}
}


###########################################################################################
# Subroutines
###########################################################################################

#########################################################################
# given two probe pair id strings strings "src,ttl,icmp", return -1,0,1 
# depending on which ttl is lower; 
#	actually kind of important for case 065-infinite2.test due
#	to multiple actions from a router, the 2nd time it appears typeC when it is not

sub byTTL
{
	my (@a,@b);
        @a = split /,/,$a;
        @b = split /,/,$b;
	return $a[1] <=> $b[1];
}

#########################################################################
# foreach file that is passed, parse it into our internal data structure
sub getdatafromfiles
{
	my @files=@_;
	foreach $file (@files)
	{
		if($file =~ /\w+-([\d\.]+)([:,]\d+)?-([\d\.]+)([:,]\d+)?/)
		{
			$sip = $1;
			$dip = $3;
			$s_ip="ip".$sip;
			$s_ip=~s/\./_/g;
			$d_ip="ip".$dip;
			$d_ip=~s/\./_/g;
			print "type($s_ip,n).\n";
			print "other($s_ip,source).\n";
			print "other($d_ip,endhost).\n";
			$base="$s_ip,0,$s_ip";
			$probes{$base}++;          # hack in source as TTL=0
			$tr_probes{$base}++;          # hack in source as TTL=0
			$adjprobes{"$sip:$dip"}->{"0"}->{$base}++;
			$tr_adjprobes{"$sip:$dip"}->{"0"}->{$base}++;
			$lastip=$s_ip;
			$lastttl=0;
		}
		else
		{
			if($file !~ /data-(clique|sql)/i)
			{
				print STDERR "File '$file' doesn't match data-sip:sport-dip:dport-id format: skipping\n";
				next;
			}
		}

		open F, "$file" or die "File $file open: $!";
		print "% Probes from $file\n";
		%iplist=();
		while(<F>)
		{
			if(/#SQL/)
			{
				&parseSqlStatement($_);
			}
			elsif(/#CLIQUE/)
			{
				&parseCliqueStatement($_);
			}
			elsif(/RECV/)
			{
				# adds probe to %probes by side effect
				if(/RR/)
				{
					&parseRRProbe($sip,$dip,$_);
				}
				else
				{
					&parseTRProbe($sip,$dip,$_);
				}
			}
		}
		# hack in unknown link between last responsive router and endhost
		print "link($lastip,$d_ip,4).\n" unless(!$lastip || !$d_ip || $lastip eq $d_ip); 	# add unknown link between last hop and endhost
		foreach $ip (keys %iplist )
		{
			$allips{$ip}+=$iplist{$ip};
		}
	}
}
############################################################
# parse an "#SQL <foo>" statement
sub parseSqlStatement
{
	my ($line)=@_;
	$line=~s/^#SQL//;
	getdatafromSQL($line);
}
############################################################
# parse an "#CLIQUE ip1 ip2 [..]" statement
sub parseCliqueStatement
{
	@ips = split /\s+/,join(" ",@_);
	shift @ips;
	foreach $ip1 ( @ips)
	{
		foreach $ip2 (@ips)
		{
			next if($ip1 eq $ip2);
			getdatafromSQL("src='$ip1'  and dst='$ip2'"); # this should be faster then the "src in (...) and dst in (...) "
								      # query, b/c we have an index based on src,dst
		}
	}
}
############################################################
# psqlCommand
#	take a sql query, and return a table with the results
#	THIS IS A HORRIBLE HACK b/c the installed libraries
#	don't know how to deal with arrays, and this is the
#	cheapest way around that

sub psqlCommand
{
	my ($sql_command) = @_;
	my (@results,@tmp);
	if(! defined($ENV{'HOME'}))
	{
		if(! defined($ENV{'CWD'}))
		{
			$ENV{'CWD'}=`pwd`;
			chomp $ENV{'CWD'};
		}
		$ENV{'HOME'}=$ENV{'CWD'};
	}
	if(! -f "$ENV{'HOME'}/.pgpass")
	{
		`cp /fs/sidecar/scripts/pgpass $ENV{'HOME'}/.pgpass`;	# copy password file into place
		`chmod 600 $ENV{'HOME'}/.pgpass`;
	}
	$cmd = "$psql -q -h $host -t -U $username -c \"$sql_command\" | ";
	#print STDERR "Running $cmd\n";
	open PSQL, $cmd or die "Couldn't run command $cmd:$!";
	while(<PSQL>)
	{
		my (@line);
		chomp;
		next if(/^\s*$/);	# skip all blank lines, like the last one
		s/^\s*//;	# remove leading whitespace
		s/\s*$//;	# remove trailing whitespace
		@line = split /\s*\|\s*/,$_;
		push @results,\@line;	# store a reference to line
	}
	close(PSQL);
	#print STDERR "Done $cmd\n";
	return @results;
}

############################################################
# getdatafromSql
#	query the database for all probes that matched the given query, and parse them into our
#	internal format
sub getdatafromSQL
{
	#my ($dbh,$sth);
	my ($sip,$dip,$tr,$ttl,$nrr,$rr);
	my (%facts);
	$where=join " ",@_;
	chomp $where;
	$select = "SELECT src,dst,resp,ttl,nrr,rr FROM $tablename WHERE $where";
#	$dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;",
#			"$username",
#			"$password");
#	
#	if(!$dbh)
#	{
#		 warn "Couldn't connect to database: " . DBI->errstr;
#		 warn "Continuing without aliases and notaliases from DB\n";
#		 return;
#	}
	print  "\%Facts from query -- '$select'\n";
#	$sth = $dbh->prepare($select) or die "Couldn't prepare select statement: " . $dbh->errstr;
#	$sth->execute() ;
	#print "% Fetching from DB '$select'\n";
	
	foreach $row ( &psqlCommand($select))
	{
		($sip,$dip,$tr,$ttl,$nrr,$rr) = @{$row};
		$allips{$sip}=1;
		$allips{$dip}=1;
		$allips{$tr}=1;
		$sip=&frobIP($sip);
		$dip=&frobIP($dip);
		$tr=&frobIP($tr);
		$base="$sip,0,$sip";
		$probes{$base}++;          # hack in source as TTL=0
		$tr_probes{$base}++;          # hack in source as TTL=0
		$adjprobes{"$sip:$dip"}->{"0"}->{$base}++;
		$tr_adjprobes{"$sip:$dip"}->{"0"}->{$base}++;
		$lastip=$s_ip;
		$facts{"type($sip,n).\n"}=1;
		$facts{"other($sip,source).\n"}=1;
		$facts{"other($dip,endhost).\n"}=1;
		$lastttl=0;
		#print STDERR "Probe : $sip,$dip,$tr,$ttl,$nrr -- ";
		if($nrr>=0) 	# RR entry
		{
			$rr =~ s/[{}]//g;
			@rr = split /,/,$rr;
			$probeline= "$sip,$ttl,$tr";
			foreach $ip (@rr)
			{
				$allips{$ip}=1;
				$ip = &frobIP($ip);
				$probeline.= ",$ip";
			}
			$probes{$probeline}++;
			$adjprobes{"$sip:$dip"}->{"$ttl"}->{$probeline}++;
		}
		else		# TR entry
		{
			$probeline= "$sip,$ttl,$tr";
			$tr_probes{$probeline}++;
			$tr_adjprobes{"$sip:$dip"}->{"$ttl"}->{$probeline}++;

		}
		#print STDERR "Done \n";
	}
	foreach $fact (keys %facts)	# now dump all of the facts at once
	{
		print $fact;
	}
	#$sth->finish;
	#$dbh->disconnect;
	#print STDERR "Done fetching\n";
}

####################################
# parse the line for a RR probe from a passenger file

sub parseRRProbe
{
	my ($sip,$dip,$str,@line);
	my ($rr,$tr,$ttl, $probeline);
	($sip,$dip,$str) = @_;
	@line = split /\s+/,$str;

	$tr = $line[6];
	$iplist{$sip}=1;
	$iplist{$dip}=1;
	$iplist{$tr}=1;
	$ttl= $line[3];
	$tr=~s/\./_/g;

	$probeline = "ip$sip,$ttl,ip$tr";	# $probeline is a one string summary of probe info
						# leave $dip out to reduce # of statements
	# append RR addresses
	foreach $rr (grep /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, @line[12..$#line])
	{
		$probeline .= ",ip$rr";
		$iplist{$rr}=1;
	}
	$probeline=~s/\./_/g;
	print "other(ip$tr,mpls).\n" if($str=~/MPLS/);

	$probes{$probeline}++;		# add this probe to list of probes; incrment count if exists
	$adjprobes{"$sip:$dip"}->{"$ttl"}->{$probeline}++;
	#($rr) = reverse  grep /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, @line[12..$#line];
	#return unless(defined($rr));
	if(($ttl>$lastttl)&&("ip".$tr ne $d_ip))
	{
		#$rr=~tr/\./_/;
		$lastip="ip".$tr;
		$lastttl=$ttl;
	}
}

####################################
# parse the line for a TR probe from a passenger file

sub parseTRProbe
{
	my ($sip,$dip,$str,@line);
	my ($tr,$ttl, $probeline);
	($sip,$dip,$str) = @_;
	@line = split /\s+/,$str;

	$tr = $line[6];
	if(!$tr)
	{
		print STDERR "Unparsable line ", join ",",@line,"\n";
		return;
	}
	$iplist{$sip}=1;
	$iplist{$dip}=1;
	$iplist{$tr}=1;
	$ttl= $line[3];
	$tr=~s/\./_/g;

	$probeline = "ip$sip,$ttl,ip$tr";	# $probeline is a one string summary of probe info
						# leave $dip out to reduce # of statements
	# append RR addresses
	foreach $rr (grep /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, @line[12..$#line])
	{
		$probeline .= ",ip$rr";
	}
	$probeline=~s/\./_/g;
	print "other(ip$tr,mpls).\n" if($str=~/MPLS/);
	if(($ttl>$lastttl)&&("ip".$tr ne $d_ip))
	{
		$lastip="ip".$tr;
		$lastttl=$ttl;
	}

	$tr_probes{$probeline}++;		# add this probe to list of probes; incrment count if exists
	$tr_adjprobes{"$sip:$dip"}->{"$ttl"}->{$probeline}++;
}

# return true if these two probes took the same path for the 2nd to last hop
# this should only be called with probes that are one TTL apart
sub tookSamePath
{
	my ($probe1,$probe2) = @_;
	my (@p1,@p2);

	@p1 = split /,/,$probe1;
	@p2 = split /,/,$probe2;
	return 0 unless(defined $p2[$#p1]);	# never same path if @p1>@p2
	return 0 if($p1[2] eq $p2[2]);	# two things from the same icmp src are never on the same path; 019-difflensplit.test
	return 1 if($p1[$#p1] eq $p1[2]);	# router1 is type C or nRR=0, then same path
	# two probes took the same path IF they took the same
	#	path as the TR only data AND if their last
	# 	RR matches
	#		this is an important test for things
	#		where there is a split caused by RR breaking
	#		load balancing
	return 1 if(($p1[$#p1] eq $p2[$#p1]) &&	
		(exists $tr_probes{"$p1[0],$p1[1],$p1[2]"}) &&
		(exists $tr_probes{"$p2[0],$p2[1],$p2[2]"}));
	# two probes took the same path IF neither took the same
	#	path as the TR only data AND if their last
	# 	RR matches
	#		this is an important test for things
	#		where there is a split caused by RR breaking
	#		load balancing
	#return 1 if(($p1[$#p1] eq $p2[$#p1]) &&	
		#(!exists $tr_probes{"$p1[0],$p1[1],$p1[2]"}) &&
		#(!exists $tr_probes{"$p2[0],$p2[1],$p2[2]"}));
	# else anything no on the TR path needs a more paranoid test
	# i.e., verify each element of the path is the same
	for($i=3;$i<=$#p1;$i++)
	{
		die unless(defined $p1[$i]);
		return 0 if($p1[$i] ne $p2[$i]); # if the rr entries don't match, not same path
	}
	# if we got this far, they took the same paths
	return 1;		
}
# if there is a break in the traceroute, try to recontruct info from forward ttl packets
sub generateGap
{
	my ($srcdst,$probe1,$ttl,$rr)=@_;
	my ($gaplen,$adjproberef,$probeidref,$i);
	my (@rr_before,@p1,@p2,@rr_after,$found,$foundp,$probe2);
	if($rr)
	{
		$probeidref=\%probeids;
		$adjproberef=\%adjprobes;
	} 
	else
	{
		$probeidref=\%tr_probeids;
		$adjproberef=\%tr_adjprobes;
	}
	$found=0;
	for($gaplen=2;($ttl+$gaplen)<=$TTLMAX;$gaplen++)
	{
		next unless(&nonEmptyHashRef( $adjproberef->{$srcdst}->{$ttl+$gaplen}));
		# now see if this probe and the past one took the same RR path
		if($rr==0)	# $rr == 0 implies no RR path, just accept it
		{ 
			$found=1;
			last;
		}
		@p1 = split /,/,$probe1;
		@rr_before=@p1[3..$#p1];	# just RR entries
		return if(@rr_before>=9);
		foreach $probe2 ( keys %{$adjproberef->{$srcdst}->{$ttl+$gaplen}})
		{
			@p2 = split /,/,$probe2;
			if(exists $lazyFixed{$p2[2]})
			{
				print "% not gap linking $p1[2] (ttl=$p1[1]) to $p2[2] (ttl=$p2[1]) b/c it was lazy fixed\n";
				next;
			}
			@rr_after=@p2[3..$#p2];	# just RR entries
			for($i=0;$i<=min($#rr_after,$#rr_before);$i++)
			{
				if($rr_before[$i] ne $rr_after[$i])
				{
					last unless(($i==min($#rr_after,$#rr_before)) &&
							($p1[2] eq $p1[$#p1]));
					# last unless prev router is type C
				}
			}
			if($i>min($#rr_after,$#rr_before))
			{
				$found=1;
				$foundp=$probe2;
				last;
			}
		}
		last if($found);

	}
	return unless($found);
	# this is to fix a bug in the 'weirdlybroken' test case where if $ttl+$gaplen+1 is > 9 weird
	# things happen
	# FIXME: this too is probably not totally safe, but I don't know what is
	if(($gaplen+@rr_before)> 9)
	{
		$gaplen=9-@rr_before;
	}
	$n = scalar(@rr_after);	 # number of RR entries
	print "gap($probeidref->{$probe1},$probeidref->{$foundp},",$gaplen,",",@rr_after-@rr_before,",$n).";
	print " % gap: $p1[2] (ttl=$p1[1]) --> $p2[2] (ttl=$p2[1])\n";
}

# return 1 if the hash ref is non-empty, else 0
sub nonEmptyHashRef
{
	my ($href) = @_;
	my @tmp;
	@tmp = keys %{$href};
	return 0 != @tmp;
}
# min.. sigh... this must be defined somewhere
sub min
{
	my ($a,$b)=@_;
	return $a if($a<=$b);
	return $b;
}
# return 1 if $ip is in %OFFBYONE_EXCEPTIONS
sub offbyone_exception
{
	my ($ip)=@_;
	my $pattern;
	foreach $pattern ( @OFFBYONE_EXCEPTIONS)
	{
		return 1 if($ip=~$pattern);
	}
	return 0;
}
# output layer2(X,Y) to indicate there is a switch between X and Y
sub testForLayer2
{
	my ($srcdst,$ttl1)=@_;	
	my ($probe,%edges,@rr,$tr,$edge,@edgelist);
	foreach $probe ( keys %{$adjprobes{$srcdst}->{$ttl1}})
	{
		@rr = split /,/,$probe;
		$tr = $rr[2];
		@rr=@rr[3..$#rr];	# just RR entries
		$edges{$rr[$#rr]}->{$tr}=1 unless(@rr<1);	# push this address on the end of edges list
	}
	foreach $edge ( keys %edges)
	{
		@edgelist = keys %{$edges{$edge}};
		next unless(@edgelist>1);
		foreach $tr ( @edgelist )
		{
			print "layer2switch($edge,$tr).\n";
			print "other($edge,layer2).\n";
			print "other($tr,layer2).\n";
			$layer2{$srcdst}=1;
		}
	}
}
# china firewall hack
#	some firewall in china responds to RR with the dst address as the source.. which is really weird
#	just delete these probes
#		SEEMS to happen from these pl nodes:
#./csu2.6planetlab.edu.cn
#./ustc2.6planetlab.edu.cn
#./tongji1.6planetlab.edu.cn
#./tongji2.6planetlab.edu.cn
# happens at third hop for sdu2.6planetlab.edu.cn. (!!)

sub applyChinaFirewallHack
{
	my ($srcdst,$probe,$trprobe,@rr,@tr,$china,$savedip,$count,$adjcount);
	my (@line,$dstaddr);
	foreach $srcdst ( keys %adjprobes)
	{
		@line = split /:/,$srcdst;
		$dstaddr=&frobIP($line[1]);	# frob ip w.x.y.z -> ipw_x_y_z
		foreach $ttl ( sort  {$a <=> $b} keys %{$adjprobes{$srcdst}}) # not sufficient to test first hop; see china-third-hop.test
		{
			foreach $probe ( keys %{$adjprobes{$srcdst}->{$ttl}})
			{
				$china=0;
				@rr = split /,/,$probe;
				next if($rr[2] ne $dstaddr);	# next if icmp src ne dst
				foreach $trprobe (keys %{$tr_adjprobes{$srcdst}->{$ttl}})
				{
					@tr = split /,/,$trprobe;
					if($rr[2] ne $tr[2])   # if the RR icmp src!=TR icmp src
					{
						$china=1;
						$savedip=$tr[2];
						print "other($tr[2],china).\n";		# tag this router as modified by china firewall hack
					}
				}
				if(!$china)	# there might be other ways something is china
				{
					# look to see if there is a next hop and if it isn't also the endhost
					#	this happens if the TR probes that would catch in the first case
					# 	have by misfortunate all been dropped
					foreach $nextprobe (keys %{$adjprobes{$srcdst}->{$ttl+1}})
					{
						@rr2 = split /,/,$nextprobe;
						next if($rr2[2] eq $dstaddr);      # next if not still endhost
						$china=1;
						$savedip=$rr2[3];		   # since we don't know the tr address, just use the next hop's RR address
						$NotTypeC{$savedip}=1;		# hack! to prevent this from looking like a typeC router
						print "other($rr2[3],china).\n";# tag this router as modified by china firewall hack
					}
				}
				if($china)
				{
					$count=$probes{$probe};
					$adjcount=$adjprobes{$srcdst}->{$ttl}->{$probe};
					delete $adjprobes{$srcdst}->{$ttl}->{$probe};
					delete $probes{$probe};
					@rr=split /,/,$probe;
					$rr[2]=$savedip;
					$probe = join ",",@rr;
					$adjprobes{$srcdst}->{$ttl}->{$probe}=$adjcount;
					$probes{$probe}=$count;
				}
			}
		}
	}
}
################################
# flaky routers 

sub flagFlakyRouters
{
	my ($srcdst,@keys,$ttl,@rr1,@rr2,$i,$j,$k,$found,@tmp,$offset);
	foreach $srcdst (keys %adjprobes)
	{
		foreach $ttl (keys %{$adjprobes{$srcdst}})
		{
			@keys=keys %{$adjprobes{$srcdst}->{$ttl}};
			for($i=0;$i<@keys;$i++)
			{
				for($j=$i+1;$j<@keys;$j++)
				{
					$found=0;
					@rr1 = split /,/, $keys[$i];
					@rr2 = split /,/, $keys[$j];
					next if($rr1[2] ne $rr2[2]);		# if same icmp source
					next if(scalar(@rr1) == scalar(@rr2)); #if same # of RR entries
					if(@rr1<@rr2)
					{
						@tmp=@rr1;	# swap things so @rr1 is always longer
						@rr1=@rr2;
						@rr2=@tmp;
					}
					$offset=0;
					for($k=3;$k<&min(scalar(@rr1),scalar(@rr2));$k++)
					{
						next if($rr1[$k+$offset] eq $rr2[$k]);
						if($rr1[$k+1+$offset] eq $rr2[$k])	# if one is missing
						{
							$found=1;
							$offset++;
							print "other(",$rr1[$k+$offset],",flaky).\n";
						}
					}
					if($found)	# if found a flaky trace, remove the shorter one
					{
						delete $adjprobes{$srcdst}->{$ttl}->{$keys[$j]};
						delete $probes{$keys[$j]};
					}
				}
			}
		}
	}
}
################################
# Fix Lazy Routers
#	Lazy routers are ones that only decrement TTL in packets w/o options
#	So if a packet has RR set, it will go on to the next router before bouncing
#	Creating a weird off-by-one descepancy between TR routers and RR routers
#	This proceedure tried to detect it and fix up effected RR packets
#		we also call these routers "Stupid" out of spite.
sub fixLazyTraces()
{	
	my ($srcdst,$probe,$ttl,@rr,@tr,$trprobe,$foundStupid,$savedTTL,$savedCount,$foundAStupid);
	$foundAStupid=0;
	foreach $srcdst (keys %adjprobes)
	{
		my %neo_adjprobes;
		$foundStupid=0;
		foreach $ttl (sort {$a <=> $b} keys %{$adjprobes{$srcdst}})   # important this is numerically sorted
		{
			foreach $probe ( keys %{$adjprobes{$srcdst}->{$ttl}})
			{
				#$probeline = "ip$sip,$ttl,ip$tr";	# $probeline is a one string summary of probe info
				@rr=split /,/,$probe;
				$trprobe=join ",",$rr[0],$rr[1]+1,$rr[2];
				$thisprobe=join ",",$rr[0],$rr[1],$rr[2];
				if(exists $tr_adjprobes{$srcdst} &&
					exists $tr_adjprobes{$srcdst}->{$ttl+1} &&	# if the next hop exists
					(! exists $tr_adjprobes{$srcdst}->{$ttl}->{$thisprobe}) &&# current hop does not have same icmp ip
					exists $tr_adjprobes{$srcdst}->{$ttl+1}->{$trprobe}) # and next hop has same icmp ip
				{
					# extra check against multipathing: due to false-stupid.test
					if(exists $adjprobes{$srcdst}->{$ttl+1})
					{
						# this is not a valid stupid router if the same RR probe shows
						# up in the next TTL as well
						next if(grep /^$trprobe/,keys %{$adjprobes{$srcdst}->{$ttl+1}});
					}

					$foundStupid=1;
					print "% Found a lazy router in one of the traces going to ULTRA PARANOID MODE\n";
					$ParanoidCheck=2;
					$lazyDemark{$rr[$#rr]}=1;# save the last RR entry in the lazy probe as
								# the lazy 'demark'
								# anything that goes through this (in this src->dst pair)
								# is also lazy
					print "other(",$rr[$#rr],",lazydemark).\n";
					foreach $trprobe ( keys %{$tr_adjprobes{$srcdst}->{$ttl}})
					{
						@tr=split /,/,$trprobe;
						# just flag all routers in previous hop as stupid; can't tell more specifically
						print "other($tr[2],lazy).\n";
					}
					last;
				}
			}
			last if($foundStupid);		# we are only capable of tracking 1 lazy router at a time
		}
		if($foundStupid)
		{
			$foundAStupid=1;
			# we know this trace has a stupid router at ttl=$savedTTL
			# snag all of the things that go through ips in $lazyDemark (069-splitpathlazy)
			foreach $ttl (sort {$a <=> $b} keys %{$adjprobes{$srcdst}})
			{
				foreach $probe ( keys %{$adjprobes{$srcdst}->{$ttl}})
				{
					if(&wentThrough($probe,\%lazyDemark))	
					{
						# went through our lazy demark point; bump this probe to next ttl
						@rr=split /,/,$probe;
						print "% probe $rr[2] (ttl=$rr[1]) lazy remapped to ttl=". ($rr[1]+1) ."\n";
						$lazyFixed{$rr[2]}=1;
						$savedCount=$probes{$probe};
						#$probeline = "ip$sip,ip$dip,$ttl,ip$tr";	# $probeline is a one string summary of probe info
						#delete $probes{$probe};	# hack 
						$rr[1]++;		# mark this probe as if it came from TTL+1
						$probe=join ",",@rr;
						$neo_adjprobes{$srcdst}->{$ttl+1}->{$probe}=$savedCount;  # replace in new adjprobes
						$probes{$probe}=$savedCount;	# put back into probes list with updated TTL
					}
					else
					{
						# don't frob this probe; just copy it over
						$neo_adjprobes{$srcdst}->{$ttl}->{$probe}=$adjprobes{$srcdst}->{$ttl}->{$probe};
					}
				}
			}
			$adjprobes{$srcdst}=\%{$neo_adjprobes{$srcdst}}; 	# swap new entries into place
		}
		#	else don't frob adjprobes, the current results are okay
	}
	return $foundAStupid;
}

####
# sub wentThrough(probe, hashref(lazyDemark)
#	return 1 if probe contains any of the keys in places hashreh
#	0 otherwise

sub wentThrough
{
	my ($probe, $places) = @_;
	my (@rr);
	@rr = split /,/,$probe;
	for($i=3;$i<=$#rr;$i++)
	{
		return 1 if(exists $places->{$rr[$i]});
	}
	return 0;
}

##### 
# &paranoidCheck($srcdst,$ttl1,$probe1,$probe2));
#	return 1 if these probes exist in TR space as well as RR space
#	else return 0
#	this is called after we already know that they exist in RR space

sub paranoidCheck
{
	if($ParanoidCheck==0)
	{
		print "% Paranoid Check disabled\n";
		return 1;
	}
	my ($srcdst,$ttl,$probe1,$probe2) = @_;
	return 1 if($ParanoidCheck==1&& !exists $layer2{$srcdst});
	my ($t1,$t2,@a1,@a2);
	@a1 = split /,/,$probe1;
	$t1 = "$a1[0],$a1[1],$a1[2]";
	@a2 = split /,/,$probe2;
	$t2 = "$a2[0],$a2[1],$a2[2]";

	if((exists $tr_adjprobes{$srcdst})&&
		(exists $tr_adjprobes{$srcdst}->{$ttl}) &&
		(exists $tr_adjprobes{$srcdst}->{$ttl}->{$t1}) &&
		(exists $tr_adjprobes{$srcdst}->{$ttl+1}) &&
		(exists $tr_adjprobes{$srcdst}->{$ttl+1}->{$t2}))
	{
		return 1;
	}
	print "% paranoid skipping gap(",$probeids{$probe1},",",$probeids{$probe2},"). $a1[2] (ttl=$a1[1]) --> $a2[2] (ttl=$a2[1])\n";
	return 0;
}

#########
#  &printSamePrefixPairs()
#  two ips are in the same prefix iff they are in the same /24 prefix

sub printSamePrefixPairs
{
	my ($ip1,$ip2,@l1,@l2);
	foreach $ip1 ( keys %allips)
	{
		foreach $ip2 (keys %allips )
		{
			next if ($ip1 eq $ip2);
			@l1 = split /\./,$ip1;
			@l2 = split /\./,$ip2;
			print "samePrefix(ip$l1[0]_$l1[1]_$l1[2]_$l1[3],ip$l2[0]_$l2[1]_$l2[2]_$l2[3]).\n" 
							if(($l1[0] eq $l2[0]) &&
								($l1[1] eq $l2[1]) &&
								($l1[2] eq $l2[2]));
		}
	}
}


###########
#         &ips2sql(%iplist,$datasource,$file) if($dumpIps2sql);
# take the hash of ip addresses and dump into a database
# if they are not already there

#sub ips2sql
#{
#	my ($iplist,$datasource,$file)=@_;
#
#	$file=`basename $file`;
#	chomp $file;
#	
#	$dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;",
#			"$username",
#			"$password") or
#			die "Couldn't connect to database: ";
#	if(undef($dbh))
#	{
#		 warn "Couldn't connect to database: " . DBI->errstr;
#		 warn "Continuing without aliases and notaliases from DB\n";
#		 return;
#	}
#
#	$sth=$dbh->prepare('SELECT ip FROM ips WHERE filename = ? AND datasource = ?')
#	                or die "Couldn't prepare statement: " . $dbh->errstr;
#	$sth->execute($file,$datasource)             # Execute the query
#	            or die "Couldn't execute statement: " . $sth->errstr;
#	return if($sth->rows>0);		# there is already data there; return
#	if($datasource)
#	{
#		$sth=$dbh->prepare('INSERT INTO ips (ip,filename,datasource) VALUES ( ? , ? , ?)')
#				or die "Couldn't prepare statement2: " . $dbh->errstr;
#	}
#	else
#	{
#		$sth=$dbh->prepare('INSERT INTO ips (ip,filename) VALUES ( ? , ? )')
#				or die "Couldn't prepare statement3: " . $dbh->errstr;
#	}
#
#	foreach $ip (keys %{$iplist})
#	{
#		$ip=&frobIP($ip);
#		if($datasource)
#		{
#			$sth->execute($ip,$file,$datasource);
#		}
#		else
#		{
#			$sth->execute($ip,$file);
#		}
#	}
#	$sth->finish;
#
#	$dbh->disconnect;
#}

sub frobIP      # convert "w.x.y.z" -> "ipw_x_y_z"
{
	my ($str)=@_;
	return $str if($str =~ /ip\d+_\d+_\d+_\d+/);
	$str=~s/\./_/g;
	return "ip$str";
}

sub pullUsefulAliases
{
	return if( scalar(keys(%allips))==0);
	my ($hostname,$tablename);
	$hostname=`hostname`;
	chomp $hostname;
	$hostname=~s/\./_/g;
	$tablename="data2dlv_tmp_table_$$"."_$hostname";
	# create DB handle
	#$dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;",
	#		"$username",
	#		"$password",
	#		{
	#			AutoCommit => 0
	#		}) or
	#		die "Couldn't connect to database: " . DBI->errstr;
	# $dbh->do("START");
	# create tmp table

	#$dbh->do("DROP TABLE IF EXISTS $tablename");	# now with rollback, cant exist
	#$dbh->do("CREATE TEMP TABLE $tablename ( ip varchar(20) )");
	# remove any old entries it might have had (shouldn't exist)
# 	$dbh->do("DELETE FROM $tablename");
	# dump allips into table
	#$thing="INSERT INTO $tablename (ip) VALUES " . join(',',  map { "('".&frobIP($_)."')" } keys %allips);
	#print STDERR "About to exec '$thing'\n";
    	#$dbh->do($thing);

	# $sth=$dbh->prepare("INSERT INTO $tablename (ip) VALUES ( ? )")
			#or die "Couldn't prepare statement: " . $dbh->errstr;
	# foreach $ip (keys %allips)
	# {
		# $sth->execute(&frobIP($ip))
			# or die "Couldn't execute statement: " . $sth->errstr;
	# }
	# $sth->finish;

	# make list of all ips
	$iplist = "(". join(",",(map {"'".&frobIP($_)."'"} keys %allips)).")";

	# suck up all of the relevant IPs; use prepare/execute just for continuity
	#$sth = $dbh->prepare("SELECT ip1,ip2,source FROM aliases " .
	#		"WHERE ip1 in $iplist AND ip2 in $iplist ")
	#                or die "Couldn't prepare statement: " . $dbh->errstr;
	#$sth->execute()             # Execute the query
	#            or die "Couldn't execute statement: " . $sth->errstr;
	@results = &psqlCommand("SELECT ip1,ip2,source FROM aliases " .
	                       "WHERE ip1 in $iplist AND ip2 in $iplist ");
	print "% Start-of-aliases-from-DB\n";
	#foreach (@ally = $sth->fetchrow_array()) 
	foreach $ally (@results)
	{
		print "potentialAlias($ally->[0],$ally->[1],$ally->[2]).\n";
	}
	#$sth->finish;
	print "% Non-aliases from DB\n";
	# suck up all of the relevant IPs; use prepare/execute just for continuity
	#$sth = $dbh->prepare("SELECT ip1,ip2,source FROM notaliases " .
	#		"WHERE ip1 in $iplist AND ip2 in $iplist ")
	#                or die "Couldn't prepare statement: " . $dbh->errstr;
	#$sth->execute()             # Execute the query
	#            or die "Couldn't execute statement: " . $sth->errstr;
	@notresults = &psqlCommand("SELECT ip1,ip2,source FROM notaliases " .
	                       "WHERE ip1 in $iplist AND ip2 in $iplist ");
	#while (@ally = $sth->fetchrow_array()) 
	foreach $ally (@notresults)
	{
		print "potentialNotAlias($ally->[0],$ally->[1],$ally->[2]).\n";
	}
	#$sth->finish;
	print "% End-of-aliases-from-DB\n";
	
	# don't remove old table -- just rollback
	#$dbh->do("DROP TABLE $tablename");
	#$dbh->rollback;	# according to http://www.perl.com/pub/a/1999/10/DBI.html, this should prevent writing to disk
	# disconnect
	#$dbh->disconnect;

	#print '#import(Sidecar,"',$username,'","',$password,'","' ,
	#	'SELECT DISTINCT ip1,ip2 FROM aliases,ips AS a, ips AS b ' ,
	#	' WHERE ' , 
	#	' a.filename=\'',$file,'\' ',
	#	' AND b.filename=\'',$file,'\' ',
	#	' AND a.datasource=b.datasource ' ,
	# 	' AND ip1=a.ip AND ip2=b.ip"' ,
	#	', alias, type: CONST, CONST).',"\n";
}

#################################
# &probeSelfLoops($probe2)
#	return 1 if the same IP shows up twice in the probe's RR 
# 	test added from 061-bighole-selfloop.test
sub probeSelfLoops
{
	my ($probe)=@_;
	my @p=split /,/,$probe;
	my ($i,$j);
	for($i=3;$i<@p;$i++)
	{
		for($j=$i+1;$j<@p;$j++)
		{
			if ($p[$i] eq $p[$j])
			{
				print "% skipping '$probe' - self loop\n";
				return 1;
			}
		}
	}
	return 0; 	# if got this far, no self loop
}
