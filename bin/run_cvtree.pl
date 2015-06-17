#!/usr/bin/env perl

use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use File::Spec;

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
    my $cfname; my $set; my $workdir; my $root; my $logger;
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

    if($cfg->{logger_conf} && ( -r $cfg->{logger_conf})) {
	Log::Log4perl::init($cfg->{logger_conf});
	$logger = Log::Log4perl->get_logger;
	$logger->debug("Logging initialize for set $set, workdir $workdir, blocking: $root");
    }

    my $app = Log::Log4perl->appender_by_name("errorlog");
    my $set_dir = File::Spec->catpath(undef, $workdir, $set);
    if(-d $set_dir) {
	$app->file_switch(File::Spec->catpath(undef, $set_dir, "distance.log"));
	$logger->info("Initializing logging for set $set");
    } else {
	$logger->error("Error, can't switch log file for set $set");
    }


    # If we're working in blocking mode we make a watchdog
    if($root) {
	eval {
	    $logger->debug("Creating zookeeper node $root/pid".$$."set.".$set);

	    $watchdog = new Net::ZooKeeper::WatchdogQueue($cfg->{zookeeper},
						      $root);

            $watchdog->create_timer("pid".$$."set".$set);
	    # We're throwing away the set because we're not
	    # actually doing it that way, we get passed the
	    # set on our command line
	    $watchdog->consume();
	};
	if($@) {
	    $logger->logdie("Error creating cvtree node for set $set: $@");
	}
    }

    # Now we have to actually run the set through cvtree
    my $set_dir = File::Spec->catpath(undef, $workdir, '$set');
    eval {
	my $dist_obj = Islandviewer::Distance->new({workdir => $set_dir });
	$logger->debug("Starting cvtree run, set $set, watchdog $watchdog");

	$dist_obj->run_and_load($set_dir, $watchdog);
        $logger->info("Finished cvtree run normally, I hope.")
    };

    if($@) {
	open(ERRORLOG, ">>" File::Spec->catpath(undef, $set_dir, "error.log")) or
	    die "Wow, we're really in trouble! Can't open error log!";
	print ERRORLOG "Error running cvtree task: $@";
	$logger->error("Error running cvtree task: $@");
	close ERRORLOG;
	die "Error running cvtree task: $@"
    }

    $logger->info("Exiting run_cvtree.pl");
};
