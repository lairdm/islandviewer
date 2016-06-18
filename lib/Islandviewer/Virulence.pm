=head1 NAME

    Islandviewer::Virulence

=head1 DESCRIPTION

    Object to calculate virulence factors

=head1 SYNOPSIS

    use Islandviewer::Virulence;

    $vir_obj = Islandviewer::Virulence->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80});

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Dec 12, 2013

=cut

package Islandviewer::Virulence;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use Data::Dumper;

use Islandviewer::DBISingleton;
use Islandviewer::IslandFetcher;
use Islandviewer::AnnotationTransfer;

use Islandviewer::GenomeUtils;

use MicrobedbV2::Singleton;

my $cfg; my $logger; my $cfg_file;

my $module_name = 'Virulence';

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;
    $cfg_file = File::Spec->rel2abs(Islandviewer::Config->config_file);

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};

    die "Error, you must specify a microbedb version"
	unless($args->{microbedb_ver});
    $self->{microbedb_ver} = $args->{microbedb_ver};

    # If we're told to process only specific modules, remember that
    if($args->{modules}) {
	$logger->trace("Only doing virulence for module(s): " . Dumper($args->{modules}));
	$self->{modules} = $args->{modules};
    }

    $logger->trace("Created Virulence object using microbedb_version " . $self->{microbedb_ver});
    
}

sub run {
    my $self = shift;
    my $accnum = shift;
    my $callback = shift;

    # Call with optional arguments
    my $islands = $callback->fetch_islands(($self->{modules} ? $self->{modules} : undef));

    my $genes = $self->run_virulence($accnum, $islands);

    $callback->record_genes($genes);

    eval {
        $logger->info("Creating AnnotationTransfer object");
        my $transfer_obj = Islandviewer::AnnotationTransfer->new({ microbedb_ver => $self->{microbedb_ver}, 
                                                                   workdir => $self->{workdir} });

        my $comparison_genomes = $transfer_obj->run($accnum);
        $logger->debug("Received back comparison genomes: " . Dumper($comparison_genomes));

        if(@{$comparison_genomes}) {
            my $args = {'transfer_genomes' => $comparison_genomes };
            $logger->trace("Updating module argument with: " . Dumper($args));
            $callback->update_args($args, $module_name);
        }
    };
    if($@) {
        # This won't be a fatal error
        $logger->error("We have an issue with the annonation transfer: $@");
    }

    return 1;
}

sub run_virulence {
    my $self = shift;
    my $rep_accnum = shift;
    my $islands = shift;

    # We're given the rep_accnum, look up the files
#    my ($name, $filename, $format_str) = $self->lookup_genome($rep_accnum);
    my $genome_obj = Islandviewer::GenomeUtils->new({microbedb_ver => $self->{microbedb_ver} });
    my($name,$filename,$format_str) = $genome_obj->lookup_genome($rep_accnum);

    unless($filename) {
	$logger->logdie("Error, couldn't find genome file for accnum $rep_accnum");
    }

    $logger->trace("For accnum $rep_accnum found: $name, $filename, $format_str");

    my $fetcher_obj = Islandviewer::IslandFetcher->new({islands => $islands});

    my $genes = $fetcher_obj->fetchGenes("$filename.gbk");

    return $genes;
}

sub find_island_genes {
    my $self = shift;
    
}

# Lookup an identifier, determine if its from microbedb
# or from the custom genomes.  Return a package of
# information such as the base filename
# We allow to say what type it is, custom or microbedb
# if we know, to save a db hit

sub lookup_genome {
    my $self = shift;
    my $rep_accnum = shift;
    my $type = (@_ ? shift : 'unknown');

    unless($rep_accnum =~ /\D/ || $type eq 'microbedb') {
    # If we know we're not hunting for a microbedb genome identifier...
    # or if there are non-digits, we know custom genomes are only integers
    # due to it being the autoinc field in the CustomGenome table
    # Do this one first since it'll be faster

	# Only prep the statement once...
	unless($self->{find_custom_name}) {
	    my $dbh = Islandviewer::DBISingleton->dbh;

	    my $sqlstmt = "SELECT name, filename,formats from CustomGenome WHERE cid = ?";
	    $self->{find_custom_name} = $dbh->prepare($sqlstmt) or 
		die "Error preparing statement: $sqlstmt: $DBI::errstr";
	}

	$self->{find_custom_name}->execute($rep_accnum);

	# Do we have a hit? There should only be one row,
	# its a primary key
	if($self->{find_custom_name}->rows > 0) {
	    my ($name,$filename,$formats) = $self->{find_custom_name}->fetchrow_array;
            # Expand filename
	    if($filename =~ /{{.+}}/) {
		$filename =~ s/{{([\w_]+)}}/$cfg->{$1}/eg;
	    }

	    return ($name,$filename,$formats);
	}
    }    

    unless($type  eq 'custom') {
    # If we know we're not hunting for a custom identifier    

        my $microbedb = MicrobedbV2::Singleton->fetch_schema;
	
        my $rep_results = $microbedb->resultset('Replicon')->search( {
            rep_accnum => $rep_accnum,
            version_id => $self->{microbedb_ver}
                                                                  }
            )->first;
	
	# We found a result in microbedb
	if( defined($rep_results) ) {

	    return ($rep_results->definition, File::Spec->catpath(undef, $rep_results->genomeproject->gpv_directory, $rep_results->file_name), $rep_results->file_types);
	}
    }

    # This should actually never happen if we're
    # doing things right, but handle it anyways
    return ('unknown',undef,undef);

}
