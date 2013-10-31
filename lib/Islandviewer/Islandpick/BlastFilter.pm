# Reuse of Morgan's old code.

#Filters blast hits based on length, fractionID, removing overlapping hits,
#	and clustering hits together.  Requires an array of Blast_hit objects (see
#	Blast_hit.pm).


package Islandviewer::Islandpick::BlastFilter;

use strict;
use Islandviewer::Islandpick::BlastHit;


#use base qw(My_Basic_Class);

my $debug         = 0;
my $debug_overlap = 0;
my $debug_cluster = 0;    



my @FIELDS =
  qw(fractionID_cutoff length_cutoff cluster_cutoff cluster_len_cutoff min_gi_size);

sub new {
    my ( $class, %arg ) = @_;

    #Bless an anonymous empty hash
    my $self = bless {}, $class;

    #Fill all of the keys with the fields
    foreach (@FIELDS) {
        $self->{$_} = undef;
    }
    #Set Defaults
    
    # minimum size of blast hits
    $self->length_cutoff(700);
    
    # minimum fraction ID
    $self->fractionID_cutoff(0.80);
    
    # maximum distance between clusters
    $self->cluster_cutoff(200);
    
    $self->min_gi_size(8000);
    

    #Set each attribute that is given as an arguement (overiding any defaults)
    foreach ( keys(%arg) ) {
        $self->$_( $arg{$_} );
    }
    
    # minimum size of cluster (use half size of island, see blast_filter())
    $self->cluster_len_cutoff($self->min_gi_size()/2);
    
    return $self;
}



# blast_filter():
# ARGS: $island_length		Length of the island (used only for %coverage)
#	@unfiltered		Unfiltered blast hits
# RETU: @temp			Filtered blast hits
# DESC: Filters blast hits based on length, fractionID, overlaps, and clusters.
sub blast_filter {

	my ( $self, $island_size, @unfiltered ) = @_;
	my @temp = ();


	if ( scalar(@unfiltered) == 0 ) {
		return @temp;
	}

	@temp = sort { $a->start <=> $b->start } @unfiltered;

	@temp = $self->length_filter( $self->length_cutoff(), @temp );

	@temp = $self->fractionID_filter(@temp);

	@temp = $self->overlap_filter(@temp);

	@temp = $self->cluster(@temp);

	@temp = $self->length_filter( $self->cluster_len_cutoff(), @temp );

	return @temp;
}

# length_filter():
# ARGS: $min_length		Minimum hit length
#	@unfiltered		Unfiltered blast hits
# RETU: @temp			Filtered blast hits
# DESC: Removes blast hits below length '$min_length', returns filtered hits
sub length_filter {
	my ( $self,$min_length, @unfiltered ) = @_;
	
	my @filtered = ();

	if ( scalar(@unfiltered) == 0 ) {
		return @filtered;
	}

	foreach my $hit (@unfiltered) {
		if ( $hit->length >= $min_length ) {
			push( @filtered, $hit );
		}
	}
	return @filtered;
}

# fractionID_filter():
# ARGS: @unfiltered		Unfiltered blast hits
# RETU: @temp			Filtered blast hits
# DESC: Removes blast hits below fractionID '$fractionID_cutoff', returns filtered hits
sub fractionID_filter {

	my ($self,@unfiltered) = @_;
	my @filtered   = ();

	if ( scalar(@unfiltered) == 0 ) {
		return @filtered;
	}

	foreach my $hit (@unfiltered) {
		if ( $hit->frac_id > $self->fractionID_cutoff() ) {
			push( @filtered, $hit );
		}
	}
	return @filtered;
}

# fractionID_filter():
# ARGS: @unfiltered		Unfiltered blast hits
# RETU: @temp			Filtered blast hits
# DESC: Removes overlapping blast hits and adds new blast hit that represents
#	the union of the two.  Returns filtered blast hits.
sub overlap_filter {
	my ($self,@unfiltered) = @_;
	my $overlap    = 1;
	my @a          = ();
	my $start      = -1;
	my $end        = -1;

	if ( scalar(@unfiltered) == 0 ) {
		return @a;
	}

	for ( my $i = 0 ; $i < scalar(@unfiltered) ; $i++ ) {
		my $count = $i + 1;
		while ( ( $overlap == 1 ) && ( $count < scalar(@unfiltered) ) ) {
			( $start, $end ) = overlap( $unfiltered[$i], $unfiltered[$count] );
			if ( ( $start > -1 ) && ( $end > -1 ) ) {
				splice( @unfiltered, $count, 1 );
				if (    ( $start != $unfiltered[$i]->start )
					 || ( $end != $unfiltered[$i]->end ) )
				{
					$unfiltered[$i]->start($start);
					$unfiltered[$i]->end($end);
					$unfiltered[$i]->length( $end - $start + 1 );
					$unfiltered[$i]->score(0);
					$unfiltered[$i]->frac_id(0);
				}
			} else {
				$overlap = 0;
				$count++;
			}
		}
		$overlap = 1;
	}
	return @unfiltered;
}

