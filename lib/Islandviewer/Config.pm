package Islandviewer::Config;
use MooseX::Singleton;

use strict;
use warnings;
use Config::Simple;
use Data::Dumper;

has config => (
    is     => 'ro',
    isa    => 'Ref',
    writer => '_set_config'
);

has config_file => (
    is     =>  'ro',
    isa    =>  'Str',
    writer =>  '_set_file'
);

sub initialize {
    my $self = shift;
    my $args = shift;

    my $cfg_file = $args->{cfg_file};

    die "Error, unable to read config file $cfg_file"
	unless(-f $cfg_file && -r $cfg_file);

    my $config = new Config::Simple($cfg_file)->param(-block => 'main');

    $self->_set_config($config);

    # Save the file name so we can pass it to
    # helper scripts
    $self->_set_file($cfg_file);

    return $self;
}

1;
