#!/usr/bin/env perl

use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Data::Dumper;

# This is the tool metascheduler will use to test the
# status of individual modules in a pipeline instance.
# It takes the analysis id (aid) and the component
# name and checks against the DB and zookeeper to see
# the status of that module.
# If a module isn't given it will list the status of
# all the modules in tab delimited format.

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

use lib "../lib";
use Islandviewer;
use Islandviewer::Status;
use Islandviewer::Constants qw(:DEFAULT $STATUS_MAP $REV_STATUS_MAP $ATYPE_MAP);

MAIN: {
    my $cfname; my $logger; my $aid; my $component;
    my $res = GetOptions("config=s"    => \$cfname,
			 "aid=s"       => \$aid,
			 "module=s" => \$component,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    my $cfg = Islandviewer::Config->config;

    # Make a status check object
    my $status = Islandviewer::Status->new();

    # Ask islandviewer the status of this analysis
    my $modules = $status->check_status($aid);

    # We allow the user not to give a component
    # otherwise we'll just return all the components
    # (not likely useful to real users than from 
    # a script)
    if($component) {
	if($modules->{$component}) {
	    # We have the module...
	    print $REV_STATUS_MAP->{$modules->{$component}} . "\n";

	    if($modules->{$component} == $STATUS_MAP->{PENDING} ||
	       $modules->{$component} == $STATUS_MAP->{RUNNING}) {
		exit 8;
	    } elsif($modules->{$component} == $STATUS_MAP->{ERROR}) {
		exit 4;
	    }

	    # Otherwise we must be complete
	    exit 0;
	} else {
	    # We didn't find the module, this is an error....
	    exit 4;
	}
    } else {
	# The user didn't specify the module, so report all of them...
	for my $c (keys %{$modules}) {
	    print "$c\t" . $REV_STATUS_MAP->{$modules->{$c}} . "\n";
	}
    }

};
