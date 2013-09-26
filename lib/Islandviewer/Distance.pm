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

use MicrobeDB::Version;
use MicrobeDB::Search;
use MicrobeDB::GenomeProject;

my $cfg;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = MetaScheduler::Config->config;

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
