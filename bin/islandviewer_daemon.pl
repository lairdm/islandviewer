#!/usr/bin/env perl

$|++;

# Catch sigint (ctrl-c) and handle properly
$SIG{'INT'} = 'INT_handler';

use warnings;
use strict;
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use Log::Log4perl;

BEGIN{
# Find absolute path of script
my ($path) = abs_path($0) =~ /^(.+)\//;
chdir($path);
sub mypath { return $path; }
};

use lib "../lib";
use Islandviewer;
use Islandviewer::Server;

my $server;

MAIN: {
    my $cfname; my $logger;
    my $res = GetOptions("config=s" => \$cfname);

    # Find the config file and make sure we can open it
    $cfname ||= '../etc/islandviewer.config';
    die "Error, no configuration file found at $cfname" 
        unless(-f $cfname && -r $cfname);    

    my $Islandviewer = Islandviewer->new({cfg_file => $cfname });

    my $cfg = Islandviewer::Config->config;

    Log::Log4perl::init($cfg->{logger_conf});
    $logger = Log::Log4perl->get_logger;
    $logger->debug("Logging initialize");

    $server = Islandviewer::Server->initialize({islandviewer => $Islandviewer});

    # Make the PID file, probably not needed, but let's make one
    writePID($cfg->{pid_file});

    eval {
	$server->runServer;
    };
    if($@) {
	$logger->error("Error!  This should never happen! $@\n");
    }

    # Clean up after ourselves
    unlink $cfg->{pid_file};

};

sub writePID {
    my $pid_file = shift;

    open PID, ">$pid_file"
	or die "Error, can't open pid file $pid_file: $@";

    print PID "$$\n";
    close PID;
}

sub INT_handler {
    print STDERR "sigint received, shutting down.\n";

    if($server) {
	$SIG{'INT'} = 'INT_handler';
	$server->finish;
	return;
    } else {
	print "scheduler doesn't seem to be started yet, goodbye\n";
	exit;
    }
}