# overlap():
# ARGS: $hit1		First blast hit object
#	$hit2		Second blast hit object
# RETU: $min_start	Minimum start coordinate of first and second hit
# 	$max_end	Maximum end coordinate of first and second hit
# DESC: If blast hits overlap, return minimum start coordinate and max
#	end coordinate.  If blast hits do not overlap, return (-1,-1)
sub overlap {
	my $hit1      = undef;
	my $hit2      = undef;
	my $min_start = -1;
	my $max_end   = -1;
	( $hit1, $hit2 ) = @_;

	if ($debug_overlap) { print "Hit 1: " . $hit1->toString; }
	if ($debug_overlap) { print "Hit 2: " . $hit2->toString; }

	if ( $hit2->start <= $hit1->end ) {
		if ($debug_overlap) { print "OVERLAP FOUND\n"; }
		$min_start = minimum( $hit1->start, $hit2->start );
		$max_end   = maximum( $hit1->end,   $hit2->end );
		return ( $min_start, $max_end );
	} else {
		return ( -1, -1 );
	}
}

# cluster():
# ARGS: @temp 		Unfiltered blast hits
# RETU: @temp		Filtered blast hits
# DESC: Iterate through all blast hits, if two blast hits with distance
#	'$cluster_len' or less between them, cluster the two hits together.
sub cluster {
	my ($self,@temp)        = @_;
	my $continue    = 1;
	my $start       = -1;
	my $end         = -1;
	my $cluster_len = 0;

	if ( scalar(@temp) == 0 ) {
		return ();
	}

	for ( my $i = 0 ; $i < scalar(@temp) ; $i++ ) {
		my $j = $i + 1;
		while ( ( $continue == 1 ) && ( $j < scalar(@temp) ) ) {
			( $start, $end ) = $self->difference( $temp[$i], $temp[$j] );
			if ( ( $start > -1 ) && ( $end > -1 ) ) {
				splice( @temp, $j, 1 );
				$temp[$i]->start($start);
				$temp[$i]->end($end);
				$temp[$i]->length( $end - $start + 1 );
				$temp[$i]->score(0);
				$temp[$i]->frac_id(0);
				$cluster_len = $temp[$i]->length();
			} else {
				$continue = 0;
				$j++;
			}
		}
		$continue = 1;
	}
	return @temp;
}

# difference():
# ARGS: $hit1		First blast hit object
#	$hit2		Second blast hit object
# RETU: $min_start	Minimum start coordinate of $hit1 and $hit2
#	$max_end	Maxmium end coordinate of $hit1 and $hit2
# DESC: If blast hits are less the '$cluster_len' apart, return minimum start
#	coordinate and max end coordinate.  If blast hits do not overlap,
#	return (-1,-1).
sub difference {
	my $hit1      = undef;
	my $hit2      = undef;
	my $min_start = -1;
	my $max_end   = -1;
	my $diff      = -1;
	my ($self, $hit1, $hit2 ) = @_;

	if ($debug_cluster) { print "Hit 1: " . $hit1->toString; }
	if ($debug_cluster) { print "Hit 2: " . $hit2->toString; }

	$diff = $hit2->start - $hit1->end;
	if ($debug_cluster)             { print "Difference: $diff \n"; }
	if ( $diff <= $self->cluster_cutoff() ) {
		if ($debug_cluster) { print "Clustering fragments...\n"; }
		$min_start = minimum( $hit1->start, $hit2->start );
		$max_end   = maximum( $hit1->end,   $hit2->end );
		return ( $min_start, $max_end );
	} else {
		return ( -1, -1 );
	}
}

# minimum():
# ARGS: $x	value 1
#	$y	value 2
# RETU: The minimum of $x and $y
# DESC: Calculates the minimum value of $x and $y and returns it
sub minimum {
	my $x;
	my $y;
	( $x, $y ) = @_;
	if ( $x < $y ) {
		return $x;
	} else {
		return $y;
	}
}

# minimum():
# ARGS: $x	value 1
#	$y	value 2
# RETU: The maximum of $x and $y
# DESC: Calculates the maximum value of $x and $y and returns it
sub maximum {
	my $x;
	my $y;
	( $x, $y ) = @_;
	if ( $x < $y ) {
		return $y;
	} else {
		return $x;
	}
}

# print_hits():
# ARGS: @b_hits		Stores all Blast_hit objects
# RETU: None
# DESC: Prints all Blast_hit objects in @b_hits
sub print_hits {
	my @b_hits = @_;
	my $count  = 0;

	if ( scalar(@b_hits) > 0 ) {
		foreach my $hit (@b_hits) {
			print "[$count] ";
			print $hit->toString();
			$count++;
		}
	}
}

END { }

1;
