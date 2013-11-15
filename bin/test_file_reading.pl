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
    my $cfname; my $workdir; my $filename;
    my $res = GetOptions("config=s"   => \$cfname,
			 "workdir=s"  => \$workdir,
			 "filename=s" => \$filename,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    my $cfg = Islandviewer::Config->config;

    my $genome_obj = Islandviewer::GenomeUtils->new(
	{ workdir => $workdir});

    my ($name, $base_file, $file_types) = $genome_obj->lookup_genome(2);

    print "$name, $base_file, $file_types\n";
 
    my $formats = $genome_obj->parse_formats($file_types);

    print Dumper $formats;

    my $format_str = $genome_obj->find_file_types();

    print "Current: $format_str\n";

    $genome_obj->read_and_convert("$base_file.gbk", $name);

    my $format_str = $genome_obj->find_file_types();

    print "Regenerated: $format_str\n";

};
