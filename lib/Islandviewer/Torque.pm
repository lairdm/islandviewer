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

use Islandviewer::Config;

my $cfg;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

}

sub submit {
    my $self = shift;
    my $name = shift;
    my $cmd = shift;

    my $qsub_file = "$cfg->{workdir}/qsub/$name.qsub";
    # Clean the paths a little since qsub doesn't like //
    $qsub_file =~ s/\/\//\//g;

    $name = 'cvtree_' . $name;

    # First let's make sure we have a work directory for qsub files
    mkdir "$cfg->{workdir}/qsub"
	unless( -d "$cfg->{workdir}/qsub" );

    open(QSUB, ">$qsub_file") or
	die "Error, can't open qsub file $cfg->{workdir}/qsub/$name.qsub: $!";

    print QSUB "# Build by Islandviewer::Torque\n\n";
    print QSUB "echo \"Running cvtree for set $name\"\n";
    print QSUB "$cmd\n";

    close QSUB;

    my $cmd = $cfg->{qsub_cmd} .
	" -d $cfg->{workdir} -N $name $qsub_file";

    open(CMD, '-|', $cmd);
    my $output = do { local $/; <CMD> };
    close CMD;

    my $return_code = ${^CHILD_ERROR_NATIVE};

    unless($return_code == 0) {
	# We have an error of some kind with the call
	return 0;
    }

    return 1;
}

1;
