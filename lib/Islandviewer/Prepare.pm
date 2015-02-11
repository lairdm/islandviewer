=head1 NAME

    Islandviewer::Prepare

=head1 DESCRIPTION

    Object to setup an Islandviewer job, including prepare
    the various input files and run an alignment against
    a reference genome if needed

=head1 SYNOPSIS

    use Islandviewer::Prepare;

    $vir_obj = Islandviewer::Prepare->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80});

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Feb 6, 2015

=cut

package Islandviewer::Prepare;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use Data::Dumper;

use Islandviewer::DBISingleton;
use Islandviewer::GenomeUtils;

my $cfg; my $logger; my $cfg_file;

my $module_name = 'Prepare';

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    $self->{microbedb_ver} = (defined($args->{microbedb_ver}) ?
			      $args->{microbedb_ver} : undef );

    $self->{ref_accnum} = (defined($args->{ref_accnum}) ?
			      $args->{ref_accnum} : undef );
    
    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};
    
}

# We're going to need to do a few things here.
#
# Make the required file formats if they don't
# exist.
# Run an alignment against a reference genome
# if requested, then build the concatonated
# input file(s) for running the pipeline.

sub run {
    my $self = shift;
    my $accnum = shift;
    my $callback = shift;

    unless($self->{microbedb_ver}) {
	$logger->error("Error, microbedb version wasn't set on object initialization");
	return 0;
    }

    my $genome_utils = Islandviewer::GenomeUtils->new({microbedb_ver => $self->{microbedb_ver} });
    my $genome_obj = $genome_utils->fetch_genome($accnum);

    # Check the file formats and rebuild them if needed, fail if we can't
    $logger->trace("Validating file types for genome");
    if(! $genome_obj->validate_types($genome_obj) ) {
	$logger->error("We weren't able to validate and generate the needed file types, we can't proceed");
	$genome_obj->genome_status('INVALID');
	return 0;
    }

    # We're going to do the GC calculation here now instead of on submission
    eval {
	$genome_obj->insert_gc( $genome_obj );
    };
    if($@) {
	$logger->error("Unable to calculate gc");
	return 0;
    }

    return 1;
    # We'll deal with the alignment stuff later

    # If we've been given a reference genome to run an alignment against...
    if($self->{ref_accnum}) {

	my $contig_aligner = Islandviewer::ContigAligner->new( { microbedb_ver => $self->{microbedb_ver},
								 ref_accnum => $self->{ref_accnum} } );
							       
	my $res = $contig_aligner->run($accnum, $callback);

	unless($res) {
	    $logger->error("Contig aligner against reference genome " . $self->{ref_accnum} . " failed");
	}
    }

    return 1;
}

1;
