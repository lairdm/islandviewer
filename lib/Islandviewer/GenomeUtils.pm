=head1 NAME

    Islandviewer::Islandpick::GenomeUtils

=head1 DESCRIPTION

    Object to load, convert and store custom genomes in to
    the internal formats needed by IslandViewer

    Most of this code is cut and pasted from Morgan's
    original run_custom_islandviewer.pl script, just updating it to match
    the overall style of the updated IslandViewer.

=head1 SYNOPSIS

    use Islandviewer::Islandpick::GenomeUtils;

    my $genome_obj = Islandviewer::Islandpick::GenomeUtils->new(
                                           { workdir => '/tmp/dir/'});

    # $genome_name optional name, will be custom_genome otherwise
    $genome_obj->read_and_convert($filename, $genome_name);

    my $success = $genome_obj->insert_custom_genome();

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Oct 30, 2013

=cut

package Islandviewer::Islandpick::GenomeUtils;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);

use Islandviewer::DBISingleton;

use Bio::SeqIO;
use Bio::Seq;

my $cfg; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified: $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};

}

# Read in a genbank or Embl file and convert it to
# the other needed formats
#
# Puts the resulting files in the same directory
# as the input genome
#
# Most code recycled from run_custom_islandviewer.pl
# function gbk_or_embl_to_other_formats

