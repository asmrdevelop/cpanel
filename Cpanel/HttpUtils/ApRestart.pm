# cpanel - Cpanel/HttpUtils/ApRestart.pm             Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::HttpUtils::ApRestart;

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::ConfigFiles ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Finally               ();
use Cpanel::PsParser              ();
use Cpanel::Config::Httpd::IpPort ();
use Cpanel::Debug                 ();
use Cpanel::Config::Httpd::Vendor ();
use Cpanel::ProcessInfo           ();
use Cpanel::FHUtils::Blocking     ();
use Cpanel::PwCache               ();
use Cpanel::FindBin               ();
use Cpanel::LoadFile              ();
use Cpanel::Logger                ();
use Cpanel::OrDie                 ();
use Cpanel::SafeFile              ();
use Cpanel::FileUtils::Open       ();
use Cpanel::TimeHiRes             ();
use Cpanel::Env                   ();
use Cpanel::Services::Enabled     ();
use Cpanel::OS                    ();
use Cpanel::Imports;

use Try::Tiny;

my $HTTP_RESTART_TIMEOUT = 180;    # This was increased to 180 per CPANEL-9271

my $RESUME_MESSAGE_READ_SIZE = 32768;    # must never be shorter than the length of the RESUME messages

# [Wed Apr 05 00:09:24.492663 2017] [mpm_prefork:notice] [pid 7232] AH00163: Apache/2.4.25 (cPanel) OpenSSL/1.0.1e-fips mod_bwlimited/1.4 mpm-itk/2.4.7-04 PHP/5.6.30 configured -- resuming normal operations
my $APACHE_RESUME_MESSAGE = "configured -- resuming normal operations\n";

# 2017-04-05 07:21:44.592 [NOTICE] [Child: 187455] LiteSpeed/5.1.14 Enterprise starts successfully!
# 2014-12-12 14:06:03.616 [NOTICE] [Child: 1301] LiteSpeed/1.3.6 Open starts successfully!
my $LITESPEED_RESUME_MESSAGE = "starts successfully!\n";

#
# lrwxrwxrwx 1 root root 0 Apr  5 08:12 /proc/531830/exe -> /usr/local/lsws/bin/lscgid.5.1.14
# lrwxrwxrwx 1 root nobody 0 Apr  5 08:12 /proc/531826/exe -> /usr/local/lsws/bin/lshttpd.5.1.14
# lrwxrwxrwx 1 root root 0 Apr  5 01:49 /proc/13794/exe -> /usr/sbin/httpd
#

my @WEBSERVER_PROCESS_NAMES = ( 'httpd', 'litespeed', 'lscgid' );

# Give apache or litespeed 15 seconds to shutdown
# nicely
our $FORCED_SHUTDOWN_TIMEOUT = 15;

my $_TIME_RESTART_LOCK_ACQUIRED;

our $CHECK_AP_RESTART_SLEEP_TIME = 6;

sub bgsafeaprestart {
    require Cpanel::HttpUtils::ApRestart::BgSafe;
    return Cpanel::HttpUtils::ApRestart::BgSafe::restart(@_);
}

sub bgsafeaprebuild {
    require Cpanel::HttpUtils::ApRestart::BgSafe;
    return Cpanel::HttpUtils::ApRestart::BgSafe::rebuild(@_);
}

{
    my $cache;    # static like variable, could use state

    sub DEFAULT_PID_FILE_LOCATION {
        if ( !defined $cache ) {
            $cache = apache_paths_facade->dir_run() . '/httpd.pid';
        }
        return $cache;
    }
}

my @bin_path = ( '/bin', '/sbin', '/usr/bin', '/usr/sbin', '/usr/local/bin', '/usr/local/sbin' );

sub httpd_is_running {
    my @pids = _httpdpids();
    return wantarray ? @pids : scalar @pids;
}

sub forced_restart {
    return safeaprestart(1);
}

