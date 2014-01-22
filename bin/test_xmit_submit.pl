#!/usr/bin/env perl

$|++;

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
use MIME::Base64::URLSafe;

use lib "../lib";
use Islandviewer;

# Set connection information here
my $cfg; my $logger;
my $host = 'localhost';
my $port = 8211;
my $handle;
my $alarm_timeout = 60;
my $protocol_version = '1.0';

MAIN: {
    my $cfname; my $filename;
    my $res = GetOptions("config=s"   => \$cfname,
			 "filename=s" => \$filename,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    $cfg = Islandviewer::Config->config;

    if($cfg->{logger_conf} && ( -r $cfg->{logger_conf})) {
	Log::Log4perl::init($cfg->{logger_conf});
	$logger = Log::Log4perl->get_logger;
	$logger->debug("Logging initialized");
    }

    myconnect($host, $port);

    open (DATA, "$filename") or die "$!";
    my $raw_string = do{ local $/ = undef; <DATA>; };
#    my $encoded = encode_base64( $raw_string );
#    $encoded = uri_escape($encoded);
    my $encoded = urlsafe_b64encode($raw_string);

    my $message = build_req($encoded);

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

    $logger->debug("Connected to $host:$port");
}

sub send_req {
    my $msg = shift;
    my $received = '';


    # Check if the message ends with a LF, if not
    # add one
    $msg .= "\n" unless($msg =~ /\n$/);
    my $length = length $msg;

    # Make sure the socket is still open and working
    if(! defined $handle->connected) {
#    if($handle->connected ~~ undef) {
	$logger->error("Error, socket seems to be closed");
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
		$logger->error("We weren't able to send to the socket for some reason.");
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
		$logger->error("We didn't receive anything back on the socket");
		alarm 0;
		return undef;
	    }
	    $received .= $data;
	}

	# We've successfully made our request, clear the alarm
	alarm 0;
    };
    # Did we get any errors back?
    if($@) {
	# Uh-oh, we had an alarm, the iteration timed out
	if($@ eq "timeout\n") {
	    $logger->error("Error sending request, the alarm went off, timeout!");
	    return undef;
	} else {
	    $logger->error("Error sending request: " . $@);
	    return undef;
	}
    }

    # Success! Return the results
    return $received;
}

sub build_req {
    my $data = shift;

    my $str = "{\n \"version\": \"$protocol_version\",\n";
    $str .= " \"action\": \"submit\",\n";
    $str .= " \"genome_name\": \"custom genome\",\n";
    $str .= " \"genome_format\": \"gbk\",\n";
    $str .= " \"email\": \"lairdm\@sfu.ca\",\n";
    $str .= " \"genome_data\": ";
    $str .= "\"$data\"" . "\n";
    $str .= " }\nEOF\n";

    return $str;
}
