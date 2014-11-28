=head1 NAME

    Islandviewer::Server

=head1 DESCRIPTION

    Server for receiving and processing islandviewer jobs over
    tcp (ie. from the frontend)

=head1 SYNOPSIS

    use Islandviewer::Server;

    $server = Islandviewer::Server->initialize({islandviewer => $islandviewer_obj});

    $server->runServer();    

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Jan 21, 2013

=cut

package Islandviewer::Server;

use strict;
use warnings;
use Moose;
use MooseX::Singleton;
use Data::Dumper;
use JSON;
use POSIX;
use IO::Select;
use IO::Socket;
use Net::hostent;      # for OOish version of gethostbyaddr
use Fcntl;
use Tie::RefHash;
use Fcntl qw/O_NONBLOCK/;
use MIME::Base64;
use URI::Escape;
use MIME::Base64::URLSafe;
use File::Temp qw/ :mktemp /;

use Islandviewer;
use Islandviewer::Config;
use Islandviewer::DBISingleton;
use Islandviewer::Distance;
use Islandviewer::Genome_Picker;
use Log::Log4perl::Level;

use MicrobeDB::Versions;

my $cfg; my $logger; my $dbi;
my $islandviewer;
my $sig_int = 0;
my $port;
my $server;
my $sel;
# begin with empty buffers
my %inbuffer  = ();
my %outbuffer = ();
my %ready     = ();

tie %ready, 'Tie::RefHash';

my $actions = {
    submit => 'submit',
    picker => 'picker',
    clone  => 'clone',
    logging => 'logging',
    rotate => 'rotate',
};

my @logging_levels = qw/TRACE DEBUG INFO WARN ERROR FATAL/;
my %Logging_level_mappings = ( TRACE => $TRACE,
                               DEBUG => $DEBUG,
                               INFO  => $INFO,
                               WARN  => $WARN,
                               ERROR => $ERROR,
                               FATAL => $FATAL 
                             );

sub initialize {
    my $self = shift;
    my $args = shift;

    $logger = Log::Log4perl->get_logger;

    $cfg = Islandviewer::Config->config;
    $dbi = Islandviewer::DBISingleton->dbh;

    $port = $cfg->{tcp_port} || 8211;

    $server = IO::Socket::INET->new( Proto     => 'tcp',
				     LocalPort => $port,
				     Listen    => SOMAXCONN,
				     Reuse     => 1);
    die "Error, can not create tcp socket" unless($server);

    # Set the server to non-blocking
    $self->nonblock($server);

    # Add the server to the select
    $sel = IO::Select->new($server);

    $islandviewer = $args->{islandviewer};

    return $self;

}

sub instance {
    my $self = shift;

    return $self;
}

sub reqs_waiting {
    my $self = shift;
    my $timeout = shift || 1;

    return 1 if($sel->can_read($timeout));

    return 0;
}

# Run the daemon to listen for submissions,
# setup the tcp port and cycle listening until
# we receive a sigint to kill

sub runServer {
    my $self = shift;

    # Setup TCP port

    $logger->info("Running the server, start the loop!");

    # Record in islandviewer we're in daemon mode
    # (vs standalone mode)
    $islandviewer->{daemon} = 1;
    $cfg->{daemon} = 1;

    # while we haven't received a finish signal
    while(!$sig_int) {

	$logger->trace("In the loop");
	
	# Wait for requests, but don't block forever
	$self->reqs_waiting(1);

	$self->process_requests();

	$self->check_socks();
    }

    $logger->info("Exiting!");
}

sub pick_genomes {
    my $self = shift;
    my $accnum = shift;
    my $args = shift;

    # Create a Versions object to look up the correct version
    my $microbedb_ver;
    my $versions = new MicrobeDB::Versions();

    $logger->trace("Picking genomes for $accnum, arguments: " . Dumper($args));

    # If we've been given a microbedb version AND its valid... 
    unless($args->{microbedb_version} && $versions->isvalid($args->{microbedb_version})) {
	$args->{microbedb_version} = $versions->newest_version();
    }
    print Dumper $args;

    $logger->trace("Running genome picker for $accnum");

    my $picker_obj = Islandviewer::Genome_Picker->new($args);

    my $results = $picker_obj->find_comparative_genomes($accnum);

    # Didn't get any results, return an empty set
    unless($results) {
	$logger->debug("No comparison genomes found");
	return () ;
    }

    return $results;
}