sub safeaprestart {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $args_ref = shift;
    my $force;
    if ( ref $args_ref ne 'HASH' ) {
        $force    = $args_ref;
        $args_ref = {};
    }
    else {
        $force = $args_ref->{'force'};
    }

    if ( !Cpanel::Services::Enabled::is_enabled('httpd') ) {
        logger()->info('Apache httpd is disabled, cannot be restarted.');
        return wantarray ? ( 0, 'Apache httpd is disabled, cannot be restarted.' ) : 0;
    }

    local %ENV = %ENV;
    Cpanel::Env::clean_env( 'http_purge' => 1 );

    if ( -e '/var/cpanel/mgmt_queue/apache_update_no_restart' ) {
        return wantarray ? ( 0, 'Apache build currently in progress. Restarts disabled by existence of /var/cpanel/mgmt_queue/apache_update_no_restart. Restarting Apache now may result in a broken Apache build.' ) : 0;
    }

    mkdir apache_paths_facade->dir_domlogs() if !-e apache_paths_facade->dir_domlogs();

    my $original_proc_name = $0;
    local $0 = $original_proc_name . ' - safeaprestart - locking config';
    my $httpc_fh;
    my $httplock = Cpanel::SafeFile::safeopen( $httpc_fh, '<', apache_paths_facade->file_conf() );
    if ( !$httplock ) {
        logger()->warn( 'Could not read from ' . apache_paths_facade->file_conf() );
        return;
    }

    # We setup a Cpanel::Finally to ensure if we die because
    # apache cannot startup that our lock gets removed.
    my $unlock_safety = Cpanel::Finally->new(
        sub {
            Cpanel::SafeFile::safeclose( $httpc_fh, $httplock );
        }
    );
    _set_time_lock_on_conf_acquired();

    local $0 = $original_proc_name . ' - safeaprestart - doing restart';

    my $error_log_fh   = _open_error_log_file();
    my $httpd_pid_file = $args_ref->{'pidfile'} || DEFAULT_PID_FILE_LOCATION();

    my $has_pid_file;
    my $do_read_pid_file = sub {
        $has_pid_file = 0;
        my $file_pid = 0;
        if ( -e $httpd_pid_file ) {
            $has_pid_file = 1;
            $file_pid     = Cpanel::LoadFile::loadfile($httpd_pid_file);
            chomp $file_pid;
        }
        return $file_pid;
    };

    my $file_pid = $do_read_pid_file->();
    my @old_pids;
    my $has_old_pids = 0;

    # If we can't locate an existing httpd process, restart becomes forced
    if ( !$file_pid ) {
        _logger("Unable to read PID from ${httpd_pid_file}. Force restart activated.");
        $force = 1;
    }
    elsif ( !_pid_is_httpd_and_running($file_pid) ) {
        @old_pids     = _httpdpids() if !$has_old_pids;
        $has_old_pids = 1;

        if (@old_pids) {
            if ( !grep { $file_pid eq $_ } @old_pids ) {
                $file_pid = $do_read_pid_file->();
                if ( $has_pid_file && $file_pid && !( grep { $file_pid eq $_ } _httpdpids() ) ) {
                    _logger("PID mismatch. Force restart activated.");
                    $force = 1;
                }
            }
        }
    }

    my $apache_restart_message = '';

    if ( !$force && $file_pid ) {
        if ( !kill( 'USR1', $file_pid ) ) {
            _logger("Unable to send USR1. Force restart activated.");
            $force = 1;
        }
    }

    # Manual Hard restart, cleanup any remnants
    if ( $force || !$file_pid ) {
        @old_pids     = _httpdpids() if !$has_old_pids;
        $has_old_pids = 1;

        _send_usr2_to_litespeed_to_allow_shutdown( \@old_pids );

        if ( Cpanel::OS::is_systemd() ) {
            _stop_via_systemd();
        }
        else {
            # Send SIGTERM and pause
            if (@old_pids) {
                require Cpanel::Kill;
                Cpanel::Kill::safekill_multipid( \@old_pids, 0, $FORCED_SHUTDOWN_TIMEOUT );
            }
        }

        # Clean up from hard restart
        unlink apache_paths_facade->dir_run() . '/httpd.pid';
        unlink apache_paths_facade->dir_run() . '/httpd.scoreboard';
        unlink apache_paths_facade->dir_run() . '/rewrite_lock';

        clear_semaphores();

        # Restart or fail
        local $0 = $original_proc_name . ' - safeaprestart - forced restart';
        $apache_restart_message = _forced_apache_startup();

    }

    my ( $restart_status, $our_restart_message );
    try {
        _wait_for_and_verify_normal_operations( $error_log_fh, $httpd_pid_file );
        $restart_status      = 1;
        $our_restart_message = 'Apache restarted successfully.';
    }
    catch {

        #Ignore the error for now; we’ll repeat this again below.
    };

    if ( !$restart_status ) {
        require Cpanel::SafeRun::Object;
        try {
            Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/ensure_conf_dir_crt_key' );
        }
        catch {
            Cpanel::Debug::log_warn($_);
        };

        # This is a work around for http://bugs.php.net/bug.php?id=38915
        # The restart failed.  Lets try to kill off anything holding apache from restarting
        my @gonner_pids = _get_pids_listening_on_apache_ports_that_are_not_apache();
        if (@gonner_pids) {
            require Cpanel::Kill;
            Cpanel::Kill::safekill_multipid( \@gonner_pids, 0, $FORCED_SHUTDOWN_TIMEOUT );

            local $0 = $original_proc_name . ' - safeaprestart - forced restart';
            $apache_restart_message = _forced_apache_startup();

            try {
                _wait_for_and_verify_normal_operations( $error_log_fh, $httpd_pid_file );
                $restart_status = 1;
            }
            catch {
                require Cpanel::Exception;
                $our_restart_message = Cpanel::Exception::get_string($_);
            };
        }
    }

    if ( $restart_status && -e $Cpanel::ConfigFiles::APACHE_LOGFILE_CLEANUP_QUEUE ) {
        require Cpanel::Transaction::File::JSON;
        require Cpanel::Autodie;

        my $transaction = Cpanel::Transaction::File::JSON->new(
            path => $Cpanel::ConfigFiles::APACHE_LOGFILE_CLEANUP_QUEUE,
        );

        my $cleanup_names = $transaction->get_data();

        if ( ref($cleanup_names) eq 'ARRAY' ) {
            for my $file ( @{$cleanup_names} ) {
                Cpanel::Autodie::unlink_if_exists($file);
            }

            $transaction->set_data( [] );

            # Saving, unlinking, and closing in this order should allow us to remove the file while not having a race on the lock.

            my ( $ok, $err ) = $transaction->save();
            Cpanel::Autodie::unlink_if_exists($Cpanel::ConfigFiles::APACHE_LOGFILE_CLEANUP_QUEUE);
            ( $ok, $err ) = $transaction->close();
        }
    }

    undef $unlock_safety;    #unlock
    if ( !$restart_status ) {
        require Cpanel::FileUtils::Lines;
        my @error = Cpanel::FileUtils::Lines::get_last_lines( apache_paths_facade->file_error_log(), 10 );
        return wantarray ? ( $restart_status, "$our_restart_message\nApache Restart Output:\n$apache_restart_message\nLog:\n" . join( "\n", @error ) ) : $restart_status;
    }
    else {
        return wantarray ? ( $restart_status, $our_restart_message ) : $restart_status;
    }
}

