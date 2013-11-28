=head1 NAME

    Islandviewer::NullScheduler

=head1 DESCRIPTION

    Run jobs using a straight system() call
    using a & to background the process.
    This module does NOT block for the system
    call.

=head1 SYNOPSIS

    use Islandviewer::NullScheduler;

    my $scheduler = Islandviewer::NullScheduler->new();
    $scheduler->submit($cmd);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Oct 30, 2013

=cut

package Islandviewer::NullScheduler;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);

use Islandviewer::Config;

my $cfg; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

}

sub submit {
    my $self = shift;
    my $name = shift;
    my $cmd = shift;
    my $workdir = shift;

    $logger->debug("Making system call $cmd");

    my $ret = system("$cmd&");

    if($ret) {
	# Non-zero return value, bad...
	$logger->error("Error making system call $cmd");
	return 0;
    }

    return 1;

}

1;
