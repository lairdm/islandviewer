#!/usr/bin/env perl

use warnings;
use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Date::Manip;

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

use lib "../lib";
use lib "/home/lairdm/libs";
use Islandviewer;
use Islandviewer::Config;
use Islandviewer::DBISingleton;
use Islandviewer::Distance;

use MicrobeDB::Search;
use MicrobeDB::Replicon;

MAIN: {
    my $cfname; my $logger;
    my $res = GetOptions("config=s" => \$cfname
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });

    my $cfg = Islandviewer::Config->config;

    if($cfg->{logger_conf} && ( -r $cfg->{logger_conf})) {
	Log::Log4perl::init($cfg->{logger_conf});
	$logger = Log::Log4perl->get_logger;
	$logger->debug("Logging initialize");
    }

    my $datestr = UnixDate("now", "%Y%m%d");
    my $app = Log::Log4perl->appender_by_name("errorlog");
    if($cfg->{logdir}) {
	$app->file_switch($cfg->{logdir} . "/ivupdate.$datestr.log");
    }

    my $dist_obj = Islandviewer::Distance->new({scheduler => 'Islandviewer::Torque', workdir => $cfg->{workdir}, num_jobs => 60, block => 1 });

    my $microbedb_ver;
    eval{
	$microbedb_ver = $dist_obj->calculate_all();
    };
    if($@) {
	die "Error updating islandviewer in distance phase: $@";
    }

    unless($microbedb_ver) {
	die "Error, this should never happen, we don't seem to have a valid microbedb version: $microbedb_ver";
    }
    # We should have all the distances done now, let's do the IV
    my $so = new MicrobeDB::Search();

    # Find all the replicons in this version
    my @reps = $so->object_search(new MicrobeDB::Replicon(version_id => $microbedb_ver, rep_type=>'chromosome'));

    my $dbh = Islandviewer::DBISingleton->dbh;
    my $check_analysis = $dbh->prepare("SELECT aid, microbedb FROM Analysis WHERE ext_id = ? and default_analysis = 1");

    # We're going to use the same arguments for all the runs
    my $args->{Islandpick} = {
			      MIN_GI_SIZE => 4000};
    $args->{Sigi} = {
			      MIN_GI_SIZE => 4000};
    $args->{Dimob} = {
			      MIN_GI_SIZE => 4000};
    $args->{Distance} = {block => 1, scheduler => 'Islandviewer::NullScheduler'};
    $args->{microbedb_ver} = $microbedb_ver;
    $args->{email} = 'lairdm@sfu.ca';

    foreach my $curr_rep (@reps) {
	my $accnum = $curr_rep->rep_accnum();

	# Has this replicon already been run before?
	$check_analysis->execute($accnum);
	if(my @row = $check_analysis->fetchrow_arry) {
	    $logger->info("We already have $accnum in the database as analysis $row[0]");
	    next;
	}
	
	# Submit the replicon for processing
	my $aid = $Islandviewer->submit_analysis($accnum, $args);
	$logger->debug("Finished submitting $accnum, has analysis id $aid");
    }

    $logger->info("All analysis should now be submitted");
}