sub _open_error_log_file {

    my $error_logfile = apache_paths_facade->dir_logs() . '/error_log';
    my $error_log_fh;

    Cpanel::FileUtils::Open::sysopen_with_real_perms( $error_log_fh, $error_logfile, 'O_RDONLY|O_CREAT', 0644 ) or die "Unable to open log file “$error_logfile” - $!";
    sysseek( $error_log_fh, -1, $Cpanel::Fcntl::Constants::SEEK_END )                                           or warn "Failed to sysseek($error_logfile)";
    return $error_log_fh;
}

sub _get_pids_listening_on_apache_ports_that_are_not_apache {
    require Cpanel::AppPort;

    # Note: lsof was so slow here that we reached the timeout and
    # another process would traple the lock.  This function
    # must happen quickly since it doesn't know about the
    # $HTTP_RESTART_TIMEOUT

    my $main_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    my $ssl_port  = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    my @ports;
    if ($main_port) { push @ports, $main_port; }
    if ($ssl_port)  { push @ports, $ssl_port; }

    my $app_pid_ref = Cpanel::AppPort::get_pids_bound_to_ports( \@ports );
    my %PIDLIST;

    my $process_regex = get_webserver_process_names_regex();
    foreach my $pid ( keys %{$app_pid_ref} ) {
        my ( $proc, $owner ) = @{ $app_pid_ref->{$pid} }{ 'process', 'owner' };
        next if ( $proc =~ $process_regex || $pid < 10 );
        $PIDLIST{$pid} = $proc;
    }
    return keys %PIDLIST;
}

