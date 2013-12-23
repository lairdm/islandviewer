=head1 NAME

    Islandviewer::Dimob

=head1 DESCRIPTION

    Object to run Dimob against a given genome

=head1 SYNOPSIS

    use Islandviewer::Dimob;

    $dimob_obj = Islandviewer::Dimob->new({workdir => '/tmp/workdir',
                                           microbedb_version => 80,
                                           MIN_GI_SIZE => 8000});

    $dimob_obj->run_dimob($rep_accnum);
    
=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Nov 10, 2013

=cut

package Islandviewer::Dimob;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use Data::Dumper;

use Islandviewer::DBISingleton;
use Islandviewer::Dimob::genomicislands;
use Islandviewer::Dimob::Mobgene;

use MicrobeDB::Replicon;
use MicrobeDB::Search;

my $cfg; my $logger; my $cfg_file;

my $module_name = 'Dimob';

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

    $self->{MIN_GI_SIZE} = $args->{MIN_GI_SIZE} || $cfg->{MIN_GI_SIZE};
    
}

# The generic run to be called from the scheduler
# magically do everything.

sub run {
    my $self = shift;
    my $accnum = shift;
    my $callback = shift;

    my @islands = $self->run_dimob($accnum);

    if(@islands) {
	# If we get a undef set it doesn't mean failure, just
	# nothing found.  Write the results to the callback
	# if we have any
	if($callback) {
	    $callback->record_islands($module_name, @islands);
	}
    }

    # We just return 1 because any failure for this module
    # would be in the form of an exception thrown.
    return 1;
    
}

