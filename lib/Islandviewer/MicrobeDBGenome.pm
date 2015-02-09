=head1 NAME

    Islandviewer::MicrobeDBGenome

=head1 DESCRIPTION

    Object for holding and managing a MicrobeDB Genome

=head1 SYNOPSIS

    use Islandviewer::MicrobeDBGenome;


=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    February 8, 2015

=cut

package Islandviewer::MicrobeDBGenome;

use strict;
use warnings;
use Log::Log4perl;
use Data::Dumper;
use Moose;
use Moose::Util::TypeConstraints;
use Carp qw( confess );
use Islandviewer::DBISingleton;

use MicrobeDB::Versions;
use MicrobeDB::Replicon;
use MicrobeDB::Search;

has cid => (
    is     => 'rw',
    isa    => 'Str',
    default => 0
);

has name => (
    is     => 'rw',
    isa    => 'Str'
);

has owner_id => (
    is     => 'rw',
    isa    => 'Int',
    default => 0
);

has cds_num => (
    is     => 'rw',
    isa    => 'Int'
);

has rep_size => (
    is     => 'rw',
    isa    => 'Int'
);

has filename => (
    is     => 'rw',
    isa    => 'Str'
);

subtype 'My::ArrayRef' => as 'ArrayRef';

    coerce 'My::ArrayRef'
        => from 'Str'
        => via { [ split / / ] };

has formats => (
    traits  => ['Array'],
    is      => 'rw',
    isa     => 'My::ArrayRef[Ref]',
    default => sub { [] },
);

has contigs => (
    is     => 'rw',
    isa    => 'Int',
    default => 1
);

has genome_status => (
    is      => 'rw',
    isa     => enum([qw(NEW UNCONFIRMED MISSINGSEQ MISSINGCDS VALID READY INVALID)]),
    default => 'NEW',
    trigger => \&update_genome,
);

my $logger; my $cfg;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $logger = Log::Log4perl->get_logger;

    $cfg = Islandviewer::Config->config;

    # Finding microbedb version
    my $versions = new MicrobeDB::Versions();

    # If we've been given a microbedb version AND its valid... 
    unless($args->{microbedb_ver} && $versions->isvalid($args->{microbedb_ver})) {
	$args->{microbedb_ver} = $versions->newest_version();
    }

    $self->{microbedb_ver} = $args->{microbedb_ver};

    if($args->{load}) {
	$self->loadGenome($args->{load});
    } else {
	$self->genome_status('NEW');
    }

}

sub loadGenome {
    my $self = shift;
    my $accnum = shift;

    # First we find the MicrobeDB record
    # We keep using the microbedb one (for now) because the file location
    # might change with new microbedb versions, so we need to always be able
    # to find it.
    my $sobj = new MicrobeDB::Search();

    my ($rep_results) = $sobj->object_search(new MicrobeDB::Replicon( rep_accnum => $rep_accnum,
#));
								      version_id => $self->{microbedb_ver} ));
	
    # We found a result in microbedb
    if( defined($rep_results) ) {
	# One extra step, we need the path to the genome file
	my $search_obj = new MicrobeDB::Search( return_obj => 'MicrobeDB::GenomeProject' );
	my ($gpo) = $search_obj->object_search($rep_results);

	$self->name( $rep_results->name() );
	$self->cid( $accnum );
	$self->filename( $gpo->gpv_directory() . $rep_results->file_name() );
	$self->cds_num( $rep_results->cds_num() );
	$self->rep_size( $rep_results->length() );
	$self->formats( $rep_results->file_types() );
	$self->contigs ( 1 );
	$self->genome_status( 'READY' );
    }

    # Make a GenomeUtils objects to do the work
    my $genome_obj = Islandviewer::GenomeUtils->new(
	{ workdir => $cfg->{workdir} });

    # Find the file types, set the second parameter to true
    # to return an array instead of a string.
    my $found_formats = $genome_obj->find_file_types($self->filename, 1);

    if( join(' ', sort $self->formats()) ne join(' ', sort $found_formats) ) {
	$logger->warn("Warning, database says we have [" . join(' ', sort $self->formats()) . "] doesn't match file system [" .  join(' ', sort $found_formats) . ']' );
	$self->formats( @$found_formats );
    }

    $logger->trace("For " . $self->cid . " found file formats: " . join(',' , sort $self->formats()) );

    
}

sub update_genome {
    my $self = shift;

    $logger->warn("We don't update MicrobeDB records right now.");
}

sub dump {
    my $self = shift;

    my $json_data;

    $json_data->{cid} = $self->cid;
    $json_data->{name} = $self->name;
    $json_data->{owner_id} = $self->owner_id;
    $json_data->{cds_num} = $self->cds_num;
    $json_data->{rep_size} = $self->rep_size;
    $json_data->{filename} = $self->filename;
    $json_data->{formats} = $self->formats;
    $json_data->{contigs} = $self->contigs;
    $json_data->{genome_status} = $self->genome_status;

    my $json = encode_json($json_data);

    return $json;
}
