package Islandviewer::DBISingleton;
use MooseX::Singleton;
use Data::Dumper;

use strict;
use DBI;

has dbh => (
    is      => 'ro',
    isa     => 'Ref',
    writer  => '_set_dbh'
);

sub initialize {
    my $self = shift;
    my $args = shift;

    my $dbh = DBI->connect($args->{dsn},
			   $args->{user},
			   $args->{pass});
    die "Error: Unable to connect to the database: $DBI::errstr\n" if ! $dbh;

    $dbh->{mysql_auto_reconnect} = 1;

    $self->_set_dbh($dbh);

    return $self;
}

1;
