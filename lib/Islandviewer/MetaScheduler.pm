=head1 NAME

    Islandviewer::MetaScheduler

=head1 DESCRIPTION

    Submit jobs to MetaScheduler

=head1 SYNOPSIS

    use Islandviewer::MetaScheduler;

    my $scheduler = Islandviewer::MetaScheduler->new();
    $scheduler->submit($cmd);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Sept 27, 2013

=cut

package Islandviewer::MetaScheduler;

use strict;
use Moose;

use Islandviewer::Config;

my $cfg;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

}

sub submit {
    my $self = shift;
    my $name = shift;
    my $cmd = shift;

    # First let's make sure we have a work directory for qsub files
    mkdir "$cfg->{workdir}/qsub"
	unless( -d "$cfg->{workdir}/qsub" );

    open(QSUB, ">$cfg->{workdir}/qsub/$name.qsub") or
	die "Error, can't open qsub file $cfg->{workdir}/qsub/$name.qsub: $!";

    print QSUB "# Build by Islandviewer::MetaScheduler\n\n";
    print QSUB "echo \"Running cvtree for set $name\"\n";
    print QSUB "$cmd\n";

    close QSUB;

    
}

1;
