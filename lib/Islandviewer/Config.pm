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

    $self->evaluate_parameters();

    # Save the file name so we can pass it to
    # helper scripts
    $self->_set_file($cfg_file);

    return $self;
}

# Go through the config variables and do
# substitutions as needed

sub evaluate_parameters {
    my $self = shift;

    my $config = $self->config;

    for my $param (keys $config) {
	if($config->{$param} =~ /{{.+}}/) {
	    $config->{$param} =~ s/{{([\w_]+)}}/$config->{$1}/eg;
	    
	}
    }
}

1;