sub get_webserver_process_names {
    return @WEBSERVER_PROCESS_NAMES;
}

sub get_webserver_process_names_regex {
    my $names_list = join( '|', map { '^' . $_, '/' . $_ } @WEBSERVER_PROCESS_NAMES );
    return qr/$names_list/i;
}

sub get_forced_startup_timeout {
    return _get_restart_timeout() - 35;
}

sub _get_restart_timeout {
    return $HTTP_RESTART_TIMEOUT;
}

# The timer is started right after we get the lock on
# httpd.conf when _set_time_lock_on_conf_acquired is called.
#
# We need to keep counting down the remaining time since
# we cannot hold the lock longer than
# Cpanel::SafeFile::DEFAULT_LOCK_WAIT_TIME or
# we risk having the lock busted.
#
sub _get_restart_timeout_remaining_seconds {
    my $seconds_remaining_in_timeout = $HTTP_RESTART_TIMEOUT - ( time() - $_TIME_RESTART_LOCK_ACQUIRED );
    return 1 if $seconds_remaining_in_timeout < 1;
    return $seconds_remaining_in_timeout;
}

sub _set_time_lock_on_conf_acquired {
    $_TIME_RESTART_LOCK_ACQUIRED = time();
    return;
}

#This throws on error and returns nothing on success.
sub _wait_for_and_verify_normal_operations {
    my ( $error_log_fh, $httpd_pid_file ) = @_;

    try {
        _wait_for_normal_operations_to_resume($error_log_fh);
    }
    catch {
        Cpanel::Debug::log_warn($_);
        local $@ = $_;
        die;
    };

    Cpanel::OrDie::multi_return(
        sub {
            _check_ap_restart($httpd_pid_file);
        }
    );

    return;
}

sub _check_ap_restart {
    my $httpd_pid_file = shift;
    my $restart_status;
    my $our_restart_message;

    # Pid file must always be created
    if ( !-e $httpd_pid_file ) {
        sleep $CHECK_AP_RESTART_SLEEP_TIME;    # Just in case
        if ( !-e $httpd_pid_file ) {
            $restart_status      = 0;
            $our_restart_message = 'Apache restart failed. No pid file created.';
        }
    }

    # Make multiple attempts to detect the pids and the pidfile, timing out if we wait too long.
    my ($file_pid);
    {

        # Not using alarm() because it is not safe with sleep()
        my $timeout_time = time + _get_restart_timeout_remaining_seconds();
        eval {
            do {
                die "timeout\n" if time >= $timeout_time;
                $file_pid = Cpanel::LoadFile::loadfile($httpd_pid_file) || 0;
                chomp $file_pid;
            } while ( !$file_pid && sleep 1 );    # Only sleep and retry if pidfile is empty
        };
    }
    if ($file_pid) {

        if ( _pid_is_httpd_and_running($file_pid) ) {
            $restart_status      = 1;
            $our_restart_message = 'Apache successfully restarted. Signaled successfully.';
        }
        else {
            $restart_status      = 0;
            $our_restart_message = 'Unable to verify Apache restart. Could not signal pid from pid file and no httpd process found in process list.';
        }
    }
    else {
        $restart_status      = 0;
        $our_restart_message = 'Apache restart failed. Unable to load pid from pid file and no httpd process found in process list.';
    }

    if ( !$restart_status ) {
        $our_restart_message .= "\n\nIf apache restart reported success but it failed soon after, it may be caused by oddities with mod_ssl." . "\n\nYou should run /usr/local/cpanel/scripts/ssl_crt_status as part of your troubleshooting process. Pass it --help for more details." . "\n\nAlso be sure to examine apache's various log files.";
    }

    return ( $restart_status, $our_restart_message );
}

