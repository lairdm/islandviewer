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
use Islandviewer::Analysis;

use Net::ZooKeeper::WatchdogQueue;

use MicrobeDB::Versions;

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
    unless($cfg->{expected_exts} eq $genome_obj->find_file_types()) {
	$logger->error("Error, we don't have the correct file types, we can't continue, have \"" . $genome_obj->find_file_types() . "\", expecting \"$cfg->{expected_exts}\"");
	return 0;
    }

    # We put it in the database
    my $cid = $genome_obj->insert_custom_genome();

    # Now we need to move things in to place, so we're nice
    # and tidy with our file organization
    unless(mkdir($cfg->{custom_genomes} . "/$cid")) {
	$logger->error("Error, can't make custom genome directory $cfg->{custom_genomes}/$cid: $!");
	return 0;
    }
    unless($genome_obj->move_and_update($cid, $cfg->{custom_genomes} . "/$cid")) {
	$logger->error("Error, can't move files to custom directory for cid $cid");
    }

    # We're ready to go... return our new cid
    return $cid;
}

# We're trying to keep things abstract as possible
# but at some level someone has to know about all
# the pipeline components, its not this guy.

sub submit_analysis {
    my $self = shift;
    my $cid = shift;
    my $args = shift;

    # If we've been given a microbedb version AND its valid...
    # Yes we do this in Analysis too, but I didn't think through we need
    # the version when looking up microbedb genomes in a GenomeUtil object
    # Create a Versions object to look up the correct version
    my $versions = new MicrobeDB::Versions();

    my $microbedb_ver;
    if($args->{microbedb_ver} && $versions->isvalid($args->{microbedb_ver})) {
	$microbedb_ver = $args->{microbedb_ver}
    } else {
	$microbedb_ver = $versions->newest_version();
    }

    my $genome_obj = Islandviewer::GenomeUtils->new({microbedb_ver => $microbedb_ver });

    my($name, $base_filename, $types) = $genome_obj->lookup_genome($cid);

    $logger->trace("For cid $cid we found filenames $name, $base_filename, $types");
    unless($base_filename) {
	$logger->error("Error, we couldn't find cid $cid");
	return 0;
    }

    # Sanity checking, did we get all the correct types?
    unless($cfg->{expected_exts} eq $genome_obj->find_file_types()) {
	# We need to regenerate the files
	$logger->trace("We don't have all the file types we need, only have: " . $genome_obj->find_file_types());
	unless($genome_obj->regenerate_files()) {
	    # Oops, we weren't able to regenerate for some reason, failed
	    $logger->error("Error, we don't have the needed files, we can't do an alaysis");
	    return 0;
	}
    }    

    # Ensure we have our GC values calculated and ready to go
    $genome_obj->insert_gc($cid);

    # We should be ready to go, let's submit our analysis!
    my $analysis_obj = Islandviewer::Analysis->new({workdir => $cfg->{analysis_directory}});
    my $aid;

    eval {
	$aid = $analysis_obj->submit($genome_obj, $args);
    };
    if($@) { 
	$logger->error("Error, we couldn't submit the analysis: $@");
	return 0;
    }

    return $aid;
}

sub run {
    my $self = shift;
    my $aid = shift;
    my $module = shift;

    # Create our watchdog so observers can keep an eye
    # on our status
    my $watchdog = new Net::ZooKeeper::WatchdogQueue($cfg->{zookeeper},
						     $cfg->{zk_analysis});

    my $analysis_obj = Islandviewer::Analysis->new({workdir => $cfg->{analysis_directory}, aid => $aid});

    my $ret;
    eval {
	$watchdog->create_timer("$aid.$module");
	$ret = $analysis_obj->run($module);
    };
    if($@) {
	$logger->error("Error running module $module: $@");
	return 0;
    }

    return $ret;
}

1;
