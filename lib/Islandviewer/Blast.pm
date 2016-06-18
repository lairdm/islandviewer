=head1 NAME

    Islandviewer::Blast

=head1 DESCRIPTION

    Object to run a Blast search on a genome

=head1 SYNOPSIS

    use Islandviewer::Blast;

    $blast_obj = Islandviewer::Blast->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80});

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    July 24, 2015

=cut

package Islandviewer::Blast;

use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use File::Spec;
use Scalar::Util qw(reftype);

use Data::Dumper;

use Bio::SearchIO;

use Islandviewer::DBISingleton;

my $logger; my $cfg;

my @temp_files;

# my @BLAST_PARAMS = qw (db query evalue outfmt out);
my @BLAST_PARAMS =  qw(db query evalue outfmt out seg);
# db = database
# query = input query
# evalue = evalue
# outfmt = output format
# out = output file

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    $self->{microbedb_ver} = (defined($args->{microbedb_ver}) ?
			      $args->{microbedb_ver} : undef );
    
    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};

    #Fill the attributes with mauve parameters
    foreach (@BLAST_PARAMS) {
        $self->{ $_ } = undef;
    }

    #Set each attribute that is given as an arguement
    foreach ( keys(%$args) ) {
        $self->{ $_ } = $args->{$_} if($_ ~~ @BLAST_PARAMS);
    }    
}

sub run {
    my $self = shift;
    my $query_file = shift;
    my $db_file = shift;

    $logger->info("Running blast of $query_file against $db_file");

    unless(-f $query_file) {
        $logger->logdie("Can't find query file $query_file");
    }

    my $database = $self->make_database($db_file);

    my $outfile = $self->_make_tempfile();
    $self->{out} = $outfile;
    push @temp_files, $outfile;

    $self->{db} = $database;
    $self->{query} = $query_file;

    my @params;
    foreach (@BLAST_PARAMS) {
        if(defined($self->{$_})) {
            push( @params, join( "", "-", $_, " ", $self->{$_} ) );
        }
    }
    my $param_str = join( " ", @params );
    
    # The location of blastp, assume it's in the path
    # unless otherwise stated in the config file
    my $blastp = 'blastp';
    $blastp = $cfg->{blastp} if($cfg->{blastp});
    
    my $cmd = "$blastp $param_str";

    #pipe the stderr from the command to a temp file
    my $tmp_stderr = $self->_make_tempfile();
    push( @temp_files, $tmp_stderr );
    $cmd .= " 2>$tmp_stderr";

    $logger->debug("Running command: $cmd");

    #run the actual command
    unless ( open( BLAST, "$cmd |" ) ) {
        $logger->logdie("Cannot run $cmd");
    }
    
    #Waits until the system call is done before saving to the array
    my @stdout = <BLAST>;
    close(BLAST);
    
    #give sometime so that files have time to be written to
    sleep(5);
    
    #Open the file that contains the std error from the command call
    open( BLAST_ERROR, $tmp_stderr )
        || $logger->logdie("Can't open std_error file: \"$tmp_stderr\" when using command: $cmd. System error: $!");
    my @stderr = <BLAST_ERROR>;
    close(BLAST_ERROR);
    
    $logger->trace("Logging stderr:");
    foreach(@stderr) {
        $logger->trace($_);
    }

    #store the results in memory as a blast results object
    my $blast_results_obj = $self->_save_results( );
	
    #return the blast results object
    return $blast_results_obj;

}

