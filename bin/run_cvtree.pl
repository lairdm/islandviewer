#!/usr/bin/env perl

use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

use lib "../lib";
use Islandviewer;
use Islandviewer::Config;
use Islandviewer::Distance;

use Net::ZooKeeper::WatchdogQueue;

MAIN: {
    my $cfname; my $set; my $workdir; my $root;
    my $watchdog;
    my $res = GetOptions("config=s"   => \$cfname,
			 "set=s"      => \$set,
			 "workdir=s"  => \$workdir,
			 "blocking=s" => \$root,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    my $cfg = Islandviewer::Config->config;

    # If we're working in blocking mode we make a watchdog
    if($root) {
	$watchdog = new Net::ZooKeeper::WatchdogQueue($cfg->{zookeeper},
						      $root);
	$watchdog->create_timer("pid".$$."set".$set);
	# We're throwing away the set because we're not
	# actually doing it that way, we get passed the
	# set on our command line
	$watchdog->consume();
    }

    # Now we have to actually run the set through cvtree
    eval {
	my $dist_obj = Islandviewer::Distance->new({workdir => "$workdir/$set" });
	$dist_obj->run_and_load("$workdir/$set", $watchdog);
    };

    if($@) {
	open(ERRORLOG, ">>$workdir/$set/error.log") or
	    die "Wow, we're really in trouble! Can't open error log!";
	print ERRORLOG "Error running cvtree task: $@";
	close ERRORLOG;
	die "Error running cvtree task: $@"
    }
};