sub _wait_for_normal_operations_to_resume {
    my ($error_log_fh) = @_;

    # NB: This used to call the filehandle’s blocking() method, but
    # we occasionally encountered this error:
    #
    #   Can't locate object method "blocking" via package "IO::File"
    #
    # … in response to which we now set this handle to non-blocking
    # via our own logic rather than using IO::File.
    Cpanel::FHUtils::Blocking::set_non_blocking($error_log_fh);

    my $MAX_BUFFER_SIZE = $RESUME_MESSAGE_READ_SIZE * 4;
    my $buffer          = '';
    my $ret;

    my $restart_timeout_remaining = _get_restart_timeout_remaining_seconds();
    my $start_time                = time();
    my $loops                     = 0;
    local $!;
    while (1) {

        #This read() has to come before the select() because Perl may
        #likely have already buffered the headers.
        $ret = sysread( $error_log_fh, $buffer, $RESUME_MESSAGE_READ_SIZE, length $buffer );
        if ($ret) {
            if ( index( $buffer, $APACHE_RESUME_MESSAGE ) > -1 || index( $buffer, $LITESPEED_RESUME_MESSAGE ) > -1 ) {
                return 1;
            }
            if ( length($buffer) > $MAX_BUFFER_SIZE ) {

                # Trim off the buffer down to just the size
                # $RESUME_MESSAGE_READ_SIZE
                #
                # We need to keep enough of the buffer so we can
                # handle partial line reads.
                #
                # We only trim the buffer because of very active servers
                # its possible to have megabytes of log data before
                # the restart finishes.
                substr( $buffer, 0, -1 * $RESUME_MESSAGE_READ_SIZE, '' );
            }
        }
        elsif ( !defined $ret ) {

            #For some reason we’re getting $ret == undef and !$!
            #even though “perldoc -f read” says an undef return will set $!.
            last if !$!;

            if ( !$!{'EINTR'} && !$!{'EAGAIN'} ) {
                die "Failed to read from error log: $!";
            }
        }
        else {
            if ( ( time() - $start_time ) > $restart_timeout_remaining ) {

                # zero read without error . log gone?

                warn "Failed to find “$APACHE_RESUME_MESSAGE” or “$LITESPEED_RESUME_MESSAGE”";
                return 0;
            }
        }

        Cpanel::TimeHiRes::sleep(0.05);

        # Check every second to see if httpd is running
        if ( ++$loops % 20 == 0 && !_httpdpids() ) {

            # This probably means the config file is broken and we will never find the
            # expected resume message.  Its pointless to wait for $HTTP_RESTART_TIMEOUT
            # since there is no webserver running that can resume operations.
            die "The webserver failed to resume normal operations and is not running";
        }
    }

    return 0;
}

sub _pid_is_httpd_and_running {
    my ($pid) = @_;
    if (
        kill( 0, $pid ) &&                # is alive
        ( stat("/proc/$pid") )[4] == 0    # and is running as root
    ) {
        my $exe = readlink("/proc/$pid/exe");

        if ( grep { index( $exe, $_ ) > -1 } @WEBSERVER_PROCESS_NAMES ) {
            return 1;
        }
    }
    return 0;
}