sub _save_results {
	my ( $self ) = @_;

	my $file_name = $self->{out};
        $logger->trace("Parsing blast outfile file: $file_name");

	my $blast_results_obj = new Bio::SearchIO(-format => 'blastxml', -file => $file_name);

	my @output;
	my %unique_hits;
	
	while (my $result = $blast_results_obj->next_result) {
            $logger->trace(" Query: ".$result->query_accession.", length=".$result->query_length);

		my $length_cutoff = ($result->query_length)*0.8;
		
		## Check if $result->num_hits is > 1 
		while (my $hit = $result->next_hit) {
			while (my $hsp = $hit->next_hsp) { 
                            $logger->trace(" Hsp: ".$hit->name." ".$hsp->percent_identity."%id length=".$hsp->length('total'));

				if ($hsp->percent_identity >= 90 && $hsp->length('total') >= $length_cutoff) {
                                    $logger->trace("Hit name: " . $hit->name . " against " . $result->query_description);
#                                    $logger->trace(Dumper($result));
                                    my $hit_headers = $self->split_header($hit->name);
                                    $logger->trace("Split header: " . Dumper($hit_headers));

#                                    if ($hit->name =~ /gi\|(\d+)\|\w+\|(.+)\|/) {
                                    if (my $ref = $hit_headers->{ref}) {
                                        # In case we have multiple hits to a particular protein, if the
                                        # key isn't defined just record it. If it's an array (multiple values
                                        # already existing) push the new one. Otherwise if the key exists 
                                        # but isn't an array, convert it to an array.
                                        if(!defined $unique_hits{"ref|$ref"}) {
                                            $unique_hits{"ref|$ref"} = $result->query_description;
                                        } elsif( reftype $unique_hits{"ref|$ref"} eq 'ARRAY') {
                                            push @{ $unique_hits{"ref|$ref"} }, $result->query_description;
                                        } else {
                                            $logger->trace("Pushing a second item on ref|$ref: " . $unique_hits{"ref|$ref"} . ", " . $result->query_description);
                                            $unique_hits{"ref|$ref"} = [$unique_hits{"ref|$ref"}, $result->query_description];
                                            $logger->trace("Now: " . Dumper($unique_hits{"ref|$ref"}));
                                        }
                                        $logger->trace("Found hit: ref|" . $ref . " against " . $result->query_description);
                                    }
				}
			}
		}
		undef $result;
	}
	undef $blast_results_obj;

        $logger->info("TOTAL UNIQUE HITS: ".keys(%unique_hits));

	return \%unique_hits;

}

# Make a blast db in a local temp file, also
# stash away the db file for cleaning up later.

sub make_database {
    my $self = shift;
    my $db_file = shift;

    $logger->debug("Making blast database for $db_file");

    unless(-f $db_file) {
        $logger->logdie("Error, db file doesn't exist: $db_file");
    }

    # Make a local database to use
    
    # The location of makeblastdb, assume it's in the path
    # unless otherwise stated in the config file
    my $makeblastdb = 'makeblastdb';
    $makeblastdb = $cfg->{makeblastdb} if($cfg->{makeblastdb});

    my $db_root = $self->_make_tempfile();
    push @temp_files, $db_root;

    my $cmd = $makeblastdb . " -in " . $db_file . " -out " . $db_root . " -input_type fasta -dbtype prot";
    $logger->trace("Running command: $cmd");
    
    my $ret = system($cmd);
    $logger->trace("Got back: $ret");

    return $db_root;
}

sub split_header {
    my $self = shift;
    my $id = shift;

    my @pieces = split /\|/, $id;

    my $identifiers = {};
    my $type;
    while(($type = shift @pieces) && (my $val = shift @pieces)) {
        $identifiers->{$type} = $val;
    }

    # See if we have a coordinate in the header
    if($type =~ /:c?(\d+)\-(\d+)/) {
        $identifiers->{start} = $1;
        $identifiers->{end} = $2;
    }

    return $identifiers;
}

sub _make_tempfile {
    my $self = shift;

    # Let's put the file in our workdir
    my $tmp_file = mktemp(File::Spec->catpath(undef, $self->{workdir}, "blasttmpXXXXXXXXXX"));
    
    # And touch it to make sure it gets made
    `touch $tmp_file`;

    return $tmp_file;
}

sub _clean_tmp {
    my $self = shift;

    while(my $base = shift @temp_files) {
        my @files = glob $base . "*";
        foreach my $file (@files) {
            $logger->trace("Removing temp file: $file");
            unlink $file;
        }
    }
}

1;
