=head1 NAME

    Islandviewer::Torque

=head1 DESCRIPTION

    Submit jobs to Torque

=head1 SYNOPSIS

    use Islandviewer::Torque;

    my $scheduler = Islandviewer::Torque->new();
    $scheduler->submit($cmd);

=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Sept 27, 2013

=cut

package Islandviewer::Torque;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use Cwd;

use Islandviewer::Config;

my $cfg; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

}

sub submit {
    my $self = shift;
    my $name = shift;
    my $cmd = shift;
    my $workdir = shift;

    my $qsub_file = "$workdir/qsub/$name.qsub";
    # Clean the paths a little since qsub doesn't like //
    $qsub_file =~ s/\/\//\//g;

    $name = 'cvtree_' . $name;

    # First let's make sure we have a work directory for qsub files
    mkdir "$workdir/qsub"
	unless( -d "$workdir/qsub" );

    open(QSUB, ">$qsub_file") or
	die "Error, can't open qsub file $workdir/qsub/$name.qsub: $!";

    print QSUB "# Build by Islandviewer::Torque\n\n";

    # We need to set the environment variable for the 
    # MicrobeDB API, so it knows what database to connect to
    my $microbedb_database;
    if($cfg->{microbedb}) {
        $microbedb_database = $cfg->{microbedb};
    } elsif($ENV{"MicrobeDBV2"}) {
        $microbedb_database = $ENV{"MicrobeDBV2"};
    } elsif($ENV{"MicrobeDB"}) {
        $microbedb_database = $ENV{"MicrobeDB"};
    }

    if($microbedb_database) {
        print QSUB "# Setting MicrobeDB database to use\n";
        print QSUB "export MicrobeDB=\"$microbedb_database\"\n\n";
    }

    print QSUB "echo \"Running cvtree for set $name\"\n";
    print QSUB "\n";
    print QSUB "#PBS -l walltime=10:00:00\n";
    print QSUB "\n";
    print QSUB "$cmd\n";

    close QSUB;

    my $cwd = getcwd;
    $logger->debug("Stashing cwd $cwd, switching to /");
    chdir '/';

    my $qsub_cmd = $cfg->{qsub_cmd} .
	" -d $workdir -N $name $qsub_file";

    $logger->debug("Issuing command: $qsub_cmd");

    # Pipe to stdin
    open(CMD, '-|', $qsub_cmd);
    my $output = do { local $/; <CMD> };
    close CMD;

    $logger->debug("Switching cwd back to $cwd");
    chdir $cwd;

    my $return_code = ${^CHILD_ERROR_NATIVE};

    unless($return_code == 0) {
	# We have an error of some kind with the call
	$logger->error("Error submitting job: $return_code: $output");
	return 0;
    }

    return 1;
}

1;
