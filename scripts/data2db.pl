#!/usr/bin/perl -w
# Copies data files generated from passenger into the sql datadbase

#use lib "/fs/sidecar/scripts";
use Sys::Hostname;
use POSIX qw(strftime);		# for time conversion

eval 'use DBI;';
if($@)
{
	die "%Problem loading DBI library (probably not installed) -- aborting: $!";
}
$dbname="capveg";
$hostname=`hostname`;
$domainname=`domainname`;
if(( $hostname=~ /\.cs\.umd\.edu/)||($domainname=~ /^cs\.umd\.edu/))
{
	$host="drive.cs.umd.edu";
}
else
{
	$host="drive127.cs.umd.edu";
}
#$host='scriptroute.cs.umd.edu';
$username="capveg";
$password="dataentrysux";
$dataset = shift || die "usage: data2db.pl <dataset> date-128.8.128.118,32134-128.8.126.104,80-124 [..]";

if(@ARGV>0 && $ARGV[0] eq "-")
{
	shift @ARGV;
	push @ARGV,<>;
	chomp @ARGV;
}


warn "No files specified\n" if(@ARGV == 0 );

$outfile="postgres-out.$$";
open OUT, ">$outfile" or die "couldn't open $outfile:$!";


#$dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;",
#		"$username",
#		"$password") or die "Couldn't connect to database: " . DBI->errstr;
#$dbh->begin_work;
#
#$rr_insert = $dbh->prepare('INSERT INTO traces (src,dst,resp,ttl,rttl,rtt,t,resptype,datasource,nrr,rr) VALUES ( ? ,? , ? , ?, ?, ? ,?,?,\''.$dataset.'\',?,?)')
#                                or die "Couldn't prepare rr_insert statement: " . $dbh->errstr;
#$tr_insert = $dbh->prepare('INSERT INTO traces (src,dst,resp,ttl,rttl,rtt,t,resptype,datasource) VALUES ( ? ,? , ? , ?, ?, ? ,?,?,\''.$dataset.'\')')
#                                or die "Couldn't prepare tr_insert statement: " . $dbh->errstr;
#$ip_insert = $dbh->prepare("INSERT INTO ips (dataset,ip,src,dst,ts) VALUES ( ?,?,?,?,? ) ")
#                                or die "Couldn't prepare ip_insert statement: " . $dbh->errstr;
# create table ips ( dataset text, ip inet ,src inet, dst inet, ts timestamp with time zone);
foreach $file (@ARGV)
{
	if($file !~ /data-([\d\.]+)[:,]\d+-([\d\.]+)[:,]\d+/)
	{
		print STDERR "File '$file' doesn't match data-sip:sport-dip:dport-id format: skipping\n";
		next;
	}
	$sip = $1;
	$dip = $2;
	$allips{$sip}=1;
	$allips{$dip}=1;
	open F, "$file" or die "File $file open: $!";
	while(<F>)
	{
		next unless(/RECV/);
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
	# snag the creation time off of the file
	$ctime=(stat($file))[10];
	$t = POSIX::strftime("%c", localtime($ctime)); # magic from http://lavasystems.se/download/asctime
	# now insert all of the ips
	#map { $ip_insert->execute($dataset,$_,$sip,$dip,$t)} keys %allips;
	%allips=();
}

#$rr_insert->finish;
#$tr_insert->finish;
#$ip_insert->finish;

close OUT;
$pwd =`pwd`;
chomp $pwd;

#$dbh->do("COPY traces FROM '$pwd/$outfile' CSV");
if(! exists $ENV{'HOME'})
{
	$ENV{'HOME'}=$pwd;
}

`cp /fs/sidecar/scripts/pgpass $ENV{'HOME'}/.pgpass`;	# copy password file to localdir
chmod(0600,"$ENV{'HOME'}/.pgpass");				# fix file perms
$password=$password;
$ENV{'PGPASSFILE'}="$ENV{'HOME'}/.pgpass";	# set the env to look at file
$cmd = "psql -d $dbname -h $host -U $username -c 'copy traces from stdin csv' < $outfile";
$val = system($cmd);
print "System $cmd: return $val\n";
#$dbh->commit;
unlink($outfile);


#$dbh->disconnect;

###########################################################################################
# Subroutines
###########################################################################################


sub parseRRProbe
{
#- RECV TTL 6 it=0 from  206.196.177.125 (250)   ROUTER   rtt=0.002477 s t=1147905384.045258 RR, hop 1 128.8.6.139 , hop 2 128.8.0.14 , hop 3 128.8.0.85 , hop 4 129.2.0.233 , hop 5 206.196.177.126 , hop 6 206.196.177.1 ,  Macro

	my ($sip,$dip,$str,@line);
	my ($rr,$tr,$ttl, $probeline);
	($sip,$dip,$str) = @_;
	@line = split /\s+/,$str;

	$tr = $line[6];
	$allips{$tr}=1;
	$ttl= $line[3];
	if(!defined($line[7]))
	{
		print STDERR "rttl not defined: $file : line $_";
		return;
	}
	$rttl=$line[7];
	$rttl=~ tr/\(\)//d;
	$rttl= -1 if($rttl =~ /\?\?/);
	if(!defined($line[9]))
	{
		print STDERR "rtt not defined: $file : line $_";
		return;
	}
	$rtt = $line[9];
	$rtt =~ s/rtt=//;
	$rtt = sprintf("%.10f",$rtt);	# to stop bogus scientific notation crap
	if(!defined($line[11]))
	{
		print STDERR "time not defined: $file : line $_";
		return;
	}
	$t = $line[11]; 
	if($t =~ /\?\?/)
	{
		$t = POSIX::strftime("%c", localtime); # magic from http://lavasystems.se/download/asctime
	}
	else
	{
		$t =~ s/t=//;
		$t = POSIX::strftime("%c", localtime($t)); # magic from http://lavasystems.se/download/asctime
	}
	$resptype='-';


	# append RR addresses
	@rr=grep /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, @line[12..$#line];
	if(@rr>0)
	{
		map {$allips{$_}=1} @rr;
		$rrstr="\"{" . join("," ,@rr). "}\"";
	}
	else
	{
		$rrstr="{}";
	}
	#print STDERR "$rrstr\n";
	#$rr_insert->execute($sip,$dip,$tr,$ttl,$rttl, "$rtt seconds",$t,$resptype,scalar(@rr),$rrstr);
	print OUT "$sip,$dip,$tr,$ttl,$rttl,$rtt seconds,$t,$resptype,$dataset,",scalar(@rr),",$rrstr\n";
}

sub parseTRProbe
{
	my ($sip,$dip,$str,@line);
	my ($rr,$tr,$ttl, $probeline);
	($sip,$dip,$str) = @_;
	@line = split /\s+/,$str;

	if(!defined($line[6]))
	{
		print STDERR "icmpresp not defined: $file : line $_";
		return;
	}
	$tr = $line[6];
	$allips{$tr}=1;
	$ttl= $line[3];
	if(!defined($line[7]))
	{
		print STDERR "rttl not defined: $file : line $_";
		return;
	}
	$rttl=$line[7];
	$rttl=~ tr/\(\)//d;
	$rttl= -1 if($rttl =~ /\?\?/);
	if(!defined($line[9]))
	{
		print STDERR "rtt not defined: $file : line $_";
		return;
	}
	$rtt = $line[9];
	$rtt =~ s/rtt=//;
	$rtt = sprintf("%.10f",$rtt);	# to stop bogus scientific notation crap
	if(!defined($line[11]))
	{
		print STDERR "time not defined: $file : line $_";
		return;
	}
	$t = $line[11]; 
	$t =~ s/t=//;
	if($t =~ /\?\?/)
	{
		$t = POSIX::strftime("%c", localtime); # magic from http://lavasystems.se/download/asctime
	}
	elsif($t =~ /^[\d\.]+$/)
	{
		$t = POSIX::strftime("%c", localtime($t)); # magic from http://lavasystems.se/download/asctime
	}
	else {
		print STDERR "time badly formatted '$t': $file : line $_";
		return;
	}
	$resptype='-';
	#$tr_insert->execute($sip,$dip,$tr,$ttl,$rttl, "$rtt seconds",$t,$resptype);
	print OUT "$sip,$dip,$tr,$ttl,$rttl,$rtt seconds,$t,$resptype,$dataset,-1,\n";
}


