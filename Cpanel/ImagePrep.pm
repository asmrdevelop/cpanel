
# cpanel - Cpanel/ImagePrep.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ImagePrep;

use cPstrict;

use Algorithm::Dependency::Ordered     ();
use Algorithm::Dependency::Source::HoA ();
use Carp                               ();
use Cwd                                ();
use File::Basename                     ();

use Cpanel::Imports;

use Cpanel::Config::Users     ();
use Cpanel::FileUtils::Touch  ();
use Cpanel::FindBin           ();
use Cpanel::ImagePrep::Task   ();
use Cpanel::ImagePrep::Common ();
use Cpanel::ImagePrep::Plugin ();
use Cpanel::LoadModule        ();
use Cpanel::OS                ();
use Cpanel::SafeDir::RM       ();
use Cpanel::SafeRun::Object   ();
use Cpanel::ServiceAuth       ();
use Cpanel::Services::Enabled ();
use Cpanel::Signal            ();
use Cpanel::Slurper           ();
use Whostmgr::Resellers::List ();

use constant PLUGIN_DIR                  => '/var/cpanel/snapshot_prep.d';
use constant SNAPSHOT_PREP_COMPLETE_FILE => '/var/cpanel/.snapshot_prep_complete';

=head1 NAME

Cpanel::ImagePrep - pre- and post-snapshot instance setup for cPanel & WHM

=cut

=head1 PREP TASKS

To define a new task, create a module under Cpanel/ImagePrep/Task/.
All of these are subclasses of C<Cpanel::ImagePrep::Task>. See that
module's documentation and existing examples to understand the interface.
The modules don't need to be separately registered in any list, as they will be
automatically discovered.

Each task provides a 'pre' (pre-snapshot) and 'post' (post-snapshot) action.

Normally 'pre' will occur on the source server and 'post' will occur on a
newly created instance. In the case of repairs, 'pre' and 'post' will
happen on the same server.

=cut

=head1 FUNCTIONS

=head2 regenerate_tokens()

Regenerate tokens based on the list of tasks that are not marked as
'non-repair only'.

For use in a repair scenario only. For normal snapshot preparation,
see snapshot_prep() and post_snapshot().

Options:

=over

=item * force - All cleanup tasks will be run regardless of their
prior state.

=item * output_callback - Code ref that must accept three arguments:
Stage, Task, and Status

=back

Returns a list with two elements:

=over

=item * Boolean status indicating success or failure.

=item * The reason (message) explaining the status.

=back

=cut

sub regenerate_tokens {
    my %opts = @_;

    common()->regular_logmsg('------- regenerate_tokens starting -------');

    return _pre_post( stages => { pre => 1, post => 1 }, force => $opts{force}, output_callback => $opts{output_callback} );
}

=head2 snapshot_prep()

Prepare a server to be snapshotted. The following tasks will be performed:

=over

=item * Suspend monitoring on services and disable crond.

=item * Shut down services that are having credentials cleared.

=item * Remove passwords, API tokens, etc. from any services known to store these on disk.
For some of these services, this will leave them in a broken state from which they cannot
recover until post_snapshot() is called.

=item * Clear other server-specific configuration.

=back

Options:

=over

=item * skip - Array of task names to skip. This will apply both
to the pre and post stages.

=item * output_callback - Code ref that must accept three arguments:
Stage, Task, and Status

=back

Returns a list with two elements:

=over

=item * Boolean status indicating success or failure.

=item * The reason (message) explaining the status.

=back

=cut

sub snapshot_prep {
    my (%opts) = @_;

    common()->_unlink( SNAPSHOT_PREP_COMPLETE_FILE() );

    common()->regular_logmsg('------- snapshot_prep starting -------');

    _systemd_check();
    _destructive_action_safeguards();

    Cpanel::SafeDir::RM::safermdir(Cpanel::ImagePrep::Common::FLAG_DIR);
    my @result = _pre_post( stages => { pre => 1 }, output_callback => $opts{output_callback}, skip => $opts{skip} );
    if ( $result[0] ) {
        common()->_touch( SNAPSHOT_PREP_COMPLETE_FILE() );
    }
    return @result;
}

=head2 post_snapshot()

Given an instance launched from a snapshot that has already had snapshot_prep() run on it, finish
the server setup by regenerating any configuration (including stored secrets) that must be unique
per server.

=over

=item * Update the server's primary IP, hostname, etc., and restore other server-specific configuration that was cleared during snapshot_prep().