sub read_and_convert {
    my $self = shift;
    my $filename = shift;
    my $genome_name = (@_ ? shift : 'custom_genome');

    #seperate extension from filename
    my ( $file, $extension ) = $filename =~ /(.+)\.(\w+)/;

    $logger->debug("From filename $filename got $file, $extension");

    my $in;

    if ( $extension =~ /embl/ ) {

	$in = Bio::SeqIO->new(
	    -file   => $filename,
	    -format => 'EMBL'
	    );
	$logger->info("The genome sequence in $filename has been read.");
    } elsif ( ($extension =~ /gbk/) || ($extension =~ /gb/) ) {
	$in = Bio::SeqIO->new(
	    -file   => $filename,
	    -format => 'GENBANK'
	    );
	$logger->info("The genome sequence in $filename has been read.");
    } else {
	$logger->logdie("Can't figure out if file is genbank (.gbk) or embl (.embl)");
    }

    while ( my $seq = $in->next_seq() ) {
	my $out;    
	if ( $extension =~ /embl/ ) {
	    $out = Bio::SeqIO->new(
		-file   => ">" . $file . '.gbk',
		-format => 'GENBANK'
		);
	} elsif ( ($extension =~ /gbk/) || ($extension =~ /gb/) ) {
	    $out = Bio::SeqIO->new(
		-file   => ">" . $file . '.embl',
		-format => 'EMBL'
		);
	} else {
	    $logger->logdie("Can't figure out if file is genbank (.gbk) or embl (.embl)");
	}

	my $faa_out = Bio::SeqIO->new(
	    -file   => ">" . $file . '.faa',
	    -format => 'FASTA'
	    );
	my $ffn_out = Bio::SeqIO->new(
	    -file   => ">" . $file . '.ffn',
	    -format => 'FASTA'
	    );
	my $fna_out = Bio::SeqIO->new(
	    -file   => ">" . $file . '.fna',
	    -format => 'FASTA'
	    );

	open( my $PTT_OUT, '>', $file . '.ptt' );

	my $total_length = $seq->length();
	my $total_seq    = $seq->seq();

	my $success = 0;

	#Create gbk or embl file
	$success = $out->write_seq($seq);
	if ($success == 0) {		
	    $logger->error(".gbk or .embl file is not generated successfully.");
	}

	#Create fna file
	$success = $fna_out->write_seq($seq);
	if ($success == 0) {		
	    $logger->error(".fna file is not generated successfully.");
	}

	#Only keep those features coding for proteins
	my @cds = grep { $_->primary_tag eq 'CDS' } $seq->get_SeqFeatures;

	#Remove any pseudogenes
	my @tmp_cds;
	foreach (@cds) {
	    unless ( $_->has_tag('pseudo') ) {
		push( @tmp_cds, $_ );
	    }
	}
	@cds = @tmp_cds;

	my $num_proteins = scalar(@cds);

	#Create header for ptt file
	print $PTT_OUT $seq->description, " - 1..", $seq->length, "\n";
	print $PTT_OUT $num_proteins, " proteins\n";
	print $PTT_OUT join(
	    "\t", qw(Location Strand Length PID Gene Synonym Code COG
			  Product)
	    ),
	    "\n";

	my $count = 0;

	#Step through each protein
	foreach my $feat (@cds) {
	    $count++;

	    #Get the general features
	    my $start  = $feat->start;
	    my $end    = $feat->end;
	    my $strand = $feat->strand;
	    my $length = $feat->length;

	    if ($length <= 2) {
		throw Bio::Root::Exception("Something's wrong with one of the protein sequences! CDS info: start=$start end=$end strand=$strand");
	    }

	    #Get more features associated with gene (not all of these will neccesarily exist)
	    my ( $product, $protein_accnum, $gene_name, $locus_tag ) =
		( '', '', '', '' );
	    ($product) = $feat->get_tag_values('product')
		if $feat->has_tag('product');
	    ($protein_accnum) = $feat->get_tag_values('protein_id')
		if $feat->has_tag('protein_id');
	    ($gene_name) = $feat->get_tag_values('gene')
		if $feat->has_tag('gene');
	    ($locus_tag) = $feat->get_tag_values('locus_tag')
		if $feat->has_tag('locus_tag');

	    my $gi = $count;
	    $gi = $1 if tag( $feat, 'db_xref' ) =~ m/\bGI:(\d+)\b/;

	    my $strand_expand  = $strand >= 0 ? '+' : '-';
	    my $strand_expand2 = $strand >= 0 ? ''  : 'c';
	    my $desc = "\:$strand_expand2" . "$start-$end";

	    $desc = "gi\|$gi\|" . $desc;

	    #Create the ffn seq
	    my $ffn_seq = $seq->trunc( $start, $end );
	    if ( $strand == -1 ) {
		$ffn_seq = $ffn_seq->revcom;
	    }
	    $ffn_seq->id($desc);
	    $ffn_seq->desc($product);
	    $success = $ffn_out->write_seq($ffn_seq);
	    if ($success == 0) {		
		$logger->error(".ffn file is not generated successfully.");
	    }	

	    #Create the faa seq
	    my $faa_seq;
	    if ( $feat->has_tag('translation') ) {
		my ($translation) = $feat->get_tag_values('translation');
		$faa_seq = new Bio::Seq( -seq => $translation ) or throw Bio::Root::Exception("Cannot read protein sequence: $!");
	    } else {
		$faa_seq =
		    $ffn_seq->translate( -codontable_id => 11, -complete => 1 );
	    }

	    $faa_seq->id($desc);
	    $faa_seq->desc($product);
	    $success = $faa_out->write_seq($faa_seq);
	    if ($success == 0) {
		$logger->error(".faa file is not generated successfully.");
	    }

	    #Print out ptt line
	    my $cog = '-';
	    $cog = $1 if tag( $feat, 'product' ) =~ m/^(COG\S+)/;
	    my @col = (
		$start . '..' . $end,
		$strand_expand,
		( $length / 3 ) - 1,
		$gi,
		tag( $feat, 'gene' ),
		tag( $feat, 'locus_tag' ),
		'-',
		$cog,
		tag( $feat, 'product' ),
		);
	    print $PTT_OUT join( "\t", @col ), "\n";

	    #load annotation into microbedb
#	    insert_record(
#		'gene',
#		{
#		    version_id     => 0,
#		    rpv_id         => $rpv_id,
#		    gpv_id         => $gpv_id,
#		    protein_accnum => $protein_accnum,
#		    pid            => $gi,
#		    gene_start     => $start,
#		    gene_end       => $end,
#		    gene_length    => $length,
#		    gene_strand    => $strand_expand,
#		    gene_name      => $gene_name,
#		    locus_tag      => $locus_tag,
#		    gene_product   => $product,
#		    gene_seq       => $ffn_seq->seq(),
#		    protein_seq    => $faa_seq->seq(),
#		}
#		);
	}    #end of foreach

#	update_record(
#	    'replicon',
#	    { rpv_id => $rpv_id },
#	    {
#		cds_num    => $num_proteins,
#		rep_size   => $total_length,
#		rep_seq    => $total_seq,
#		file_types => '.gbk .fna .faa .ffn .ptt .embl',
#	    }
#	    );

	# Save the details of the file we just loaded
	$self->{name} = $genome_name;
	$self->{num_proteins} = $num_proteins;
	$self->{total_length} = $total_length;
	$self->{base_filename} = $file;
	$self->{ext} = $extension;
	$self->{orig_filename} = $filename;
	$self->{genome_read} = 1;

	close($PTT_OUT);
    }    #end of while
    
}    #end of gbk_or_embl_to_other_formats

sub insert_custom_genome {
    my $self = shift;

    # If we're trying to insert the genome without
    # calling read_and_convert first, fail
    return 0 unless($self->{genome_read});

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $sqlstmt = "INSERT INTO CustomGenome (name, cds_num, rep_size, filename, formats) VALUES (?, ?, ?, ?, ?)";
    my $insert_genome = $dbh->prepare($sqlstmt) or 
	die "Error preparing statement: $sqlstmt: $DBI::errstr";

    $insert_genome->execute($self->{name}, $self->{num_proteins}, 
			    $self->{total_length}, $self->{base_filename},
			    '.gbk .fna .faa .ffn .ptt .embl');

    my $cid = $dbh->last_insert_id(undef, undef, undef, undef);
    unless($cid) {
	$logger->error("Error inserting custom genome $self->{base_filename}");
	return 0;
    }

    $self->{rep_accnum} = $cid;

    return $cid;
}

#used to create ptt file
sub tag {
	my ( $f, $tag ) = @_;
	return '-' unless $f->has_tag($tag);
	return join( ' ', $f->get_tag_values($tag) );
}

1;
