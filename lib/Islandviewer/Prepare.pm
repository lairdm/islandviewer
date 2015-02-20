=head1 NAME

    Islandviewer::Prepare

=head1 DESCRIPTION

    Object to setup an Islandviewer job, including prepare
    the various input files and run an alignment against
    a reference genome if needed

=head1 SYNOPSIS

    use Islandviewer::Prepare;

    $prepare_obj = Islandviewer::Prepare->new({workdir => '/tmp/workdir',
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
use Islandviewer::ContigAligner;

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

    # First we need to validate and see if we need to merge in
    # the fna file's sequences
    my $contigs;
    eval {
	$contigs = $genome_utils->read_and_check( $genome_obj );
#	$contigs = $genome_utils->read_and_check( $genome_obj->filename() );

    };
    if($@) {
	$logger->warn("Received an exception when checking genome " . $genome_obj->cid() . ", " . $genome_obj->filename() . ": $@");

	# The only allowed error being thrown is MISSINGSEQ, as in
	# the sequence isn't in the genbank/embl file but we have
	# it in an fna file. If that's the case, build a new
	# genbank/embl file with the sequence information, otherwise
	# die to our parent.

	$logger->error("Error checking the sequence, this shouldn't have happened! $@");
	$genome_obj->update_status('INVALID');
	return 0;
    }

    # If our checking detected we're missing the sequence and we
    # need to integrate it from the fna, try to do so.
    if($genome_obj->genome_status() eq 'MISSINGSEQ') {
	$logger->info("We noticed the genome is missing sequence information, trying to integrate...");
	my $res = $genome_utils->integrate_sequence($genome_obj);
	
	if($res) {
	    $logger->trace("Looks good, sequence information was integrated");
	    $genome_obj->genome_status("READY");
	} else {
	    $logger->error("Merging the sequnce from the fna file failed for some reason");
	    $genome_obj->genome_status('INVALID');
	    return 0;
	}
    }

    # Then we need to do the alignment against a reference genome if needed/requested
    # and build the single input genome to send to the pipeline
    if($contigs > 1) {
	$logger->trace("$contigs contigs found, we better have an alignment genome!");

	unless($self->{ref_accnum}) {
	    $logger->error("We have multiple contigs but no genome to align against, error! " . $genome_obj->cid());
	    return 0;
	}

	# Align the contigs against the reference genome
	$logger->trace("Trying to align " . $genome_obj->cid() . " against " . $self->{ref_accnum});
	$callback->set_module_status("RUNNING", 'ContigAligner');
	my $res;
	eval {
	    my $contig_aligner = Islandviewer::ContigAligner->new( { microbedb_ver => $self->{microbedb_ver},
								     ref_accnum => $self->{ref_accnum},
								     workdir => $self->{workdir} } );
							       
	    $res = $contig_aligner->run($accnum, $callback);

	    # We need to recalculate the stats now that we've combined
	    # the contigs
	    $logger->trace("Fetching genome stats");
	    my $stats = $genome_obj->genome_stats( $genome_obj->filename() );

	    foreach my $key (keys $stats) {
		$logger->trace("For file " . $genome_obj->filename . " found $key: " . $stats->{$key});
		$genome_obj->$key($stats->{$key});
	    }

	    # And save the updates...
	    $self->update_genome();
	};
	if($@) {
	    $logger->error("Error running ContigAligner sub-module: $@");
	    $callback->set_module_status("ERROR", 'ContigAligner');
	    return 0;
	}
	unless($res) {
	    $logger->error("Contig aligner against reference genome " . $self->{ref_accnum} . " failed");
	    $callback->set_module_status("ERROR", 'ContigAligner');
	    return 0;
	}

	$callback->set_module_status("COMPLETE", 'ContigAligner');
    }

    # Finally...
    # Check the file formats and rebuild them if needed, fail if we can't
    $logger->trace("Validating file types for genome");
    if(! $genome_utils->validate_types($genome_obj) ) {
	$logger->error("We weren't able to validate and generate the needed file types, we can't proceed");
	$genome_obj->genome_status('INVALID');
	return 0;
    }

    # We're going to do the GC calculation here now instead of on submission
    eval {
	$logger->trace("Calculating gc for genome " . $genome_obj->cid);
	$genome_utils->insert_gc( $genome_obj );
    };
    if($@) {
	$logger->error("Unable to calculate gc: $@");
	return 0;
    }

    return 1;

}

1;
