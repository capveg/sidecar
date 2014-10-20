#!/usr/bin/perl -w

# Copyright (c) 2003 Intel Corporation
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:

#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.

#     * Redistributions in binary form must reproduce the above
#       copyright notice, this list of conditions and the following
#       disclaimer in the documentation and/or other materials provided
#       with the distribution.

#     * Neither the name of the Intel Corporation nor the names of its
#       contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE INTEL OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# EXPORT LAWS: THIS LICENSE ADDS NO RESTRICTIONS TO THE EXPORT LAWS OF
# YOUR JURISDICTION. It is licensee's responsibility to comply with any
# export regulations applicable in licensee's jurisdiction. Under
# CURRENT (May 2000) U.S. export regulations this software is eligible
# for export from the U.S. and can be downloaded by or otherwise
# exported or reexported worldwide EXCEPT to U.S. embargoed destinations
# which include Cuba, Iraq, Libya, North Korea, Iran, Syria, Sudan,
# Afghanistan and any other country to which the U.S. has embargoed
# goods and services.

# $gProxy = 'proxy.yourdomain.com:911';
$gProxy = '';
# $gWeb   = 'https://www.planet-lab.org/db/nodes/known_hosts.php';
$gWeb   = 'https://www.planet-lab.org/planetlab/nodes/known_hosts.php';
$gCurl  = '/usr/bin/curl';
$gKnown = $ENV{'HOME'} . '/.ssh/known_hosts';

#
# Setup the environment
#
if ( $gProxy ne '' ) {
    $ENV{'HTTPS_PROXY'} = $gProxy;
    $ENV{'HTTP_PROXY'}  = $gProxy;
}

#
# Load up the current keys into a hash
#
my %plnodes;
my $curl_dash_k = '';
my $retry = 1;
do {
  open( WEB, "$gCurl $curl_dash_k --silent $gWeb |" ) || die 'Failed to open web page';
  while ( <WEB> ) {
    chomp;
    next if /^$/;
    my ( $key, $value ) = split( ' ', $_, 2 );
    if ( $key =~ /^Could/ ) {
      print STDERR "planetlab reported: $_\n";
      exit;
    }
    while ( $value=~ /^None(\S+) (.*)$/ ) {
      print STDERR "Warning: key for $key starts with None.\n";
      ( $key, $value ) = ( $1, $2 )
    }
    $plnodes{ $key } = $value;
  }
  close WEB;
  if ( scalar(keys %plnodes) > 0 ) {
    $retry = 0; # we got it
  } else {
    if( $curl_dash_k eq "-k" ) {
      print STDERR "ERROR: empty plnodes, adding -k option didn't help.\n";
      exit 1;
    }
    $curl_dash_k = "-k";
    print STDERR "Warning: empty plnodes, adding -k option to bypass certificate check.\n";
  }
} while ( $retry ) ;

foreach my $key ( keys %plnodes ) {
  # a somewhat messy 172.16/12 match, 10/8 and 192.168/16 are easy.
  if ($key =~ /^192\.168\./ || $key =~ /^10\./ || $key =~ /^172\.[123][0-9]\./ ) {
    print STDERR "Warning: removing RFC 1918 $key $plnodes{ $key }\n";
    delete $plnodes{ $key };
  }
}

#
# Update the known keys file
#
if ( -r $gKnown ) {
    rename $gKnown, "$gKnown.bak";
}

open( NEW, ">$gKnown" ) || die "Cannot open $gKnown for writing";
if ( -r "$gKnown.bak" ) {
    open( OLD, "$gKnown.bak" );
    while( <OLD> ) {
        chomp;
        my ( $key, $value ) = split( ' ', $_, 2 );
        if ( defined $plnodes{ $key } ) {
            print NEW "$key $plnodes{ $key }\n";
            delete $plnodes{ $key };
        } else {
            print NEW "$_\n";
        }
    }
    close OLD;
}
foreach my $key ( keys %plnodes ) {
    print NEW "$key $plnodes{ $key }\n";
}
close NEW;

