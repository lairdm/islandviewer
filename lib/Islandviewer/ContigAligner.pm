=head1 NAME

    Islandviewer::ContigAligner

=head1 DESCRIPTION

    Object to run the Mauve contig aligner on a custom
    genome against a given reference genome either from
    microbedb or a custom uploaded genome

=head1 SYNOPSIS

    use Islandviewer::ContigAligner;

    $contigaligner_obj = Islandviewer::ContigAligner->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80});

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Feb 13, 2015

=cut

package Islandviewer::ContigAligner;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use File::Copy;
use Set::IntervalTree;
use Data::Dumper;
use File::Path qw(remove_tree);

use Islandviewer::DBISingleton;
use Islandviewer::GenomeUtils;

my $cfg; my $logger; my $cfg_file;

my $module_name = 'ContigAligner';

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

sub run {
    my $self = shift;
    my $accnum = shift;
    my $callback = shift;

    unless($self->{microbedb_ver}) {
	$logger->error("Error, microbedb version wasn't set on object initialization");
	return 0;
    }

    # Get a GenomeUtils object so we can do lookups
    my $genome_utils = Islandviewer::GenomeUtils->new({microbedb_ver => $self->{microbedb_ver} });

    # First we need to fetch our own genome object, a fairly
    # important thing...
    my $genome_obj;
    unless($genome_obj = $genome_utils->fetch_genome($accnum)) {
	$logger->error("Failed in fetching genome object for $accnum");
	return 0;
    }
    $self->{genome_obj} = $genome_obj;

    # Next, we need to fetch our reference genome to use
    my $ref_genome_obj;
    unless($ref_genome_obj = $genome_utils->fetch_genome( $self->{ref_accnum} )) {
	$logger->error("Failed to fetch reference genome: " . $self->{ref_accnum});
	return 0;
    }
    $self->{ref_genome_obj} = $ref_genome_obj;

    # Move the genome file to _raw, if needed.  Doing it this way
    # so the module is idempotent
    $self->rename_genomes();

    # Get all the sequences, we'll need this for regenerating the fna
    # file as well as for remapping the final contig alignment
    my $seqs = $self->read_seq_file($self->{genome_obj}->filename());

    # We don't trust the fna file, if there is one, that it has
    # the correct identifiers for later, just's just make our own
    $self->regenerate_fna($seqs);

    # We need to run our contig move now against the reference genome
    unless($self->runContigMover()) {
	$logger->error("Contig mover run failed");
	return 0;
    }

    # Read the backbone file and store the tree of range mappings
    my $tree = $self->read_backbone_file( $self->find_by_extension($self->{alignment_dir},
								   'backbone') );

    $self->{tree} = $tree;

    my $contigs = $self->read_order_file( $self->find_by_extension($self->{alignment_dir},
								   'tab') );
    
    # Space the contigs out with 1000 bp between each
    $contigs = $self->space_contigs($contigs, 1000);

    # Find the regions that are aligned against the reference
    # and those which aren't
    my $alignments = $self->annotate_alignment($contigs);

    # Record these aligned and unaligned regions
    $callback->record_islands("Alignments", @$alignments);

    # We should be ready to write out the realigned genbank
    # file for the genome, yes we're going to pick
    # genbank sepcifically.
    my $outfile = $self->{genome_obj}->filename() . '.gbk';
    my $gaps = $self->write_genome($outfile, $contigs, $seqs);

    # Record the gaps as islands
    $callback->record_islands("Contig_Gap", @$gaps);
    
    return 1;
}

