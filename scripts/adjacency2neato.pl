#!/usr/bin/perl -w

# ./internet2dot < internet > internet.dot

use Socket;
$skipUnknown=0;

$down=0;
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
print "     overlap=scale\n";
print "		node [";
# height and width do something?  seems to have little effect. -ns
print "shape=record,style=filled,height=.1,width=.1];\n";

$|=1;	# turn off buffering

&readIpCache();
if(@ARGV>=1 && $ARGV[0] eq "-skipUnknown")
{
        $skipUnknown=1;
        shift @ARGV;
}


my(%from_count, %to_count);

while(<>)
{
	next if(/^\s+$/);
	if(/^(Router|Endhost|NAT|HIDDEN|Source)/)
	{
      # store the routerline for later, so that we can sort the interfaces.
      push @routerline, $_;
      next;
    }

	if(/^Link/)
	{
		next if($skipUnknown && /UNKNOWN/);
		# Link  Router10:205.171.8.222 -- Router11:205.171.251.14 : 2
		@line=split;
		($r1,$l1)=split /:/,$line[1];
		($r2,$l2)=split /:/,$line[3];
        $from_count{$l1}+=1;
        $from_count{$l2}+=0;
        $to_count{$l1}+=0;
        $to_count{$l2}+=1;
		print "\"$r1\":\"$l1\" $line[2] \"$r2\":\"$l2\" [$linkattribs{$line[5]},dir=forward]\n";
#		if($down)
#		{
#			print "\"$r1\":\"$l1\":e $line[2] \"$r2\":\"$l2\":w [$linkattribs{$line[5]}]\n";
#		} 
#		else 
#		{
#			print "\"$r1\":\"$l1\":s $line[2] \"$r2\":\"$l2\":n [$linkattribs{$line[5]}]\n";
#		}
		next;
	}
	chomp;
	die "Unknown line '$_'\n";
}


foreach ( @routerline ) {
  if(/^(Router|Endhost|NAT|HIDDEN|Source)/) {
    $type=$1;
    #Router Router6: 206.196.177.49 205.171.203.88
    @line=split;
    print "\"$line[1]\" [fillcolor=$nodecolors{$type},label = \"";
    print "{" unless($down);
    print "$line[1]  ";
    @ips = @line[3..@line-1];
    foreach $ip ( @ips ) {
      $to_count{$ip}+=0;
      $from_count{$ip}+=0;
    }
    foreach $ip ( sort { ($from_count{$a} - $to_count{$a}) <=> ($from_count{$b} - $to_count{$b}) } @ips ) {
    # for($i=3;$i<@line;$i++)
    # {
      # $host = ip2hostname($line[$i]);
      $host = ip2hostname($ip);
      # print " | <$line[$i]> $host\\n$line[$i]";
      print " | <$ip> $host\\n$ip";
    }
    print "}" unless($down);
    print "\"]\n";
  }
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
