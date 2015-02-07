=head1 NAME

    Islandviewer::CustomGenome

=head1 DESCRIPTION

    Object for holding and managing a custom genome

=head1 SYNOPSIS

    use Islandviewer::CustomGenome;


=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    February 4, 2015

=cut

package Islandviewer::CustomGenome;

use strict;
use warnings;
use Log::Log4perl;
use Data::Dumper;
use Moose;
use Moose::Util::TypeConstraints;
use Carp qw( confess );
use Islandviewer::DBISingleton;

has cid => (
    is     => 'rw',
    isa    => 'Str',
    default => 0
);

has genome_type => (
    is     => 'rw',
    isa    => enum([qw(microbedb custom)]),
    default => 'microbedb'
);

has name => (
    is     => 'rw',
    isa    => 'Str'
);

has owner_id => (
    is     => 'rw',
    isa    => 'Int'
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
    isa    => 'Int'
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

    if($args->{load}) {
	$self->loadGenome($args->{load});
    } else {
	$self->genome_status('NEW');
    }
}

sub loadGenome {
    my $self = shift;
    my $cid = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $sqlstmt = qq{SELECT name, owner_id, cds_num, rep_size, filename, formats, contigs, genome_status FROM CustomGenome WHERE cid = ?};
    my $fetch_cg = $dbh->prepare($sqlstmt) or die "Error preparing statement: $sqlstmt: $DBI::errstr";

    $logger->debug("Fetching custom genome [$cid]");
    $fetch_cg = execute($cid);

    if(my $row = $fetch_job->fetchrow_hashref) {
	# Load the pieces
	for my $k (keys %$row) {
	    if($row->{$k}) {
		$self->$k($row->{$k});
	    }
	}
    }

    $self->cid($cid);
}

sub validate {
    my $self = shift;
    my $args = shift;

    # If we're brand new, there better be a genome file (genbank or embl)
    # for us to use. Save it to disk, save ourselves to the db,
    # and we become unconfirmed
    if($self->genome_status eq 'NEW') {
	unless($args->{genome_data} && $args->{genome_format}) {
	    $logger->logdie("No genome data given, this is a failure [NOGENOMEDATA]");
	}

	$self->filename( $self->write_genome($args->{genome_data}, $args->{genome_format}) );
	$self->genome_status('UNCONFIRMED');
	$self->save_genome();
    }

    # Alright, this will catch both a new genome that's transitioned
    # in to an unconfirmed, and a returning call with updated fna
    # file info
    if($self->genome_status eq 'UNCONFIRMED' || $self->genome_status eq 'MISSINGSEQ') {
	if($args->{fna_data}) {
	    $self->write_genome($args->{fna_data}, 'fna');
	} elsif($self->genome_status eq 'MISSINGSEQ') {
	    # We were in MISSINGSEQ and didn't find an fna_data?
	    # Uh-oh, that's not good.

	    # Signal that we need an fna file
	    $logger->logdie("We don't have sequence information and were't given an fna, file " . $self->filename . " [NOSEQNOFNA]");
	}

	# We should be ready to try to validate...
	my $genome_obj = Islandviewer::GenomeUtils->new(
	{ workdir => $cfg->{workdir} });

	# What happens when we check the file...
	my $contigs;
	eval{ 
	    $contigs = $genome_obj->read_and_check($self->filename);
	};
	if($@) {
	    if($@ =~ /FILEFORMATERROR/) {
		$self->genome_status('INVALID');
#		$self->update_genome();
		$logger->logdie("Invalid file format for file " . $self->filename ." [FILEFORMATERROR]");
	    } elsif($@ =~ /NOSEQFNA/) {
		$self->genome_status('INVALID');
#		$self->update_genome();
		$logger->logdie("Missing sequenceinformation for file " . $self->filename . ", FNA file was found [NOSEQFNA]");
	    } elsif($@ =~ /NOSEQNOFNA/) {
		$self->genome_status('MISSINGSEQ');
#		$self->update_genome();
		$logger->logdie("Missing sequence information for file " . $self->filename . ", FNA file was not found [NOSEQNOFNA]");
	    } elsif($@ =~ /NOCDSRECORDS/) {
		$self->genome_status('INVALID');
#		$self->update_genome();
		$logger->logdie("Missing cds records for file " . $self->filename . " [NOCDSRECORDS]");		
	    }
	}

	# Some sanity checking in case they upload
	# a genome with zero contigs...
	unless($contigs > 0) {
	    $self->genome_status('INVALID');
#	    $self->update_genome();
	    $logger->logdie("Invalid file format for file " . $self->filename ." [FILEFORMATERROR]");
	}

	$self->contigs($contigs);
	$self->genome_status('VALID');
#	$self->update_genome();

    }

}

