#!/usr/bin/perl -w

# ./internet2dot < internet > internet.dot

use Socket;
$skipUnknown=0;

$down=1;
$IpCacheFile = "$ENV{'HOME'}/.ipcache";

%linkattribs = ( 
	"HIDDEN" =>"color=red", 
	"RR" => "color=blue",
	"STR" => "color=purple",
	"TR" => "color=black",
	"UNKNOWN" => "color=orange");

%nodecolors = (
	HIDDEN => "pink",
	Router => "white",
	Endhost => "cyan",
	NAT => "red",
	Source => "purple"
);


print "graph Internet {\n";
print "		rankdir=LR\n" if($down);
print "		node [";
print "shape=record,style=filled,height=.1,width=.1];\n";

$|=1;	# turn off buffering

&readIpCache();
if(@ARGV>=1 && $ARGV[0] eq "-skipUnknown")
{
	$skipUnknown=1;
	shift @ARGV;
}

while(<>)
{
	next if(/^\s+$/);
	if(/^(Router|Endhost|NAT|HIDDEN|Source)/)
	{
		$type=$1;
		#Router Router6: 206.196.177.49 205.171.203.88
		@line=split;
		print "\"$line[1]\" [fillcolor=$nodecolors{$type},label = \"";
		print "{" unless($down);
		print "$line[1]  ";
		for($i=3;$i<@line;$i++)
		{
			$host = ip2hostname($line[$i]);
			print " | <$line[$i]> $host ($line[$i]) ";
		}
		print "}" unless($down);
		print "\"]\n";
		next;
	}

	if(/^Link/)
	{
		next if($skipUnknown && /UNKNOWN/);
		# Link  Router10:205.171.8.222 -- Router11:205.171.251.14 : 2
		@line=split;
		($r1,$l1)=split /:/,$line[1];
		($r2,$l2)=split /:/,$line[3];
		if($down)
		{
			print "\"$r1\":\"$l1\":e $line[2] \"$r2\":\"$l2\":w [$linkattribs{$line[5]}]\n";
		} 
		else 
		{
			print "\"$r1\":\"$l1\":s $line[2] \"$r2\":\"$l2\":n [$linkattribs{$line[5]}]\n";

		}
		next;
	}
	chomp;
	die "Unknown line '$_'\n";
}

print "}\n";
&writeIpCache();
######################################################################################################

sub ip2hostname
{
	my ($host) = (undef);
	my ($ip) = @_;
	if($ip eq "unknown")
	{
		$host = "unknown";
	} 
	elsif(exists$ipcache{$ip})
	{
		$host = $ipcache{$ip};
	} 
	else
	{
		print STDERR "Resolving $ip... ";
		$host = gethostbyaddr(inet_aton($ip),AF_INET) || "??";
		print STDERR " '$host' done.\n";
		$ipcache{$ip}=$host unless($host eq "??");
	}
	return $host;
}

#######################################################################################################
sub readIpCache
{
	%ipcache = ();
	open CACHE, "$IpCacheFile" or return; 	#file not found
	while(<CACHE>)
	{
		@line=split;
		$ipcache{$line[0]}=$line[1];
	}
}
#######################################################################################################
sub writeIpCache
{
	open CACHE, ">$IpCacheFile.tmp" or die "open $IpCacheFile.tmp : $!";
	foreach $key (sort keys %ipcache)
	{
		print CACHE "$key $ipcache{$key}\n";
	}
	close CACHE;
	system("mv $IpCacheFile $IpCacheFile.old") if(-f $IpCacheFile);
	system("mv $IpCacheFile.tmp $IpCacheFile");
}
