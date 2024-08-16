package Cpanel::TailWatch::ChkServd;

# cpanel - Cpanel/TailWatch/ChkServd.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#chkservd is special: it doesn't actually tail any log files, despite being
#a tailwatchd module.
#
#It also monitors disk usage, which isn't related to services.
#----------------------------------------------------------------------

##############################################################
## no other use()s, require() only *and* only then in init() #
##############################################################

use cPstrict;

use base 'Cpanel::TailWatch::Base';
use Cpanel::TailWatch::ChkServd::Version ();
use Cpanel::RestartSrv::Script           ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::Chkservd::Tiny               ();
use Cpanel::Waitpid                      ();
use Socket                               ();    # only brings an extra 100 kB to the binary
use Cpanel::Sys::Boot                    ();
use Cpanel::Sys::Setsid                  ();
use Cpanel::Notify::Deferred             ();

our $VERSION;
*VERSION = \$Cpanel::TailWatch::ChkServd::Version::CHKSERVD_VERSION;

our $CHECK_FAILED  = 0;
our $CHECK_OK      = 1;
our $CHECK_SKIPPED = 2;
our $CHECK_UNKNOWN = 3;

my $HANG_ALLOWED_INTERVALS = 2;

my $DEFAULT_DISKUSAGE_WARN_PERCENT     = 82.55;
my $DEFAULT_DISKUSAGE_CRITICAL_PERCENT = 92.55;

my $DEFAULT_DISKUSAGE_INTERVAL = 60 * 60 * 23;    #23 hours

my $DEFAULT_CHECK_INTERVAL = 60 * 5;              #5 minutes

my $NUMBER_OF_RUNS_BETWEEN_DISK_USAGE_CHECKS = 300;
my $NUMBER_OF_RUNS_BETWEEN_OOM_CHECKS        = 10;

my $DEFAULT_TCP_FAILURE_THRESHOLD = 3;

my $DEFAULT_FTPD_PORT = 21;

my $DEFAULT_NOTIFY_INTERVAL = 1;

our $LOWEST_ROOT_RESTRICTED_PORT = 1023;

our $_SOCKET_FAILURES_FILE = '/var/cpanel/chkservd_tcp_failures';

our $_CHKSERVD_RUN_DIR = '/var/run/chkservd';

our $_UPGRADE_IN_PROGRESS_FILE = '/usr/local/cpanel/upgrade_in_progress.txt';

##############################################################
## no other use()s, require() only *and* only then in init() #
##############################################################

our $service_checking_file = '/var/run/chkservd.checking';

=pod

=head1 NAME

Cpanel::TailWatch::ChkServd - Monitor disk usage and service uptime

=head1 SYNOPSIS

   use strict;
   use warnings;

   use Cpanel::TailWatch ();
   use Cpanel::TailWatch::ChkServd ();

   # Create a new TailWatch object
   my $tail = Cpanel::TailWatch->new( { 'type' => 1 } );
   my $monitor = Cpanel::TailWatch::ChkServd->new( $tail );

   # Perform all the checks
   $monitor->run( $tail );

   # Check whether the cPanel & WHM is updating
   Cpanel::TailWatch::ChkServd::is_upcp_running()

=head1 DESCRIPTION

The ChkServd driver is a special TailWatch driver. It monitors
disk usage and service uptime. Unlike other TailWatch drivers,
it does not rely on watching log files.

Both object and static methods are defined here.

=head1 METHODS

=cut

sub init {

    # this is where modules should be require()'d
    # this method gets called if PKG->is_enabled()
    require Cpanel::Chkservd::Tiny::Suspended;
    require Cpanel::ForkAsync;
    require Cpanel::ProcessInfo;

    return;
}

sub internal_name { return 'chkservd'; }

sub reload {
    my ( $my_ns, $tailwatch_obj ) = @_;

    my $data_cache = $tailwatch_obj->{'global_share'}{'data_cache'};

    $my_ns->{'internal_store'}->{'check_interval'} = $data_cache->{'cpconf'}->{'chkservd_check_interval'} || $DEFAULT_CHECK_INTERVAL;

    $tailwatch_obj->setup_max_action_wait_time( $my_ns, __PACKAGE__ );

    return;
}

=head2 new

Creates an instance of the driver.

=cut

sub new {
    my ( $my_ns, $tailwatch_obj ) = @_;
    my $self = bless { 'tailwatch_obj' => $tailwatch_obj, 'internal_store' => { 'number_of_runs' => 0, 'last_check_time' => 0 } }, $my_ns;

    # case 4953
    # $self->_ensure_dbh();
    my $data_cache = $tailwatch_obj->{'global_share'}{'data_cache'};
    $self->{'internal_store'}->{'check_interval'} = $data_cache->{'cpconf'}->{'chkservd_check_interval'} || $DEFAULT_CHECK_INTERVAL;

    $tailwatch_obj->register_action_module( $self, __PACKAGE__ );
    $tailwatch_obj->register_reload_module( $self, __PACKAGE__ );

    # $tailwatch_obj->{'global_share'}{'objects'}{'param_obj'}->param('debug');
    # $tailwatch_obj->{'global_share'}{'data_cache'}{'domain_user_map'}'

    return $self;
}

sub is_recently_booted ($my_ns) {
    state $not_recent;
    return 0 if $not_recent;

    require Cpanel::Sys::Uptime;
    my $uptime = Cpanel::Sys::Uptime::get_uptime();
    return 0 unless $uptime;

    return 1 if $uptime < $my_ns->{'internal_store'}->{'check_interval'};

    $not_recent = 1;
    return 0;
}

sub is_upcp_running {

    # This won't work if $SIG{'CHLD'} is set to IGNORE;
    local $SIG{'CHLD'} = 'DEFAULT';

    # do nothing during upcp
    Cpanel::SafeRun::Simple::saferunnoerror( '/usr/local/cpanel/scripts/upcp-running', '--quiet' );
    return 1 if $? == 0;

    return 0;
}

sub can_service_do_serviceauth {
    my $service = shift;
    return unless $service;

    return 1 if $service eq 'cpsrvd' || $service eq 'cpdavd' || $service eq 'dnsadmin';

    return;
}

