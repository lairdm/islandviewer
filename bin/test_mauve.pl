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
use Islandviewer::Mauve;

MAIN: {
    my $cfname; my $workdir;
    my $res = GetOptions("config=s"   => \$cfname,
			 "workdir=s"  => \$workdir,
    );

    die "Error, no config file given"
      unless($cfname);

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });
    my $cfg = Islandviewer::Config->config;

    my $mauve_obj = Islandviewer::Mauve->new({workdir => $workdir,
					     });

    my $result_obj = $mauve_obj->run('/data/NCBI_genomes/curated/Bacteria/Pseudomonas_aeruginosa_PAO1_uid57945/NC_002516.faa', '/data/NCBI_genomes/curated/Bacteria/Burkholderia_mallei_ATCC_23344_uid57725/NC_006348.faa');

    print Dumper $result_obj;

};
