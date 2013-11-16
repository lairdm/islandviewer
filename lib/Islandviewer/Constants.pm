=head1 NAME

    Islandviewer::Constants

=head1 DESCRIPTION

    Because we have to maintain inter-operbility with
    the python based front end and Django's model
    doesn't understand enums properly we need some 
    mapping constants

=head1 SYNOPSIS

    use Islandviewer::Constants;


=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Nov 15, 2013

=cut

package Islandviewer::Constants;

use base 'Exporter';

use strict;
use base 'Exporter';

our @EXPORT = qw();
our @EXPORT_OK = qw($STATUS_MAP $REV_STATUS_MAP $ATYPE_MAP $REV_ATYPE_MAP);

our $STATUS_MAP = {PENDING  => 1,
                   RUNNING  => 2,
                   ERROR    => 3,
                   COMPLETE => 4 };

our $REV_STATUS_MAP = { 1 => 'PENDING',
                        2 => 'RUNNING',
                        3 => 'ERROR',
                        4 => 'COMPLETE' };

our $ATYPE_MAP = { custom    => 1,
                   microbedb => 2 };

our $REV_ATYPE_MAP = { 1 => 'custom',
                       2 => 'microbedb' };

1;