=item * Regenerate passwords, API tokens, etc. for any services that had them removed during snapshot_prep().

=item * Restart services that were shut down during snapshot_prep().

=item * Enable crond and resume service monitoring.

=back

Options:

=over

=item * output_callback - Code ref that must accept three arguments:
Stage, Task, and Status

=back

Returns a list with two elements:

=over

=item * Boolean status indicating success or failure.

=item * The reason (message) explaining the status.

=back

=cut

sub post_snapshot {
    my %opts = @_;

    if ( !common()->_exists( SNAPSHOT_PREP_COMPLETE_FILE() ) ) {
        die "snapshot_prep must complete successfully before post_snapshot can run.\n";
    }

    common()->regular_logmsg('------- post_snapshot starting -------');

    _systemd_check();
    _destructive_action_safeguards();

    my @result = _pre_post( stages => { post => 1 }, output_callback => $opts{output_callback} );
    if ( $result[0] ) {
        common()->_unlink( SNAPSHOT_PREP_COMPLETE_FILE() );
        common()->clear_data();
    }
    return @result;
}

# _pre_post()
#
#   Private implementation behind regenerate_tokens(), snapshot_prep(), and post_snapshat().
#
#   Options:
#     - stages - Hash ref where each key is a stage to run: 'pre', 'post' or both.
#     - force  - If true, the tasks will be performed again even if their touch files are already in place.
#     - output_callback - (Optional) If provided, it should accept the following arguments and use them
#                         for formatting status output: stage_info, task, status
sub _pre_post {
    my (%opts)                 = @_;
    my $stages                 = delete $opts{stages}          // die 'need stages';
    my $force                  = delete $opts{force}           // 0;
    my $output_callback        = delete $opts{output_callback} // sub { 1 };
    my %manually_skipped_tasks = map { $_ => 1 } @{ delete $opts{skip} // [] };

    my $failed = 0;

    Cpanel::SafeDir::RM::safermdir(Cpanel::ImagePrep::Common::FLAG_DIR) if $stages->{post} && $force;

    unless ( -d Cpanel::ImagePrep::Common::FLAG_DIR ) {
        mkdir Cpanel::ImagePrep::Common::FLAG_DIR, 0700;
    }

    my %prep_tasks = _load_prep_tasks( skip => \%manually_skipped_tasks );

    #
    # Checks
    #
    for my $name ( sort keys %prep_tasks ) {
        if ( $prep_tasks{$name}->isa('Cpanel::ImagePrep::Check') ) {
            my $check_task = delete $prep_tasks{$name};
            my $output     = sub { $output_callback->( 'check', $check_task->task_name, shift ) };
            my ( $should_run, $reason ) = $check_task->should_run_for_stages($stages);
            if ( !$should_run ) {
                $output->($reason);
                next;
            }
            eval { $check_task->check() };
            my $exception = $@;
            if ($exception) {
                if ( $stages->{pre} ) {
                    common()->regular_logmsg("$name check failed: $exception");
                    $output->('FAILED');
                    $failed++;
                }
                else {
                    common()->regular_logmsg("$name check failed, but it's too late to abort the process: $exception");
                    $output->('FAILED (ignored)');
                }
            }
            else {
                $output->('OK');
            }
        }
    }
    if ($failed) {
        return ( 0, 'check stage failed' );
    }

    #
    # Tasks
    #

    # Allow dependency validation failures to occur before modifications.
    my @task_order = _calculate_dep_order( \%prep_tasks );

    if ( $stages->{pre} ) {
        _drain_taskqueue();
        _suspend_monitoring();
        _disable_crond();
    }
    if ( $stages->{post} ) {

        # Suspending monitoring does not survive a reboot
        _suspend_monitoring();
    }
    my %to_restart;
    my $stage_info = join( ',', reverse sort keys %$stages );
    for my $task (@task_order) {
        my $output = sub {
            my $task_cell = sprintf( '%s%s', $task, $prep_tasks{$task}->is_plugin ? ' [P]' : '' );
            $output_callback->( $stage_info, $task_cell, shift );
        };

        my ( $should_run, $reason ) = $prep_tasks{$task}->should_run_for_stages($stages);
        if ( !$should_run ) {
            $output->($reason);
            next;
        }

        my $work_done = eval {
            my $constants = Cpanel::ImagePrep::Task->new();

            if ( $stages->{pre} ) {
                my $outcome = $prep_tasks{$task}->pre();
                return                       if $outcome == $constants->PRE_POST_NOT_APPLICABLE;    # out of eval
                die "Failure in $task/pre\n" if $outcome == $constants->PRE_POST_FAILED;
            }

            if ( $stages->{post} ) {
                my $outcome = $prep_tasks{$task}->post();
                return                        if $outcome == $constants->PRE_POST_NOT_APPLICABLE;    # out of eval
                die "Failure in $task/post\n" if $outcome == $constants->PRE_POST_FAILED;
                $prep_tasks{$task}->write_flag_file;
                $to_restart{$_} = 1 for @{ $prep_tasks{$task}->need_restart() };
            }

            1;
        };
        if ( my $exception = $@ ) {
            common()->regular_logmsg("Error: ${task}: $exception");
            $output->('FAILED');
            $failed++;
        }
        elsif ($work_done) {
            $output->('Done');
        }
        else {
            $output->('Unnecessary (not applicable)');
        }
    }

    if ( $stages->{pre} ) {
        _drain_taskqueue();
    }

    common()->regular_logmsg("Finished: There were $failed failures.");

    #
    # Restart
    #
    my $restarted_ok = 1;
    if ( $stages->{post} ) {
        $restarted_ok &= _restart_services(%to_restart);
        _enable_crond();
        _resume_monitoring();

        $output_callback->(
            'restart',
            '*',
            keys(%to_restart) == 0 ? 'Unnecessary'
            : $restarted_ok        ? 'Done'
            :                        'FAILED'
        );
    }

    my $ready = $failed == 0 && $restarted_ok;
    common()->regular_logmsg( sprintf( 'Done: %s', $ready ? 'Ready' : 'Not ready' ) );
    my $reason = sprintf( '%sSystem %s ready for %s.', $ready ? ( '', 'is' ) : ( 'ERROR: ', 'is NOT' ), $stages->{post} ? 'use' : 'snapshotting' );

    return ( $failed == 0 ? 1 : 0, $reason );
}

sub _restart_services {
    my %to_restart = @_;
    my $restarted  = 0;

    for my $service ( sort keys %to_restart ) {
        if ( !Cpanel::Services::Enabled::is_enabled($service) ) {

            # Don't attempt to restart any disabled services
            common()->regular_logmsg("The $service service is disabled.");
            delete $to_restart{$service};
            next;
        }
        common()->regular_logmsg("Restarting $service …");
        my $restartsrv_script = '/usr/local/cpanel/scripts/restartsrv_' . $service;
        if ( -x $restartsrv_script ) {
            eval {
                Cpanel::SafeRun::Object->new_or_die(
                    program => $restartsrv_script,
                );
                ++$restarted;
            };
            if ( my $exception = $@ ) {
                common()->regular_logmsg("Failed to restart $service: $exception");
            }
        }
        else {
            common()->regular_logmsg("No restart script found for $service");
        }
    }

    return ( $restarted == %to_restart );
}

=head2 install_post_service()

Expected to be called immediately after snapshot_prep(): Install an on-first-boot service (similar to cloud-init) that will automatically run post_snapshot() via /usr/local/cpanel/scripts/post_snapshot.

This is helpful for the basic use case where instances should become ready shortly after boot, but if you need the flexibility to run on-first-boot tasks in a predictable order, you might prefer to call post_snapshot() via your own utilities rather than relying on this service.

Limitation: This only works on distros that use systemd and will throw an exception if a non-systemd distro is found.

=cut

sub install_post_service {
    _systemd_check();

    my $service_dir = '/lib/systemd/system';
    my $systemctl   = Cpanel::FindBin::findbin('systemctl');
    if ( !common()->_exists($service_dir) || !$systemctl ) {
        die 'install_post_service requires systemd';
    }

    Cpanel::Slurper::write(
        "$service_dir/post_snapshot.service",
        <<EOF
[Unit]
Description=Run cPanel scripts to fix VM attributes
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/cpanel/scripts/post_snapshot --yes --systemd

[Install]
WantedBy=multi-user.target
EOF
        , 0644,    # systemd wants it to be world-readable and will warn if it isn't
    );

    Cpanel::SafeRun::Object->new_or_die(
        program => $systemctl,
        args    => [ 'enable', 'post_snapshot' ],
    );

    common()->regular_logmsg('Installed and enabled post_snapshot service.');

    return 1;
}

=head2 delete_post_service()

Expected to be called as part of the C<post_snapshot> script.

Deletes the systemd service that was previously installed by C<install_post_service>.
If the service is not found or systemd is not present at all, a false value is returned.
The function returns a true value if the service is deleted.

=cut

sub delete_post_service {
    _systemd_check();

    my $service_dir = '/lib/systemd/system';
    my $systemctl   = Cpanel::FindBin::findbin('systemctl');
    if ( !common()->_exists($service_dir) || !$systemctl || !common()->_exists("$service_dir/post_snapshot.service") ) {
        common()->regular_logmsg('post_snapshot service is not present.');
        return;
    }

    Cpanel::SafeRun::Object->new_or_die(
        program => $systemctl,
        args    => [ 'disable', 'post_snapshot' ],
    );

    common()->_unlink("$service_dir/post_snapshot.service");

    common()->regular_logmsg('Disabled and deleted post_snapshot service.');

    return 1;
}

=head2 list_tasks()

List all of the Checks and Tasks.

Caller must provide C<output_callback>, which accepts a Check or Task object
and decides what to do with the information from each object.

=cut

sub list_tasks {
    my (%opts) = @_;
    my $output_callback = delete( $opts{output_callback} ) // sub { 1 };

    my %prep_tasks = _load_prep_tasks();

    for my $task_name ( sort keys %prep_tasks ) {
        my $task = $prep_tasks{$task_name};
        $output_callback->($task);
    }

    return;
}

sub _suspend_monitoring {
    return if -e '/var/run/chkservd.suspend';
    common()->regular_logmsg('Disabling service monitoring.');
    Cpanel::FileUtils::Touch::touch_if_not_exists('/var/run/chkservd.suspend');
    Cpanel::Signal::send_usr1_tailwatchd();
    return;
}

sub _resume_monitoring {
    common()->regular_logmsg('Restoring service monitoring.');
    common()->_unlink('/var/run/chkservd.suspend');
    return;
}

sub _cron_service {
    return Cpanel::OS::systemd_service_name_map()->{'crond'} || 'crond';
}

sub _disable_crond {
    return common()->disable_service( _cron_service() );
}

sub _enable_crond {
    return common()->enable_service( _cron_service() );
}

sub _drain_taskqueue {
    common()->regular_logmsg('Draining the cPanel task queue.');
    return common()->run_command( '/usr/local/cpanel/bin/servers_queue', 'run' );
}

sub _load_prep_tasks {
    my %opts = @_;
    my %skip = %{ delete( $opts{skip} ) || {} };
    Carp::croak('unknown option') if %opts;

    my %prep_tasks;

    my ( $check_dir, $task_dir ) = map { Cwd::abs_path( File::Basename::dirname(__FILE__) ) . "/ImagePrep/$_" } qw(Check Task);
    my @main_tasks = ( common()->_glob("$check_dir/*.pm"), common()->_glob("$task_dir/*.pm") );
    for my $module_path (@main_tasks) {
        my ( $module_type, $task_name ) = $module_path =~ m{/(Check|Task)/([a-zA-Z0-9_]+)\.pm$} or die "incomprehensible module path: $module_path";
        my $module_name = sprintf( 'Cpanel::ImagePrep::%s::%s', $module_type, $task_name );

        my $obj = eval {
            Cpanel::LoadModule::load_perl_module($module_name);
            $module_name->new();
        };
        if ( my $exception = $@ ) {
            die "Unable to load prep task '$task_name': $exception";
        }

        if ( delete $skip{$task_name} ) {
            $obj->manual_skip;
        }

        $prep_tasks{$task_name} = $obj;
    }

    die 'no tasks' if !%prep_tasks;

    my @prep_plugins = common()->_glob( PLUGIN_DIR . '/*.json' );
    for my $plugin_file (@prep_plugins) {
        my $plugin_task = Cpanel::ImagePrep::Plugin->load($plugin_file);
        my $plugin_name = $plugin_task->task_name;
        if ( delete $skip{$plugin_name} ) {
            $plugin_task->manual_skip;
        }
        $prep_tasks{$plugin_name} = $plugin_task;
    }

    die 'Unknown skip item(s): ' . join( ', ', sort keys %skip ) if %skip;

    return %prep_tasks;
}

sub _calculate_dep_order {
    my ($tasks) = @_;

    my @task_names = sort keys %$tasks;

    my $dep_input = {};
    for my $this_task (@task_names) {
        $dep_input->{$this_task} //= [];
        foreach my $dep_task ( $tasks->{$this_task}->deps() ) {
            die "Failed to set up dependencies for '$this_task' because the 'deps' attribute contains a self-reference: [ $dep_task ]\n" if $this_task eq $dep_task;
            die "Failed to set up dependencies for '$this_task' because the 'deps' attribute contains a missing task: [ $dep_task ]\n" unless exists $tasks->{$dep_task};
            push @{ $dep_input->{$this_task} }, $dep_task;
        }
        foreach my $before_task ( $tasks->{$this_task}->before() ) {

            # When a 'before' task exists, it gets a dependency inserted for this task
            die "Failed to set up dependencies for '$this_task' because the 'before' attribute contains a self-reference: [ $before_task ]\n" if $this_task eq $before_task;
            unless ( exists $tasks->{$before_task} ) {
                common()->warn_logmsg("$this_task - The 'before' attribute contains a missing task: [ $before_task ]");
                next;
            }
            push @{ $dep_input->{$before_task} }, $this_task;
        }
    }

    my $source = Algorithm::Dependency::Source::HoA->new($dep_input);
    my $dep    = Algorithm::Dependency::Ordered->new( source => $source, selected => [] ) or die "Failed to set up dependencies for tasks: " . _dump( [$dep_input], ['dep_input'] );
    my $order  = $dep->schedule_all;
    if ( ref $order ne 'ARRAY' ) {
        die "Failed to resolve task dependencies for tasks. There may be a circular dependency: " . _dump( [$dep_input], ['dep_input'] );
    }
    return @$order;
}

=head2 common()

Get an instance of Cpanel::ImagePrep::Common

=cut

my $common;

sub common {
    $common ||= Cpanel::ImagePrep::Common->new();
    return $common;
}

sub _destructive_action_safeguards {
    my %users = map { $_ => 1 } Cpanel::Config::Users::getcpusers(), keys %{ Whostmgr::Resellers::List::list() };
    if ( my @users = sort keys %users ) {
        if ( $ENV{DESTROY_CPANEL_USER_DATA} ) {
            common()->regular_logmsg('Server administrator requested destruction of cPanel user data by setting DESTROY_CPANEL_USER_DATA environment variable.');
            return;
        }
        die sprintf(
            <<EOF

**** WARNING ***********************************************************

  The snapshot_prep and post_snapshot scripts are only meant to be used
  with fresh installs of cPanel. They cannot be safely used on active
  production servers.

  Your server has %d cPanel accounts and/or resellers: %s

  THESE USERS WILL EXPERIENCE DATA LOSS.

  If these are customer accounts, using this script is very dangerous
  for two reasons:

  1) Some cPanel user data will be destroyed.

  2) The accounts themselves will remain on the server and therefore
     become part of any image you create. This could potentially give
     these users access to servers you did not intend for them to access
     if the snapshot is used as a template for future servers.

  No work has been performed yet. If you are sure you want to perform
  this destructive action, you can use the DESTROY_CPANEL_USER_DATA
  environment variable to bypass this safeguard.

************************************************************************

EOF
            , scalar(@users), join( ', ', @users )
        );
    }

    return;
}

