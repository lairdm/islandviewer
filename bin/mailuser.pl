#!/usr/bin/env perl

use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Data::Dumper;
use File::Spec::Functions;

# This is the tool metascheduler will use notify when
# jobs have finished.
# It takes the analysis id (aid)
# and checks against the DB to see
# the status of the analysis.

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

use lib "../lib";
use Islandviewer;
use Islandviewer::Status;
use Islandviewer::Notification;
use Islandviewer::Constants qw(:DEFAULT $STATUS_MAP $REV_STATUS_MAP $ATYPE_MAP);

MAIN: {
    my $cfname; my $logger; my $aid; my $resend;
    my $res = GetOptions("config=s"    => \$cfname,
			 "aid=s"       => \$aid,
			 "resend"      => \$resend,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer; my $cfg;
    eval {
	$Islandviewer = Islandviewer->new({cfg_file => $cfname });
	$cfg = Islandviewer::Config->config;
    };
    if($@) {
	print "Error initiating module_test for aid $aid";
	exit 16;
    }

    if($cfg->{logger_conf} && ( -r $cfg->{logger_conf})) {
	Log::Log4perl::init($cfg->{logger_conf});
	$logger = Log::Log4perl->get_logger;

	my $app = Log::Log4perl->appender_by_name("errorlog");

	my $logpath = catdir($cfg->{analysis_directory}, $aid);
	if( -d $logpath ) {
	    $app->file_switch("$logpath/analysis.log");	    
	} else {
	    $app->file_switch($cfg->{analysis_log});
	}

	$logger->debug("Logging initialized, aid $aid");
    }

    # Make a status check object
    my $status;
    eval {
	my $status = Islandviewer::Status->new();

	# Ask islandviewer the status of this analysis
	$status = $status->check_analysis_status($aid);
    };
    if($@) {
	$logger->error("Error with analysis module for analysis $aid: $@");
	exit 4;
    }

    $logger->info("Found analysis $aid in status " . $REV_STATUS_MAP->{$status});

    eval {
	my $notification = Islandviewer::Notification->new({aid => $aid});
	$notification->notify($status, $resend);
    };
    if($@) {
	$logger->error("Error doing notification for analysis $aid: $@");
	exit 4;
    }

    exit 0;

};
