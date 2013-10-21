=head1 NAME

    Islandviewer::Distance

=head1 DESCRIPTION

    Object to calculate distance between replicons, depends on
    MicrobeDB

=head1 SYNOPSIS

    use Islandviewer::Distance;

    $dist = Islandviewer::Distance->new({scheduler => Islandviewer::Metascheduler});
    $dist->calculate_all(version => 73, custom_replicon => $repHash);
    $distance->add_replicon(cid => 2, version => 73);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Sept 25, 2013

=cut


package Islandviewer::Distance;

use strict;
use Moose;
use File::Basename;
use File::Spec;
use File::Copy;
use Log::Log4perl qw(get_logger :nowarn);

use MicrobeDB::Version;
use MicrobeDB::Versions;
use MicrobeDB::Search;
use MicrobeDB::GenomeProject;

use Net::ZooKeeper::WatchdogQueue;

use Islandviewer::Schema;

my $cfg; my $logger; my $cfg_file;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;
    $cfg_file = File::Spec->rel2abs(Islandviewer::Config->config_file);

    $logger = Log::Log4perl->get_logger;

    if($args->{scheduler}) {
	$self->{scheduler} = $args->{scheduler};
    } else {
	$self->{scheduler} = $cfg->{default_scheduler};
    }

    $self->{num_jobs} = $args->{num_jobs};

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};

    $self->{schema} = Islandviewer::Schema->connect($cfg->{dsn},
					       $cfg->{dbuser},
					       $cfg->{dbpass})
	or die "Error, can't connect to Islandviewer via DBIx";

    # Vocalize a little
    $logger->info("Initializing Islandviewer::Distance");
    $logger->info("Using scheduler " . $self->{scheduler});
    $logger->info("Using workdir " .  $self->{workdir});
    $logger->info("Using num_jobs " . $self->{num_jobs}) if($self->{num_jobs});

}

sub calculate_all {
    my $self = shift;
    my (%args) = @_;

    my $version = ($args{version} ? $args{version} : undef );
    my $custom_rep = ($args{custom_replicon} ?
		      $args{custom_replicon} : undef );

    my $replicon;

    # Check the version we're given
    $version = $self->set_version($version);
    $logger->debug("Using MicrobeDB version $version");

    die "Error, not a valid version"
	unless($version);

    # Create the filter on what type of records we're looking for
    my $rep_obj = new MicrobeDB::Replicon( version_id => $version,
	                                   rep_type => 'chromosome' );

    # Create the search object
    my $search_obj = new MicrobeDB::Search();

    # do the actual search
    my @result_objs = $search_obj->object_search($rep_obj);

    # Loop through the results and store them away
    foreach my $curr_rep_obj (@result_objs) {
	my $rep_accnum = $curr_rep_obj->rep_accnum();
	my $filename = $curr_rep_obj->get_filename('faa');

	$replicon->{$rep_accnum} = $filename
	    if($filename && $rep_accnum);
    }

    # Once we have all the possible replicons let's build our set
    # of pairs that need running
    # if we're running a custom replicon set, use that for the
    # first sets in the pairs comparison
    my $runpairs = ($custom_rep ? 
		    $self->build_pairs($custom_rep, $replicon) :
		    $self->build_pairs($replicon, $replicon));

    if($custom_rep) {
	$self->build_sets($runpairs, $custom_rep, $replicon);
    } else {
	$self->build_sets($runpairs, $replicon, $replicon);
    }

    $self->submit_sets();
}