sub run {
    my ( $my_ns, $tailwatch_obj, $time ) = @_;

    # Status of true means we are inside a service check but we have passed control back to the main tailwatch
    # process so other drivers can be handled.  If we are here then we need to continue service checks.
    #
    my $last_check_delta     = $time - $my_ns->{'internal_store'}->{'last_check_time'};
    my $clock_moved_backward = $last_check_delta < -$my_ns->{'internal_store'}->{'check_interval'};    # Time moved backwards by more than check_interval

    if ( $last_check_delta > $my_ns->{'internal_store'}->{'check_interval'} || $clock_moved_backward ) {

        if ($clock_moved_backward) {
            $my_ns->log_ts_asis("Chkservd detected the system clock moved backward since the last time it ran.\n");
        }

        if ( Cpanel::Chkservd::Tiny::Suspended::is_suspended() ) {
            $my_ns->log_ts_asis("Chkservd is currently suspended (/var/run/chkservd.suspend exists), waiting 100 seconds\n");
            $my_ns->{'internal_store'}->{'last_check_time'} = $time + 100;
            return;
        }

        if ( is_upcp_running() ) {
            $my_ns->log_ts_asis("Chkservd will not run during upcp or first install, deferring until next run.\n");
            $my_ns->{'internal_store'}->{'last_check_time'} = $time;
            return;
        }

        if ( $my_ns->is_recently_booted() ) {
            $my_ns->log_ts_asis("The system has recently booted.  Chkservd is deferring service checks until system uptime exceeds one service check interval.\n");
            $my_ns->{'internal_store'}->{'last_check_time'} = $time;
            return;
        }

        if ( Cpanel::Sys::Boot::is_booting() ) {
            $my_ns->log_ts_asis("Chkservd will not run while the system is rebooting, deferring until next run.\n");
            $my_ns->{'internal_store'}->{'last_check_time'} = $time;
            return;
        }

        $my_ns->log_asis("Service Check Started\n");
        $my_ns->{'internal_store'}->{'last_check_time'} = $time;

        alarm(0);

        if (   $my_ns->{'internal_store'}->{'child_pid'}
            && kill( 0, $my_ns->{'internal_store'}->{'child_pid'} ) == 1
            && Cpanel::ProcessInfo::get_parent_pid( $my_ns->{'internal_store'}->{'child_pid'} ) == $$ ) {

            my $child_run_time = ( $time - $my_ns->{'internal_store'}->{'child_start_time'} );
            my $data_cache     = $my_ns->{'tailwatch_obj'}->{'global_share'}{'data_cache'};
            if ( exists $data_cache->{'cpconf'}->{'chkservd_hang_allowed_intervals'} ) {
                $HANG_ALLOWED_INTERVALS = $data_cache->{'cpconf'}->{'chkservd_hang_allowed_intervals'};
            }

            if ( ++$my_ns->{'internal_store'}->{'chkservd_hang_count'} >= $HANG_ALLOWED_INTERVALS ) {
                $my_ns->{'internal_store'}->{'chkservd_hang_count'} = 0;
                $my_ns->log_asis("The previous service check was still running ($child_run_time second).  It was terminated.\n");

                kill( 'KILL', $my_ns->{'internal_store'}->{'child_pid'} );

                Cpanel::Waitpid::sigsafe_blocking_waitpid( $my_ns->{'internal_store'}->{'child_pid'} );    # reap the child

                Cpanel::ForkAsync::do_in_child(
                    sub {
                        alarm(60);

                        local $0 = "$0 - sending HANG notification";

                        my %TEMPLATE_VARS = (
                            child_pid      => $my_ns->{'internal_store'}->{'child_pid'},
                            child_run_time => $child_run_time,
                            check_interval => $my_ns->{'internal_store'}->{'check_interval'},
                        );

                        eval { _send_hang_notification( \%TEMPLATE_VARS, $data_cache->{'cpconf'}->{'chkservd_plaintext_notify'} ? 'text' : 'html', ); };

                        if ($@) {
                            require Cpanel::Logger;

                            my $err     = $@;
                            my $err_str = eval { $err->to_string() } || $err;
                            Cpanel::Logger->new()->die("error in _send_hang_notification: $err_str");
                        }
                    }
                );
            }
            else {
                $my_ns->log_asis("The previous service check is still running ($child_run_time second).  It will be terminated if still hanging after $HANG_ALLOWED_INTERVALS check intervals. ($my_ns->{'internal_store'}->{'chkservd_hang_count'}/$HANG_ALLOWED_INTERVALS)\n");
                return;
            }
        }

        $my_ns->_run_checks( $tailwatch_obj, $time );
    }

    return;
}

sub _send_hang_notification {
    my ( $tmpl_vars_hr, $body_format ) = @_;

    require Cpanel::Notify;

    my @constructor_args = (
        from        => 'cPanel Monitoring',
        body_format => $body_format,
        %$tmpl_vars_hr,
    );

    Cpanel::Notify::notification_class(
        interval         => 1,
        status           => 'hang',
        class            => 'chkservd::Hang',
        application      => 'chkservd::Hang',
        constructor_args => \@constructor_args,
    );

    return;
}

sub _run_checks {
    my ( $my_ns, $tailwatch_obj, $time ) = @_;

    $my_ns->{'internal_store'}->{'child_start_time'} = $time;

    # needs to run in a child to prevent recentauthedmailiptracker waiting
    return $my_ns->{'internal_store'}->{'child_pid'} if ( $my_ns->{'internal_store'}->{'child_pid'} = fork() );

    # dedicated child process

    local $0 = $0 . " - chkservd";
    require Cpanel::Chkservd::Manage;
    require Cpanel::SafeFile;
    require Cpanel::Exception::Utils;
    require Cpanel::Finally;

    my $lock    = Cpanel::SafeFile::safelock($service_checking_file);
    my $finally = Cpanel::Finally->new(
        sub {
            Cpanel::SafeFile::safeunlock($lock) if $lock;
            $lock = undef;
            return;
        }
    );

    my $conf_mtime = ( stat($Cpanel::Chkservd::Tiny::chkservd_conf) )[9];
    if ( !exists $my_ns->{'internal_store'}{'services_config'} || !exists $my_ns->{'internal_store'}{'services_config_mtime'} || int( $my_ns->{'internal_store'}{'services_config_mtime'} ) < $conf_mtime ) {
        $tailwatch_obj->debug("re-initializing chkservd config ($my_ns->{'internal_store'}{'services_config_mtime'}) based on mtime of $Cpanel::Chkservd::Tiny::chkservd_conf ($conf_mtime)") if $tailwatch_obj->{'debug'};
        $my_ns->{'internal_store'}{'services_config_mtime'} = $conf_mtime;
        $my_ns->_load_config();
    }

    # Reset signal handlers we inherit from tailwatchd
    $SIG{'CHLD'} = $SIG{'USR1'} = $SIG{'HUP'} = 'DEFAULT';
    $SIG{'TERM'} = sub {
        $my_ns->log_asis("Service Check Interrupted\n");
        exit 0;
    };

    # Run checks
    $my_ns->_check_services();
    $my_ns->log_asis("Service Check Finished\n");

    exit;
}

## Driver specific helpers ##
sub _check_service {

    my ( $service, $command, $owner, %options ) = @_;

    my $my_ns = $options{'my_ns'};

    # Case 122885, we are adding pop monitoring back.  But it is restarted
    # by the imap restart service.   But that would fail the test below,
    # so the restart_service can be changed from pop to imap for doing the
    # restartsrv_imap --check.

    my $restart_service = $options{'restart_service'};
    if ( !defined $restart_service || $restart_service eq "" ) {
        $restart_service = $service;
    }

    my $raw_check_output;
    my $cmd_service_check_ok = 0;

    if ( $command && $command ne 'x' ) {
        if ( $service eq 'syslogd' || $service eq 'rsyslogd' ) {
            require Cpanel::OS;
            if ( $my_ns->_servicecmdcheck( $service, $owner, Cpanel::OS::syslog_service_name() ) ) {
                $cmd_service_check_ok = $CHECK_OK;
            }
            else {
                $cmd_service_check_ok = $CHECK_FAILED;
            }
        }
        elsif ( my $restart_script = Cpanel::RestartSrv::Script::get_restart_script($restart_service) ) {
            my $can_use_status_code = Cpanel::RestartSrv::Script::can_use_status_code_for_service($restart_service);

            my @check_args = ('--check');

            # non-Cpanel::ServiceManager::Services scripts don't need to output the special header #
            local $ENV{'RESTARTSRV_CHECKMODE_HEADER'} = 1 if !$can_use_status_code;

            # we don't want to generate a failed return code because we're not going to try to start non-configured services #
            push @check_args, '--notconfigured-ok' if $can_use_status_code;

            $raw_check_output = Cpanel::SafeRun::Errors::saferunallerrors( $restart_script, @check_args );

            if ($can_use_status_code) {
                if ( $? == 0 ) {
                    $cmd_service_check_ok = $CHECK_OK;
                }
                else {
                    my $err_code = $?;
                    $cmd_service_check_ok = $CHECK_FAILED;
                    require Cpanel::ChildErrorStringifier;
                    my $err = Cpanel::ChildErrorStringifier->new( $err_code, $restart_script );
                    $raw_check_output ||= '';
                    $raw_check_output .= "\n" . $err->autopsy();
                }
            }
            else {
                # handle "no output" of older restartsrv scripts #
                my $header;
                ( $header, $raw_check_output ) = split( /\n/, $raw_check_output, 2 );
                chomp($raw_check_output);

                if ( $header ne '--restartsrv: check mode starting--' ) {
                    $cmd_service_check_ok = $CHECK_UNKNOWN;
                    $raw_check_output     = $header . "\n" . $raw_check_output;
                }
                else {
                    $cmd_service_check_ok = ( !$raw_check_output || $raw_check_output =~ m/disabled/m ) ? $CHECK_OK : $CHECK_FAILED;
                }
            }
        }
        else {
            $cmd_service_check_ok = $my_ns->_servicecmdcheck( $command, $owner, $service );
        }
    }
    else {
        $cmd_service_check_ok = $CHECK_SKIPPED;    # skipped
    }
    return $raw_check_output, $cmd_service_check_ok;
}