sub run_dimob {
    my $self = shift;
    my $rep_accnum = shift;
    my @tmpfiles;

    # We're given the rep_accnum, look up the files
    my ($name, $filename, $format_str) = $self->lookup_genome($rep_accnum);

    unless($filename && $format_str) {
	$logger->error("Error, can't find genome $rep_accnum");
	return ();
    }    

    # To make life easier, break out the formats available
    my $formats;
    foreach (split /\s+/, $format_str) { $_ =~ s/^\.//; $formats->{$_} = 1; }

    # Ensure we have the needed files
    unless($formats->{ffn}) {
	$logger->error("Error, we don't have the needed ffn file...");
	return ();
    }
    unless($formats->{faa}) {
	$logger->error("Error, we don't have the needed faa file...");
	return ();
    }
    unless($formats->{ptt}) {
	$logger->error("Error, we don't have the needed ptt file...");
	return ();
    }

    # We need a temporary file to hold the hmmer output
    my $hmmer_outfile = $self->_make_tempfile();
    push @tmpfiles, $hmmer_outfile;

    # Now the command and database to use....
    my $cmd = $cfg->{hmmer_cmd};
    my $hmmer_db = $cfg->{hmmer_db};
    $cmd .= " $hmmer_db $filename.faa >$hmmer_outfile";
    $logger->debug("Running hmmer command $cmd");
    my $rv = system($cmd);
#	or $logger->logdie("Error runnging hmmer: $!");

#    if($rv != 0) {
#	$logger->logdie("Error running hmmer, rv: $rv");
#    } 

    unless( -s $hmmer_outfile ) {
	$logger->logdie("Error, hmmer output seems to be empty");
    }

    my $mob_list;

    $logger->debug("Parsing hmmer results with Mobgene");
    my $mobgene_obj = Islandviewer::Dimob::Mobgene->new();
#    my $mobgenes = $mobgene_obj->parse_hmmer('/home/lairdm/islandviewer/workdir/dimob//blasttmpoHyYLgBj5w', $cfg->{hmmer_evalue} );
    my $mobgenes = $mobgene_obj->parse_hmmer( $hmmer_outfile, $cfg->{hmmer_evalue} );

    foreach(keys %$mobgenes){
	$mob_list->{$_}=1;   
    }

    #get a list of mobility genes from ptt file based on keyword match
    my $mobgene_ptt = $mobgene_obj->parse_ptt("$filename.ptt");

    foreach(keys %$mobgene_ptt){
	$mob_list->{$_}=1;   
    }

    #calculate the dinuc bias for each gene cluster of 6 genes
    #input is a fasta file of ORF nucleotide sequences
    my $dinuc_results = cal_dinuc("$filename.ffn");
    my @dinuc_values;
    foreach my $val (@$dinuc_results) {
	push @dinuc_values, $val->{'DINUC_bias'};
    }

    #calculate the mean and std deviation of the dinuc values
    my $mean = cal_mean( \@dinuc_values );
    my $sd   = cal_stddev( \@dinuc_values );

    #generate a list of dinuc islands with ffn fasta file def line as the hash key
    my $gi_orfs = dinuc_islands( $dinuc_results, $mean, $sd, 8 );

    #convert the def line to gi numbers (the data structure is maintained)
    my $dinuc_islands = defline2gi( $gi_orfs, "$filename.ptt" );

    #check the dinuc islands against the mobility gene list
    #any dinuc islands containing >=1 mobility gene are classified as
    #dimob islands
    my $dimob_islands = dimob_islands( $dinuc_islands, $mob_list );

    my @gis;
    foreach (@$dimob_islands) {

	#get the pids from the  for just the start and end genes
	push (@gis, [ $_->[0]{start}, $_->[-1]{end}]);
	#my $start = $_->[0]{start};
	#my $end = $_->[-1]{end};
 
	#print "$start\t$end\n";
    }

    # And cleanup after ourself
    if($cfg->{clean_tmpfiles}) {
	$logger->trace("Cleaning up temp files for Dimob");
	$self->_remove_tmpfiles(@tmpfiles);
    }

    return @gis;
}


# Reuse most of Morgan's code, it works...
sub parse_sigi {
    my $self = shift;
	my $filename = shift;
	open( INFILE, $filename ) or die "can't open Input File: $filename\n";
	my @islands;    #an array of hash with start position and end position
	my $criterion   = 'PUTAL';
	my $islandcount = 0;
	my $islandstart;
	my $islandend;
	my $islandstatus = 0;    #start with out (0)

	while (<INFILE>) {
		if (/\#/) {
			next;
		}
		else {
			chomp;
			my @fields = split /\t/;
			my $start  = $fields[3];
			my $end    = $fields[4];
			my $class  = $fields[2];
			if (   ( $class eq $criterion )
				&& ( $islandstatus == 0 )
				&& ( $end != 0 ) )
			{
				$islandstart  = $start;
				$islandend    = $end;
				$islandstatus = 1;
			}
			elsif (( $class eq $criterion )
				&& ( $islandstatus == 1 )
				&& ( $end != 0 ) )
			{
				$islandend    = $end;
				$islandstatus = 1;
			}
			elsif ( ( $class ne $criterion ) && ( $islandstatus == 1 ) ) {
				$islands[$islandcount] =
				  { "start" => $islandstart, "end" => $islandend };
				$islandstatus = 0;
				$islandcount++;
			}
			else {
				$islandstatus = 0;
			}
		}
	}

	#in case where the last lines actually form an island
	if ( $islandstatus == 1 ) {
		$islands[ $islandcount++ ] =
		  { "start" => $islandstart, "end" => $islandend };
	}

	my @gis;
	foreach my $island (@islands) {
		if ( ( $island->{end} - $island->{start} ) >= $self->{MIN_GI_SIZE} ) {
			#my %curr = ();
			#$curr{start} = $island->{start};
			#$curr{end} = $island->{end};
			#push (@gis, \%curr);
			push( @gis, [ $island->{start}, $island->{end} ] );
		}
	}
	close INFILE;

	return @gis;

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
	    return ($name,$filename,$formats);
	}
    }    

    unless($type  eq 'custom') {
    # If we know we're not hunting for a custom identifier    

	my $sobj = new MicrobeDB::Search();

	my ($rep_results) = $sobj->object_search(new MicrobeDB::Replicon( rep_accnum => $rep_accnum,
								      version_id => $self->{microbedb_ver} ));
	
	# We found a result in microbedb
	if( defined($rep_results) ) {
	    # One extra step, we need the path to the genome file
	    my $search_obj = new MicrobeDB::Search( return_obj => 'MicrobeDB::GenomeProject' );
	    my ($gpo) = $search_obj->object_search($rep_results);

	    return ($rep_results->definition(),$gpo->gpv_directory() . $rep_results->file_name(),$rep_results->file_types());
	}
    }

    # This should actually never happen if we're
    # doing things right, but handle it anyways
    return ('unknown',undef,undef);

}


# Make a temp file in our work directory and return the name

sub _make_tempfile {
    my $self = shift;

    # Let's put the file in our workdir
    my $tmp_file = mktemp($self->{workdir} . "/blasttmpXXXXXXXXXX");
    
    # And touch it to make sure it gets made
    `touch $tmp_file`;

    return $tmp_file;
}

sub _remove_tmpfiles {
    my $self = shift;
    my @tmpfiles = @_;

    foreach my $file (@tmpfiles) {
	unless(unlink $file) {
	    $logger->error("Can't unlink file $file: $!");
	}
    }
}

1;
