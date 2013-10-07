=head1 NAME

    Islandviewer

=head1 DESCRIPTION

    Object for managing islandviewer jobs

=head1 SYNOPSIS

    use Islandviewer;


=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Sept 25, 2013

=cut

package Islandviewer;

use strict;
use Moose;
use Islandviewer::Config;
use Islandviewer::DBISingleton;

my $cfg;

sub BUILD {
    my $self = shift;
    my $args = shift;

    # Initialize the configuration file
    Islandviewer::Config->initialize({cfg_file => $args->{cfg_file} });
    $cfg = Islandviewer::Config->config;

    # Initialize the DB connection
    Islandviewer::DBISingleton->initialize({dsn => $cfg->{'dsn'}, 
                                             user => $cfg->{'dbuser'}, 
                                             pass => $cfg->{'dbpass'} });
    
}

1;
