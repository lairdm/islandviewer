=head1 NAME

    Islandviewer::Islandpick::BlastIslands

=head1 DESCRIPTION

    Object to blast the putative islands and filter them down

    Most of this code is cut and pasted from Morgan's
    original blast_islands.pl script, just updating it to match
    the overall style of the updated IslandViewer.

=head1 SYNOPSIS

    use Islandviewer::Islandpick::BlastIslands;

    my $filter_obj = Islandviewer::Islandpick::BlastIslands->new(
                                           { workdir => '/tmp/dir/',
                                             island_size => 4000 });

    $filtered_coords = $filter_obj->run($blast_db, 
                                        $rep_filename, @island_coords);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Oct 30, 2013

=cut

package Islandviewer::Islandpick::BlastIslands;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);

use Bio::Tools::Run::StandAloneBlast;
use Bio::SearchIO;
use Bio::SeqIO;
use Bio::Seq;

use Islandviewer::Islandpick::BlastHit;
use Islandviewer::Islandpick::BlastFilter;

my $cfg; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};

    # Set default island size
    $self->{island_size} = 4000;

    # Set each attribute that is given as an arguement
    foreach ( keys(%{$args}) ) {
	$self->{$_} = $args->{$_};
    }

    # And let's setup our enviromental variables in
    # preparation for the blasting
    $ENV{'BLASTDIR'} = $cfg->{blastdir};
    $ENV{'BIOPATH'} = $cfg->{blastdir};
    unless($ENV{'PATH'} =~ /$cfg->{blastdir}/) {
	$ENV{'PATH'} .= ":$cfg->{blastdir}";
    }

}

# We're changing from a stand alone script to a module,
# here we'll pass in the island coordinates and do
# the blast filtering.

sub run {
    my $self = shift;
    my $blast_db = shift;
    my $rep_filename = shift;
    my @islands = @_;

    # We should have been given the fna file for the
    # original query sequence
    my $in = Bio::SeqIO->new(-file => $rep_filename,
			     -format => 'Fasta');
    my $rep_seq = $in->next_seq();

    # Run through the putative island coordinates
    my @unique_regions_with_seq;
    foreach my $coordinates (@islands) {
	# Just for readability, mark down the coordinates
	my $start = $coordinates->[0];
	my $end   = $coordinates->[1];

	# Fetch the sub sequence for this island
	my $seq = $rep_seq->subseq($start,$end);
	push( @unique_regions_with_seq, [ $start, $end, $seq ] );

    }

    # Now we're going to blast our sequences against the db we were given
    if(scalar(@unique_regions_with_seq) > 0) {
	my @all_islands = $self->blast_sequences($blast_db, @unique_regions_with_seq);

	return $self->produce_islands(@all_islands);
    } else {
	$logger->debug("No islands to blast against");
	return ();
    }

}

sub blast_sequences {
    my $self = shift;
    my $blast_db = shift;
    my @unfiltered_islands = @_;

    my @all_islands;

    # For each of our candidate islands we're
    # going to blast it
    foreach(@unfiltered_islands) {
	my $offset = $_->[0];
	my $end = $_->[1];
	my $nuc = $_->[2];
	my $seq = new Bio::Seq(-display_id =>"$offset,$end", -seq => $nuc);
		
	my $island_size = $seq->length;
		
	my $isl_name ="";

	my @params = ('program' => $cfg->{ip_blastprog}, 
		      'database' => $blast_db,
		      'e' => $cfg->{ip_e_cutoff});

	# And blast the sequence...
	my $blast = Bio::Tools::Run::StandAloneBlast->new(@params);
	my $blast_report = $blast->blastall($seq);

	while ( my $result = $blast_report->next_result() ) { # blast hits for each island
	    my $num_hits = 0;
	    my @islands =();
	    my @blast_hits =();
	    while( my $hit = $result->next_hit) {
		while (my $hsp = $hit->next_hsp) {
		    my $bhit = $self->createNewBlastHit($hit->name,$hsp);
		    push (@blast_hits, $bhit);
		    $num_hits++;
		}
	    }
	    if ($num_hits == 0) { 
		@islands = getIslandCoords($offset, $isl_name, $island_size, ());
	    }else {
		my $filter_obj = new Islandviewer::Islandpick::BlastFilter(min_gi_size => $min_island_size);
		@blast_hits = $filter_obj->blast_filter($island_size,@blast_hits);
		@islands = getIslandCoords($offset, $isl_name, $island_size, @blast_hits);
				
		#TODO:Make sure each island is still over the minimum GI size
				
	    }
	    push (@all_islands, @islands);
	}
    }

    #system("rm $db*");

    return (@all_islands);


    }
    
}

sub create_blast_db {
    my $self = shift;
    my $joint_fna_file = shift;
    my @fna_files = @_;

    # Make one big fasta file
    system("cat @genomes > $joint_fna_file");

    system("$cfg->{formatdb} -i $joint_fna_file -p F");
}

sub produce_islands {
    my $self = shift;
    my @islands = @_;

    my @sets;
    foreach(@unique_regions){
	my $start = $_->{begin} + $_->{offset};
	my $end = $_->{end} + $_->{offset};
	push @sets, [$start,$end];
    }

    return @sets
}

# createNewBlastHit(): 
# ARGS: $name	Name of the organism
#	$hsp	Bioperl hsp object
# RETU: $bit	A new Blast_hit object
# DESC: Stores information of a single blast hit and returns it.
sub createNewBlastHit {
    (my $self, $name, my $hsp) = @_;
    my $bhit = new Islandviewer::Islandpick::Blast_hit;

    $bhit->start($hsp->query->start);
    $bhit->end($hsp->query->end);
    $bhit->length($hsp->length);
    $bhit->score($hsp->score);
    $bhit->frac_id($hsp->frac_identical);
    $bhit->name($name);

    return $bhit;
}

# getIslandCoords(): 
# ARGS: $offset		Offset of the island in the organism nucleotide sequence
#	$isl_name	Name of the organism
#	$isl_size	Size of the island
#	@b_hits		Array containing all Blast_hit objects
# RETU: @island_coords	Array containing all new island coordinates
# DESC: Calculate coordinates of islands after removing portions of the island
#	that have a blast hit against
sub getIslandCoords {

    my ($self, $offset, $isl_name, $isl_size, @b_hits) = @_;
    my $begin = 0;
    my $end = undef;
    my $diff = undef;
    my @island_coords = ();

    my $num_hits = scalar(@b_hits);
    

    for (my $i = 0; $i <= $num_hits; $i++) {	
	my $hit = $b_hits[$i];
	if ($i == $num_hits) {
	    $end = $isl_size;
	}
	else {
	    $end = $hit->start;
	}

	$diff = $end - $begin;
	if ($diff > $min_island_size) {
	    my $seq_start = $begin + $offset;
	    my $seq_end = $end + $offset;
	    my %isl = ();
	    $isl{begin} = $begin;
	    $isl{end} = $end;
	    $isl{offset} = $offset;
	    $isl{len} = $diff;
	    $isl{name} = $isl_name;
	    push (@island_coords, \%isl);
	    
	}
	if ($i !=$num_hits) {
	    $begin = $hit->end;
	}
    }
    return @island_coords;
}


1;
