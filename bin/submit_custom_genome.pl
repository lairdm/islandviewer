#!/usr/bin/env perl

# Used to submit a custom genome, given a file name it copies it over
# and tries to prep it for analysis
# Returns the cid number which can be used to sub the analysis
# for execution.

use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Data::Dumper;
use File::Slurp;

use IO::Select;
use IO::Socket;
use Net::hostent;      # for OOish version of gethostbyaddr
use Fcntl;
use Tie::RefHash;
use Fcntl qw/O_NONBLOCK/;
#use Fcntl qw/F_GETFL, F_SETFL, O_NONBLOCK/;
use MIME::Base64;
use MIME::Base64::URLSafe;
use URI::Escape;
use JSON;

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

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
    my $cfname; my $filename; my $name; my $logger;
    my $format; my $email; my $comparison_genomes;
    my $microbedb_ver;
    my $res = GetOptions("config=s"   => \$cfname,
			 "filename=s" => \$filename,
			 "name=s"     => \$name,
			 "type=s"   => \$format,
			 "email=s"    => \$email,
			 "islandpick_genomes=s" => \$comparison_genomes,
			 "microbedb_ver=s" => \$microbedb_ver,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    my $cfg = Islandviewer::Config->config;

    if($cfg->{logger_conf} && ( -r $cfg->{logger_conf})) {
	Log::Log4perl::init($cfg->{logger_conf});
	$logger = Log::Log4perl->get_logger;
	$logger->debug("Logging initialized");
    }

    unless( -f $filename && -r $filename ) {
	$logger->error("Custom genome $filename is not readable, failing");
	print "0\n";
	exit;
    }

    $host = $cfg->{daemon_host}
        if($cfg->{daemon_host});
    $port = $cfg->{tcp_port}
        if($cfg->{tcp_port});

    myconnect($host, $port);

    # We're going to build the structure to send the server, piece by piece
    my $req_struct = {action => 'submit',
		      ip_addr => '0.0.0.0',
		      version => $protocol_version
                     };

    # Add the genome to the structure
    my $file_contents = read_file($filename);
    my $genome_data = urlsafe_b64encode($file_contents);
    $req_struct->{genome_data} = $genome_data;

    $req_struct->{genome_name} = ($name ? $name : 'user genome');

    # Set the format
    $format = 'gbk' if($format eq 'gbk');
    $format = 'gbk' if($format eq 'gb');
    $format = 'embl' if($format eq 'embl');
    $req_struct->{genome_format} = ($format ? $format : 'gbk');

    $req_struct->{email} = $email if($email);

    # Add islandpick comparison genomes if given
    if($comparison_genomes) {
	my $genomelist_str = join(' ', split(',', $comparison_genomes));
	$req_struct->{Islandpick} = { args => { comparison_genomes => $genomelist_str } };
    }

    $req_struct->{microbedb_ver} = $microbedb_ver if ($microbedb_ver);

    my $req_str = to_json($req_struct, { pretty => 1});
    $req_str .= "\nEOF";

    my $recieved = send_req($req_str);

    print "$recieved\n";


};

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

