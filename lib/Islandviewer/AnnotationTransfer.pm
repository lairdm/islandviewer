=head1 NAME

    Islandviewer::AnnotationTransfer

=head1 DESCRIPTION

    Object to run the annotation transfer on a genome from
    similar genomes within the same family

=head1 SYNOPSIS

    use Islandviewer::AnnotationTransfer;

    $annotationtransfer_obj = Islandviewer::AnnotationTransfer->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80});

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    July 22, 2015

=cut

package Islandviewer::AnnotationTransfer;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use File::Spec;

use Data::Dumper;

use Bio::SeqIO; 

use Islandviewer::DBISingleton;
use Islandviewer::Genome_Picker;
use Islandviewer::GenomeUtils;
use Islandviewer::Blast;

use MicrobedbV2::Singleton;

my $module_name = 'AnnotationTransfer';

my $logger; my $cfg;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    $self->{microbedb_ver} = (defined($args->{microbedb_ver}) ?
			      $args->{microbedb_ver} : undef );

    unless($self->{microbedb_ver}) {
	my $microbedb = MicrobedbV2::Singleton->fetch_schema;
	$self->{microbedb_ver} = $microbedb->latest();
	
	$logger->info("Microbedb version not defined, using latest: " . $self->{microbedb_ver})
    }

    $self->{ref_accnum} = (defined($args->{ref_accnum}) ?
			      $args->{ref_accnum} : undef );
    
    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};
    
}

sub run {
    my $self = shift;
    my $accnum = shift;
    my $callback = shift;

    # Find all the comparison genomes within the approved distance and
    # who's names match the criteria
    my $comparison_genomes = $self->find_comparison_genomes($accnum);

    # And now start blasting and transfering the annotations
    foreach my $ref_accnum (@$comparison_genomes) {
	$self->transfer_single_genome($accnum, $ref_accnum);
    }

}

# Find all the genomes we want to transfer annotations from

sub find_comparison_genomes {
    my $self = shift;
    my $accnum = shift;

    # Get a GenomeUtils object so we can do lookups
    my $genome_utils = Islandviewer::GenomeUtils->new({microbedb_ver => $self->{microbedb_ver} });
    
    $logger->debug("Finding candidate genomes for accnum $accnum");
    
    # We're going to reuse the genome picker code for finding candidates
    my $picker_obj = Islandviewer::Genome_Picker->new({workdir => $self->{workdir},
						       microbedb_ver => $self->{microbedb_ver},
						       MIN_CUTOFF => 0,
						       MAX_CUTOFF => 0.3 });

    my $dists = $picker_obj->find_distance_range($accnum);

    # Find ourself and then filter down our name for the comparison step
    my $genome_obj = $genome_utils->fetch_genome($accnum);
    unless($genome_obj->genome_status() eq 'READY') {
	$logger->error("Failed in fetching genome object for $accnum");
	return 0;
    }

    # Stash the name of the main genome object
    my $definition = $self->filter_name($genome_obj->name());
    $logger->info("Our shortened name: $definition");

    my $dbh = Islandviewer::DBISingleton->dbh;
    my $check_curated = $dbh->prepare("SELECT rep_accnum FROM virulence_curated_reps WHERE rep_accnum=?");

    # Now the real work, go through the candidates and see if they match the 
    # name patterns we're allowing
    my @run_shortlist;
    foreach my $cur_accnum (keys %{$dists}) {
	$logger->info("Examining: $cur_accnum, dist: " . $dists->{$cur_accnum});

	$check_curated->execute($cur_accnum);
	unless(my @row = $check_curated->fetchrow_array) {
	    $logger->info("Not in curated set, skipping");
	    next;
	}

	my $cur_genome_obj = $genome_utils->fetch_genome($cur_accnum);
	unless($cur_genome_obj->genome_status() eq 'READY') {
	    $logger->error("Failed in fetching genome object for $cur_accnum");
	    next;
    }

	# Grab and shorten the name of our current candidate
	my $cur_def = $self->filter_name($cur_genome_obj->name());
	$logger->info("Candidate's name: $cur_def");

	my $okay = $self->check_names_match($definition, $cur_def);
	
	if($okay) {
	    push @run_shortlist, $cur_accnum;
	    $logger->info("Name passes, using $cur_accnum for transfer");
	}
    }

    return \@run_shortlist;
}

sub transfer_single_genome {
    my $self = shift;
    my $accnum = shift;
    my $ref_accnum = shift;

    # Get a GenomeUtils object so we can do lookups
    my $genome_utils = Islandviewer::GenomeUtils->new({microbedb_ver => $self->{microbedb_ver} });

    my $query_file = $self->make_vir_fasta($ref_accnum);

    # Fetch the referencd genome object, and fasta file
    my $ref_genome_obj = $genome_utils->fetch_genome($ref_accnum);
    unless($ref_genome_obj->genome_status() eq 'READY') {
	$logger->logdie("Failed in fetching genome object for $ref_accnum, this shouldn't happen!");
    }

    my $ref_filename = $ref_genome_obj->filename() . '.faa';
    $logger->trace("Fasta file for ref genome $ref_accnum should be: $ref_filename");
    unless(-f $ref_filename) {
        $logger->logdie("Error, can't find file for ref genome $ref_accnum: $ref_filename");
    }

    my $blast_obj = new Islandviewer::Blast({microbedb_ver => $self->{microbedb_ver},
                                             workdir => $self->{workdir},
                                             db => $ref_filename,
                                             query => $query_file,
                                             evalue => 1e-10,
                                             outfmt => 6,
                                             seg => 'no',
                                             K => 3
                                            }
        );

    my $vir_hits = $blast_obj->run($query_file, $ref_filename);

    print Dumper $vir_hits;


}

