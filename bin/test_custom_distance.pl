#!/usr/bin/env perl

use warnings;
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
use lib "/home/lairdm/libs";
use Islandviewer;
use Islandviewer::Config;
use Islandviewer::Distance;

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

    my $dist_obj = Islandviewer::Distance->new({scheduler => 'Islandviewer::NullScheduler', workdir => $cfg->{workdir}, num_jobs => 8, block => 1 });

    my $repHash->{2} = '/home/lairdm/islandviewer/docs/sample_files/NC_002516.faa';

    $dist_obj->calculate_all(custom_replicon => $repHash);
#    $dist_obj->submit_sets(1);


}
