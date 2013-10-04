=head1 NAME

    Islandviewer::Distance

=head1 DESCRIPTION

    Object to calculate distance between replicons, depends on
    MicrobeDB

=head1 SYNOPSIS

    use Islandviewer::Distance;

    $dist = Islandviewer::Distance->new(scheduler => Islandviewer::Metascheduler);
    $dist->calculate_all(version => 73);
    $distance->add_replicon(cid => 2);

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
use Log::Log4perl qw(get_logger :nowarn);

use MicrobeDB::Version;
use MicrobeDB::Search;
use MicrobeDB::GenomeProject;

my $cfg;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = MetaScheduler::Config->config;

    if($args->{scheduler}) {
	$self->{scheduler} = $args->{scheduler};
    } else {
	$self->{scheduler} = $cfg->{default_scheduler};
    }

    $self->{num_jobs} = $args->{num_jobs};

    die "Error, work dir not specified"
	unless( -d $workdir };
    $self->{workdir} = $args->{workdir};

}

sub calculate_all {
    my $self = shift;
    my $version = shift;

    $replicons;

    # Check the version we're given
    $version = $self->set_version($version);

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
    my $runpairs = $self->build_pairs($replicon, $replicon);

    $self->build_sets($runpairs, $replicon, $replicon);

    $self->submit_sets();
}

sub build_pairs {
    my $self = shift;
    my $set1 = shift;
    my $set2 = shift;

    my $runpairs;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $sqlstmt = "SELECT id FROM $cfg->{dist_table} WHERE rep_accnum1 = ? AND rep_accnum2 = ?";
    my $find_dist = $dbh->prepare($sqlstmt) or 
	die "Error preparing statement: $sqlstmt: $DBI::errstr";

    # Now we need to make a double loop to find the pairs
    # which need to be calculated
    foreach my $outer_rep (keys %{$set1}) {
	foreach my $inner_rep (keys %{rep2}) {
	    # We don't run it against itself
	    next if($outer_rep eq $inner_rep);

	    # Check both ways around in case it was added in
	    # reverse during a previous run
	    next if($runpairs->{$outer_rep . ':' . $inner_rep} ||
		    $runpairs->{$inner_rep . ':' . $outer_rep});
	    
	    $find_dist->execute($outer_rep, $inner_rep);
	    next if($find_dist->rows > 0);

	    $find_dist->execute($inner_rep, $outer_rep);
	    next if($find_dist->rows > 0);

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
	    mkdir $self->{workdir} . '/' . "cvtree_$job"
		or die "Error making workdir " . $self->{workdir} . '/' . "cvtree_$job";
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

sub submit_sets {
    my $self = shift;

    # Find the sets we're going to submit
    my @sets = $self->find_sets;

    # Create an instance of the scheduler wrapper
    my $scheduler = "$self->{scheduler}"->new
	or die "Error, can't create instance of scheduler $self->{scheduler}";

    foreach my $set (@sets) {
	# Build the command to run the set
	$set =~ /\/(cvtree_\d+)$/;
	my $name = $1;

	my $cmd = sprintf($cfg->{cvtree_displatcher}, $self->{workdir},
			  $set, $name);

	# Submit it to the scheduler
	"$self->{dispatcher}"->submit($name, $cmd);
    }
}

sub run_and_load {
    my $self = shift;
    my $set = shift;

    # We're going to open the sets file, and for each
    # run cvtree and load the results, if any
    # We also need to record the attempt so we know
    # later what has been tried

    die "Error, can't access set file $set/set.txt"
	unless( -f "$set/set.txt" && -r "$set/set.txt" );

    # Fetch the DBH
    my $dbh = Islandviewer::DBISingleton->dbh;

    my $cvtree_attempt = $dbh->prepare("REPLACE INTO DistanceAttempt (rep_accnum1, rep_accnum2, status, run_date) VALUES (?, ?, ?, now()") or
	die "Error, can't prepare statement:  $DBI::errstr";
    $self->{cvtree_attempt_sth} = $cvtree_attempt;

    my $cvtree_distance = $dbh->prepare("REPLACE INTO Distance (rep_accnum1, rep_accnum2, distance) VALUES (?, ?, ?)") or
	die "Error, can't prepare statement:  $DBI::errstr";
    $self->{cvtree_distance_sth} = $cvtree_distance;

    open(SET, "<$set/set.txt") or die "Error, can't open $set: $!";

    while(<SET>) {
	chomp;

	my ($first, $second, $first_file, $second_file) =
	    split "\t";

	my $dist = $self->run_cvtree($first, $second, $first_file, $second_file);
	
	if($dist > 0) {
	    # Success! Insert it to the Distance table and mark it
	    # in the Attempt table.
	} else {
	    # Failure, mark it in the Attempt table
	}
    }

}

sub run_cvtree {
    my $self = shift;
    my $first = shift;
    my $second = shift;
    my $first_file = shift;
    my $second_file = shift;
    my $work_dir = shift;

    die "Error, can't read first input file $first_file"
	unless( -f $first_file && -r $first_file );
    my $first_base = basename($frst_file, ".faa");

    die "Error, can't read second input file $second_file"
	unless( -f $second_file && -r $second_file );
    my $second_base = basename($second_file, ".faa");

    # Make the input file
    open(INPUT, ">$work_dir/cvtree.txt") or
	die "Error, can't create cvtree input file $work_dir/cvtree.txt: $!";

    print INPUT "2\n";
    print INPUT "$first_base, $first\n";
    print INPUT "$second_base, $second\n";

    close INPUT;

    my $cmd = sprintf($cfg->{cvtree_cmd}, "$work_dir/cvtree.txt", "$work_dir/results.txt", "$work_dir/output.txt");
    my $ret = system($cmd);

    # did we get a non-zero return value? If so, cvtree failed
    unless($ret) {
	
    }

}

sub find_sets {
    my $self = shift;

    opendir(my $dh, $cfg->{workdir}) or 
	die "Error, can't opendir $cfg->{workdir}";

    # We only want to find the directories starting with "cvtree_"
    @sets = grep { /^cvtree_/ && -d "$cfg->{workdir}/$_" } readir($dh);

    closedir $dh;

    return @sets;
}

sub set_version {
    my $self = shift;
    my $v = shift;

    # Create a Versions object to look up the correct version
    my $versions = new MicrobeDB::Versions();

    # If we're not given a version, use the latest
    $v = $versions->newest_version() unless($version);

    # Is our version valid?
    return 0 unless($versions->isvalid($v));

    return $v;
}

1;