sub runContigMover {
    my $self = shift;

    # We need an output directory for the output alignments
    my $alignment_dir = $self->{workdir} . '/alignments';
    $logger->info("Making contig mover workdir: $alignment_dir");
    mkdir $alignment_dir;
    unless(-d $alignment_dir) {
	$logger->error("Couldn't make contig mover output directory: $!");
	return 0;
    }

    my $draft_genome = $self->{genome_obj}->filename() . '_raw.fna';
    my $reference_genome = $self->{ref_genome_obj}->filename() . '.gbk';

    if(-f $draft_genome &&
       -s $draft_genome) {
	$logger->info("Using draft genome file: $draft_genome");
    } else {
	$logger->error("Can't find needed draft genome file $draft_genome");
	return 0;
    }

    if(-f $reference_genome &&
       -s $reference_genome) {
	$logger->info("Using draft genome file: $reference_genome");
    } else {
	$logger->error("Can't find needed draft genome file $reference_genome");
	return 0;
    }

    # Build the contig mover command
    my $cmd = "cd " . $cfg->{mauve_dir} . ';';
    $cmd .= $cfg->{java_bin} . ' ' . sprintf($cfg->{contig_mover_cmd}, $alignment_dir, 
		      $reference_genome, $draft_genome) . " &>$alignment_dir/alignment.log";

    $logger->trace("Using contig mover command: $cmd");

    my $ret = system($cmd);

    if($ret) {
	$logger->error("We received a non-zero exit code, something went wrong [$ret]");
	return 0;
    }

    if(my $alignment_output_dir = $self->find_alignment_dir($alignment_dir)) {

	$self->{alignment_dir} = $alignment_output_dir;
	return 1;
    }

    $logger->error("Failed to find alignment dir in $alignment_dir?");
    return 0;    

}

# Read either the genbank or embl file
# and return the sequence objects in a
# hash with the access as the key
sub read_seq_file {
    my $self = shift;
    my $base_filename = shift;

    my $filename; my $format;
    # Check if an embl or genbank file exists for this genome
    if(-f $base_filename . '_raw.gbk' &&
       -s $base_filename . '_raw.gbk') {
	$logger->info("We seem to have a genbank file, preferred format");
	$filename = $base_filename . '_raw.gbk';
	$format = 'genbank';
    } elsif(-f $base_filename . '_raw.embl' &&
	    -s $base_filename . '_raw.embl') {
	$logger->info("We seem to have a embl file");
	$filename = $base_filename . '_raw.embl';
	$format = 'EMBL';
    } else {
	$logger->logdie("Can't find file format for $base_filename, this is very bad");
    }

    my $in = Bio::SeqIO->new(
	-file => $filename,
	-format => $format
	);

    my $seqs;
    my $contig_count = 1;

    while( my $seq = $in->next_seq() ) {
	my $name = sprintf("Contig%03d", $contig_count);

	# We can't trust the user's Accession and Locus, we need
	# to just make out own for the integrating, not as nice.
	$seqs->{ $name } = $seq;
	$logger->info("We're mapping " . $seq->accession_number . "," . $seq->display_id() . "to contig name $name");

	# We're going to check what identifiers we
	# have any pick the best available...

#	if($seq->accession_number) {
#	    $seqs->{ $seq->accession_number } = $seq;
#	} elsif($seq->display_id()) {
#	    $seqs->{ $seq->display_id() } = $seq;
#	} else {
#	    $logger->logdie("We can't find a valid identifier for this sequence, fail!");
#	}

	$contig_count += 1;
    }

    return $seqs;
}

sub regenerate_fna {
    my $self = shift;
    my $seqs = shift;

    my $filename = $self->{genome_obj}->filename() . '_raw.fna';

    if(-f $filename &&
       -s $filename) {
	$logger->warn("fna file $filename exists, clobbering");
    }

    my $out = Bio::SeqIO->new(
	-file => ">$filename",
	-format => "FASTA"
	) or $logger->logdie("Can't open fna file $filename for writing: $!");

    for my $seqid (keys %{$seqs}) {
	$logger->trace("Writing contig: $seqid");

	# Set the display id so we're sure to have the
	# correct identifier in the fna file
	$seqs->{$seqid}->display_id($seqid);

	$out->write_seq($seqs->{$seqid});
    }

}

