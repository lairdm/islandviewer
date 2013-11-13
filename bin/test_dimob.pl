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
use Islandviewer::Dimob;


MAIN: {
    my $cfname; my $workdir; my $logger;
    my $res = GetOptions("config=s"   => \$cfname,
			 "workdir=s"  => \$workdir
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

    my $dimob_obj = Islandviewer::Dimob->new({workdir => "$workdir",
                                         microbedb_version => 80,
                                         MIN_GI_SIZE => 4000});

    my @gis = $dimob_obj->run_dimob(2);

    print Dumper @gis;
};
