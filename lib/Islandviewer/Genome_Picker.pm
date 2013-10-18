=head1 NAME

    Islandviewer::GenomePicker

=head1 DESCRIPTION

    Object to pick nearest genomes for IslandPick

=head1 SYNOPSIS

    use Islandviewer::GenomePicker;

    $dist = Islandviewer::Distance->new({workdir => '/tmp/workdir'});
    $dist->calculate_all(version => 73, custom_replicon => $repHash);
    $distance->add_replicon(cid => 2, version => 73);
    
=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Oct 17, 2013

=cut

package Islandviewer::GenomePicker;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);

use Islandviewer::Schema;

use MicrobeDB::Replicon;
use MicrobeDB::Search;

my $cfg; my $logger; my $cfg_file;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $self->{schema} = Islandviewer::Schema->connect($cfg->{dsn},
					       $cfg->{dbuser},
					       $cfg->{dbpass})
	or die "Error, can't connect to Islandviewer via DBIx";

    die "Error, you must specify a microbedb version"
	unless($args->{microbedb_version});
    $self->{microbedb_ver} = $args->{microbedb_version};

    # Setup the cutoffs for the run, we'll use the defaults
    # unless we're explicitly told otherwise
    # and yes, I used all caps, that's what it is in the original
    # code and I'm playing it safe in case of code reuse.
    $self->{max_cutoff} = $args->{MAX_CUTOFF} || $cfg->{MAX_CUTOFF};
    $self->{min_cutoff} = $args->{MIN_CUTOFF} || $cfg->{MIN_CUTOFF};
    $self->{max_compare_cutoff} = $args->{MAX_COMPARE_CUTOFF} || $cfg->{MAX_COMPARE_CUTOFF};
    $self->{min_compare_cutoff} = $args->{MIN_COMPARE_CUTOFF} || $cfg->{MIN_COMPARE_CUTOFF};
    $self->{max_dist_single_cutoff} = $args->{MAX_DIST_SINGLE_CUTOFF} || $cfg->{MAX_DIST_SINGLE_CUTOFF};
    $self->{min_dist_single_cutoff} = $args->{MIN_DIST_SINGLE_CUTOFF} || $cfg->{MIN_DIST_SINGLE_CUTOFF};
    $self->{min_gi_size} = $args->{MIN_GI_SIZE} || $cfg->{MIN_GI_SIZE};
}

# Find all the genomes within our range, and par it down to fit the min/max
# number of comparative genomes we're allowed
#
# Input: a rep_accnum

sub find_comparative_genomes {
    my $self = shift;
    my $rep_accnum = shift;

    # First let's get all the genomes which meet our distance
    # criteria, we'll now have a hash matching that
    my $dists = $self->find_distance_range();

    # Next let's find our own strain's name
    my $name = $self->find_name($rep_accnum);

    # Start building our data structure we'll need for
    # the calculations
    $self->{dist_set}->{$rep_accnum}->{name} = $name;
    $self->{dist_set}->{$rep_accnum}->{dists} = $dists;
    $self->{primary_rep_accnum} = $rep_accnum;

    # Next let's go through all the distances we have so far, find
    # their names, and skip them if they're the same
    # This qualification if from Morgan's original code, we want
    # to skip if its the same strain just from a different
    # sequencing centre
    foreach my $cur_accnum (keys %{$dists}) {
	# Special case, we know its a microbedb identifier so
	# skip a DB hit by saying so
	my $cur_name = $self->find_name($cur_accnum, 'microbedb');

	# Is it the same strain? if not, we don't want it
	next if($cur_name eq $name);

	# Save this for later in our dataset
	$self->{dist_set}->{$cur_accnum}->{name} = $cur_name;
    }

    # Alright, at this point we have a data structure of all
    # the genomes that match the min/max distance from our reference
    # genome, and are not different variants of the same strain.
    # We're probably looping once more time than needed, but now
    # we go through this set again and fill in all the distances to
    # each other that we don't have.
    $self->fill_in_distances();

    # Do a quick sanity check, do we have at least one matching the min/max
    # single distance cutoffs? If not, we're done, bye bye.
    return undef
	unless($self->check_thresholds);

    
}

# Check the min and max single cutoff thresholds, to ensure
# we have a set that meets these.  Some comments from Morgan's
# original code why this is important:
#
#Setting a maxmimum distance that at least one genome has to be within
#This is to ensure that the POSITIVE DATASET is searching for events on a similar time scale
#Decreasing this will reduce our positive dataset
#
#Setting a minimum distance that at least one genome has to be over
#This is to ensure that the NEGATIVE DATASET is finding old enough conserved regions
#Increasing this will reduce our negative dataset