sub build_pairs {
    my $self = shift;
    my $set1 = shift;
    my $set2 = shift;

    my $runpairs;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $sqlstmt = "SELECT id FROM $cfg->{dist_log_table} WHERE rep_accnum1 = ? AND rep_accnum2 = ?";
    my $find_dist = $dbh->prepare($sqlstmt) or 
	die "Error preparing statement: $sqlstmt: $DBI::errstr";

    # Now we need to make a double loop to find the pairs
    # which need to be calculated
    foreach my $outer_rep (keys %{$set1}) {
	foreach my $inner_rep (keys %{$set2}) {
	    # We don't run it against itself
	    next if($outer_rep eq $inner_rep);

	    # Check both ways around in case it was added in
	    # reverse during a previous run
	    next if($runpairs->{$outer_rep . ':' . $inner_rep} ||
		    $runpairs->{$inner_rep . ':' . $outer_rep});
	    
	    # Try to look up the pair in the cache, -1 means
	    # it hasn't been run yet.  We don't care in this
	    # case if the past run was successful or not.
	    next if($self->lookup_pair($outer_rep, $inner_rep) == -1);

#	    $find_dist->execute($outer_rep, $inner_rep);
#	    next if($find_dist->rows > 0);

#	    $find_dist->execute($inner_rep, $outer_rep);
#	    next if($find_dist->rows > 0);

	    # Ok, it looks like we need to run this pair
	    $runpairs->{$outer_rep . ':' . $inner_rep} = 1;
	}
    }
    
    return $runpairs;
}

sub build_sets {
    my $self = shift;
    my $pairs = shift;
    my $first_set = shift;
    my $second_set = shift;

    my $batch_size;

    # Find the batch size if we're going wide
    if($self->{num_jobs}) {
	$batch_size = scalar(keys %{$pairs}) / $self->{num_jobs};
    } else {
	$batch_size = scalar(keys %{$pairs});
    }

    my $i = 0; my $job = 0; my $fh;
    foreach my $pair (keys %{$pairs}) {
	unless($i) {
	    # Start a new batch directory
	    close $fh if($fh);
	    unless( -d $self->{workdir} . '/' . "cvtree_$job" ) {
		mkdir $self->{workdir} . '/' . "cvtree_$job"
		    or die "Error making workdir " . $self->{workdir} . '/' . "cvtree_$job";
	    }
	    open $fh, ">$self->{workdir}/cvtree_$job/set.txt" 
		or die "Error opening set file $self->{workdir}/cvtree_$job/set.txt";
	}

	my ($first, $second) = split ':', $pair;
	print $fh "$first\t$second\t" . $first_set->{$first} . 
	    "\t" . $second_set->{$second} . "\n";

	# Increment and check to see if we have to start a 
	# new cycle
	$i++;
	if($i >= $batch_size) {
	    $i = 0;
	    $job++;
	}
    }

    close $fh if($fh);

}

# Add the distance for a custom genome

sub add_replicon {
    my $self = shift;
    my (%args) = @_;

    my $cid = $args{cid};

    # Fetch the record from the database for this custom genome
    my $custom_genome = $self->{schema}->resultset('CustomGenome')->find(
	{ c_id => $cid } ) or
	return 0;

    my $filename = $custom_genome->filename;

    # Do some checking on the file name and munge it for our needs
    unless($filename =~ /^\//) {
	# The file doesn't start with a /, its not an absolute path
	# fix it up, assume its under the custom_genomes folder
	$filename = $cfg->{custom_genomes} . "/$filename";
    }

    # Filenames are just saved as basenames, check if the fasta version exists
    unless( -f "$filename.faa" ) {
	$logger->error("Error, can't find filename $filename.faa");
	return 0;
    }

    # We have a valid filename, lets toss it to calculate_all
    # pass along the specific microbedb version if we've
    # been given one
    my $custom_rep->{$cid} = "$filename.faa";
    if($args{version}) {
	$self->calculate_all(custom_replicon => $custom_rep,
			     version => $args{version});
    } else {
	$self->calculate_all(custom_replicon => $custom_rep);
    }

}

# Submit the sets of cvtree jobs to the queue,
# take a single boolean option on if we should
# block for the jobs or just submit and exit

