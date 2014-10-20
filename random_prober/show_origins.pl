#!/usr/bin/perl -w

# a crontab-able script for converting a next-hop ip address
# to a next-hop asn, using a specified (but should be the most 
# recent) bgp dump.

use strict 'refs';
use strict 'subs';
use strict;

#copied over from connectivity.pl via utils.pl
sub canonicalize {
  my $network = shift(@_);
  my ($prefix,$bits) = split(/\//,$network);

  my ($octet1,$octet2,$octet3,$octet4) = split(/\./,$prefix);
  if (defined($bits)) {
    # my $andAgent = (255 << 24) | (255 << 16) | (255 << 8) | 255;
    # $andAgent = ($andAgent >> (32 - $bits)) << (32 - $bits);
    my $andAgent = (4294967295 >> (32 - $bits)) << (32 - $bits);
    my $net = ($octet1 << 24) | ($octet2 << 16) | ($octet3 << 8) | $octet4;
    $net = $net & $andAgent;

    my $newOctet1 = ($net >> 24);
    my $newOctet2 = ($net << 8) >> 24;
    my $newOctet3 = ($net << 16) >> 24;
    my $newOctet4 = ($net << 24) >> 24;

    my $newNet = "$newOctet1.$newOctet2.$newOctet3.$newOctet4/$bits";

    #if ($newNet ne $network) {
      # this is what I use it for -ns print STDERR "Ooops $network =/= $newNet\n";
    #}
    return $newNet;
  }

  if (!$octet4 and !$octet3 and !$octet2) {
    $bits = 8;
  } 
  elsif (!$octet4 and !$octet3) {
    $bits=16;
  }
  elsif (!$octet4) {
    $bits=24;
  }
  else {
    print STDERR "Canocalize: Something weird is up '$network'\n";
  }
  return "$prefix/$bits"
}

my $force = 0; # redo them all. fsck.

#my $bgpfile = `ls -t /var/autofs/hosts/rocketfuel/ratul/routeviews/oix-full-snapshot* | head -1`;
my $bgpfile;
if($#ARGV < 0) {
  print STDERR "using default file";
  $bgpfile = `ls -t /var/autofs/hosts/rocketfuel/ratul/routeviews/oix-full-snapshot* | head -1`;
  chomp($bgpfile);
} else {
  $bgpfile = $ARGV[0];
}
(-e $bgpfile) || die "dump $bgpfile does not exist\n";
if($bgpfile =~ /.gz$/) {
  open(DUMP,"gunzip -c $bgpfile |") or die "Cannot open dump $bgpfile: $!\n";
} elsif($bgpfile =~ /.bz2$/) {
  open(DUMP,"bunzip2 -c $bgpfile |") or die "Cannot open dump $bgpfile: $!\n";
} else {
  open(DUMP,$bgpfile) or die "Cannot open dump $bgpfile: $!\n";
}

my ($started,$nett) = (0,0);
my ($networkPos, $pathPos);
my (%originHash);
while (<DUMP>) {
  if (!$started) {
    if(m/(\s)*Network(\s)*Next Hop(\s)*/) { 
      $networkPos = index($_, "Network");
      $pathPos = index($_,"Path");
      $started = 1;
    }
    next;
  }

  my $network;
  my $substring = substr($_,$networkPos);
  if($substring =~ m/^(\d+\.\d+\.\d+\.\d+(\/\d+)?)/) {
    $network = $1;
    $nett = canonicalize($1);
  } elsif($substring !~ /^\s/) {
    print STDERR "Probably Invalid Network :$substring: .. skipping\n";
    next;
  } else {
    $network = "";
  }

  #some networks may occupy more bytes than the 16 char positions 
  #allocated in the formatted position 
  my $shift = length($network) - 16;
  if    ($shift < 0) { $shift=0;}
  elsif ($shift > 2) {
    print STDERR "Probably Invalid Network :$network: .. skipping\n";
    next;
  }

  next unless (length($_) > $pathPos+$shift);
  my $pathstring = substr($_,$pathPos+$shift);
  # die "failed to skip undefined" unless defined($pathstring);  # should never happen: length checked above 
  my @path = split(/\s+/,$pathstring); 
  if (@path == 1) {
    next;
  }
  my $aspathLength =  $#path - 1;
  my $originAS = $path[$aspathLength];
  print "$nett $originAS\n"
  #$originHash{$nett}->{$originAS} = 1;
}
close(DUMP);

