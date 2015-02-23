=head1 NAME

    Islandviewer::DummyScheduler

=head1 DESCRIPTION

    Submit jobs and always return true, for testing purposes

=head1 SYNOPSIS

    use Islandviewer::DummyScheduler;

    my $scheduler = Islandviewer::MetaDummy->new();
    $scheduler->submit($cmd);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Feb 23, 2015

=cut

package Islandviewer::DummyScheduler;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use JSON;
use Data::Dumper;

use Islandviewer::Config;

my $cfg; my $cfg_file; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;
    $cfg_file = File::Spec->rel2abs(Islandviewer::Config->config_file);

    $logger = Log::Log4perl->get_logger;

}

sub submit {
    my $self = shift;
    my $name = shift;
    my $cmd = shift;

    $logger->info("Received submit command with name $name");
    $logger->info("Received submit command with cmd $cmd");

    $logger->info("Returning true.");

    return 1;
}

sub build_and_submit {
    my $self = shift;
    my $aid = shift;
    my $job_type = shift;
    my $workdir = shift;
    my $args = shift;
    my @modules = @_;

    $logger->info("Received submit command with aid $aid");
    $logger->info("Received submit command with job_type $job_type");
    $logger->info("Received submit command with workdir $workdir");
    $logger->info("Received submit command with args $args");
    $logger->info("Received submit command with modules " . join(',', @modules));

    $logger->info("Returning true.");

    return 1;
}

1;