sub write_genome {
    my $self = shift;
    my $filename = shift;
    my $contigs = shift;
    my $seqs = shift;

    $logger->info("Creating new combined genbank file");

    # We make this empty first one so the
    # process is non-destructive on any of
    # the sequences
    my $new_seq = Bio::Seq->new(-alphabet => 'dna');
    my @seqs = ( $new_seq );
    my $curr_bp = 1;
    
    # We're going to want to track the gaps so
    # we can add these as islands
    my @gaps;

    for my $contig (@{$contigs}) {
	$logger->trace("Processing contig " . $contig->{id});
	my $gap = $contig->{start} - $curr_bp;

	# If there's a gap between where we currently
	# are int eh new genome and the current contig,
	# build and insert a gap sequence
	if($gap) {
	    $logger->trace("Adding gap between contigs of $gap");
	    push @seqs, Bio::Seq->new(-seq => ('N' x $gap),
				     -alphabet => 'dna');

	    # Track the gap, this will be an "island"
	    # in the display
	    push @gaps, [$curr_bp,
			 ($curr_bp + $gap)];

	}

	# And push the sequence in, we know this should
	# work because we made both the input fna and the
	# seqs data structure using the same identifiers
	if($contig->{strand} == -1) {
	    $logger->trace("Adding revcom for contig " . $contig->{id});
	    push @seqs, Bio::SeqUtils->revcom_with_features( $seqs->{ $contig->{id} } );
	} else {
	    $logger->trace("Adding forward contig " . $contig->{id});
	    push @seqs, $seqs->{ $contig->{id} };
	}

	# And move the current bp to just beyond the
	# end of the current contig
	$curr_bp = $contig->{end} + 1;
    }

    # Push all the sequences together
    $logger->trace("Concating the sequences together now");
    Bio::SeqUtils->cat(@seqs);

    $logger->trace("Writing sequence to genbank file $filename");
    my $out = Bio::SeqIO->new(
	-file => ">$filename",
	-format => "Genbank"
	) or $logger->logdie("Error opening output genbank file $filename");

    # And write the concatanated sequence, done.
    $out->write_seq($new_seq);

    return \@gaps;
}

sub rename_genomes {
    my $self = shift;

    my $base_filename = $self->{genome_obj}->filename();

    for my $ext (qw{embl gbk fna}) {
	if(-f $base_filename . '_raw.' . $ext &&
	   -s $base_filename . '_raw.' . $ext) {
	    $logger->trace("Raw file " . $base_filename . '_raw.' . $ext . " exists, doing nothing");
	    next;
	}

	if(-f $base_filename . ".$ext" &&
	   -s $base_filename . ".$ext") {
	    $logger->trace("File " .  $base_filename . ".$ext exists, moving to _raw");

	    move("$base_filename.$ext", "$base_filename" . "_raw.$ext");

	}
    }
}

sub read_order_file {
    my $self = shift;
    my $order_file = shift;

    unless(-f $order_file &&
	   -s $order_file) {
	$logger->logdie("Can't read contig order file $order_file");
    }

    $logger->trace("Reading order file $order_file");

    open(ORDER, "$order_file") or
	$logger->logdie("Error opening order file $order_file: $!");

    my $start_reading = 0;
    my @contigs;
    while(<ORDER>) {
	chomp;
	# Go until we hit the section header we want
	if(/^Ordered Contigs/) {
	    $start_reading = 1;
	    # Read an extra line because of the table header
	    <ORDER>;
	    next;
	}
	if($start_reading) {

	    # If we're reading then hit a blank line, we're done
	    if(/^$/) {
		last;
	    }

	    # Now the meat of reading out lines
	    $logger->trace("Found contig ordering: $_");
	    my @pieces = split /\s+/;

	    # Check the alignment tree from the backbone file and see
	    # if our contig maps to the genome
	    my $aligned = scalar(@{$self->{tree}->fetch($pieces[4], $pieces[5])}) ? 1 : 0;

	    push @contigs, { id => $pieces[1], 
			     start => $pieces[4],
			     end => $pieces[5],
			     strand => ($pieces[3] eq 'complement' ? -1 : 1),
			     aligned => $aligned
	    };
	}
	
    }

    close ORDER;

    return \@contigs;
}

sub annotate_alignment {
    my $self = shift;
    my $contigs = shift;

    my $max = 100000000;
    my $start_aligned = $max;
    my $end_aligned = -1;
    my $start_unaligned = $max;
    my $end_unaligned = -1;
    for my $contig (@{$contigs}) {
	if($contig->{aligned}) {
	    $logger->trace("Aligned contig: " . $contig->{start} . ', ' . $contig->{end});
	    $start_aligned = $contig->{start} if($contig->{start} < $start_aligned);
	    $end_aligned = $contig->{end} if($contig->{end} > $end_aligned);
	} else {
	    $logger->trace("Unaligned contig: " . $contig->{start} . ', ' . $contig->{end});
	    $start_unaligned = $contig->{start} if($contig->{start} < $start_unaligned);
	    $end_unaligned = $contig->{end} if($contig->{end} > $end_unaligned);
	}
    }

    my @alignments;

    $logger->trace("Aligned: $start_aligned, $end_aligned; Unaligned: $start_unaligned, $end_unaligned");

    # If we actually found a region, because the coordinates would be
    # different, push it on to this "island"
    unless($start_aligned == $max && $end_aligned == -1) {
	$logger->debug("Found aligned region: $start_aligned, $end_aligned");
	push @alignments, [$start_aligned, $end_aligned, 'aligned'];
    }

    unless($start_unaligned == $max && $end_unaligned == -1) {
	$logger->debug("Found unaligned region: $start_unaligned, $end_unaligned");
	push @alignments, [$start_unaligned, $end_unaligned, 'unaligned'];
    }

    return \@alignments;
}

