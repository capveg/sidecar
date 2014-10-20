#!/usr/bin/perl -w
# take a .dump file and commit it to the given database

use DBI;

$dbname="capveg";
$host="drive";
$username="capveg";
$password="dataentrysux";


sub usage
{
	print STDERR join("\n", @_ )if(@_>0);
	print STDERR "$0 foo.aliases [tablename]\n";
	exit 0;
}

$aliases = shift @ARGV || usage("Need to specify an aliases file\n");

$dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;",
                                  "$username",
				  "$password") or 
		die "Couldn't connect to database: " . DBI->errstr;

$dbh->do("        CREATE TABLE aliases (" .
		" ip1 char(20), ".
		" ip2 char(20), ".
		" source  char(20), ".
		" source_time timestamp DEFAULT now(), ".
		" update_time timestamp DEFAULT now()); ");
$dbh->do("        CREATE TABLE notaliases (" .
		" ip1 char(20), ".
		" ip2 char(20), ".
		" source  char(20), ".
		" source_time timestamp DEFAULT now(), ".
		" update_time timestamp DEFAULT now()); ");


$alias_sth = $dbh->prepare('INSERT INTO aliases VALUES(?,?,?)')
	or die "Couldn't prepare statement: " . $dbh->errstr;
$notalias_sth = $dbh->prepare('INSERT INTO notaliases VALUES(?,?,?)')
	or die "Couldn't prepare statement: " . $dbh->errstr;

open ALLY, "$aliases" or die "open $aliases: $!";

$dbh->begin_work or die "Couldn't do begin_work: " . $dbh->errstr;

while(<ALLY>)
{
	chomp;
	@ally=split;
	$ip1=&frobIP($ally[0]);
	$ip2=&frobIP($ally[1]);
	# 128.8.0.82 134.75.85.53 :: NOT ALIAS. quick (2): 30403, 23665
	if(/NOT ALIAS.\s+(\S+)/)
	{
		$type=&str2type($1);
		# add to DB
		$notalias_sth->execute($ip1,$ip2,$type) or 
			die "Couldn't execute statement: " . $notalias_sth->errstr;


	}
	#202.112.53.166 202.127.216.74 :: ALIAS! ally/ipid: 64985, 64986, 65087, 65086
	elsif(/ALIAS!\s+(\S+)/)
	{
		$type=&str2type($1);
		# add to DB
		$alias_sth->execute($ip1,$ip2,$type) or 
			die "Couldn't execute statement: " . $alias_sth->errstr;

	}
	elsif(/UNKNOWN/)
	{
		next;
	}
	else
	{
		print STDERR "unparsed line: $_\n";
	}

}

$dbh->do("CREATE INDEX IDX_aliases on aliases (ip1)");
$dbh->do("CREATE INDEX IDX_notaliases on aliases (ip1)");

$dbh->commit or die "Couldn't do COMMIT: " . $dbh->errstr;
$dbh->disconnect;

sub frobIP	# convert "w.x.y.z" -> "ipw_x_y_z"
{
	my ($str)=@_;
	$str=~s/\./_/g;
	return "ip$str";
}

sub str2type
{
	my ($str)=@_;
	$str =~s/\W+//g;	# remove all non letter chars
	return $str
}
