package Cpanel::TaskProcessors::TailwatchTasks;

# cpanel - Cpanel/TaskProcessors/TailwatchTasks.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

{

    package Cpanel::TaskProcessors::RestartTailwatch;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return 0 == $task->args();
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'restart tailwatchd script',
                'cmd'    => '/usr/local/cpanel/scripts/restartsrv_tailwatchd',
            }
        );
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/restart/;
    }
}

{

    package Cpanel::TaskProcessors::ReloadTailwatch;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    sub overrides {
        my ( $self, $new, $old ) = @_;

        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;

        return 0 == $task->args();
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        require Cpanel::Signal;
        return if Cpanel::Signal::send_hup('tailwatchd');

        $self->checked_system(
            {
                'logger' => $logger,
                'name'   => 'restart tailwatchd script',
                'cmd'    => '/usr/local/cpanel/scripts/restartsrv_tailwatchd',
            }
        );
        return;
    }

    sub deferral_tags {
        my ($self) = @_;
        return qw/restart/;
    }
}

{

    package Cpanel::TaskProcessors::Eximstats::SQLImport;
    use parent 'Cpanel::TaskQueue::FastSpawn';

    use Cpanel::LoadModule ();

    our $_UPGRADE_IN_PROGRESS_FILE = '/usr/local/cpanel/upgrade_in_progress.txt';

    sub overrides {
        my ( $self, $new, $old ) = @_;
        return $self->is_dupe( $new, $old );
    }

    sub is_valid_args {
        my ( $self, $task ) = @_;
        return ( 1 == $task->args() );
    }

    # The work defined in _do_child_task will not procede if a WHM update is in progress,
    # if $file no longer exists, or $import_file exists (indicating another task/process
    # is already executing).
    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        Cpanel::LoadModule::load_perl_module('Cpanel::TimeHiRes');
        Cpanel::LoadModule::load_perl_module('File::Copy');
        Cpanel::LoadModule::load_perl_module('Time::HiRes');
        Cpanel::LoadModule::load_perl_module('File::ReadBackwards');
        Cpanel::LoadModule::load_perl_module('Cpanel::EximStats::ConnectDB');
        Cpanel::LoadModule::load_perl_module('Cpanel::EximStats::Retention');

        my ($file) = $task->args();

        my $import_file = qq{$file.import};

        return 1 if ( -e $_UPGRADE_IN_PROGRESS_FILE and not -e q{/var/cpanel/dev_sandbox} ) or not -e $file or -e $import_file;

        my $dbh = Cpanel::EximStats::ConnectDB::dbconnect();

        $dbh->{PrintError} = 0;    # hush errors in foreground

        # move $file to $import_file
        File::Copy::move( $file, $import_file );

        my $eximstats_retention_days = Cpanel::EximStats::Retention::get_valid_exim_retention_days();
        my $eximstats_retention_sec  = $eximstats_retention_days * 24 * 3600;

        my $saw_error;
        my $write_count = 0;

        my $bw = File::ReadBackwards->new($import_file) or die $!;

        # start at the bottom of the file, process backwards (newest first); end processing
        # at EOF (top) or when we reach the first record outside of our retention window.
      INSERT:
        while ( my $query = $bw->readline ) {
            ++$write_count;
            chomp $query;

            #-- trust, but minimally verify there are no red flags in the SQL
            next INSERT if $query =~ m/DELETE|DROP|JOIN|SELECT|TRUNCATE|WHERE/i;

            # extract unixtime (all eximstats tables, therefore INSERTS, contain a "sendunixtime" field
            $query =~ m/([1-9]\d\d\d\d\d\d\d\d\d)/;
            my $query_time = $1;

            # $query_time must be
            my $oldest_allowed = time - $eximstats_retention_sec;

            # check to see if $query_time is older than the oldest allowed
            if ( $query_time < $oldest_allowed ) {
                $logger->warn(qq{Found a record outside of the retentions window. Stopping import and deleting import file.});
                last;
            }

            #-- try all SQL statements even if some give error
            local $@;
            my $ok = eval { $dbh->do($query) } || undef;
            ++$saw_error if not $ok;

            # play nice with eximstats' writing to $dbh, pause for .25 seconds every
            # time 5 records are read from existats.sql
            if ( $write_count == 5 ) {
                $write_count = 0;
                Cpanel::TimeHiRes::sleep(.25);    # 250000 = .25 seconds
            }
        }

        # close out file handle managed by File::ReadBackwards
        $bw->close;

        $logger->warn(qq{Errors seen while processing $import_file}) if $saw_error;

        unlink $import_file;

        return 1;
    }

}

sub to_register {
    return (
        [ 'restarttailwatch',          Cpanel::TaskProcessors::RestartTailwatch->new() ],
        [ 'reloadtailwatch',           Cpanel::TaskProcessors::ReloadTailwatch->new() ],
        [ 'eximstats_import_sql_file', Cpanel::TaskProcessors::Eximstats::SQLImport->new() ],
    );
}

1;