sub submit_sets {
    my $self = shift;
    my $block = do { @_ ? shift : 0 };

    # Find the sets we're going to submit
    my @sets = $self->find_sets;

    my $scheduler; my $watchdog;

    # If we're running in blocking mode, we need the watchdog module
    if($block) {
	$watchdog = new Net::ZooKeeper::WatchdogQueue($cfg->{zookeeper},
						      $cfg->{zk_root} . $$);

	$watchdog->create_queue(timer => $cfg->{zk_timer},
				queue => \@sets,
				sync_start => 1);
    }

    # Create an instance of the scheduler wrapper
    eval {
	no strict 'refs';
	$logger->debug("Initializing scheduler " . $self->{scheduler});
	(my $mod = "$self->{scheduler}.pm") =~ s|::|/|g; # Foo::Bar::Baz => Foo/Bar/Baz.pm
	require "$mod";
	$scheduler = "$self->{scheduler}"->new()
	    or die "Error, can't create instance of scheduler $self->{scheduler}";
    };

    if($@) {
	$logger->fatal("Error, can't load scheduler " . $self->{scheduler} . ": $@");
	die "Error loading scheduler: $@";
    }

    foreach my $set (@sets) {
	# Build the command to run the set
	print "Doing set $set\n";

	my $cmd = sprintf($cfg->{cvtree_dispatcher}, $self->{workdir},
			  $set, $cfg_file);
	$cmd .= " -b " . $cfg->{zk_root} . $$
	    if($block);
	print "Running command $cmd\n";

	# Submit it to the scheduler
	my $ret = $scheduler->submit($set, $cmd, $self->{workdir});

	$logger->error("Returned error from scheduler when trying to submit set $set");
    }

    # If we're blocking, go wait for the watchdog then
    # clean up after ourself
    if($block) {
	my $ret = $self->block_for_cvtree($watchdog);

	$watchdog->clear_timers();

	die "Error while waiting for cvtree, bailing!"
	    unless($ret);
    }
}

sub run_and_load {
    my $self = shift;
    my $set = shift;
    my $watchdog = do { @_ ? shift : undef };

    # We're going to open the sets file, and for each
    # run cvtree and load the results, if any
    # We also need to record the attempt so we know
    # later what has been tried

    die "Error, can't access set file $set/set.txt"
	unless( -f "$set/set.txt" && -r "$set/set.txt" );

    # Fetch the DBH
    my $dbh = Islandviewer::DBISingleton->dbh;

    my $cvtree_attempt = $dbh->prepare("REPLACE INTO $cfg->{dist_log_table} (rep_accnum1, rep_accnum2, status, run_date) VALUES (?, ?, ?, now())") or
	die "Error, can't prepare statement:  $DBI::errstr";
    $self->{cvtree_attempt_sth} = $cvtree_attempt;

    my $cvtree_distance = $dbh->prepare("REPLACE INTO $cfg->{dist_table} (rep_accnum1, rep_accnum2, distance) VALUES (?, ?, ?)") or
	die "Error, can't prepare statement:  $DBI::errstr";
    $self->{cvtree_distance_sth} = $cvtree_distance;

    open(SET, "<$set/set.txt") or die "Error, can't open $set: $!";

    # We're going bulk load the results after the fact
    # for speed, so open some logging file
    open(RESULTSET, ">$set/bulkload.txt") or
	die "Error opening $set/bulkload.txt output file: $!";
    open(RESULTLOG, ">$set/bulklog.txt") or
	die "Error opening $set/bulklog.txt log file: $!";

    while(<SET>) {
	chomp;

	my ($first, $second, $first_file, $second_file) =
	    split "\t";

	my $dist = $self->run_cvtree($first, $second, $first_file, $second_file);
	
	if($dist > 0) {
	    # Success! Insert it to the Distance table and mark it
	    # in the Attempt table.
	    print RESULTSET "$first\t$second\t$dist\n";
#	    $cvtree_distance->execute($first, $second, $dist);

	    print RESULTLOG "$first\t$second\t1\n";
#	    $cvtree_attempt->execute($first, $second, 1);
	} else {
	    # Failure, mark it in the Attempt table
	    print RESULTLOG "$first\t$second\t0\n";
#	    $cvtree_attempt->execute($first, $second, 0);
	}

	# If we're using the watchdog module, reset the timer
	# every cycle
	$watchdog->kick_dog()
	    if($watchdog);
    }

    close SET;
    close RESULTSET;
    close RESULTLOG;

    # Bulk load the results
    $dbh->do("LOAD DATA LOCAL INFILE '$set/bulklog.txt' REPLACE INTO TABLE $cfg->{dist_log_table} FIELDS TERMINATED BY '\t' (rep_accnum1, rep_accnum2, status) SET run_date = CURRENT_TIMESTAMP");
    
    # Reset the timer just in case the load takes a while
    $watchdog->kick_dog()
	if($watchdog);


    $dbh->do("LOAD DATA LOCAL INFILE $set/bulkload.txt REPLACE INTO TABLE $cfg->{dist_table} FIELDS TERMINATED BY '\t' (rep_accnum1, rep_accnum2, distance)");

    # And we're done.

}

