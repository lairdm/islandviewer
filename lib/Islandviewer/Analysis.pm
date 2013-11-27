=head1 NAME

    Islandviewer::Analysis

=head1 DESCRIPTION

    Object to maintain and evaluate an analysis

=head1 SYNOPSIS

    use Islandviewer::Analysis;



=head1 AUTHOR

    Matthew Laird
    Brinkman Laboratory
    Simon Fraser University
    Email: lairdm@sfu.ca

=head1 LAST MAINTAINED

    Nov 15, 2013

=cut

package Islandviewer::Analysis;

use strict;
use Moose;
use Log::Log4perl qw(get_logger :nowarn);
use JSON;
use Data::Dumper;

use Islandviewer::DBISingleton;
use Islandviewer::Constants qw(:DEFAULT $STATUS_MAP $REV_STATUS_MAP $ATYPE_MAP);

use MicrobeDB::Versions;

my $cfg; my $logger; my $cfg_file;

my @modules = qw(Distance Islandpick Sigi Dimob Summary);

sub BUILD {
    my $self = shift;
    my $args = shift;

    $cfg = Islandviewer::Config->config;
    $cfg_file = File::Spec->rel2abs(Islandviewer::Config->config_file);

    $logger = Log::Log4perl->get_logger;

    die "Error, work dir not specified:  $args->{workdir}"
	unless( -d $args->{workdir} );
    $self->{base_workdir} = $args->{workdir};

    # We're loading an existing analysis
    if($args->{aid}) {
	$self->{aid} = $args->{aid};
	$self->load_analysis($args->{aid});
    }

}

sub change_logfile {
    my $self = shift;

    my $app = Log::Log4perl->appender_by_name("errorlog");
    if($self->{workdir}) {
	$app->file_switch($self->{workdir} . "/analysis.log");

    } else {
	$app->file_switch($self->{base_workdir} . "/analysis.log");
    }
    $logger->debug("Logging initialized, aid $self->{aid}");
}

sub load_analysis {
    my $self = shift;
    my $aid = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;
	
    my $fetch_analysis = $dbh->prepare("SELECT atype, ext_id, default_analysis, status, workdir, microbedb_ver FROM Analysis WHERE aid = ?");

    $fetch_analysis->execute($aid) 
	or $logger->logdie("Error, can't fetch analysis $aid");
    
    # There should only be one
    if(my($atype, $ext_id, $default_analysis, $status, $workdir, $microbedb_ver) =
       $fetch_analysis->fetchrow_array) {
	$self->{atype} = $atype;
	$self->{ext_id} = $ext_id;
	$self->{default_analysis} = $default_analysis;
	$self->{status} = $status;
	$self->{base_workdir} = $workdir;
	$self->{microbedb_ver} = $microbedb_ver;
    } else {
	$logger->logdie("Error, can't find analysis $aid");
    }

    unless( -d $self->{base_workdir} ) {
	$logger->logdie("Error, workdir " . $self->{base_workdir} . " doesn't exist for aid " . $self->{aid});
    }

    # Move the logging over to the analysis
    $self->change_logfile();

}

# Submit the analysis and all its pieces in to the
# database, this is the guy who has to know about all
# the various modules for a submission.