sub rotate_log {
    my $self = shift;

    return $islandviewer->log_rotate();
}

sub clone_job {
    my $self = shift;
    my $aid = shift;
    my $args = shift;

    $logger->trace("Clone job for aid $aid: " . Dumper($args));
    my $new_aid = $islandviewer->clone_job($aid, $args);
    $logger->trace("New analysis id is $new_aid");

    return $new_aid;
}

sub submit_job {
    my $self = shift;
    my $genome_data = shift;
    my $genome_format = shift;
    my $genome_name = shift;
    my $email = shift;
    my $microbedb_ver = shift;

    my @tmpfiles;

    # Create a Versions object to look up the correct version
    my $versions = new MicrobeDB::Versions();

    # If we've been given a microbedb version AND its valid... 
    if($microbedb_ver && $versions->isvalid($microbedb_ver)) {
	$microbedb_ver = $microbedb_ver;
    } else {
	$microbedb_ver = $versions->newest_version();
    }

    # Write out the genome file
    my $tmp_file = mktemp($cfg->{tmp_genomes} . "/custom_XXXXXXXXX");
    push @tmpfiles, $tmp_file;
    $tmp_file .= ".$genome_format";

    open(TMP_GENOME, ">$tmp_file") or 
	$logger->logdie("Error, can't create tmpfile $tmp_file: $@");

    print TMP_GENOME $genome_data;

    close TMP_GENOME;

    my $cid = 0;
    eval {
	$cid = $islandviewer->submit_and_prep($tmp_file, $genome_name);
    };
    if($@) {
	$logger->logdie("Error submitting custom genome ($tmp_file): $@");
    }
    unless($cid) {
	$logger->logdie("Error, didn't get a cid for custom genome ($tmp_file)");
    }
    $logger->info("Submitted custom genome ($tmp_file), cid $cid");

    # We're going to use the same arguments for all the runs
    my $args->{Islandpick} = {
			      MIN_GI_SIZE => 4000};
    $args->{Sigi} = {
			      MIN_GI_SIZE => 4000};
    $args->{Dimob} = {
			      MIN_GI_SIZE => 4000};
    $args->{Distance} = {block => 1, scheduler => 'Islandviewer::NullScheduler'};
    $args->{microbedb_ver} = $microbedb_ver;
    $args->{owner_id} = 1;
    $args->{email} = $email;

    my $aid;
    eval {
	# Submit the replicon for processing
	$aid = $islandviewer->submit_analysis($cid, $args);
    };
    if($@) {
	$logger->logdie("Error submitting analysis ($tmp_file, $cid): $@");
    }
    if($aid) {
	$logger->info("Finished submitting $cid, has analysis id $aid");
    } else {
	$logger->logdie("Error, failed submitting, didn't get an analysis id");
    }

    $logger->info("Analysis $aid should now be submitted");
   
    for my $f (@tmpfiles) {
	unlink $f if( -e $f );
    }

    # Spit out the analysis id back for the web service
    return $aid;

}