sub check_thresholds {
    my $self = shift;

    # Loop through all the distances associated with the query
    # rep_accnum and ensure we have at least one meeting the
    # min and max
    my $found_min = 0; my $found_max = 0;
    foreach my $accnum (keys %{$self->{data_set}->{$self->{primary_rep_accnum}}->{dists}}) {
	# Have we found a distance less than the max cutoff?
	$found_max = 1
	    if($self->{data_set}->{$self->{primary_rep_accnum}}->{dists}->{$accnum} <=
	       $self->{max_dist_single_cutoff} );

	# Have we found a distance greater than the min cutoff?
	$found_min = 1
	    if($self->{data_set}->{$self->{primary_rep_accnum}}->{dists}->{$accnum} >=
	       $self->{min_dist_single_cutoff} );

	# We've found both, return true
	return 1
	    if($found_max && $found_min);
    }

    # We haven't found one or the other, return false
    return 0;
}

# Will return all accnum's between the cutoff values

sub find_distance_range {
    my $self = shift;
    my $rep_accnum = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $sqlstmt = "SELECT rep_accnum1, rep_accnum2, distance FROM Distance WHERE (rep_accnum1 = ? OR rep_accnum2 = ?) AND distance < $self->{max_cutoff} AND distance > $self->{min_cutoff}";
    my $find_dists = $dbh->prepare($sqlstmt) or 
	die "Error preparing statement: $sqlstmt: $DBI::errstr";

    $find_dists->execute($rep_accnum, $rep_accnum);

    # Alright, now let's build a set of the distances in a data structure
    $dists;
    while(my @row = $find_dists->fetchrow_array) {
	# Find which way around the pair is, put it in the data structure
	if($row[0] eq $rep_accnum) {
	    $dist->{$row[1]} = $row[2];
	} elsif($row[1] eq $rep_accnum) {
	    $dist->{$row[0]} = $row[2];
	}
    }
    
    return $dist;
}

sub fill_in_distances {
    my $self = shift;

    # We want to go through the dist_set and for every
    # entry that doesn't have a ->{dist} entry, build one
    # but first we need to know all the identifiers we're
    # going to be comparing against
    my @accnums = keys %{$self->{dist_set}};

    my $dbh = Islandviewer::DBISingleton->dbh;
    my $sqlstmt = "SELECT rep_accnum1, rep_accnum2, distance FROM Distance WHERE rep_accnum1 = ? OR rep_accnum2 = ?";
    my $find_dists = $dbh->prepare($sqlstmt) or 
	die "Error preparing statement: $sqlstmt: $DBI::errstr";

    foreach my $accnum (@accnums) {
	# Is there already a set of distances? Skip.
	next if(defined($self->{dist_set}->{$accnum}->{dists}));

	$find_dists->execute($accnum, $accnum);
	while(my @row = $find_dists->fetchrow_array) {
	    if($row[0] eq $rep_accnum) {
		# If the referenced accnum is in the first slot, we need to hunt the second
		if($row[1] ~~ @accnums) {
		    # We've found a pair!
		    $self->{data_set}->{$accnum}->{dists}->{$row[1]} = $row[2];
		}
	    } else {
		# If the referenced accnum is in the second slot, we need to hunt the first
		if($row[0] ~~ @accnums) {
		    # We've found a pair!
		    $self->{data_set}->{$accnum}->{dists}->{$row[0]} = $row[2];
		}

	    }
	}
    }

    # By this point we should have a set of all the distances, we're done
}

# Looks up the definition or custom genome name associated with
# a rep_accnum, takes an optional second parameter of 'custom'
# or 'microbedb' to save a DB hit if we know what type its going
# to be

sub find_name {
    my $self = shift;
    my $rep_accnum = shift;
    my $type = (@_ ? shift : 'unknown');

    unless($type eq 'microbedb' || $rep_accnum =~ /\D/) {
    # If we know we're not hunting for a microbedb genome identifier...
    # or if there are non-digits, we know custom genomes are only integers
    # due to it being the autoinc field in the CustomGenome table
    # Do this one first since it'll be faster

	# Only prep the statement once...
	unless($self->{find_custom_name}) {
	    my $sqlstmt = "SELECT name from CustomGenome WHERE cid = ?";
	    $self->{find_custom_name} = $dbh->prepare($sqlstmt) or 
		die "Error preparing statement: $sqlstmt: $DBI::errstr";
	}

	$self->{find_custom_name}->execute($rep_accnum);

	# Do we have a hit? There should only be one row,
	# its a primary key
	if($self->{find_custom_name}->rows > 0) {
	    my ($name) = $self->{find_custom_name}->fetchrow_array;
	    return $name;
	}
    }

    unless($type  eq 'custom') {
    # If we know we're not hunting for a custom identifier    

	my $sobj = new MicrobeDB::Search();

	my ($rep_results) = $sobj->object_search(new MicrobeDB::Replicon( rep_accnum => $rep_accnum,
								      version => $self->{microbedb_ver} ));
	
	# We found a result in microbedb
	if( defined($rep_results) ) {
	    return $rep_results->definition();
	}
    }

    # This should actually never happen if we're
    # doing things right, but handle it anyways
    return 'unknown';

}