sub submit {
    my $self = shift;
    my $genome_obj = shift;
    my $args = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;
    
    my $microbedb_ver;
    # Create a Versions object to look up the correct version
    my $versions = new MicrobeDB::Versions();

    # If we've been given a microbedb version AND its valid...
    if($args->{microbedb_ver} && $versions->isvalid($args->{microbedb_ver})) {
	$microbedb_ver = $args->{microbedb_ver}
    } else {
	$microbedb_ver = $versions->newest_version();
    }

    # Submit the analysis!
    my $insert_analysis = $dbh->prepare("INSERT INTO Analysis (atype, ext_id, default_analysis, status, microbedb_ver) VALUES (?, ?, ?, ?, ?)");
    
    $logger->trace("Submitting analysis type: " . $genome_obj->{type} . ", id: " . $genome_obj->{accnum});
    $insert_analysis->execute($genome_obj->{type}, 
			      $genome_obj->{accnum}, 
			      ($args->{default_analysis} ? 1 : 0),
			      $STATUS_MAP->{PENDING},
			      $microbedb_ver
	) or $logger->logdie("Error inserting analysis, accnum $genome_obj->{accnum}: $DBI::errstr");

    # Now we fetch the analysis id, because this is needed in making
    # the workdir....
    my $aid = $dbh->last_insert_id(undef, undef, undef, undef);
    $self->{aid} = $aid;

    # We could do this with triggers but we won't, see below.
    # Make the workdir for our analysis
    $self->{workdir} = $self->{base_workdir} . "/$aid";
    unless(mkdir $self->{workdir}) {
	# Oops, we weren't able to make the workdir...
	$self->set_status('ERROR');
	return 0;
    }

    # Move the logging over to the analysis
    $self->change_logfile();

    $dbh->do("UPDATE Analysis SET workdir = ? WHERE aid = ?", undef, $self->{workdir}, $aid);

    # Alright, we have our analysis inserted, now time to add the components
    foreach my $mod (@modules) {
	$logger->trace("Adding GI task $mod");
	eval {
	    $self->submit_module($mod, $genome_obj, $args->{$mod});
	};
	if($@) {
	    $logger->error("Error adding $mod, $@");
	    return 0;
	}
    }

    # We need to submit the job to the scheduler
    $logger->debug("Submitting aid $aid to scheduler " . $cfg->{default_scheduler});
    my $scheduler;
    eval {
	no strict 'refs';
	$logger->trace("Initializing scheduler... (aid $aid)");
	(my $mod = "$cfg->{default_scheduler}.pm") =~ s|::|/|g; # Foo::Bar::Baz => Foo/Bar/Baz.pm
	require "$mod";
	$scheduler = "$cfg->{default_scheduler}"->new();
    };
    if($@) {
	$self->set_status('ERROR');
	$logger->logdie("Error, can't load scheduler (aid $aid): $@");
    }

    # We have a scheduler object, submit!
    my $job_type = ($args->{job_type} ? $args->{job_type} : 'Islandviewer');
    $scheduler->build_and_submit($aid, $job_type, $self->{workdir}, $args, @modules);

    $logger->trace("Finished submitting aid $aid");
    return $aid;
}

sub submit_module {
    my $self = shift;
    my $module = shift;
    my $genome_obj = shift;
    my $args = shift;

    my $dbh = Islandviewer::DBISingleton->dbh;
    
    my $JSON_args;
    if($args) {
	$JSON_args = to_json($args);
    }

    $logger->trace("Adding module $module, json: $JSON_args");

    $dbh->do("INSERT INTO GIAnalysisTask (aid_id, prediction_method, status, parameters) VALUES (?, ?, ?, ?)", undef, 
	     $self->{aid},
	     $module,
	     $STATUS_MAP->{PENDING},
	     $JSON_args
	) or $logger->logdie("Error inserting analysis module $module: $DBI::errstr");

}

