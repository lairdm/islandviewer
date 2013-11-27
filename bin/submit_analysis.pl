#!/usr/bin/env perl

# Used to submit an analysis based on a given
# cid (a cid can either be a custom genome id
# or a ref_accnum from microbedb)
# We can also use this to start a new analysis
# of a genome, for example with altered
# parameters.

use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Data::Dumper;

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

use lib "../lib";
use Islandviewer;

MAIN: {
    my $cfname; my $filename; my $logger;
    my $res = GetOptions("config=s"   => \$cfname,
			 "filename=s" => \$filename,
			 "name=s"     => \$name
    );

# Incomplete, we'll need to determine how we pass
# parameters from the front end to the various modules,
# likely via a json structure to avoid overloading this
# script with parameters

};