sub process_requests {
    my $self = shift;

    my $client;
    my $rv;
    my $data;

    # anything to read or accept?
    foreach my $client ($sel->can_read(1)) {
	
	if($client == $server) {
	    # accept a new connection
	    
	    $client = $server->accept();
	    $sel->add($client);
	    $self->nonblock($client);
	} else {
	    # read data
	    $data = '';
	    $rv = $client->recv($data, POSIX::BUFSIZ, 0);

	    unless (defined($rv) && length $data) {
		# This would be the end of file, so close the client
                delete $inbuffer{$client};
                delete $outbuffer{$client};
                delete $ready{$client};

                $sel->remove($client);
                close $client;
		$logger->debug("Closing socket");
                next;
	    }

	    $inbuffer{$client} .= $data;
#	    print "Reading data:\n$data\n";

	    # test whether the data in the buffer or the data we
            # just read means there is a complete request waiting
            # to be fulfilled.  If there is, set $ready{$client}
            # to the requests waiting to be fulfilled.
#            while ($inbuffer{$client} =~ s/(.*)\nblahEOF\n$//) {
            while ($inbuffer{$client} =~ s/EOF\n$//) {
                push( @{$ready{$client}}, $inbuffer{$client});
		undef $inbuffer{$client};
            }
	}
    }

    # Any complete requests to process?
    foreach $client (keys %ready) {
        $self->handle($client);
    }

    # Buffers to flush?
    foreach $client ($sel->can_write(0.1)) {
        # Skip this client if we have nothing to say
        next unless exists $outbuffer{$client};

        $rv = $client->send($outbuffer{$client}, 0);
        unless (defined $rv) {
            # Whine, but move on.
            $logger->warn("I was told I could write, but I can't.");
            next;
        }
        if ($rv == length $outbuffer{$client} ||
            $! == POSIX::EWOULDBLOCK) {
            substr($outbuffer{$client}, 0, $rv) = '';
	    # If there's nothing left in the send buffer, shut it down, remove it
	    unless(length $outbuffer{$client}) {
		delete $inbuffer{$client};
		delete $outbuffer{$client};
		delete $ready{$client};

		$sel->remove($client);
		delete $outbuffer{$client} ;
		close($client);
		$logger->debug("We're done sending, closing socket");
	    }
        } else {
            # Couldn't write all the data, and it wasn't because
            # it would have blocked.  Shutdown and move on.
            delete $inbuffer{$client};
            delete $outbuffer{$client};
            delete $ready{$client};

            $sel->remove($client);
            close($client);
	    $logger->debug("Closing socket, error?");
            next;
        }
    }

    # Out of band data?
    foreach $client ($sel->has_exception(0)) {  # arg is timeout
        # Deal with out-of-band data here, if you want to.
	$logger->error("Error, we're being asked to process out of band data, this shouldn't happen.");
    } 
}

sub process_request {
    my $self = shift;
    my $req = shift;

    my $json;

    $logger->trace("Received tcp request: $req");
    eval {
	$json = decode_json($req);
    };
    if($@) {
	$logger->error("Error decoding submitted json:\t$req");
	return (400, $self->makeResStr(400, "Error decoding JSON"));
    }

    # Does the job have a valid action?
    unless($json->{action} && $actions->{$json->{action}}) {
	$logger->error("Error, no valid action was submitted: " . $json->{action});
	return (400, $self->makeResStr(400, "Error, no valid action submitted"));
    }

    # Dispatch the request
    my $action = $json->{action};
    my ($ret_code, $ret_json);
    eval {
	($ret_code, $ret_json) = $self->$action($json);
    };

    if($@) {
	$logger->error("Error dispatching action $action: $@");
	return (500, $self->makeResStr(500, "Error dispatching action $action", '', "Error dispatching action $action"));
    }

    return ($ret_code, $ret_json);
}

sub handle {
    my $self = shift;
    my $client = shift;

    foreach my $request (@{$ready{$client}}) {
        # $request is the text of the request
        # put text of reply into $outbuffer{$client}

	# Some sanity checking on what we receive?
	my ($ret_code, $results) = $self->process_request($request);
	$outbuffer{$client} = $results;
    }
    delete $ready{$client};
}

sub nonblock {
    my $self = shift;
    my $sock = shift;
    my $flags;

    $flags = fcntl($sock, F_GETFL, 0)
            or die "Can't get flags for socket: $!\n";
    fcntl($sock, F_SETFL, $flags | O_NONBLOCK)
            or die "Can't make socket nonblocking: $!\n";
}

# Check the sockets are still alive and remove 
# them from the select (and socks array) if they've
# closed

sub check_socks {
    my $self = shift;

    foreach my $sock ($sel->handles) {
	# We don't want to check the server in this context
	next if($sock == $server);

	if($sock->connected ~~ undef) {
	    # Hmm, the socket seems to have gone away...

	    delete $inbuffer{$sock};
	    delete $outbuffer{$sock};
	    delete $ready{$sock};

	    $sel->remove($sock);
	    close $sock;
	}
    }

}

####
#
# Request types
#
####

sub submit {
    my $self = shift;
    my $args = shift;

#    print Dumper $args;

#    my $genome_data = uri_unescape($args->{genome_data});
#    $genome_data = decode_base64($genome_data);
    my $genome_data = urlsafe_b64decode($args->{genome_data});

    my $aid;
    eval {
	$aid = $self->submit_job($genome_data, $args->{genome_format}, $args->{genome_name}, $args->{email}, $args->{microbedb_ver});
    };
    if($@) {
	$logger->error("Error submitting analysis: $@");
	return (500, $self->makeResStr(500, "Error submitting analysis: $@", '', "An error occurred when submitting the analysis, please try again later."));
    }

    unless($aid) {
	return (500, $self->makeResStr(500, "Unknown error, no aid returned", '', "No analysis id was returned when submitting, oops, something's wrong"));
    } else {
	return (200, $self->makeResStr(200, "Job submitted, job id: [$aid]"));
    }
}