# Find all the virulence genes and write them out of a fasta file

sub make_vir_fasta {
    my $self = shift;
    my $accnum = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;

    # Get a GenomeUtils object so we can do lookups
    my $genome_utils = Islandviewer::GenomeUtils->new({microbedb_ver => $self->{microbedb_ver} });

    # Find ourself and then filter down our name for the comparison step
    my $genome_obj = $genome_utils->fetch_genome($accnum);
    unless($genome_obj->genome_status() eq 'READY') {
	$logger->error("Failed in fetching genome object for $accnum, this shouldn't happen!");
	return undef;
    }
    
    my $find_vir_genes = $dbh->prepare("SELECT virulence.protein_accnum, virulence.external_id, virulence.source, virulence.flag, virulence.pmid, Genes.start, Genes.end, Genes.strand  from virulence, Genes where Genes.ext_id = ? AND Genes.name = virulence.protein_accnum AND virulence.type='virulence' AND virulence.source!='BLAST' and virulence.source!='PAG'");

    $find_vir_genes->execute($accnum);

    # Make a temporary file and a fasta file for the virulence sequences
    my $query_file = $self->_make_tempfile();
    my $out = Bio::SeqIO->new(-file => ">$query_file" ,
				  -format => 'Fasta');
    $logger->trace("Making temporary fasta file $query_file");
	
    while(my @row = $find_vir_genes->fetchrow_array) {
	# Fetch the sequence from the fna file
	my $seq = $genome_utils->fetch_protein_seq($genome_obj, $row[7], $row[5], $row[6]);

	my @display_id = ("ref|" . $row[0] . "|ext_id|" . $row[1] . "|source|" . $row[2]);
	if($row[3]) {
	    push @display_id, "flag|" . $row[3];
	}
	if($row[4]) {
	    push @display_id, "pmid|" . $row[4];
	}
	my $display = join '|', @display_id;

	my $pseq = Bio::PrimarySeq->new(
	    -display_id => $display, 
	    -seq => $seq,
	    -alphabet => 'protein');

	$out->write_seq($pseq);
	
    }

    return $query_file;
}

# Little helper to shorten the genome name of the pieces
# we don't want

sub filter_name {
    my $self = shift;
    my $name = shift;

    $name =~ s/ chromosome, complete genome.//;
    $name =~ s/, complete sequence.//;
    $name =~ s/, complete genome.//;
    $name =~ s/plasmid.+//;

    return $name;

}

# Filter to see if the name matches between the two
# genomes using our fragile filtering criteria

sub check_names_match {
    my $self = shift;
    my $def = shift;
    my $sub_def = shift;

    $logger->trace("[$def] vs [$sub_def]");

    my $okay = 0;

    if ($sub_def =~ /^Escherichia coli/){
	if ($sub_def =~/Escherichia coli str. (.+) substr.+/){
	    my $str = $1;
	    if ($def =~ /Escherichia coli str. (.+) substr.+/){
		if ($1 eq $str){
		    $okay = 1;
		}
	    }
	}
	elsif ($sub_def =~ /Escherichia coli (.+)str. (.+)/){
	    my $str = $1;
	    if ($def =~ /Escherichia coli (.+)str. (.+)/){
		if ($1 eq $str){
		    $okay = 1;
		}
	    }
	}
	elsif ($sub_def =~ /Escherichia coli (.+)/){
	    my $str = $1;
	    if ($def =~ /Escherichia coli (\.+)/){
		if ($1 eq $str){
		    $okay = 1;
		}
	    }
	}
    }
    elsif ($sub_def =~ /(.+)subsp\. (.+)serovar (\w+).+/){
	my $genussp = $1;
	my $subsp = $2;
	my $serovar = $3;
	if ($def =~ /(.+)subsp\. (.+)serovar (\w+).+/){
	    if ($1 eq $genussp && $2 eq $subsp && $3 eq $serovar){
		$okay = 1;
	    }
	}
    }	
    elsif ($sub_def =~ /(.+)subsp\. (.+) .+/){
	my $genussp = $1;
	my $subsp = $2;
	if ($def =~ /(.+)subsp\. (.+) .+/){
	    if ($1 eq $genussp && $2 eq $subsp){
		$okay = 1;
	    }
	}
			
    }			
    elsif($sub_def =~ /(.+)pv\. (.+) .+/){
	my $genussp = $1;
	my $pavar = $2;
	if ($def =~ /(.+)pv\. (.+) .+/){
	    if ($1 eq $genussp && $2 eq $pavar){
		$okay = 1;
	    }
	}
	
    }
    elsif ($sub_def =~ /(\w+) (\w+) .+/){
	my $genus = $1;
	my $species = $2;
	if ($def =~ /(\w+) (\w+) .+/){
	    if ($1 eq $genus && $2 eq $species){
		$okay = 1;
	    }
	}
    }

    return $okay;

}

# Make a temp file in our work directory and return the name

sub _make_tempfile {
    my $self = shift;

    # Let's put the file in our workdir
    my $tmp_file = mktemp(File::Spec->catpath(undef, $self->{workdir}, "blasttmpXXXXXXXXXX"));
    
    # And touch it to make sure it gets made
    `touch $tmp_file`;

    return $tmp_file;
}

1;
