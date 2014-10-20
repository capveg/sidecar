#!/usr/bin/perl
#
# Aaron Schulman
# University of Maryland College Park
# ===================================
#
# 1. connect to each server in smtplist.txt
# 2. send several no-op commands
# 3. close connection and go to next server

use IO::Socket;
use Time::HiRes qw(usleep);
use Time::Local;
use Event;

#Globals
$domain_message = 'TEST.contact.aschulmATgmail.com.with.questions';
$message_timeout = 2;
$succ_servers = 0;
$done_sockets = 0;
$num_sockets = 30;

# Main Function 
my $server;
my $smtplist, $connection_hold_time;
my $sock;
$SIG{PIPE} = 'IGNORE';

if ($#ARGV != 3) {
	print "smtpnoop.pl: Send NOOPs to a list of SMTP servers\n";
	print "Usage: smtpnoop.pl <smtplist> <#noops> <welcome_timeout> <connection_hold_time> \n";
	print 'Report bugs to Aaron Schulman <aschulm@umd.edu>'; print "\n";
	exit;
}
my $smtplist = $ARGV[0];
$num_noops = $ARGV[1];
$welcome_timeout= $ARGV[2];
$connection_hold_time = $ARGV[3];

open(SMTPLIST, $smtplist) || die "Could not open $smtplist!";
	
	for ($i = 0; $i < $num_sockets; $i++) {
		if ($line = <SMTPLIST>) {
			chomp $line;
			if ($line =~ /^(\S+)\s(\S+)$/s) {
				$name = $1;
				$ip = $2;
				my $sock = connect_to_server($name, $ip);
				if ($sock) {
					$w = Event->io (
						desc => $name,
						fd => $sock,
						cb => \&connected_callback,
						poll => 'r',
						timeout => $welcome_timeout,
						timeout_cb => \&timeout_callback);
				}
				else {
					$i--;
				}
			}
			else {
				$i--;
			}
		}
		else {
			last;
		}
	}
if (scalar(Event::all_watchers()) > 0) {
	my $result = Event::loop();
}
print "DONE: $succ_servers smtp servers successfully NOOPed\n";
close (SMTPLIST);

# connected_callback()
sub connected_callback($) {
	my $event = shift;
	my $watcher = $event->w;
	my $server = $watcher->desc;
	my $sock  = $watcher->fd;

	if ($resp = <$sock>) {
		if ($resp =~ /^220/) {
			print "$server: $resp";
			print "$server: Sending HELO message\n";
			print $sock "HELO $domain_message\n";
			$watcher->cb(\&helo_callback);
			$watcher->timeout($message_timeout);
		}
		else {
			close_connection($sock,$server);
			next_server($watcher);
		}
	}
	else {
		close_connection($sock,$server);
		next_server($watcher);
	}
}

sub helo_callback($) {
	my $event = shift;
	my $watcher = $event->w;
	my $server = $watcher->desc;
	my $sock = $watcher->fd;
	if ($resp = <$sock>) {
		if ($resp =~ /^250/) {
			print "$server: Sending $num_noops NOOPs\n";
			print $sock "NOOP\n";
			$watcher->data(0);
			$watcher->cb(\&noop_callback);
			$watcher->timeout($message_timeout);
		}
		else {
			close_connection($sock,$server);
			next_server($watcher);
		}
	}
	else {
		close_connection($sock,$server);
		next_server($watcher);
	}
}

sub noop_callback($) {
	my $event = shift;
	my $watcher = $event->w;
	my $server = $watcher->desc;
	my $sock = $watcher->fd;

	if ($resp = <$sock>) {
		if ($resp=~/^250/) {
			$watcher->data($watcher->data + 1);
			if ($watcher->data == $num_noops) {
				print "$server: $num_noops NOOPs successfully sent\n";
				$succ_servers++;
				$watcher->cancel;
				my $curr_time= time;	
				my $w = Event->timer (
					at => $curr_time + $connection_hold_time,
					cb => \&connection_held_callback,
					data => $sock,
					desc => $server);
			}
			else {
				print $sock "NOOP\n";
			}
		}
	}
	else {
		close_connection($sock,$server);
		next_server($watcher);
	}
}

sub timeout_callback($) {
	my $event = shift;
	my $watcher = $event->w;
	my $server = $watcher->desc;
	my $sock = $watcher->fd;

	# TODO Refine this so timeouts from sending NOOPS still continues attempts
	close_connection($sock,$server);
	next_server($watcher);
}

# connection_held_callback(EVENT)
sub connection_held_callback($) {
	my $event = shift;
	my $watcher = $event->w;
	my $server = $watcher->desc;
	my $sock = $watcher->data;

	close_connection($sock,$server);
	next_server($watcher);
}

# next_server(WATCHER)
sub next_server($) {
	my $watcher = shift;
	my $server = $watcher->desc;

	$watcher->cancel;
	if ($line= <SMTPLIST>) {
		chomp $line;
		$ip = "";
		$name = "";
		if ($line =~ /^(\S+)\s(\S+)$/s) {
			$name = $1;
			$ip = $2;
			my $sock = connect_to_server($name, $ip);
			if ($sock) {
				$w = Event->io (
					desc => $name,
					fd => $sock,
					cb => \&connected_callback,
					poll => 'r',
					timeout => $welcome_timeout,
					timeout_cb => \&timeout_callback);
			}
		}
		else {
			next_server($watcher);
		}
	}
	else {
		$done_sockets++;
		if ($done_sockets == $num_sockets) {
			Event::unloop(0);
		}
	}
}

# connect_to_server(SERVER_NAME, SERVER_IP)
sub connect_to_server($$) {
	my $name = shift;
	my $ip = shift;
	print "$name: Connecting\n";
	$sock = create_socket($name, $ip);
}

# create_socket(SERVER_NAME, SERVER_IP)
sub create_socket($$) {
	my $name = shift;
	my $ip = shift;
	my $sock = new IO::Socket::INET (
		PeerAddr => $ip,
		PeerPort => '25',
		Proto => 'tcp',
		Blocking => '0'
		);
	print "$name: Could not connect to server\n" unless $sock;
	return $sock;
}

# close_connection(SOCKET,SERVER_NAME)
sub close_connection($$) {
	my $sock = shift;
	my $server = shift;
	print "$server: Closing Connection\n";
	close($sock);
}
