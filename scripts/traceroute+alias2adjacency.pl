#!/usr/bin/perl

# traceroute+alias2adjacency.pl
# Make a Rob-formatted adj file from iPlane traceroute and iPlane alias files
# University of Maryland Department of Computer Science
# Origional Author: Aaron Schulman
# Contributors:

use Socket;
use Net::IP;
use bytes;

if ($#ARGV != 1) {
	die "traceroute+alias2adjacency.pl <router_alias_list> <iPlane_traceroute>\n";
}

$aliasfilename = $ARGV[0];
$traceroutefilename = $ARGV[1];

open(ALIASFILE, $aliasfilename) || die "Could not open $aliasfilename\n";
$alias_routers = 0;

# Read in the alias file
while ($line = <ALIASFILE>) {
	chomp($line);
	$router_name = "R".$alias_routers++;
	$router_ips = [split(/\s/, $line)];
	foreach $router (@$router_ips) {
		$routeriptoname{$router} = $router_name;
	}
	$routernametoiplist{$router_name} = $router_ips;
}

# Read in the traceroute file
open (TRACEROUTEFILE, $traceroutefilename) || die "Could not open \"$traceroutefilename\"\n";
$m = $alias_routers;
$j = 0;
$l = 0;
while (!eof(TRACEROUTEFILE)) {
	read (TRACEROUTEFILE, $buffer, 16);
	($clientid, $uniqueid, $records, $tracebytes) = unpack("L L L L", $buffer);
	for ($i = 0; $i < $records; $i++) {
		read (TRACEROUTEFILE, $buffer, 20);
		($destip, $hops, $sourceip, $RTT, $TTL) = unpack("N L N f L", $buffer);
		if ($ttl > 512 || $hops > 512) {
			print STDERR "File $traceroutefilename is corrupted\n";
			exit(1);
		}
		$destip =  int_to_ip($destip);
		if (($endpoints{$destip} eq "")) {
			$endpoints{$destip} = "E".$l++;
		}
		$sourceip = int_to_ip($sourceip);
		if (($sources{$sourceip} eq "")) {
			$sources{$sourceip} = "S".$j++;
		}
		$previousip = $sourceip;
		if ($hops > 1) {
			for ($k = 0; $k < ($hops - 2) ; $k++) {
				read(TRACEROUTEFILE, $buffer, 12);
				($routerip, $RTT, $TTL) = unpack("N f L", $buffer);
				$routerip = int_to_ip($routerip);
				$router_name = $routeriptoname{$routerip};

				# Put the name into the name hash if it was not added as an alias
				if ($router_name eq "") {
					$router_name = "R".$m++;
					$router_lista = [$routerip];
					$routernametoiplist{$router_name} = $router_lista;
					$routeriptoname{$routerip} = $router_name;
				}
				$routers{$router_name} = 1;
				$links{$previousip." ".$routerip} = 1;
				$previousip = $routerip;
			}
			read (TRACEROUTEFILE, $buffer, 12);
			$links{$previousip." ".$destip} = 1;
		}
	}
}

foreach $source (keys (%sources)) {
	print "Source $sources{$source} nAlly=1 $source\n";
}

foreach $endpoint (keys (%endpoints)) {
	print "Endhost $endpoints{$endpoint} nAlly=1 $endpoint\n";
}

foreach $router_name (keys (%routers)) {
	$router_lista = $routernametoiplist{$router_name};
	@router_list = @$router_lista;
	print "Router $router_name nAlly=".($#router_list+1);
	foreach $router_alias (@router_list) {
		print " $router_alias";
	}
	print "\n";
}

foreach $link (keys (%links)) {
	@ips = split(/\s/, $link);
	print "Link ".ip_to_name($ips[0]).":".$ips[0]." -- ".ip_to_name($ips[1]).":".$ips[1]." : TR\n";
}

sub ip_to_name($) {
	$ip = $_[0];
	if (!($routeriptoname{$ip} eq "")) {
		return $routeriptoname{$ip};
	}
	if (!($endpoints{$ip} eq "")) {
		return $endpoints{$ip};
	}
	if (!($sources{$ip} eq "")) {
		return $sources{$ip};
	}
	return "";
}

# takes IP in big endian order only need this because Perl's IP functions suck
sub int_to_ip($) {
	$int = $_[0];
	$d = $int & 0xff;
	$c = ($int >> 8) & 0xff;
	$b = ($int >> 16) & 0xff;
	$a = ($int >> 24) & 0xff;
	return $a.".".$b.".".$c.".".$d;
}
