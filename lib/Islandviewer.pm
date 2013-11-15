=head1 NAME

    Islandviewer

=head1 DESCRIPTION

    Object for managing islandviewer jobs

=head1 SYNOPSIS

    use Islandviewer;


=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Sept 25, 2013

=cut

package Islandviewer;

use strict;
use Moose;
use Islandviewer::Config;
use Islandviewer::DBISingleton;
use Islandviewer::GenomeUtils;

use Log::Log4perl qw(get_logger :nowarn);

my $cfg; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    # Initialize the configuration file
    Islandviewer::Config->initialize({cfg_file => $args->{cfg_file} });
    $cfg = Islandviewer::Config->config;

    # Initialize the DB connection
    Islandviewer::DBISingleton->initialize({dsn => $cfg->{'dsn'}, 
                                             user => $cfg->{'dbuser'}, 
                                             pass => $cfg->{'dbpass'} });
   
    $logger = Log::Log4perl->get_logger;

}

# Submit a file, it will be a custom genome,
# load it in to the database and ensure
# all needed formats are there

sub submit_and_prep {
    my $self = shift;
    my $file = shift;
    my $genome_name = (@_ ? shift : 'custom_genome');

    $logger->info("Received file $file, checking and loading");
    unless(-f $file && -s $file) {
	$logger->logdie("Error, can't access $file");
    }

    # Make out genomeutils object
    my $genome_obj = Islandviewer::GenomeUtils->new();

    # Load it and ensure we have all the proper formats
    $genome_obj->read_and_convert($file, $genome_name);

    # Sanity checking, did we get all the correct types?
    unless($cfg->{expected_exts} eq $genome_objs->find_file_types()) {
	$logger->error("Error, we don't have the correct file types, we can't continue");
	return 0;
    }

    # We put it in the database
    my $cid = $genome_obj->insert_custom_genome();

    # Now we need to move things in to place, so we're nice
    # and tidy with our file organization
    unless(mkdir($cfg->{custom_genomes} . "/$cid")) {
	$logger->error("Error, can't make custom genome directory: $!");
	return 0;
    }
    unless($genome_obj->move_and_update($cid, $cfg->{custom_genomes} . "/$cid")) {
	$logger->error("Error, can't move files to custom directory for cid $cid");
    }

    # We're ready to go... return our new cid
    return $cid;
}

sub submit_analysis {
    my $self = shift;
    my $cid = shift;
    my $args = shift;


}

1;
