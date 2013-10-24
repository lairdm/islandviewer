=head1 NAME

    Islandviewer::Mauve

=head1 DESCRIPTION

    Object to call Mauve and parse results

    Most of this code is cut and pasted from Morgan's
    original Mauve.pm package, just updating it to match
    the overall style of the updated IslandViewer.

=head1 SYNOPSIS

    use Islandviewer::Mauve;

    
=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Oct 24, 2013

=cut

package Islandviewer::Mauve;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use Data::Dumper;

my $cfg; my $logger; 

my @MAUVE_PARAMS =
  qw(output output-alignment output-guide-tree island-size island-output backbone-size max-backbone-gap backbone-output);

#Using attributes with '-' cause problems with function calls so we convert them all to '_'
my %PARAM_CONVERT;
foreach (@MAUVE_PARAMS) {
	my $translate = $_;
	$translate =~ s/-/_/g;
	$PARAM_CONVERT{$_} = $translate;
}

my @FILES  =
  qw(output output-alignment output-guide-tree island-output backbone-output);

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;
    $cfg_file = File::Spec->rel2abs(Islandviewer::Config->config_file);

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};

    # Set default island size
    $self->island_size(4000);

    #Set each attribute that is given as an arguement
    foreach ( keys(%{$arg}) ) {
	$self->$_( $arg{$_} );
    }

    return $self;
}

sub run {
    my $self = shift;
    my @seqs = @_;

    # Maintain a list of temp files to remove if we're
    # doing that
    my @tmp_files;

    # Mauve wants to create all the files, if you need them or
    # not, so we have to make temp files for each of them
    foreach (@FILES) {
	my $param = $PARAM_CONVERT{$_};
	my $tmp   = $self->_make_tempfile();
	push( @tmp_files, $tmp );
	$self->$param($tmp);
    }

    # Now let's build the command line parameters we're
    # going to pass to Mauve
    my @params;
    foreach (@MAUVE_PARAMS) {
	my $stored_param = $PARAM_CONVERT{$_};
	push( @params, join( "", "--", $_, "=", $self->$stored_param() ) )
	    if defined( $self->$stored_param() );
    }
    my $param_str = join( " ", @params );
        
    if(scalar(@seqs) < 2 ) {
	$logger->error("Mauve needs at least 2 sequences to align");
	die "Mauve needs at least 2 sequences to align";
    }

    # Now let's build the list of sequence files to pass,
    # each fasta files needs a corresponding sml file, basically
    # a temp file Mauve will use as a temp file, odd, I know...
    my $seq_srt;
    foreach (@seqs) {
	# Can we read the sequence file?
	die "Error, can't open sequence file"
	    unless( -f $_ && -r $_ );

	my $tmp   = $self->_make_tempfile();
	push( @tmp_files, $tmp );
	$seq_str .= " $_ $tmp";	
    }

    # Alright we should be ready to go, let's find the mauve binary...
    my $mauve_bin = $cfg->{mauve_cmd};
    my $cmd = "$mauve_bin $param_str $seq_str";

    # Let's make somewhere to save the stderr
    my $tmp_stderr = $self->_make_tempfile();
    push( @tmp_files, $tmp_stderr );
    $cmd .= " 2>$tmp_stderr";

    # And now let's run the command...
    unless( open (MAUVE, "$cmd|") ) {
	$logger->error("Error, can't run command $cmd: $!");
	die "Error, can't run command $cmd: $!";
    }

    # Waits until the system call is done before saving to
    # the array
    my @stdout = <MAUVE>;
    close(MAUVE);

    # We've had issues with file system delay, let's take
    # a moment of reflection.
    sleep(2);

    # Are we interested in logging the errors?
    if($self->{log_errors}) {
	open(MAUVE_ERROR, $tmp_stderr) or
	    die "Error opening stderr file (the irony...) $tmp_stderr: $!";

	$logger->error("From Mauve stderr stream:");
	while(<MAUVE_ERROR>) {
	    $logger->error($_);
	}
	close(MAUVE_ERROR);
    }

    # And let's package up the results to send them back
    my $result_obj = $self->_save_results( \@stdout );

    # And clean up the temp files if we've been asked to
    if($self->{clean_tmpfiles}) {
	$logger->debug("Cleaning up temp files");
	$self->_remove_tmpfiles(@tmp_files);
    }

    # And we're done, send back the results
    return $result_obj;

}

sub _save_results {
    my $self = shift;
    my $stdout = shift;

    
}

# Make a temp file in our work directory and return the name

sub _make_tempfile {
    my $self = shift;

    # Let's put the file in our workdir
    my $tmp_file = mktemp($self->{workdir} . "/mauvetmpXXXXXXXXXX");
    
    # And touch it to make sure it gets made
    `touch $tmp_file`;

    return $tmp_file;
}