sub rotate {
    my $self = shift;

    $logger->info("Log rotation request");

    my $logfile;
    eval {
	$logfile = $self->rotate_log();
    };
    if($@) {
	$logger->error("Error rotating log file: $@");
	return (500, $self->makeResStr(500, "Error rotating log file", '', 'An error occurred while trying to rotate the log files'));
    }

    return (200, $self->makeResStr(200, "Logfile rotated, new file: $logfile", $logfile));   
}

sub clone {
    my $self = shift;
    my $args = shift;

    $logger->trace("Request to clone analysis received");

    my $new_aid;
    eval {
        $new_aid = $self->clone_job($args->{aid}, $args->{args});
    };
    if($@) {
	$logger->error("Error cloning analysis $args->{aid}: $@");
	return (500, $self->makeResStr(500, "Error cloning analysis $args->{aid}", '', 'An error occurred when submitting your new alanysis'));
    }

    $logger->trace("Received back new aid $new_aid");

    if($new_aid) {
	return (200, $self->makeResStr(200, "Submission successful, new job id: [$new_aid]", $new_aid));
    } else {
	return (500, $self->makeResStr(500, "Error cloning analysis $args->{aid}", '', 'An error occurred when submitting your new alanysis'));

    }
}

sub picker {
    my $self = shift;
    my $args = shift;

    my $picker_args = {};
    my $results;

    eval{
	$picker_args->{microbedb_version} = $args->{microbedb_ver} if($args->{microbedb_ver});

	$picker_args->{MAX_CUTOFF} = $args->{max_cutoff} || $cfg->{MAX_CUTOFF};
	$picker_args->{MIN_CUTOFF} = $args->{min_cutoff} || $cfg->{MIN_CUTOFF};
	$picker_args->{MAX_COMPARE_CUTOFF} = $args->{max_compare_cutoff} || $cfg->{MAX_COMPARE_CUTOFF};
	$picker_args->{MIN_COMPARE_CUTOFF} = $args->{min_compare_cutoff} || $cfg->{MIN_COMPARE_CUTOFF};
	$picker_args->{MAX_DIST_SINGLE_CUTOFF} = $args->{max_dist_single_cutoff} || $cfg->{MAX_DIST_SINGLE_CUTOFF};
	$picker_args->{MIN_DIST_SINGLE_CUTOFF} = $args->{min_dist_single_cutoff} || $cfg->{MIN_DIST_SINGLE_CUTOFF};

	$results = $self->pick_genomes($args->{accnum}, $picker_args);
    };
    if($@) {
	$logger->error("Error picking comparison genomes for $args->{accnum}: $@");
	return (500, $self->makeResStr(500, "Error picking comparison genomes for $args->{accnum}", '', "An error occurred when picking comparison genomes."));
    }

    return (200, $self->makeResStr(200, "Selection successful", $results));

}

sub logging {
    my $self = shift;
    my $args = shift;

    if($args->{level} ~~ @logging_levels) {
	$logger->info("Adjusting logging level to " . $args->{level});

	$logger->level($Logging_level_mappings{$args->{level}});


	return (200, $self->makeResStr(200, "Success"));
    } else {
	return (500, $self->makeResStr(500, "Unknown log level"));
    }

}

sub makeResStr {
    my $self = shift;
    my $code = shift;
    my $msg = shift;
    my $data = shift;
    my $error_str = shift;

    my $struct = {code => $code,
		  msg =>  $msg,
		  data => ($data ? $data : '')
    };

    if($error_str) {
	$struct->{user_error_msg} = $error_str;
    }

#    my $ret_json = to_json($struct, { pretty => 1 } );
    my $ret_json = to_json($struct);

#    my $ret_json = "{\n \"code\": $code,\n \"msg\": \"$msg\"\n";
#    if($error_str) {
#	$ret_json .= ", \"user_error_msg\": \"$error_str\"\n";
#    }
#    $ret_json .= "}\n";

    return $ret_json;
}

sub finish {
    my $self = shift;

    $logger->info("Receiver terminate signal, exiting at the end of this cycle.");
    $sig_int = 1;
}

1;
