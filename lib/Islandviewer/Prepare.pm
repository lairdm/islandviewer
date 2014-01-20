=head1 NAME

    Islandviewer::Prepare

=head1 DESCRIPTION

    Ensure an Islandviewer job is prepared and ready to go,
    make the needed file types, put everything in place,
    and update the database with the proper working directory.

    This module needs a little more knowledge about the underlying
    "Analysis" module and configuration, it probably could have
    been integrated in to the Analysis module itself but we
    kept it here to maintain the underlying paradigm of how
    the workflow operates.

=head1 SYNOPSIS

    use Islandviewer::Prepare;

    $vir_obj = Islandviewer::Summary->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80});

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Jan 20, 2013

=cut

package Islandviewer::Prepare;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use Data::Dumper;

use Islandviewer::DBISingleton;

my $module_name = 'Prepare';

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;
    $cfg_file = File::Spec->rel2abs(Islandviewer::Config->config_file);

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};
}

sub run {
    my $self = shift;
    my $accnum = shift;
    my $callback = shift;


}
