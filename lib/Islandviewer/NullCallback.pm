=head1 NAME

    Islandviewer::NullCallback

=head1 DESCRIPTION

    Dummy object that just provides the record_islands()
    callback for testing purposes, can be passed to
    a module as the callback object

=head1 SYNOPSIS

    use Islandviewer::NullCallback;

    $callback_obj = Islandviewer::NullCallback->new();

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Feb 19, 2015

=cut

package Islandviewer::NullCallback;

use strict;
use Moose;
use Data::Dumper;
use Log::Log4perl qw(get_logger :nowarn);

my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $logger = Log::Log4perl->get_logger;

}

sub record_islands {
    my $self = shift;
    my $module = shift;
    my @islands = @_;

    $logger->info("Received callback from $module");

    for my $island (@islands) {
	$logger->info("Island: " .  $island->[0] . ':' . $island->[1]);
    }
}

1;
