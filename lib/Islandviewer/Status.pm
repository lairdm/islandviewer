=head1 NAME

    Islandviewer::Status

=head1 DESCRIPTION

    Object for monitoring Islandviewer jobs

=head1 SYNOPSIS

    use Islandviewer::Status;


=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Nov 26, 2013

=cut

package Islandviewer::Status;

use strict;
use Moose;
use Islandviewer::Config;
use Islandviewer::DBISingleton;
use Islandviewer::Constants qw(:DEFAULT $STATUS_MAP $REV_STATUS_MAP $ATYPE_MAP);

use Net::ZooKeeper::WatchdogQueue;

use Log::Log4perl qw(get_logger :nowarn);

my $cfg; my $logger;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;

    $logger = Log::Log4perl->get_logger;

    # Create our watchdog so observers can keep an eye
    # on our status
    $self->{watchdog} = new Net::ZooKeeper::WatchdogQueue($cfg->{zookeeper},
							  $cfg->{zk_analysis});

    eval {
	$self->{watchdog}->attach_queue(timer => $cfg->{zk_analysis_timer});
    };
    if($@) {
	$logger->logdie("Error attaching to zookeeper analysis timer: $@")
    }

}

# We're going to check the status of an
# analysis, including all the modules associated
# with it.  This involves both checking the 
# database and if its running then checking 
# the zookeeper node for it

sub check_status {
    my $self = shift;
    my $aid = shift;
    my $modules;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $find_modules = $dbh->prepare("SELECT taskid, prediction_method, status FROM GIAnalysisTask WHERE aid_id = ?");

    $find_modules->execute($aid)
	or $logger->logdie("Error fetching status for analysis $aid, $DBI::errstr");

    while(my($taskid, $method, $status) = 
	  $find_modules->fetchrow_array) {

	if($status == $STATUS_MAP->{PENDING}) {
	    # If its pending, we're just waiting, 
	    # nothing to do
	    $modules->{$method} = $status;

	} elsif($status == $STATUS_MAP->{RUNNING}) {
	    # We think its running, is it really?
	    if($self->find_timer($aid, $method)) {
		$modules->{$method} = $status;
	    } else {
		$modules->{$method} =  $STATUS_MAP->{ERROR};

		# Mark it as an error
		$dbh->do("UPDATE GIAnalysisTask SET status = ? WHERE taskid = ?", undef, $STATUS_MAP->{ERROR}, $taskid)
		    or $logger->logdie("Error updating status for analysis $aid, $DBI::errstr");
	    } 

	} else {
	    # We think its an error or complete
	    $modules->{$method} = $status;
	}
    }

    # Send back all the statuses for the modules
    return $modules;
}

sub check_analysis_status {
    my $self = shift;
    my $aid = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $analysis_status = $dbh->prepare("SELECT status from Analysis WHERE aid_id = ?")
	or $logger->logdie("Error preparing fetch analysis status for $aid, $DBI::errstr");

    $analysis_status->execute($aid)
	or $logger->logdie("Error fetching analysis status for $aid, $DBI::errstr"); 

    if(my($status) = 
       $analysis_status->fetchrow_array()) {
	return $status;
    }

    return 0;
}

# For checking for run-aways by a maitenance script,
# find all the stuck running jobs
# Returned in the format ["aid.module", "aid.module"...]

sub find_expired {
    my $self = shift;

    # Fetch only the expired timers
    my $timers = $self->{watchdog}->get_timers(1);

    my @expired;
    foreach my $job (keys %{$timers}) {
	push @expired, $job;
    }

    return @expired;
}

sub find_timer {
    my $self = shift;
    my $aid = shift;
    my $method = shift;

    my $timers = $self->{watchdog}->get_timers();

    # Find our module
    if(my $t_alive = $timers->{"$aid.$method"}) {
	# If our timer has expired that's a fail
	# But we're going to allow some modules to take longer
	# than others, we want to have a pretty short default
	# time but allow a per module custom time limit
	if($cfg->{"zk_analysis_timer_$method"}) {
	    return ($t_alive > $cfg->{"zk_analysis_timer_$method"} ? 0 : 1);
	} else {
	    return ($t_alive > $cfg->{zk_analysis_timer} ? 0 : 1);
	}
    }

    # If we don't find it, that's a fail
    $logger->warn("We didn't find a timer for aid $aid, module $method but we expecting to");
    return 0;
}

1;