sub scan_genome {
    my $self = shift;

    # We only allow scanning of the genome if we're in a state of READY
    unless($self->genome_status eq 'READY') {
	$logger->trace("Genome " . $self->cid . " not READY, bailing");
	return 0;
    }

    # Make a GenomeUtils objects to do the work
    my $genome_obj = Islandviewer::GenomeUtils->new(
	{ workdir => $cfg->{workdir} });

    # Find the file types, set the second parameter to true
    # to return an array instead of a string.
    $self->formats( $genome_obj->find_file_types($self->filename, 1) );
    $logger->trace("For " . $self->cid . " found file formats: " . $self->formats());

    # Next we need to scan the file to find CDS numbers and total length


    # And save the updates...
    $self->update_genome();

    return 1;
}

sub write_genome {
    my $self = shift;
    my $genome_data = shift;
    my $genome_format = shift;

    my $decoded_genome_data = urlsafe_b64decode($genome_data);

    # Write out the genome file
    my $base_tmp_file;

    if($self->filename) {
	$logger->trace("Found an existing filename: " . $self->filename);
	$base_tmp_file = $self->filename;
    } else {
	$base_tmp_filename = mktemp($cfg->{tmp_genomes} . "/custom_XXXXXXXXX");
#    push @tmpfiles, $tmp_file;
    }

    $logger->trace("Using filename: $tmp_file");
    $tmp_file = $base_tmp_file . ".$genome_format";

    open(TMP_GENOME, ">$tmp_file") or 
	$logger->logdie("Error, can't create tmpfile $tmp_file: $@");

    print TMP_GENOME $decoded_genome_data;

    close TMP_GENOME;

    return $base_tmp_file
}

sub save_genome {
    my $self = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my ($params, $values) = $self->build_params();

    my $sqlstmt = qq{INSERT INTO CustomeGenome (} . join(',', @$params) . ") VALUES (" . join( ',', ('?') x @values ) . ')';

    my $insert_cg = $dbh->prepare($sqlstmt) or die "Error preparing statement: $sqlstmt: $DBI::errstr";
    
    $insert_cg->execute(@$values);

    my $cid = $dbh->last_insert_id( undef, undef, undef, undef );

    $self->cid($cid);

    return $cid;
}

sub update_genome {
    my $self = shift;

    # If we haven't saved the genome already we can't do an update
    return unless($self->cid);

    my $dbh = Islandviewer::DBISingleton->dbh;

    my ($params, $values) = $self->build_params();

    my $sqlstmt = qq{REPLACE INTO CustomeGenome (cid, } . join(',', @$params) . ") VALUES (?," . join( ',', ('?') x @values ) . ')';

    my $insert_cg = $dbh->prepare($sqlstmt) or die "Error preparing statement: $sqlstmt: $DBI::errstr";

    unshift @$values, $self->cid;

    my $res = $insert_cg->execute(@$values);

    $logger->trace("Updated " . $self->cid . " results: $res");

}

sub build_params {
    my $self = shift;

    my @params; my @values;

    if($self->name) {
	push @params, 'name';
	push @values, $self->name;
    }

    if($self->owner_id) {
	push @params, 'owner_id';
	push @values, $self->owner_id;
    }

    if($self->cds_num) {
	push @params, 'cds_num';
	push @values, $self->cds_num;
    }

    if($self->rep_size) {
	push @params, 'rep_size';
	push @values, $self->rep_size;
    }

    if($self->filename) {
	push @params, 'filename';
	my $path = Islandviewer::Config->shorten_directory($self->filename);

	push @values, $path;
    }

    if($self->formats) {
	push @params, 'formats';
	push @values, join( ' ', sort $self->formats);
    }

    if($self->contigs) {
	push @params, 'contigs';
	push @values, $self->contigs;
    }

    if($self->genome_status) {
	push @params, 'genome_status';
	push @values, $self->genome_status;
    }

    return (\@params, \@values);
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
