#!/usr/bin/env perl

# Used to submit a custom genome, given a file name it copies it over
# and tries to prep it for analysis
# Returns the cid number which can be used to sub the analysis
# for execution.

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

MAIN: {
    my $cfname; my $filename; my $name; my $logger;
    my $res = GetOptions("config=s"   => \$cfname,
			 "filename=s" => \$filename,
			 "name=s"     => \$name
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

    unless( -f $filename && -r $filename ) {
	$logger->error("Custom genome $filename is not readable, failing");
	print "0\n";
	exit;
    }

    my $cid;
    eval {
	$cid = $Islandviewer->submit_and_prep($filename, 
						 ($name ? $name : 'custom genome'));
    };
    if($@) {
	$logger->error("Failed upload of file $filename: $@");
	print "0\n$@\n";
	exit;
    }

    print "$cid\n";
};
