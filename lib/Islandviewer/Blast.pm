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

use static;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;

use Bio::SearchIO;

use Islandviewer::DBISingleton;

my $logger; my $cfg;

# my @BLAST_PARAMS = qw (db query evalue outfmt out);
my @BLAST_PARAMS =  qw(p d i e m o F K);
# p = blast program
# d = database
# i = input query
# e = evalue
# m = output format
# o = output file

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
    foreach ( keys(%arg) ) {
        $self->$_( $arg{$_} ) if($_ ~~ @BLAST_PARAMS);
    }    
}