sub _httpdpids {
    my $allowed_users = shift;

    $allowed_users ||= {
        0                                                    => 1,
        scalar( ( Cpanel::PwCache::getpwnam('nobody') )[2] ) => 1,
    };

    my $process_regex = get_webserver_process_names_regex();

    my $current_pid = $$;
    my $parent_pid  = getppid();

    my @pids = sort grep { $_ != $current_pid && $_ != $parent_pid } Cpanel::PsParser::get_pids_by_name( $process_regex, $allowed_users );

    return @pids;
}

sub clear_semaphores {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %args = @_;
    if ( !$args{'user'} ) {
        $args{'user'} = 'nobody';
    }
    if ( !defined $args{'threshold'} ) {
        $args{'threshold'} = 0;
    }
    else {
        $args{'threshold'} = int $args{'threshold'};
    }
    my $verbose = $args{'verbose'} || $args{'test'} ? 1 : 0;

    my $ipcs  = Cpanel::FindBin::findbin( 'ipcs',  'path' => [ '/bin', '/sbin', '/usr/bin', '/usr/local/bin', '/usr/local/sbin' ] );
    my $ipcrm = Cpanel::FindBin::findbin( 'ipcrm', 'path' => [ '/bin', '/sbin', '/usr/bin', '/usr/local/bin', '/usr/local/sbin' ] );
    return if ( !$ipcs || !$ipcrm );

    # this only works on linux
    require Cpanel::SafeRun::Errors;
    my $ipcs_limit_output = Cpanel::SafeRun::Errors::saferunallerrors( $ipcs, '-s', '-l' );
    if ( $ipcs_limit_output =~ m/max\s+number\s+of\s+arrays\s+=\s+(\d+)/ ) {
        my $new_threshold = ( $1 / 2 );
        if ($verbose)                              { print "Calculated Threshold: $new_threshold\n"; }
        if ( $new_threshold < $args{'threshold'} ) { $args{'threshold'} = $new_threshold; }
    }

    # '-s' is for semaphores only
    my @ipcs_output = Cpanel::SafeRun::Errors::saferunallerrors( $ipcs, '-s' );

    my $valid_ipcs_output = scalar @ipcs_output ? 1 : 0;

    my @semaphore_ids;

    foreach my $line (@ipcs_output) {
        next if $line =~ m/^(?:T|key)\s+(?:ID|semid)/;    # Skip header
        if ( $line =~ m/^\S+\s+(\d+)\s+(\S+)\s+\d+\s+\d+/ ) {
            my $owner = $2;
            if ( $owner eq $args{'user'} ) {
                print "Adding semaphore ID $1 to list\n" if $verbose;
                push @semaphore_ids, $1;
            }
            else {
                print "Skipping semaphore $1 for user $owner\n" if $verbose;
            }
        }
        elsif ( $line =~ m/^\S+\s+(\d+)\s+\d+\s+\S+\s+(\S+)\s+/ ) {
            my $owner = $2;
            if ( $owner eq $args{'user'} ) {
                print "Adding semaphore ID $1 to list\n" if $verbose;
                push @semaphore_ids, $1;
            }
            else {
                print "Skipping semaphore $1 for user $2\n" if $verbose;
            }
        }
    }

    if (@semaphore_ids) {
        if ( scalar @semaphore_ids > $args{'threshold'} ) {
            my $ipcrm_usage_mtime = ( stat('/var/cpanel/version/ipcrm_usage') );
            my $ipcrm_mtime       = ( stat($ipcrm) );
            my $ipcrm_output;
            if ( $ipcrm_usage_mtime && $ipcrm_usage_mtime >= $ipcrm_mtime && $ipcrm_usage_mtime < time() ) {
                $ipcrm_output = Cpanel::LoadFile::loadfile('/var/cpanel/version/ipcrm_usage');
            }
            if ( !$ipcrm_output ) {
                $ipcrm_output = Cpanel::SafeRun::Errors::saferunallerrors( $ipcrm, '-h' );
                open( my $ipc_rm_fh, '>', '/var/cpanel/version/ipcrm_usage' );
                print {$ipc_rm_fh} $ipcrm_output;
                close $ipc_rm_fh;
            }

            my $ipcrm_flag = ( $ipcrm_output =~ m/-s/ ? '-s' : 'sem' );
            foreach my $id (@semaphore_ids) {
                next if !$id;
                if ( !$args{'test'} ) {
                    print "Removing semaphore $id\n" if $verbose;
                    print Cpanel::SafeRun::Errors::saferunallerrors( $ipcrm, $ipcrm_flag, $id );
                }
                else {
                    print "Would remove semaphore $id\n";
                }
            }
            return 1;
        }
    }
    else {
        if ($valid_ipcs_output) {
            print "No semaphores for user $args{'user'} located.\n" if $verbose;
        }
        else {
            print "Unable to parse ipcs output.\n" if $verbose;
        }
    }
    return $valid_ipcs_output;
}

