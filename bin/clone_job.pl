#!/usr/bin/env perl

$|++;

#
# Clone a job and rerun islandpick with
# given genomes
#

use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Data::Dumper;

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

use IO::Select;
use IO::Socket;
use Net::hostent;      # for OOish version of gethostbyaddr
use Fcntl;
use Tie::RefHash;
use Fcntl qw/O_NONBLOCK/;
#use Fcntl qw/F_GETFL, F_SETFL, O_NONBLOCK/;
use MIME::Base64;
use URI::Escape;
use JSON;

use lib "../lib";
use Islandviewer;

# Set connection information here
my $cfg;
my $host = 'localhost';
my $port = 8211;
my $handle;
my $alarm_timeout = 60;
my $protocol_version = '1.0';

MAIN: {
    my $cfname; my $aid; my $genomelist;
    my $res = GetOptions("config=s"   => \$cfname,
			 "aid=s" => \$aid,
			 "genomelist=s" => \$genomelist,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    $cfg = Islandviewer::Config->config;

    $host = $cfg->{daemon_host}
        if($cfg->{daemon_host});
    $port ||= $cfg->{tcp_port}
        if($cfg->{tcp_port});

    myconnect($host, $port);

    my $message = build_req($aid, $genomelist);

    my $recieved = send_req($message);

    print "$recieved\n";

}

sub myconnect {
    my $host = shift;
    my $port = shift || 8211;

    $handle = IO::Socket::INET->new(Proto     => "tcp",
				    PeerAddr  => $host,
				    PeerPort  => $port)
       or die "can't connect to port $port on $host: $!";

}

sub send_req {
    my $msg = shift;
    my $received = '';

    print "Sending: $msg\n";

    # Check if the message ends with a LF, if not
    # add one
    $msg .= "\n" unless($msg =~ /\n$/);
    my $length = length $msg;

    # Make sure the socket is still open and working
    if(! defined $handle->connected) {
#    if($handle->connected ~~ undef) {
	return;
    }

    # Set up an alarm, we don't want to get stuck
    # since we are allowing blocking in the send
    # (the server might not be ready to receive, it's
    # not multi-threaded, just multiplexed)
    eval {
	local $SIG{ALRM} = sub { die "timeout\n" };
	alarm $alarm_timeout;
	
	# While we still have data to send
	while($length > 0) {
	    my $rv = $handle->send($msg, 0);

	    # Oops, did we fail to send to the socket?
	    unless(defined $rv) {
		# Turn the alarm off!
		alarm 0;
		return undef;
	    }

	    # We've sent some or all of the buffer, record that
	    $length -= $rv;

	}

	# The message is sent, now we wait for a reply, or until
	# our alarm goes off
	while($received !~ /\n$/) {
	    my $data;
	    # Receive the response and put it in the queue
	    my $rv = $handle->recv($data, POSIX::BUFSIZ, 0);
	    unless(defined($rv)) {
		alarm 0;
		return undef;
	    }
	    $received .= $data;

	    if($received) {
		my $status = $handle->send(' ', 0);
		unless(defined($status)) {
		    last;
		}
	    }
	}

	# We've successfully made our request, clear the alarm
	alarm 0;
    };
    # Did we get any errors back?
    if($@) {
	# Uh-oh, we had an alarm, the iteration timed out
	if($@ eq "timeout\n") {
	    return undef;
	} else {
	    return undef;
	}
    }

    # Success! Return the results
    return $received;
}

sub build_req {
    my $aid = shift;
    my $genomelist = shift;

    my $genomelist_str = join(' ', split(',', $genomelist));
    my $modules = { islandpick => { args => { comparison_genomes => $genomelist_str } } };

    my $req = { version => $protocol_version,
		action => 'clone',
		aid => $aid,
		args => { modules => $modules }
    };

    my $req_str = to_json($req, { pretty => 1});

    $req_str .= "\nEOF";

    my $str = "{\n \"version\": \"$protocol_version\",\n";
    $str .= " \"action\": \"clone\",\n";
#    $str .= " \"max_cutoff\": \"0.48\",\n";
#    $str .= " \"max_compare_cutoff\": \"10\",\n";
    $str .= " \"aid\": \"$aid\"\n";
    $str .= " }\nEOF";

    return $req_str;
}
