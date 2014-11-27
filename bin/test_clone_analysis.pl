#!/usr/bin/env perl

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
use Islandviewer::Analysis;

MAIN: {
    my $cfname; my $aid; my $logger;
    my $res = GetOptions("config=s"   => \$cfname,
			 "aid=s" => \$aid,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    my $cfg = Islandviewer::Config->config;

    if($cfg->{logger_conf} && ( -r $cfg->{logger_conf})) {
	Log::Log4perl::init($cfg->{logger_conf});
	$logger = Log::Log4perl->get_logger;
	$logger->debug("Logging initialized");
    }

    $logger->info("Creating analysis object for aid $aid");
    my $analysis = Islandviewer::Analysis->new({workdir => $cfg->{analysis_directory}, aid => $aid});

    $logger->info("Cloning analysis object for aid $aid");
    my $new_analysis = $analysis->clone();

    print "new aid: $new_analysis->{aid}\n";
    print Dumper $new_analysis;

};