sub _logger {
    my ($msg) = @_;
    return Cpanel::Logger::logger(
        {
            'message'   => $msg,
            'level'     => 'info',
            'service'   => __PACKAGE__,
            'output'    => 0,
            'backtrace' => 0,
        }
    );
}

#
# Litespeed requires USR2 to be sent right
# before TERM to allow a shutdown
#
# Sadly, this only appears to be documented (the code is the doc) in
#  /usr/local/lsws/bin/lswsctrl
#
sub _send_usr2_to_litespeed_to_allow_shutdown {
    my ($old_pids_ar) = @_;
    my ( $vendor, $version ) = Cpanel::Config::Httpd::Vendor::httpd_vendor_info();
    if ( index( $vendor, 'litespeed' ) > -1 ) {
        if ( my @litespeed_pids = grep { index( Cpanel::ProcessInfo::get_pid_cmdline($_), 'litespeed' ) > -1 } @$old_pids_ar ) {
            kill 'USR2', @litespeed_pids;
            return @litespeed_pids;
        }
    }

    return ();

}

sub _stop_via_systemd {
    require Cpanel::SafeRun::Object;

    my $timeout = _get_restart_timeout_remaining_seconds();

    my $run = Cpanel::SafeRun::Object->new(
        'program'      => '/usr/bin/systemctl',
        'args'         => [ 'stop', 'httpd.service' ],
        'timeout'      => $timeout,
        'read_timeout' => $timeout,
    );

    if ( $run->CHILD_ERROR() ) {
        return "Apache could not be started due to an error: " . join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) );
    }

    return $run->stdout();
}

sub _forced_apache_startup {
    require Cpanel::SafeRun::Object;

    my $timeout = _get_restart_timeout_remaining_seconds();

    my $program = '/usr/local/cpanel/scripts/restartsrv_httpd';
    my $args    = ['--start'];

    my $run = Cpanel::SafeRun::Object->new(
        'program'      => $program,
        'args'         => $args,
        'timeout'      => $timeout,
        'read_timeout' => $timeout,
        'before_exec'  => sub {

            # restartsrv cannot pass options to ServiceManager modules
            # at this time so we are stuck with an ENV
            $ENV{'SKIP_DEFERRAL_CHECK'} = 1;
        }
    );

    if ( $run->CHILD_ERROR() ) {
        return "Apache could not be started due to an error: " . join( q< >, map { $run->$_() // () } qw( autopsy stdout stderr ) );
    }

    return $run->stdout();
}

1;

__END__

Linux:
------ Semaphore Arrays --------
key        semid      owner      perms      nsems
0x0052e2c1 0          postgres  600        17
0x0052e2c2 32769      postgres  600        17
0x0052e2c3 65538      postgres  600        17
0x0052e2c4 98307      postgres  600        17