=head2 delete_saved_copies()

Delete backup copies of files that were removed by the snapshot_prep utility.

The name of this function and the corresponding command-line argument avoid use of
the term "backup" to avoid creating confusion with the cPanel backup system.

=cut

sub delete_saved_copies {
    my $delete = common()->BACKUP_DIR;
    if ( !common()->_exists($delete) ) {
        common()->regular_logmsg('There are no saved copies of configuration files.');
        return 1;
    }
    if ( Cpanel::SafeDir::RM::safermdir($delete) ) {
        common()->regular_logmsg('Deleted saved copies of configuration files');
        return 1;
    }
    common()->regular_logmsg("Failed to delete $delete");
    return 0;
}

=head1 CLOUDLINUX 6 / NON-SYSTEMD

regenerate_tokens is supported on CloudLinux 6, but snapshot_prep
and post_snapshot are not.

This means for anything that is only used in snapshot_prep and
post_snapshot (including any tasks marked as C<non-repair only>),
it is acceptable to rely on systemd.

=cut

sub _systemd_check {
    if ( !Cpanel::OS::is_systemd() ) {
        my $os_name = Cpanel::OS::display_name();
        die <<EOF;

The snapshot_prep and post_snapshot utilities require systemd and do
not support your OS, $os_name.

EOF
    }
    return;
}

sub _dump {
    my @args = @_;
    require Data::Dumper;
    return Data::Dumper->new(@args)->Sortkeys(1)->Terse(1)->Dump();
}

=head1 SEE ALSO

=over

=item * /usr/local/cpanel/scripts/snapshot_prep

=item * /usr/local/cpanel/scripts/post_snapshot

=back

=cut

1;
