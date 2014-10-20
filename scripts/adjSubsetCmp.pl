#!/usr/bin/perl -w

$file1 = shift @ARGV or die "give me two files!!!\n";
$file2 = shift @ARGV or die "give me two files!!!\n";

# this hashes an ip address to a string which is a space-separated list
# of aliases on the same router.  
%aliases = ();  
# this hashes an ip address to it's routers' type.
%ipType = ();
# this is a space seperated list of ip addresses the
# hashed ip is linked to.
%links = ();

$routerCnt = 0;
$linkCnt = 0;
$ipCnt = 0;

# parse first file.

open F,"<$file1" or die "$file1 doesn't work. Please fix.\n";
while(<F>)
{
    chomp;
    if (/Link/) {
        @line = split;
        shift @line; # Link
        $ip1 = shift @line;
        $ip1 =~ s/^[^:]*://;
        shift @line; # --
        $ip2 = shift @line;
        $ip2 =~ s/^[^:]*://g;
        $links{$ip1} .= " " if defined $links{$ip1};
        $links{$ip1} .= $ip2;
        $links{$ip2} .= " " if defined $links{$ip2};
        $links{$ip2} .= $ip1;
        $linkCnt++;
    } elsif (/Router/) {
        @line = split;
        shift @line;
        $router = shift @line;
        $type = "U";
        $type = $1 if $router =~ /R\d+_(\S+)/;
        shift @line; #nAlly=?
        $ipList = join " ",@line;
        foreach $ip (@line) {
            $ipType{$ip} = $type;
            $aliases{$ip} = $ipList;
            $ipCnt++;
        }
        $routerCnt++;
    }
}
close F;

# stats...
print "Stats on $file1: $routerCnt routers, $linkCnt links, $ipCnt ips\n";

# now check the same information for the second file.
open F2, "<$file2" or die "$file2 doesn't work...\n";
$missingLinks = 0;
$totalLinks = 0;
$missingAlias = 0;
$totalAliases = 0;
$misslabeledTypes = 0;
$totalIPs = 0;
$missingIPs = 0;
while (<F2>) 
{
    chomp;
    if (/Link/) {
        @line = split;
        shift @line; # Link
        $ip1 = shift @line;
        $ip1 =~ s/^[^:]*://;
        shift @line; # --
        $ip2 = shift @line;
        $ip2 =~ s/^[^:]*://g;
        next if (not defined $ipType{$ip1}) or (not defined $ipType{$ip2});
        $missingLinks++ if not ((defined $links{$ip1} and $links{$ip1} =~ /$ip2/) or 
                                (defined $links{$ip2} and $links{$ip2} =~ /$ip1/));
        $totalLinks++;
    } elsif (/Router/) {
        @line = split;
        shift @line;
        $router = shift @line;
        $type = "U";
        $type = $1 if $router =~ /R\d+_(\S+)/;
        shift @line; #nAlly=?
        $ipList = join " ",@line;
        for($i=0; $i<@line; ++$i) {
            if (defined $ipType{$line[$i]}) {
                $misslabeledTypes++ if $ipType{$line[$i]} ne $type;
                $totalIPs++;
            } else {
                $missingIPs++;
            }
            for($j=$i+1; $j<@line; ++$j) {
                my $tmp = $line[$j];
                next if not defined $aliases{$line[$i]};
                $missingAlias++ if $aliases{$line[$i]} !~ /$tmp/;
                $totalAliases++;
            }
        }
    }
}
close F2;

print "Looking at what it would take to make $file1 a superset of $file2:\n";
$t = 0;
$t = $missingAlias / $totalAliases if $totalAliases > 0;
print "Missing aliases:\t$missingAlias of $totalAliases ($t)\n";
$t = 0;
$t = $missingLinks / $totalLinks if $totalLinks > 0;
print "Missing links  :\t$missingLinks of $totalLinks ($t)\n";
$t = 0;
$t = $misslabeledTypes / $totalIPs if $totalIPs > 0;
print "Miss-typed IPs :\t$misslabeledTypes of $totalIPs ($t)\n";
print "Missing IPs    :\t$missingIPs\n";