# Take a contig set, as returned by read_order_file, and
# add a gap of $gap_size between each contig.  This function
# is destructive on the input $contigs pointer

sub space_contigs {
    my $self = shift;
    my $contigs = shift;
    my $gap_size = shift;

    $logger->trace("Spacing contigs back to back");

    my $loop_counter = 0;

    for my $contig (@{$contigs}) {
	my $gap = $gap_size * $loop_counter;
	$logger->trace("Adding contig: " . $contig->{start} . ',' . $contig->{end} . " (gap: $gap)");
	$contig->{start} += $gap;
	$contig->{end} += $gap;

	$logger->trace("New coordinates: " . $contig->{start} . ',' . $contig->{end});
	$loop_counter += 1;
    }

    return $contigs;
}

sub read_backbone_file {
    my $self = shift;
    my $backbone_file = shift;

    unless(-f $backbone_file) {
	$logger->logdie("Error, can't find backbone file $backbone_file");
    }

    $logger->trace("Reading backbone file $backbone_file");

    open(BACKBONE, "$backbone_file") or
	$logger->logdie("Can't open backbone file $backbone_file: $!");

    # Skip first line
    <BACKBONE>;

    # Store the ranges in an interval tree for
    # fast lookups
    my $tree = Set::IntervalTree->new;

    while(<BACKBONE>) {
	chomp;
	my @pieces = split /\s+/;

	# If we have a zero in the first coordinate
	# of either mapping, we're done
	last unless($pieces[0] && $pieces[2]);

	# Make all the numbers positive
	@pieces = map { abs($_) } @pieces;

	$tree->insert( {ref_start => $pieces[0], ref_end => $pieces[1]}, $pieces[2], $pieces[3] )
    }

    close BACKBONE;

    return $tree;
}

sub find_alignment_dir {
    my $self = shift;
    my $alignmentdir = shift;

    $logger->trace("Looking for alignment dir in $alignmentdir");

    # We're going to find the directory with the larger number at the
    # end, this is where the final alignment should be found

    opendir(ADIR, $alignmentdir) || $logger->logdie("Can't open directory $alignmentdir: $!");
    my @files = readdir(ADIR);
    closedir(ADIR);

    my $highest = 0;
    my @alignmentdirs;
    foreach my $item (@files) {
	my $full_file = $alignmentdir . '/' . $item;
	$logger->trace("Found dir $item in $full_file");
	# If it doesn't start with "alignment", next
	next unless($item =~ /^alignment/ && -d $full_file);

	my ($i) = $item =~ /alignment(\d+)/;

        push @alignmentdirs, $full_file;

	$logger->trace("Is $i higher than $highest?");
	$highest = $i if($i > $highest);

    }

    if($highest) {
	$logger->trace("Found alignment dir: " . $alignmentdir . "/alignment$highest");
        my $highestalignmentdir = $alignmentdir . "/alignment$highest";

        # We're going to cycle through all the alignment directories we found and
        # clean them up
        for my $dir (@alignmentdirs) {
            # We don't want to remove the directory we're returning
            next if($dir eq $highestalignmentdir);
	    $logger->trace("Removing alignment  directory $dir");
            remove_tree($dir);
        }

	return $highestalignmentdir;
    } else {
	return undef;
    }
}

sub find_by_extension {
    my $self = shift;
    my $directory = shift;
    my $ext = shift;

    opendir(ADIR, $directory) || $logger->logdie("Can't open directory $directory: $!");
    my @files = grep {$_ =~ /$ext$/} readdir(ADIR);
    closedir(ADIR);

    # We're going to be a little lazy and just return the first
    return "$directory/" . shift @files;
#    return "$directory/" .  $files[0];
}

1;