sub run_cvtree {
    my $self = shift;
    my $first = shift;
    my $second = shift;
    my $first_file = shift;
    my $second_file = shift;

    my $work_dir = $self->{workdir};

    die "Error, can't read first input file $first_file"
	unless( -f $first_file && -r $first_file );
    $first_file =~ s/\.faa$//;

    die "Error, can't read second input file $second_file"
	unless( -f $second_file && -r $second_file );
    $second_file =~ s/\.faa$//;

    # Make the input file
    open(INPUT, ">$work_dir/cvtree.txt") or
	die "Error, can't create cvtree input file $work_dir/cvtree.txt: $!";

    print INPUT "2\n";
    print INPUT "$first_file $first\n";
    print INPUT "$second_file $second\n";

    close INPUT;

    my $cmd = sprintf($cfg->{cvtree_cmd}, "$work_dir/cvtree.txt", "$work_dir/results.txt", "$work_dir/output.txt");
    print "Running $cmd\n";
    my $ret = system($cmd);

    my $dist = 0;

    # did we get a non-zero return value? If so, cvtree failed
    unless($ret) {
	open(RES, "<$work_dir/results.txt") or
	    die "Error opening results file $work_dir/results.txt: $!";

	while(<RES>) {
	    # Look for the line with the decimal number
	    chomp;

	    # cvtree adds a space at the end of the dist, kludge
	    s/\s//g;

	    next unless(/^\d+\.\d+$/);

	    # Found a result
	    $dist = $_;
	    last;
	}
	close RES;
    }

#    unlink "$work_dir/output.txt"
#	if( -f "$work_dir/output.txt" );
    
    return $dist if($dist);

    # Are we saving failed runs for later examination?
    if($cfg->{save_failed}) {
	mkdir "$work_dir/failed"
	    unless( -d "$work_dir/failed" );

	move("$work_dir/results.txt", "$work_dir/failed/$first.$second.txt");
    }

    return -1;
}

sub find_sets {
    my $self = shift;

    opendir(my $dh, $self->{workdir}) or 
	die "Error, can't opendir $self->{workdir}";

    # We only want to find the directories starting with "cvtree_"
    my @sets = grep { /^cvtree_/ && -d "$self->{workdir}/$_" } readdir($dh);

    closedir $dh;

    return @sets;
}

# For speed we're going to cache the distance attempt
# log as needed, but only as needed, this will save
# time with custom genomes since in that case there
# should be no hits to begin with, so why cache
# the whole table?  A potential space/time savings
# for partial updates as well.
# As long as we remember to put the smaller or less
# likely to have been run set in the $first element
# we'll save lookups too.

