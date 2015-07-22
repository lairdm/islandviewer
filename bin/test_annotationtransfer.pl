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
use Islandviewer::Config;
use Islandviewer::AnnotationTransfer;

MAIN: {
    my $cfname; my $set; my $workdir; my $root;
    my $watchdog; my $logger;
    my $res = GetOptions("config=s"   => \$cfname,
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
	$logger->debug("Logging initialized");
    }

    my $transfer_obj = Islandviewer::AnnotationTransfer->new({microbedb_ver => 89, 
							   workdir => $workdir});

    my $results = $transfer_obj->run('NC_017436.1');

    print Dumper $results;
};
