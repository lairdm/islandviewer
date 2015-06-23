=head1 NAME

    Islandviewer::Sigi

=head1 DESCRIPTION

    Object to run SigiHMM against a given genome

=head1 SYNOPSIS

    use Islandviewer::Sigi;

    $sigi_obj = Islandviewer::Sigi->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80,
                                         MIN_GI_SIZE => 8000});

    # Optional comparison rep_accnums, otherwise it uses the genome picker
    $sigi_obj->run_sigi($rep_accnum);
    
=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Nov 10, 2013

=cut

package Islandviewer::Sigi;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use Data::Dumper;
use File::Spec;

use Islandviewer::DBISingleton;

use Islandviewer::GenomeUtils;

use MicrobedbV2::Singleton;

my $cfg; my $logger; my $cfg_file;

my $module_name = 'Sigi';

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

    my @islands = $self->run_sigi($accnum);

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

sub run_sigi {
    my $self = shift;
    my $rep_accnum = shift;
    my @tmpfiles;

    # We're given the rep_accnum, look up the files
#    my ($name, $filename, $format_str) = $self->lookup_genome($rep_accnum);
    my $genome_obj = Islandviewer::GenomeUtils->new({microbedb_ver => $self->{microbedb_ver} });
    my($name,$filename,$format_str) = $genome_obj->lookup_genome($rep_accnum);

    unless($filename && $format_str) {
	$logger->logdie("Error, can't find genome $rep_accnum");
#	return ();
    }    

    # To make life easier, break out the formats available
    my $formats;
    foreach (split /\s+/, $format_str) { $_ =~ s/^\.//; print $_; $formats->{$_} = 1; }

    # Ensure we have the needed file
    # Just check for the file, because GenomeUtils doesn't update the
    # formats string for microbedb its not always accurate, if we've
    # gotten to this point we must have generated the needed files,
    # but sanity check anyways.
    unless(-f "$filename.embl" ) {
#    unless($formats->{embl}) {
	$logger->logdie("Error, we don't have the needed embl file... looking in $filename");
#	return ();
    }

    # Now we need to start buildingthe command we'll run
    my $cmd = $cfg->{sigi_cmd} . " " . $cfg->{java_bin} . " " . $cfg->{sigi_path};
    # And the parameter...
    my $SIGI_JOIN_PARAM = 3;

    # Now we're going to need an output file
    my $tmp_out_file = $self->_make_tempfile();
    push @tmpfiles, $tmp_out_file;

    # And we need an output embl file, reuse the same basename
    my $tmp_out_gff = $tmp_out_file . '.gff';
    $tmp_out_file .= '.embl';
    push @tmpfiles, $tmp_out_gff;
    push @tmpfiles, $tmp_out_file;

    # And a file for stderr...
    my $tmp_stderr = $self->_make_tempfile();
    push @tmpfiles, $tmp_stderr;

    # Build the command further...
    $cmd .= " input=$filename.embl output=$tmp_out_file gff=$tmp_out_gff join=$SIGI_JOIN_PARAM 2>$tmp_stderr";

    $logger->trace("Sending the sigi command: $cmd");

    # run SigiHMM
    unless ( open( COMMAND, "$cmd |" ) ) {
	$logger->logdie("Cannot run $cmd");
    }

    #Waits until the system call is done before saving to the array
    my @stdout = <COMMAND>;
    close(COMMAND);

    #Open the file that contains the std error from the command call
    open( ERROR, $tmp_stderr )
	|| $logger->logdie("Can't open std_error file: $tmp_stderr when using command: $cmd", "$!");
    my @stderr = <ERROR>;
    close(ERROR);

    if ( scalar(@stderr) > 0 ) {
	$logger->logdie("Something went wrong in sigi: @stderr");
    }

    # And go parse the islands!
    my @gis = $self->parse_sigi($tmp_out_gff);

    # And cleanup after ourself
    if($cfg->{clean_tmpfiles}) {
	$logger->trace("Cleaning up temp files for Sigi");
	$self->_remove_tmpfiles(@tmpfiles);
    }

    # And its that simple, we should be done...
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

	    return ($rep_results->definition, File::Spec->catpath(undef, $rep_results->genomeproject->gpv_directory, $rep_results->file_name),$rep_results->file_types);
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
    my $tmp_file = mktemp($self->{workdir} . "/sigitmpXXXXXXXXXX");
    
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