sub lookup_pair {
    my $self = shift;
    my $first = shift;
    my $second = shift;

    # Make the query if it doesn't exist, why recreate
    # the query each time we call this function?
    unless($self->{find_log_forward}) {
	my $dbh = Islandviewer::DBISingleton->dbh;

	my $sqlstmt = "SELECT rep_accnum2, status FROM $cfg->{dist_log_table} WHERE rep_accnum1 = ?";
	my $self->{find_log_forward} = $dbh->prepare($sqlstmt) or 
	    die "Error preparing statement: $sqlstmt: $DBI::errstr";
    }

    # And in the reverse direction... yes we're fetching
    # the dbh handle twice, but this is still better than
    # getting it for *every* call to this function.
    unless($self->{find_log_reverse}) {
	my $dbh = Islandviewer::DBISingleton->dbh;

	my $sqlstmt = "SELECT rep_accnum1, status FROM $cfg->{dist_log_table} WHERE rep_accnum2 = ?";
	my $self->{find_log_reverse} = $dbh->prepare($sqlstmt) or 
	    die "Error preparing statement: $sqlstmt: $DBI::errstr";
    }

    # We only need to save the cache in one direction of
    # the pair if we remember to check it in both directions

    if($self->{log_cache}->{$first}) {
	# If we have a copy of the cache using the first
	# accnum as a lookup....

	if(defined($self->{log_cache}->{$first}->{$second})) {
	    # The value exists in the cache
	    return $self->{log_cache}->{$first}->{$second};
	}

	# This pair hasn't been run....
	return -1;

    } elsif($self->{log_cache}->{$second}) {
	# If we have a copy of the cache using the second
	# accnum as a lookup....

	if(defined($self->{log_cache}->{$second}->{$first})) {
	    # The value exists in the cache
	    return $self->{log_cache}->{$second}->{$first};
	}

	# This pair hasn't been run....
	return -1;

    } else {
	$logger->debug("No cache hit for $first:$second, loading cache for $first");
	# Neither direction is cached, cache all records in
	# the forward direction only.

	# Build the cache in the forward direction for $first
	$self->{find_log_forward}->execute($first);
	while(my @row = $self->{find_log_forward}->fetchrow_array) {
	    $self->{log_cache}->{$first}->{$row[0]} = $row[1];
	}

	# Build the cache in the forward direction for $first
	$self->{find_log_reverse}->execute($first);
	while(my @row = $self->{find_log_reverse}->fetchrow_array) {
	    $self->{log_cache}->{$first}->{$row[0]} = $row[1];
	}

	# Now we only need to check the forward direction since
	# that's all we've loaded in to the cache
	
	if(defined($self->{log_cache}->{$first}->{$second})) {
	    # The value exists in the cache
	    return $self->{log_cache}->{$first}->{$second};
	}

	# This pair hasn't been run....
	return -1;

    }
}

sub set_version {
    my $self = shift;
    my $v = shift;

    # Create a Versions object to look up the correct version
    my $versions = new MicrobeDB::Versions();

    # If we're not given a version, use the latest
    $v = $versions->newest_version() unless($v);

    # Is our version valid?
    return 0 unless($versions->isvalid($v));

    return $v;
}

sub block_for_cvtree {
    my $self = shift;
    my $watchdog = shift;
    my $loop_count = 0;

    # Wait until a child process begins
    until($watchdog->wait_sync()) {
	$logger->info("Waiting for a cvtree jobto start");
    }

    # Next we wait for all the children to empty the queue
    # and all children to finish, so as long as there is
    # something waiting in the queue or something running,
    # keep checking
    my $alive; my $expired;
    do {
	($alive, $expired) = $watchdog->check_timers();

	if($expired) {
	    $logger->fatal("Something serious is wrong, a cvtree seems to be stuck, bailing");
	    return 0;
	}

	# Sleep for a while to loosen the loop
	sleep $cfg->{zk_timer};

	# We don't need to be overly noisy, let's only check in
	# ever 10 iterations
	if($loop_count >= 10) {
	    $loop_count = 0;
	    $logger->debug("Still waiting for cvtree, $alive alive");
	}

    } while($watchdog->queue_count() || $alive);

    return 1;
}

1;