# We need queueprocd to be first bc we use it to send notifications
# Otherwise, sorted in reverse order so [i]map gets checked/restarted before [e]xim in case we are using dovecot
sub _get_ordered_services {
    my $_services_ref = shift;
    my @sorted =
      sort { ( $b eq 'queueprocd' ) <=> ( $a eq 'queueprocd' ) || $b cmp $a } @$_services_ref;
    return @sorted;
}

# This has been moved to a function so we can filter it out to avoid this
# process becoming a false positive for _servicecmdcheck's ps parsing.  See
# case 164269.
sub _service_check_message {
    my ($service) = @_;

    return " - $service check";
}

sub _check_services {    ## no critic(Subroutines::ProhibitExcessComplexity) - refactoring this is a project
    my $my_ns = shift;

    my $data_cache = $my_ns->{'tailwatch_obj'}->{'global_share'}{'data_cache'};

    if ( !$data_cache->{'cpconf'}->{'skipdiskusage'} && ( $my_ns->{'internal_store'}->{'number_of_runs'} % $NUMBER_OF_RUNS_BETWEEN_DISK_USAGE_CHECKS == 0 || $my_ns->{'internal_store'}->{'number_of_runs'} == 0 ) ) {
        $my_ns->_diskcheck();
    }

    if ( !$data_cache->{'cpconf'}->{'skipoomcheck'} && ( $my_ns->{'internal_store'}->{'number_of_runs'} % $NUMBER_OF_RUNS_BETWEEN_OOM_CHECKS == 0 || $my_ns->{'internal_store'}->{'number_of_runs'} == 0 ) ) {
        $my_ns->_oomcheck();
    }

    require Cpanel::SafeRun::Errors;

    my $hostname = $data_cache->{'hostname'};

    $my_ns->{'internal_store'}->{'number_of_runs'}++;
    $my_ns->log_ts_asis('Service check ....');

    #3 is the default in the distribution
    my $tcp_failure_threshold;
    if ( exists $data_cache->{'cpconf'}->{'tcp_check_failure_threshold'} ) {    # should really be socket_check_failure_threshold
        $tcp_failure_threshold = $data_cache->{'cpconf'}->{'tcp_check_failure_threshold'};
    }
    if ( !defined $tcp_failure_threshold || !length $tcp_failure_threshold || $tcp_failure_threshold !~ m{\A\d+\z} ) {
        $tcp_failure_threshold = $DEFAULT_TCP_FAILURE_THRESHOLD;
    }

    # check_services happens after a fork() so when we're accumulating failures we need to serialize them to an external file
    my $accumulated_tcp_failures_hr = {};
    if ( $tcp_failure_threshold && $tcp_failure_threshold >= 2 ) {
        require Cpanel::DataStore;
        $accumulated_tcp_failures_hr = Cpanel::DataStore::fetch_ref($_SOCKET_FAILURES_FILE);    # should really be socket failures
    }

    my $service_suspends = Cpanel::Chkservd::Tiny::load_service_suspensions();

    my $_queueprocd_ok = 1;
    my $ret;
    my @_services = _get_ordered_services( [ keys %{ $my_ns->{'internal_store'}->{'services_config'} } ] );
    foreach my $service (@_services) {
        local $0 = $0 . _service_check_message($service);
        my $tcp_service_check_ok  = 0;
        my $cmd_service_check_ok  = 0;
        my $service_check_message = '';

        $accumulated_tcp_failures_hr->{$service} ||= 0;

        # if check for the service is suspended,
        $my_ns->log_asis("\n$service [");
        if ( Cpanel::Chkservd::Tiny::is_service_suspended( $service_suspends, $service ) ) {
            $my_ns->log_asis("too soon after restart to check]...");
            next;
        }

        my ( $port, $send, $res, $restart, $command, $owner, $tcp_transaction, $restart_service ) =
          split( /\,/, ( $my_ns->{'internal_store'}->{'services_config'}{$service}{'cmd'} // '' ) );

        my $raw_check_output;
        ( $raw_check_output, $cmd_service_check_ok ) = _check_service( $service, $command, $owner, 'restart_service' => $restart_service, 'my_ns' => $my_ns );

        if ( $cmd_service_check_ok && $port && $port ne 'x' && !-e '/var/cpanel/' . $service . '_tcp_check_disabled' ) {    #only spend the time to check tcp if the service check was ok or skipped
            if ( $service eq 'httpd' ) {

                # Get port from cpanel.config if set
                $port =
                    ( !defined $data_cache->{'cpconf'}{'apache_port'} || !$data_cache->{'cpconf'}{'apache_port'} ) ? $port
                  : $data_cache->{'cpconf'}{'apache_port'} =~ /^\s*(?:\d+\.\d+\.\d+\.\d+:)?(\d+)\s*$/              ? $1
                  :                                                                                                  $port;
            }
            elsif ( $service eq 'ftpd' ) {
                require Cpanel::FtpUtils::Config;
                $port = eval { Cpanel::FtpUtils::Config->new()->get_port() } || $DEFAULT_FTPD_PORT;
            }

            ( $tcp_service_check_ok, $service_check_message ) = $my_ns->_service_socket_check( $service, $port, $send, $res, $tcp_transaction );
        }
        else {
            $tcp_service_check_ok = $CHECK_SKIPPED;    #skipped
        }

        # If one of the checks fails, we need to check if the system is being shut down after checks started, and re-check the
        # suspension list to see if the service was suspended after we checked last.
        if ( !$cmd_service_check_ok || !$tcp_service_check_ok ) {

            # Failed, so check to see if the system is shutting down after the service checks started and skip the rest of the checks.
            # Because is_booting() is also checked BEFORE service checks start, then is_booting() can only become true when a shutdown is commanded between then and now.
            if ( Cpanel::Sys::Boot::is_booting() ) {
                $my_ns->log_asis("...The system is shutting down after the service check started. Skipping checks.]...\n");
                last;
            }

            # Failed, so let's check tp see if it was suspended after we loaded last.
            $service_suspends = Cpanel::Chkservd::Tiny::load_service_suspensions();
            if ( Cpanel::Chkservd::Tiny::is_service_suspended( $service_suspends, $service ) ) {
                $my_ns->log_asis("...The service check for this service was suspended during the check. Another process may have attempted to restart this service.]...");
                next;
            }
        }

        $my_ns->log_asis( '[check command:' . ( $cmd_service_check_ok ? ( $cmd_service_check_ok == $CHECK_UNKNOWN ? '?' : $cmd_service_check_ok == $CHECK_OK ? '+' : 'N/A' ) : '-' ) . ']' );
        if ( !$cmd_service_check_ok && length $raw_check_output ) {
            $my_ns->log_asis("[check command output:$raw_check_output]");
        }
        $my_ns->log_asis( '[socket connect:' . ( $tcp_service_check_ok ? ( $tcp_service_check_ok == $CHECK_OK ? '+' : 'N/A' ) : '-' ) . ']' );
        $accumulated_tcp_failures_hr->{$service} = $tcp_service_check_ok ? 0 : $accumulated_tcp_failures_hr->{$service} + 1;
        if ( !$tcp_service_check_ok ) {
            $my_ns->log_asis( '[socket failure threshold:' . $accumulated_tcp_failures_hr->{$service} . '/' . $tcp_failure_threshold . ']' );
        }

        my $tcp_failures_have_reached_threshold = ( $tcp_failure_threshold && $accumulated_tcp_failures_hr->{$service} >= $tcp_failure_threshold ) ? 1 : 0;

        my $restart_count = $my_ns->_increment_restart_count($service);

        my $notify_type;

        my $what_failed;

        if ( $cmd_service_check_ok == $CHECK_UNKNOWN && $tcp_service_check_ok == $CHECK_SKIPPED ) {
            $my_ns->log_asis('[could not determine status]');
            $my_ns->_servicefile( $service, '?' );

            if ( -e $_UPGRADE_IN_PROGRESS_FILE ) {
                $my_ns->log_asis('[no notification for unknown status due to upgrade in progress]');
            }
            else {
                $notify_type = 'unknown';
            }
        }
        elsif ( !$cmd_service_check_ok || $tcp_failures_have_reached_threshold ) {
            if ($cmd_service_check_ok) {
                $what_failed = 'socket';
            }
            else {
                $what_failed = 'command';
            }

            $my_ns->log_asis( '[fail count:' . $restart_count . ']' );
            $my_ns->_servicefile( $service, '-' );
            $my_ns->log_asis("Restarting $service....\n");
            $notify_type = 'failed';

            $_queueprocd_ok = undef if ( $service eq 'queueprocd' );    # allows notifications to be sent outside of queueprocd if queueprocd is failed
        }
        else {
            my $previous_status = $my_ns->_previous_servicefile($service);
            if ( $previous_status && $previous_status eq '-' && !$data_cache->{'cpconf'}{'skip_chkservd_recovery_notify'} ) {
                $notify_type = 'recovered';
            }
            $my_ns->_servicefile( $service, '+' );
        }

        if ($notify_type) {
            my $interval = $DEFAULT_NOTIFY_INTERVAL;
            if ( length $my_ns->{'internal_store'}->{'services_config'}{$service}{'interval'} ) {
                $interval = int( $my_ns->{'internal_store'}->{'services_config'}{$service}{'interval'} );
            }

            require Cpanel::Services::Log;
            my ( $startup_log_ok,  $startup_log )  = Cpanel::Services::Log::fetch_service_startup_log($service);
            my ( $log_messages_ok, $log_messages ) = Cpanel::Services::Log::fetch_service_log_messages( $service, $command );

            my $service_name = ( $service eq 'named' ? 'nameserver' : $service );

            my %TEMPLATE_VARS = (
                service_name    => $service_name,
                service_status  => $notify_type,
                socket_error    => $service_check_message,
                command_error   => $raw_check_output,
                startup_log     => $startup_log,
                syslog_messages => $log_messages,
                port            => ( $port eq 'x' ? "" : $port ),
            );

            if ( $notify_type ne 'recovered' ) {
                my $restart_info = $my_ns->_servicerestart( $restart_service || $service, $restart, $restart_count );
                $TEMPLATE_VARS{'restart_count'} = $restart_count;
                $TEMPLATE_VARS{'restart_info'}  = $restart_info;
                $TEMPLATE_VARS{'what_failed'}   = $what_failed;
            }

            $my_ns->log_asis("[notify:$notify_type service:$service_name]");

            my $plaintext_only = $data_cache->{'cpconf'}->{'chkservd_plaintext_notify'};

            local $0 = "$0 - sending $notify_type notification";

            my @notification_arguments = (
                interval         => $interval,
                status           => $notify_type,
                class            => 'chkservd::Notify',
                application      => 'chkservd::Notify',
                constructor_args => [
                    block_on_send => 1,
                    body_format   => $plaintext_only ? 'text' : 'html',
                    %TEMPLATE_VARS,
                ],
            );

            # send service notifications via queueprocd, unless queuprocd (which is checked first) is failed
            $ret = _send_notification_via_queueprocd( \@notification_arguments, $_queueprocd_ok );
        }

        $my_ns->log_asis(']...');
        alarm(0);
    }
    if ( defined $tcp_failure_threshold && $tcp_failure_threshold >= 2 ) {
        Cpanel::DataStore::store_ref( $_SOCKET_FAILURES_FILE, $accumulated_tcp_failures_hr );
    }
    $my_ns->log_asis("Done\n");

    return $ret;
}

sub _send_notification_via_queueprocd {
    my ( $notification_arguments_ref, $_queueprocd_ok ) = @_;
    my $ret;
    if ($_queueprocd_ok) {
        Cpanel::Notify::Deferred::notify(@$notification_arguments_ref);
        $ret = 1;
    }

    # fallback notification method, use blocking form of notification
    else {
        require Cpanel::Notify;
        $ret = Cpanel::Notify::notification_class(@$notification_arguments_ref);
    }
    return $ret;
}

sub _service_is_enabled_backcompat {
    my ($service) = @_;

    # Exim alternate ports are recorded as something like “exim-26,99”
    # in chkservd’s configuration. Cpanel::Services::Enabled doesn’t
    # understand that, though, so this translates into the format that
    # Cpanel::Services::Enabled does understand.
    $service =~ s{^exim-[\d,]+$}{exim-altport}g;

    return Cpanel::Services::Enabled::is_enabled($service);
}

sub _load_config {
    my $my_ns = shift;
    require Cpanel::Services::Enabled;

    $my_ns->{'internal_store'}{'services_config'} = {};

    my $monitored_ref = Cpanel::Chkservd::Manage::getmonitored();
    my $drivers_ref   = Cpanel::Chkservd::Manage::load_drivers();

    $my_ns->log_asis('Loading services ...');
    foreach my $service ( sort keys %{$monitored_ref} ) {
        if ( exists $drivers_ref->{$service} ) {
            $my_ns->{'internal_store'}->{'services_config'}{$service}{'status'} = $monitored_ref->{$service};
            if ( $monitored_ref->{$service} && _service_is_enabled_backcompat($service) ) {
                $my_ns->log_asis("..$service..");
                $my_ns->{'internal_store'}->{'services_config'}{$service}{'cmd'}      = $drivers_ref->{$service};
                $my_ns->{'internal_store'}->{'services_config'}{$service}{'interval'} = 1;
            }
        }
    }
    $my_ns->log_asis("Done\n");

    if ( open my $interval_fh, '<', '/var/cpanel/notification/interval' ) {
        while ( my $line = readline $interval_fh ) {
            chomp $line;
            my ( $service, $interval ) = split( /\:/, $line, 2 );
            next if ( !$service || !defined $interval || $interval eq '' || !$my_ns->{'internal_store'}->{'services_config'}{$service}{'status'} );
            $my_ns->{'internal_store'}->{'services_config'}{$service}{'interval'} = int $interval;
        }
        close $interval_fh;
    }
    return 1;
}

sub _oomcheck {
    my $my_ns = shift;
    require Cpanel::Sys::OOM;
    require Cpanel::Sys::Kernel;

    my $OOMCHECK_NOTIFY_INTERVAL = ( 86400 * 120 );    # If we do not have printk timestamps
                                                       # we can't be sure when the oom happened
                                                       # which will cause notifications
                                                       # to be sent every time time the interval
                                                       # is exausted of the dmesg (ring buffer)
                                                       # has not expunged the OOM message.
                                                       # This is set to 120 days by default in the
                                                       # hopes that the buffer will be cleared by than

    # Make sure timestamps are enabled so we can determine when OOM
    # messages were displayed.  If the kernel supports these (centos 6+)
    # this prevents the above condition where we do not know when the OOM message happened
    Cpanel::Sys::Kernel::enable_printk_timestamps();

    my $ONE_DAY_AGO = ( time() - 86400 );
    my $data_cache  = $my_ns->{'tailwatch_obj'}->{'global_share'}{'data_cache'};
    my $oom_message = Cpanel::Sys::OOM::fetch_oom_data_from_dmesg();
    $my_ns->log_ts_asis('OOM check ....');

    my @NOTIFY;
    foreach my $message ( @{$oom_message} ) {

        # We want to avoid notifying on duplicate events, however we cannot always be
        # sure printk is giving us a timestamp so we have the large interval above
        if (
               $message->{'process_killed'}
            && ( !$message->{'time'} || $message->{'time'} > $ONE_DAY_AGO )
            && !$message->{'is_cgroup'}

            # Do not send notifications for cgroups.
            # This is only intended to notify when OOM happens
            # for the entire system, not a particular cgroup.
            #
            # (NB: CloudLinux enables cgroups by default, but other
            # supported OSes don’t.)
        ) {
            my $log_message = join( ',', map { "$_=$message->{$_}" } grep { $_ ne 'process_killed' && $_ ne 'data' } sort keys %{$message} );
            $my_ns->log_asis("..OOM Event:[$log_message]..");
            push @NOTIFY, $message;
        }
    }
    if (@NOTIFY) {
        my $plaintext_only = $data_cache->{'cpconf'}->{'chkservd_plaintext_notify'};
        require Cpanel::Notify;
        my $interval = $OOMCHECK_NOTIFY_INTERVAL;
        if ( $my_ns->{'internal_store'}->{'services_config'}{'interval'}{'oomcheck'} ) {
            $interval = int( $my_ns->{'internal_store'}->{'services_config'}{'interval'}{'oomcheck'} );
        }

        foreach my $notify (@NOTIFY) {
            my $notify_key = join( ',', grep { length $_ } ( $notify->{'uid'}, $notify->{'proc_name'} ) );

            # If we don't have a proc_name and uid we don't have enough
            # information to generate a unique key so we just get our
            # key to 'oom' to avoid notifing when there are lots of
            # oom messages like tkt8398055
            $notify_key ||= 'oom';

            local $0 = "$0 - sending OOM notification";
            my $notified = Cpanel::Notify::notification_class(
                application      => 'oomcheck',
                interval         => $interval,
                status           => $notify_key,
                class            => 'chkservd::OOM',
                constructor_args => [
                    %$notify,
                    body_format  => $plaintext_only ? 'text' : 'html',
                    attach_files => [
                        { name => 'oom_dmesg.txt', content => \$notify->{'data'} },
                    ]
                ],
            );

            if ($notified) {
                $my_ns->log_asis("...Sent OOM Notification...");
            }
            else {
                $my_ns->log_asis("...Skipped OOM Notification (too soon)...");
            }
        }
        $my_ns->log_asis("... Done\n");
        return 1;
    }
    $my_ns->log_asis("Done\n");
    return 0;
}

sub _diskcheck {
    my $my_ns = shift;

    require Cpanel::Filesys::Mounts;
    Cpanel::Filesys::Mounts::clear_mounts_cache();

    require Cpanel::DiskLib;

    $my_ns->log_ts_asis("Loading list of mount points to ignore...");
    my $ignored_mounts = ignored_mount_points();
    $my_ns->log_asis( ' ignoring mount points that match: ' . $ignored_mounts . '...' );
    $my_ns->log_asis(" Done\n");

    my $data_cache = $my_ns->{'tailwatch_obj'}->{'global_share'}{'data_cache'};
    my $hostname   = $data_cache->{'hostname'};

    my $diskfree_ref = Cpanel::DiskLib::get_disk_used_percentage_with_dupedevs();

    my $critical_check_enabled = !exists $data_cache->{'cpconf'}->{'system_diskusage_critical_percent'};
    $critical_check_enabled ||= defined $data_cache->{'cpconf'}->{'system_diskusage_critical_percent'};

    my $warn_check_enabled = !exists $data_cache->{'cpconf'}->{'system_diskusage_warn_percent'};
    $warn_check_enabled ||= defined $data_cache->{'cpconf'}->{'system_diskusage_warn_percent'};

    my $critical_diskusage_percent = $data_cache->{'cpconf'}->{'system_diskusage_critical_percent'} || $DEFAULT_DISKUSAGE_CRITICAL_PERCENT;
    my $warn_diskusage_percent     = $data_cache->{'cpconf'}->{'system_diskusage_warn_percent'}     || $DEFAULT_DISKUSAGE_WARN_PERCENT;

    my $status = 'ok';
    $my_ns->log_ts_asis('Disk check ....');
    my @NOTIFY;
    foreach my $device ( @{$diskfree_ref} ) {
        next if ( $device->{'mount'} =~ m{/?(?:$ignored_mounts)} );

        #Normalize, no more than 2 decimal places.
        my $pct = 0 + sprintf( '%.02f', 100 * ( $device->{'total'} - $device->{'available'} ) / $device->{'total'} );

        if ( $device->{'inodes_total'} ) {    # only if the device supports inodes
                                              # INODES
            my $pct_inodes = 0 + sprintf( '%.02f', 100 * ( $device->{'inodes_total'} - $device->{'inodes_available'} ) / $device->{'inodes_total'} );
            if ( $critical_check_enabled && $pct_inodes > $critical_diskusage_percent ) {
                push @NOTIFY, {
                    'usage_type' => 'inodes',
                    'filesystem' => $device->{'filesystem'},
                    'mount'      => $device->{'mount'},
                    'status'     => 'critical',
                    'total'      => $device->{'inodes_total'},
                    'used'       => $device->{'inodes_used'},
                    'available'  => $device->{'inodes_available'},

                };
                $status = 'failed';
            }
            elsif ( $warn_check_enabled && $pct_inodes > $warn_diskusage_percent ) {
                $status = 'warn' unless $status eq 'failed';
                push @NOTIFY,
                  {
                    'usage_type' => 'inodes',
                    'filesystem' => $device->{'filesystem'},
                    'mount'      => $device->{'mount'},
                    'status'     => 'warn',
                    'total'      => $device->{'inodes_total'},
                    'used'       => $device->{'inodes_used'},
                    'available'  => $device->{'inodes_available'},
                  };

            }
        }

        # DISK SPACE
        if ( $critical_check_enabled && $pct > $critical_diskusage_percent ) {
            push @NOTIFY, {
                'usage_type' => 'blocks',
                'filesystem' => $device->{'filesystem'},
                'mount'      => $device->{'mount'},
                'status'     => 'critical',
                'total_kib'  => $device->{'total'},
                'used_kib'   => $device->{'used'},
                'available'  => $device->{'available'},

            };
            $status = 'failed';
        }
        elsif ( $warn_check_enabled && $pct > $warn_diskusage_percent ) {
            $status = 'warn' unless $status eq 'failed';
            push @NOTIFY,
              {
                'usage_type' => 'blocks',
                'filesystem' => $device->{'filesystem'},
                'mount'      => $device->{'mount'},
                'status'     => 'warn',
                'total_kib'  => $device->{'total'},
                'used_kib'   => $device->{'used'},
                'available'  => $device->{'available'},
              };

        }

        $my_ns->log_asis(" $device->{'filesystem'} ($device->{'mount'}) [$pct%] ...");
    }
    $my_ns->log_asis(" {status:$status} ... ");
    if (@NOTIFY) {
        my $plaintext_only = $data_cache->{'cpconf'}->{'chkservd_plaintext_notify'};
        require Cpanel::Notify;

        my $interval = 0;
        if ( $my_ns->{'internal_store'}->{'services_config'}{'interval'}{'diskcheck'} ) {
            $interval = int( $my_ns->{'internal_store'}->{'services_config'}{'interval'}{'diskcheck'} );
        }
        else {
            $interval = $DEFAULT_DISKUSAGE_INTERVAL;
        }

        foreach my $notify (@NOTIFY) {
            my $stripped_mount = $notify->{'mount'};
            $stripped_mount =~ tr</><>d;

            local $0 = "$0 - sending $notify->{'usage_type'} notification";

            my %usage_type_args;
            if ( $notify->{'usage_type'} eq 'inodes' ) {
                %usage_type_args = (
                    used_inodes      => $notify->{'used'},
                    total_inodes     => $notify->{'total'},
                    available_inodes => $notify->{'available'},
                );
            }
            elsif ( $notify->{'usage_type'} eq 'blocks' ) {
                %usage_type_args = (
                    used_bytes  => $notify->{'used_kib'} * 1024,
                    total_bytes => $notify->{'total_kib'} * 1024,
                    available   => $notify->{'available'} * 1024,
                );
            }
            else {
                die "Unknown usage_type: $notify->{'usage_type'}";
            }

            my $notified = Cpanel::Notify::notification_class(
                application => "diskcheck_${stripped_mount}_$notify->{'status'}",
                interval    => $interval,
                status      => $notify->{'status'},

                class            => 'chkservd::DiskUsage',
                constructor_args => [
                    body_format => $plaintext_only ? 'text' : 'html',
                    notify_type => $notify->{'status'},
                    usage_type  => $notify->{'usage_type'},
                    mount       => $notify->{'mount'},
                    filesystem  => $notify->{'filesystem'},
                    %usage_type_args,
                ],
            );

            if ($notified) {
                $my_ns->log_asis("...Sent Disk Notification...");
            }
            else {
                $my_ns->log_asis("...Skipped Disk Notification (too soon)...");
            }
        }
        $my_ns->log_asis("... Done\n");
        return 1;
    }
    $my_ns->log_asis("Done\n");
    return;
}

=head2 ignored_mount_points

The disk space check ignores some virtual file systems since they are always at 100% capacity.
The default check ignores virtfs and cagefs. If the optional
configuration file C</var/cpanel/chkservd_ignored_mounts> exists, its contents are
added to the mount points to ignore.

=head3 Arguments

=over 4

=item Input

No input.

=item Output

Returns a pipe-delimited ('|') string of mount points to ignore.

=back

=head3 Format of chkservd_ignored_mounts

One entry per line, newline separated. An entry must consist of one or more letters,
numbers, the underscore(_),  or the forward slash (/). Entries that have other characters are ignored.
Right now, only English characters are allowed.

=cut

sub ignored_mount_points {

    require Cpanel::LoadFile;
    my $custom_ignore_mounts = Cpanel::LoadFile::load_if_exists( _custom_mounts_ignore_file() );

    my $ignore_mounts = 'virtfs|cagefs';
    if ($custom_ignore_mounts) {
        foreach my $entry ( split( "\n", $custom_ignore_mounts ) ) {
            next if !length $entry;
            next if $entry !~ m/^[\w\/]+$/;
            $ignore_mounts .= '|' . $entry;
        }
    }
    return $ignore_mounts;
}

sub _custom_mounts_ignore_file {
    return '/var/cpanel/chkservd_ignored_mounts';
}

sub _servicecmdcheck {
    my ( $my_ns, $command, $owner, $service ) = @_;

    require Cpanel::SafeRun::Errors;

    if ( $command =~ m/nslookup/ ) {
        $command = 'named';
        $owner   = 'named|bind';
    }
    if ( $owner eq 'named' ) { $owner = 'named|bind'; }

    my @OWNERS = split( /\|/, $owner );
    my @PS;
    my $message = _service_check_message($service);
    foreach my $owner (@OWNERS) {
        my @RUN = Cpanel::SafeRun::Errors::saferunnoerror( 'ps', 'xuww', '-u', $owner );
        push @PS, @RUN;
    }
    @PS = grep { !/ps\s*xuw*\s*\-u/i && !/\Q$message\E/ } @PS;

    foreach my $procset ( split( /\s*\|+\s*/, $command ) ) {
        my $ok_procs = 0;
        my @PROCS    = grep( !/^\s*$/, split( /\s*[\&\,]+\s*/, $procset ) );
        next if ( !@PROCS );

        my $num_procs_to_check = scalar @PROCS;
        foreach my $proc (@PROCS) {
            if ( grep( /$proc/, @PS ) ) {
                $ok_procs++;
            }
        }
        if ( $ok_procs == $num_procs_to_check ) {

            # $my_ns->log_asis("Service Check Ok: ok_procs=$ok_procs num_procs_to_check=$num_procs_to_check procset=$procset");
            return 1;
        }
        else {

            # $my_ns->log_asis("Service Check Failed: ok_procs=$ok_procs num_procs_to_check=$num_procs_to_check procset=$procset");
        }
    }

    return 0;
}

sub _service_socket_check {    ## no critic(ProhibitExcessComplexity,ProhibitManyArgs)
    my ( $my_ns, $service, $port, $send, $res, $tcp_transaction ) = @_;
    my $sok                   = 0;
    my $service_check_message = 'Service check failed to complete';

    my $srv_obj;
    my $can_do_serviceauth_for_service = can_service_do_serviceauth($service);
    if ( $can_do_serviceauth_for_service || $tcp_transaction ) {
        require Cpanel::ServiceAuth;
        $srv_obj = Cpanel::ServiceAuth->new();
    }

    $send =~ s{\\r}{\r}g;
    $send =~ s{\\n}{\n}g;
    if ( index( $send, '%hulkkey_' ) > -1 ) {
        require Cpanel::Hulk;    # PPI USE OK - used in the regex below
        $send =~ s{%hulkkey_([^%]+)%}{Cpanel::Hulk::Key::cached_fetch_key($1)}e;
    }

    require Cpanel::Socket::Constants;
    require Cpanel::FHUtils::Blocking;
    require Cpanel::Exception::Utils;

    my $socket_scc;

    eval {
        local $SIG{ALRM} = sub {
            $service_check_message .= "\nTimeout while trying to connect to service";
            die;
        };
        local $SIG{PIPE} = sub {
            $service_check_message .= "\nFailure while trying to read from service : broken pipe";
            die;
        };
        if ( !$Cpanel::Socket::Constants::AF_INET ) {
            $service_check_message .= "\nFailed to load Cpanel::Socket::Constants (AF_INET value is missing)";
            die;
        }
        $sok = 0;
        if ( $port =~ m/^[0-9]+$/ ) {

            # we need a socket to connect to services on, cpsrvd and cpdavd verify the client ephemeral port so we need to specifically #
            # bind to a port prior to connecting to avoid a race condition where the daemons check the connecting port #
            if ( !socket( $socket_scc, $Cpanel::Socket::Constants::AF_INET, $Cpanel::Socket::Constants::SOCK_STREAM, $Cpanel::Socket::Constants::PROTO_TCP ) || !$socket_scc ) {
                $service_check_message .= "\nCould not setup tcp socket for connection to $port: $!";
                die;
            }

            if ($can_do_serviceauth_for_service) {

                # bind to client port before connect, it's too late after connect #
                my $client_address = Socket::sockaddr_in( 0, Socket::inet_aton('127.0.0.1') );
                bind( $socket_scc, $client_address )
                  or die "Can't bind to an ephemeral port on 127.0.0.1: $!\n";

                if ( open( my $srv_port, '>', '/var/cpanel/serviceauth/' . $service . '/port' ) ) {
                    print {$srv_port} ( unpack( 'nnC4', getsockname($socket_scc) ) )[1];
                    close($srv_port);
                }
            }

            alarm(10);
            if ( !connect( $socket_scc, pack( 'S n a4 x8', $Cpanel::Socket::Constants::AF_INET, $port, ( pack 'C4', ( split /\./, "127.0.0.1" ) ) ) ) ) {
                $service_check_message .= "\nUnable to connect to port $port on 127.0.0.1: $!";
                die;
            }
            alarm(0);

        }
        else {
            require Cpanel::Socket::UNIX::Micro;

            #$port is really a unix socket path
            if ( !socket( $socket_scc, $Cpanel::Socket::Constants::AF_UNIX, $Cpanel::Socket::Constants::SOCK_STREAM, 0 ) || !$socket_scc ) {
                $service_check_message .= "\nCould not setup unix socket for connection to $port: $!";
                die;
            }

            my $usock = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($port);
            alarm(10);
            if ( !connect( $socket_scc, $usock ) ) {
                $service_check_message .= "\nUnable to connect to unix socket $port: $!";
                die;
            }
            alarm(0);
        }
        local $SIG{ALRM} = sub {
            $service_check_message .= "\nTimeout while trying to get data from service";
            die;
        };

        alarm(60);

        my $has_tcp_transaction_support = 1;
        if ( $service eq 'ftpd' && ( -e '/usr/sbin/proftpd' || -e '/usr/local/sbin/proftpd' ) ) {
            $has_tcp_transaction_support = 0;
        }
        elsif ( $service eq 'exim' && !-e '/var/cpanel/exim_service_auth_enable' ) {
            $has_tcp_transaction_support = 0;
        }
        elsif ( -e '/var/cpanel/' . $service . '_service_auth_check_disabled' ) {
            $has_tcp_transaction_support = 0;
        }

        if ( $tcp_transaction && $has_tcp_transaction_support ) {    #not supported under proftpd
            $srv_obj->set_service($service);
            if ( $port > $LOWEST_ROOT_RESTRICTED_PORT ) {            # No need to swap out the keys if port < 1024 as only root can bind to it
                $srv_obj->generate_authkeys(1);
            }
            else {
                $srv_obj->generate_authkeys_if_missing();
            }

            # Normally we wait 6 seconds for the keys to be on the disk to ensure the service has the right one
            # In this case the service will not be caching it so we will not wait
            my $service_auth_user     = $srv_obj->fetch_userkey($Cpanel::ServiceAuth::NO_WAIT);
            my $service_auth_pass     = $srv_obj->fetch_passkey($Cpanel::ServiceAuth::NO_WAIT);
            my $service_auth_user_str = '__cpanel__service__auth__' . $service . '__' . $service_auth_user;
            $tcp_transaction =~ s/%service_auth_user%/$service_auth_user_str/g;
            if ( $tcp_transaction =~ s/%service_auth_pass%/$service_auth_pass/g ) {
                $my_ns->log_asis('[socket_service_auth:1]');
            }
            if ( $tcp_transaction =~ /%service_auth_plain%/ ) {
                require MIME::Base64;
                my $service_auth_plain = MIME::Base64::encode_base64( "\0" . $service_auth_user_str . "\0" . $service_auth_pass );
                $service_auth_plain =~ s/[\r\n]//g;

                $tcp_transaction =~ s/%service_auth_plain%/$service_auth_plain/g;
            }
            chomp($tcp_transaction);
            my $part = 2;
            $service_check_message = 'TCP Transaction Log: ' . "\n";

            foreach my $step ( split( /\|/, $tcp_transaction ) ) {
                if ( $part % 2 == 0 ) {
                    my @GETS;
                    my $get = readline($socket_scc) || do {
                        $service_check_message .= "\nFailed to read from socket: $!";
                    };
                    $get =~ s/[\r\n]//g;
                    $service_check_message .= "<< $get\n";
                    push @GETS, $get;
                    my $tries     = 0;
                    my $max_tries = 120;    # 15 seconds instead of 0.125 :)

                    #special case for imap as we may need to wait for the auth daemon
                    if ( $step !~ /^\*\s*OK/ && $get =~ /^\*\s*OK/ ) {
                        alarm(60);
                        $max_tries = 360;
                    }

                    $GETS[ $#GETS + 1 ] = '';    #create an empty element to fill below
                    Cpanel::FHUtils::Blocking::set_non_blocking($socket_scc);
                    while ( $tries < $max_tries ) {
                        while ( $get = readline($socket_scc) ) {
                            if ( $get =~ /[\r\n]/ ) {
                                $get =~ s/[\r\n]//g;
                                $GETS[-1] .= $get;                            #finish filling the element
                                $service_check_message .= "<< $GETS[-1]\n";

                                push @GETS, '';                               #create an empty element for the next line to fill
                            }
                            else {
                                $GETS[-1] .= $get;                            #not a complete line -- append to the current element
                            }
                            $tries = 0;
                        }
                        $tries++;
                        last if ( grep( /^\Q$step\E/, @GETS ) );    # success, we can pop out
                        select( undef, undef, undef, 0.125 );       #sleep 0.125 seconds
                    }
                    Cpanel::FHUtils::Blocking::set_blocking($socket_scc);
                    if ( $GETS[-1] eq '' ) {
                        pop(@GETS);
                    }
                    if ( !grep( /^\Q$step\E/, @GETS ) ) {
                        $service_check_message .= qq{$service: ** [} . join( "\n", @GETS ) . qq{ != $step]\n};
                        die;                                        #exit eval
                    }

                }
                else {
                    $service_check_message .= ">> $step\n";
                    send( $socket_scc, $step . "\r\n", 0 );
                    alarm(60);

                    #send
                }
                $part++;
            }
            $sok = 1;
        }
        else {
            $srv_obj->set_service($service) if $can_do_serviceauth_for_service;
            if ( defined($send) && $send ne '' ) {

                # On some systems exim tcp check will fail with
                # a sync error without this pause.
                if ( $service =~ m{ \A exim }xms ) {
                    sleep(2);
                }
                if ($can_do_serviceauth_for_service) {
                    $my_ns->log_asis('[http_service_auth:1]');
                    send( $socket_scc, "GET /.__cpanel__service__check__./serviceauth?sendkey=" . $srv_obj->fetch_sendkey() . "&version=1.2 HTTP/1.0\r\nConnection: close\r\n\r\n", 0 );    #special url
                }
                else {
                    send( $socket_scc, $send . "\r\n\r\n\r\n", 0 );
                }
            }
            if ($can_do_serviceauth_for_service) {
                my $get = readline($socket_scc);
                $get =~ s/[\r\n]*//g;
                my $in_body = 0;
                my $key;
                while ( readline($socket_scc) ) {
                    if (/^[\r\n]*$/) { $in_body = 1; next; }
                    if ($in_body) {
                        $key .= $_;
                    }
                }
                $key =~ s/\n//g;
                my $rkey = $srv_obj->fetch_recvkey();
                if ( $key eq $rkey ) {
                    $sok                   = 1;
                    $service_check_message = '';
                }
                else {
                    $service_check_message = qq{$service: [$get != HTTP/1.x 200 OK] [received_key=$key] [expected_key=$rkey]\n};
                }
            }
            else {
                my $retr;
                recv( $socket_scc, $retr, ( length($res) ), 0 );
                if ( $retr =~ /^$res/ ) {
                    $sok                   = 1;
                    $service_check_message = '';
                }
                else {
                    chomp $res;
                    chomp $retr;
                    $service_check_message .= qq{$service: [$retr != $res]\n};
                }
            }
        }
        alarm(0);
    };
    if ($@) {
        $sok = 0;
        $service_check_message .= ': ' . Cpanel::Exception::Utils::traceback_to_error($@);
    }

    alarm(0);
    if ($tcp_transaction) {

        if ( $port > $LOWEST_ROOT_RESTRICTED_PORT ) {    # No need to swap out the keys if port < 1024 as only root can bind to it
                                                         #make new auth keys for security
            $srv_obj->generate_authkeys(1);
        }
    }
    if ( !$sok && $service_check_message ) {
        $my_ns->log_asis($service_check_message);
    }

    return ( $sok, $service_check_message );
}

sub _increment_restart_count {
    my ( $my_ns, $service ) = @_;

    require Cpanel::FileUtils::Open;
    require Cpanel::LoadFile;

    mkdir( $_CHKSERVD_RUN_DIR,                 0755 ) if !-e $_CHKSERVD_RUN_DIR;
    mkdir( "$_CHKSERVD_RUN_DIR/restart_track", 0700 ) if !-e "$_CHKSERVD_RUN_DIR/restart_track";

    my $service_status_file = "$_CHKSERVD_RUN_DIR/$service";
    my $restart_track_file  = "$_CHKSERVD_RUN_DIR/restart_track/$service";

    my $status = Cpanel::LoadFile::loadfile($service_status_file) || '';    # We do not really care if this fails
                                                                            # since there may not be a status yet.
    my $restart_count;

    if ( Cpanel::FileUtils::Open::sysopen_with_real_perms( my $service_fh, $restart_track_file, 'O_RDWR|O_CREAT', 0700 ) ) {
        $restart_count = readline($service_fh) // '';
        chomp($restart_count);
        $restart_count = ( $status eq '-' ) ? ( $restart_count + 1 ) : 1;
        seek( $service_fh, 0, 0 );
        print {$service_fh} $restart_count;
        truncate( $service_fh, tell($service_fh) );
        close $service_fh;
    }
    else {
        $my_ns->{'tailwatch_obj'}->log("Failed to open “$restart_track_file” because of an error: “$!”");
    }
    return $restart_count || 0;
}

sub _previous_servicefile {
    my ( $my_ns, $service ) = @_;
    my $status;
    if ( open my $service_fh, '<', "$_CHKSERVD_RUN_DIR/$service" ) {
        $status = readline($service_fh);
        chomp($status);
        close($service_fh);
    }
    return $status;
}

sub _servicefile {
    my ( $my_ns, $service, $status ) = @_;
    if ( open my $service_fh, '>', "$_CHKSERVD_RUN_DIR/$service" ) {
        print {$service_fh} $status;
        close $service_fh;
        return 1;
    }
    return;
}

sub _servicerestart {
    my ( $my_ns, $service, $restart, $restart_count ) = @_;
    eval {
        local $SIG{ALRM} = sub {
            die "Stuck on restart of $service";
        };
        alarm(450);
        if ( -x '/usr/local/cpanel/scripts/restartsrv_' . $service ) {
            system( '/usr/local/cpanel/scripts/restartsrv_' . $service, '--restart', '--hard', '--attempt', $restart_count );
        }
        else {
            my @CMDS = split( /;/, $restart );
            foreach my $cmd (@CMDS) {
                $my_ns->log_asis("system: $cmd\n");
                my $pid;
                if ( $pid = fork() ) {

                    #parent
                }
                else {
                    Cpanel::Sys::Setsid::full_daemonize();
                    local $0 = "$0 - restarting $service";
                    $SIG{'TERM'} = 'DEFAULT';
                    require Cpanel::CloseFDs;
                    Cpanel::CloseFDs::fast_daemonclosefds();
                    system($cmd);
                    alarm(0);
                    exit;
                }
                waitpid( $pid, 0 );
                wait;
            }
            alarm(0);
        }
    };
    alarm(0);
    if ($@) {
        return Cpanel::Exception::Utils::traceback_to_error($@);
    }
    else {
        return '';
    }
}

sub log_ts_asis {
    my ( $self, $log ) = @_;
    return $self->log_asis( '[' . $self->{'tailwatch_obj'}->datetime() . '] ' . $log );
}

sub log_asis {
    my ( $self, $log ) = @_;

    #   re-open fh if needed print to handle/cplogger
    if ( !$self->{'internal_store'}{'log_fh'} || !fileno( $self->{'internal_store'}{'log_fh'} ) ) {
        $self->{'tailwatch_obj'}->debug('initializing /var/log/chkservd.log file handle') if $self->{'tailwatch_obj'}->{'debug'};

        undef $self->{'internal_store'}{'log_fh'};
        my $old_umask = umask(0077);    # Case 92381: Logs should not be world-readable.
        if ( open $self->{'internal_store'}{'log_fh'}, '>>', '/var/log/chkservd.log' ) {
            $self->{'tailwatch_obj'}->info("Opening /var/log/chkservd.log in append mode");
            umask($old_umask);
        }
        else {
            $self->{'tailwatch_obj'}->error("Failed to open /var/log/chkservd.log in append mode: $!");
            $self->{'tailwatch_obj'}->log($log);    # since we can't put it where it goes, put it somewhere
            umask($old_umask);
            return;
        }
    }
    else {
        $self->{'tailwatch_obj'}->debug('reusing /var/log/chkservd.log file handle') if $self->{'tailwatch_obj'}->{'debug'};
    }

    syswrite( $self->{'internal_store'}{'log_fh'}, $log );
    return 1;
}

=head1 How ChkServd drivers work

So let's say you have a line like the following in /etc/chkservd.d/exim:

    service[exim]=25,QUIT,220,/usr/local/cpanel/scripts/restartsrv_exim stop;/usr/local/cpanel/scripts/restartsrv_exim stop;/usr/local/cpanel/scripts/restartsrv_exim stop;/usr/local/cpanel/scripts/restartsrv_exim start,exim,root|mailnull,220 |EHLO localhost|250 |AUTH PLAIN %service_auth_plain%|2|QUIT|2

What does all this mean? If you read the code in _check_services, you
should notice that this does a split() on the string mentioned earlier which
yields the following:

    ( $port, $send, $res, $restart, $command, $owner, $tcp_transaction, $restart_service )

There's a bit more to it than that, however, as the variable names themselves
don't quite give all the context you'll need to gain a full understanding of
this system. Anyways, The main thing to understand here is that there's two
ways of checking whether a service is up and one way to respond to it being
downed. The two checks are:
1) Port knocking
2) Process tree check

If either of these checks fail, it is time to restart the service.

Here's a bit more context for the individual variables:

=over

=item $port

Port to "knock" on when doing "is this service up" checks.

=item $send

How to properly "knock" on the port (what to send over the socket).

=item $res

What's the response to our "knock knock" joke?

=item $restart

Command to run to restart the service when this is needed.

=item $command

What does this service look like when running the follwoing:

    ps xuww -u $owner

=item $owner

See above item. What to pass to -u. Can have pipes we split on if more than
one owner is possible.

=item $tcp_transaction

A short play by play script which describes a bi-directional transaction over
the socket when doing a port knock. The format is like so:

    RESPONSE|REPLY|RESPONSE|REPLY...

In the exim example above, you'll note that this is what logging into a mail
server looks like.

=item $restart_service

If the 'service' is somehow different than $SERVICE (the filename), override
it here for restarts. Otherwise defaults to $SERVICE in code.

=back

=cut

1;