sub run {
    my $self = shift;
    my $module = shift;

    $self->{module} = $module;

    # Load the module information
    my $dbh = Islandviewer::DBISingleton->dbh;

    my $fetch_task = $dbh->prepare("SELECT taskid, status, parameters FROM GIAnalysisTask WHERE aid_id = ? AND prediction_method = ?");
    
    $fetch_task->execute($self->{aid}, $module) 
	or $logger->logdie("Error, can't fetch analysis $module");
    
    # There should only be one
    my($taskid, $task_status, $parameters, $args);
    if(($taskid, $task_status, $parameters) =
       $fetch_task->fetchrow_array) {
	$self->{taskid} = $taskid;

	if($parameters) {
	    $args = decode_json $parameters;
	    print "Parameters for $module\n";
	    print Dumper $args;
	}
    } else {
	$logger->logdie("Error, can't find analysis task $module");
    }

    $self->set_module_status('RUNNING');

    # Now we need to make our working directory
    $self->{workdir} = $self->{base_workdir} . "/$module";
    unless( -d $self->{workdir} ) {
	unless(mkdir $self->{workdir}) {
	    # Oops, we weren't able to make the workdir...
	    $self->set_status('ERROR');
	    $self->set_module_status('ERROR');
	    $logger->error("Can't make module working directory " . $self->{workdir});
	    return 0;
	}
    }

    # Move the logging over to the analysis
    $self->change_logfile();

    # Setup the needed arguments for the modules
    $args->{workdir} = $self->{workdir};
    $args->{microbedb_ver} = $self->{microbedb_ver};
    print "Sending args:\n";
    print Dumper $args;

    my $mod_obj; my $res;
    eval {
	no strict 'refs';
	$logger->trace("Loading module $module");
	require "Islandviewer/$module.pm";
	$mod_obj = "Islandviewer::$module"->new($args);

	# How we're going to do it is the module doesn't
	# need to know about how to write results or such
	# it just reports back success or failure.  But we'll
	# pass ourself in, and provide an interface for it
	# to send results to, if it has any (things like Distance
	# do it themself)
	$res = $mod_obj->run($self->{ext_id}, $self);
    };
    if($@) {
	$self->set_module_status('ERROR');
	$logger->logdie("Can't run module $module: $@");
    }

    if($res) {
	$self->set_module_status('COMPLETE');
	return 1;
    } else {
	$self->set_module_status('ERROR');
	return 0;
    }
}

sub record_islands {
    my $self = shift;
    my $module_name = shift;
    my @islands = @_;

    my $dbh = Islandviewer::DBISingleton->dbh;

    my $insert_island = $dbh->prepare("INSERT INTO GenomicIsland (aid_id, start, end, prediction_method) VALUES (?, ?, ?, ?)");

    foreach my $island (@islands) {
	$insert_island->execute($self->{aid}, $island->[0], $island->[1], $self->{module})
	    or $logger->logdie("Error loading island: $DBI::errstr");
    }
}

sub set_status {
    my $self = shift;
    my $status = shift;

    $status = uc $status;

    my $dbh = Islandviewer::DBISingleton->dbh;

    # Make sure its a valid status
    if($STATUS_MAP->{$status}) {
	$logger->trace("Updating analysis " .  $self->{aid} . " to status $status");
	$dbh->do("UPDATE Analysis SET status = ? WHERE aid = ?", undef, $STATUS_MAP->{$status}, $self->{aid});
    } else {
	$logger->error("Error, status $status doesn't seem to be valid");
    }
}

sub set_module_status {
    my $self = shift;
    my $status = shift;

    $status = uc $status;

    my $dbh = Islandviewer::DBISingleton->dbh;

    # Make sure its a valid status
    if($STATUS_MAP->{$status}) {
	my $datestr = '';
	$datestr = ', start_date = NOW() ' if($status eq 'RUNNING');
	$datestr = ', complete_date = NOW() ' if($status eq 'COMPLETE');

	$logger->trace("Updating analysis " .  $self->{aid} . ", module " . $self->{module} . " to status $status");
	$dbh->do("UPDATE GIAnalysisTask SET status = ? $datestr WHERE taskid = ?", undef, $STATUS_MAP->{$status}, $self->{taskid});
    } else {
	$logger->error("Error, status $status doesn't seem to be valid (module $self->{module})");
    }
}

# We could use a trigger like this for the insertion in to
# the analysis table, but we're not going to, just to be
# safe, since someone in the future might not notice this
# when making a new dev version, etc of the software

# DELIMITER //    

#    CREATE TRIGGER inserName BEFORE INSERT ON name FOR EACH ROW
#    BEGIN
#        DECLARE next_ai INT;
#        SELECT auto_increment INTO next_ai
#          FROM information_schema.tables
#          WHERE table_schema = DATABASE() AND table_name = 'name';
#        SET NEW.name = CONCAT("I am number ", next_ai);
#    END //

#DELIMITER ;
