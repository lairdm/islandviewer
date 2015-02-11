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
use Islandviewer::GenomeUtils;

MAIN: {
    my $cfname; my $workdir; my $filename; my $logger;
    my $res = GetOptions("config=s"   => \$cfname,
			 "workdir=s"  => \$workdir,
			 "filename=s" => \$filename,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    my $cfg = Islandviewer::Config->config;

    if($cfg->{logger_conf} && ( -r $cfg->{logger_conf})) {
	Log::Log4perl::init($cfg->{logger_conf});
	$logger = Log::Log4perl->get_logger;
	$logger->debug("Logging initialize");
	# We want to ensure trace level for an update
	$logger->level("TRACE");
    }

    my $genome_obj = Islandviewer::GenomeUtils->new(
	{ workdir => $workdir});

    my $res = $genome_obj->read_and_check($filename);

    print "Found $res contigs\n";
}
