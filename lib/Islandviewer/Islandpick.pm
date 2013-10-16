=head1 NAME

    Islandviewer::Islandpick

=head1 DESCRIPTION

    Object to run Islandpick against a given genome

=head1 SYNOPSIS

    use Islandviewer::Islandpick;

    $dist = Islandviewer::Distance->new(scheduler => Islandviewer::Metascheduler);
    $dist->calculate_all(version => 73, custom_replicon => $repHash);
    $distance->add_replicon(cid => 2, version => 73);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Oct 16, 2013

=cut

package Islandviewer::Islandpick;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);

use Islandviewer::Schema;

# local modules
use Mauve;
use Genome_Picker;

my $cfg; my $logger; my $cfg_file;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;
    $cfg_file = File::Spec->rel2abs(Islandviewer::Config->config_file);

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};

    $self->{schema} = Islandviewer::Schema->connect($cfg->{dsn},
					       $cfg->{dbuser},
					       $cfg->{dbpass})
	or die "Error, can't connect to Islandviewer via DBIx";

    die "Error, you must specify a microbedb version"
	unless($args->{microbedb_version});
    $self->{microbedb_ver} = $args->{microbedb_version};

    # Setup the cutoffs for the run, we'll use the defaults
    # unless we're explicitly told otherwise
    $self->{MAX_CUTOFF} = $args->{MAX_CUTOFF} || $cfg->{MAX_CUTOFF};
    $self->{MIN_CUTOFF} = $args->{MIN_CUTOFF} || $cfg->{MIN_CUTOFF};
    $self->{MAX_COMPARE_CUTOFF} = $args->{MAX_COMPARE_CUTOFF} || $cfg->{MAX_COMPARE_CUTOFF};
    $self->{MIN_COMPARE_CUTOFF} = $args->{MIN_COMPARE_CUTOFF} || $cfg->{MIN_COMPARE_CUTOFF};
    $self->{MAX_DIST_SINGLE_CUTOFF} = $args->{MAX_DIST_SINGLE_CUTOFF} || $cfg->{MAX_DIST_SINGLE_CUTOFF};
    $self->{MIN_DIST_SINGLE_CUTOFF} = $args->{MIN_DIST_SINGLE_CUTOFF} || $cfg->{MIN_DIST_SINGLE_CUTOFF};
    $self->{MIN_GI_SIZE} = $args->{MIN_GI_SIZE} || $cfg->{MIN_GI_SIZE};


}
