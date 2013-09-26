package Islandviewer::Config;
use MooseX::Singleton;

use strict;
use warnings;
use Config::Simple;

has config => (
    is     => 'ro',
    isa    => 'Ref',
    writer => '_set_config'
);

sub initialize {
    my $self = shift;
    my $args = shift;

    my $cfg_file = $args->{cfg_file};

    die "Error, unable to read config file $cfg_file"
	unless(-f $cfg_file && -r $cfg_file);

    my $config = new Config::Simple($cfg_file)->param(-block => 'main');

    $self->_set_config($config);

    return $self;
}

1;
