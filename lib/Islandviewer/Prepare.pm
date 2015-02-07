=head1 NAME

    Islandviewer::Prepare

=head1 DESCRIPTION

    Object to setup an Islandviewer job, including prepare
    the various input files and run an alignment against
    a reference genome if needed

=head1 SYNOPSIS

    use Islandviewer::Prepare;

    $vir_obj = Islandviewer::Prepare->new({workdir => '/tmp/workdir',
                                         microbedb_version => 80});

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Feb 6, 2015

=cut

package Islandviewer::Prepare;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use File::Temp qw/ :mktemp /;
use Data::Dumper;

use Islandviewer::DBISingleton;

my $cfg; my $logger; my $cfg_file;

my $module_name = 'Prepare';

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{workdir} = $args->{workdir};
    
}

# We're going to need to do a few things here.
#
# Make the required file formats if they don't
# exist.
# Run an alignment against a reference genome
# if requested, then build the concatonated
# input file(s) for running the pipeline.

sub run {
    my $self = shift;
    my $accnum = shift;
    my $callback = shift;


}

1;
