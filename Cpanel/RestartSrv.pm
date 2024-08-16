package Cpanel::RestartSrv;

# cpanel - Cpanel/RestartSrv.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic(RequireUseWarnings) - requires auditing for potential warnings

use Try::Tiny;    # for perlpkg updatenow.static

use Cpanel::LoadModule                   ();
use Cpanel::Exception                    ();
use Cpanel::LoadFile                     ();
use Cpanel::ProcessCheck::Running        ();
use Cpanel::PwCache                      ();
use Cpanel::Services::Log                ();
use Cpanel::RestartSrv::Systemd          ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Sys::Setsid                  ();

$SIG{'HUP'} = 'IGNORE';    ## no critic qw(Variables::RequireLocalizedPunctuationVars) - by design

$ENV{'RESTARTSRV'} = 1;

our $RESTART = 1;
our $STOP    = -1;
our $RELOAD  = -2;

my $logger;

sub loadcpconfig {
    require Cpanel::Config::LoadCpConf;
    goto &Cpanel::Config::LoadCpConf::loadcpconf;
}

#XXX: This overwrites global $ENV{'PATH'}.
sub setuppath {
    my @PDIRS = ( '/bin', '/usr/bin', '/sbin', '/usr/sbin', '/usr/local/bin', '/usr/local/sbin' );
    my @EPDIRS;
    foreach my $pdir (@PDIRS) {
        next if !-e $pdir;
        push @EPDIRS, $pdir;
    }
    $ENV{'PATH'} = join( ':', @EPDIRS );

    return;
}

sub _get_argv {
    return @ARGV;
}

sub _set_argv {
    @ARGV = @_;    ## no critic qw(Variables::RequireLocalizedPunctuationVars) - legacycode
    return;
}

sub parseargv {
    my $restart = $RESTART;
    my $check   = 0;
    my $status  = 0;
    my $verbose = 0;
    my $restart_attempts;
    my $graceful;

    my @args = _get_argv();
    require Getopt::Long;
    import Getopt::Long qw( :config pass_through );
    Getopt::Long::GetOptionsFromArray(
        \@args,
        'status!'   => \$status,
        'check!'    => \$check,
        'verbose!'  => \$verbose,
        'debug!'    => sub { $verbose = $_[1] ? 2 : 0; },
        'attempt=i' => \$restart_attempts,
        'stop!'     => sub {
            if ( $_[1] ) {
                $restart = $STOP;
                $check   = 0;
                $status  = 0;
            }
            else {
                $restart = $RESTART;
                $check   = 0;
                $status  = 0;
            }
        },
        'reload!' => sub {
            if ( $_[1] ) {
                $restart = $RELOAD;
                $check   = 0;
                $status  = 0;
            }
            else {
                $restart = $RESTART;
                $check   = 0;
                $status  = 0;
            }
        },
        'restart!' => sub {
            if ( $_[1] ) {

                # can't be anything else #
                $restart = $RESTART;
                $check   = 0;
                $status  = 0;
            }
            else {
                $restart = 0;
            }
        },
        'graceful!' => \$graceful,
    );
    _set_argv(@args);

    # state protection #
    if ( $status || $check ) {

        # ensure no restart action is defined when status or check is requested #
        $restart          = 0;
        $graceful         = undef;
        $restart_attempts = undef;
    }
    elsif ( !$restart && !$check && !$status ) {

        # protect against a no operation being specified here (passing --no-restart as only arg) #
        $status           = 1;
        $graceful         = undef;
        $restart_attempts = undef;
    }

    # compatibility services not using non-Cpanel::ServiceManager logic #
    print "--restartsrv: check mode starting--\n" if $check && $ENV{'RESTARTSRV_CHECKMODE_HEADER'};

    return ( $restart, $check, $status, $verbose, $restart_attempts, $graceful );
}

sub get_formatted_output_object {
    my (@argv) = @_;

    if ( grep( /html/, @argv ) ) {
        require Cpanel::Output::Formatted::HTML;
        return Cpanel::Output::Formatted::HTML->new();
    }

    require Cpanel::Output::Formatted::Terminal;
    return Cpanel::Output::Formatted::Terminal->new();
}

sub getinitfile {
    my ($service) = @_;
    my @initdirarray;

    # systemd systems need to use systemctl to start and stop services #
    return if Cpanel::RestartSrv::Systemd::has_service_via_systemd($service);

    # No init script.
    return if $service eq 'clamd';

    push @initdirarray, '/etc/init.d';

    foreach my $initdir (@initdirarray) {
        my @initfiles;
        if ( opendir my $dh, $initdir ) {
            @initfiles = readdir $dh;
            closedir $dh;
        }

        my $partial_match;
        my $numeric_match;
        foreach my $strtscript (@initfiles) {
            next if $strtscript =~ m/^\./;
            next if $strtscript =~ m/\.rpm[a-z]+$/;    # expanded match for .rpmorig, etc.
            next if !-f $initdir . '/' . $strtscript;
            if ( -x _ ) {
                if ( lc $strtscript eq lc $service ) {
                    return "$initdir/$strtscript";
                }
                elsif ( !$partial_match && $strtscript =~ m/^\Q$service\E/i ) {
                    $partial_match = $strtscript;
                }
                elsif ( !$numeric_match && $strtscript =~ m/^[\d\.]+\Q$service\E/i ) {
                    $numeric_match = $strtscript;
                }
            }
        }
        if ($partial_match) {
            return "$initdir/$partial_match";
        }
        if ($numeric_match) {
            return "$initdir/$numeric_match";
        }
    }
    return;
}

# Case 186205, _is_installed is a bit of a misnomer
# but I did not have a better name.
# _is_probably_installed might be better?

sub _is_installed {
    my ($service) = @_;

    return 0 if $service eq 'rsyslog' && !-x '/sbin/rsyslogd';

    # Case 186205, mark as disabled if not installed
    if (   $service eq "syslogd"
        || $service eq "rsyslog" ) {
        return 1 if Cpanel::RestartSrv::Systemd::has_service_via_systemd($service);    # do not care if systemd.

        # if /etc/init.d/syslogd exists that is what will
        # be called, so it must exist.

        my $exists = 0;
        $exists = 1 if defined getinitfile('syslog');
        $exists = 1 if defined getinitfile('syslogd');
        $exists = 1 if defined getinitfile('rsyslogd');
        $exists = 1 if defined getinitfile('rsyslog');

        return $exists;
    }

    return 1;
}

sub is_service_disabled {
    my $p_service = shift;

    # Case 186205, mark as disabled if not installed to prevent
    # an ugly stack trace on the command line.
    return 1 if ( !_is_installed($p_service) );
    return -f "/etc/${p_service}disable" ? 1 : 0;
}

sub setuids {
    require Cpanel::AccessIds::SetUids;
    goto &Cpanel::AccessIds::SetUids::setuids;
}

sub runasuser {
    require Cpanel::AccessIds;
    goto &Cpanel::AccessIds::runasuser;
}

sub doomedprocess {
    my ( $deadcmd, $verbose, $wait_time, $allowed_owners ) = @_;

    require Cpanel::Kill;
    require Cpanel::ProcessInfo;

    #Don’t kill() ancestor processes of the current process.
    my @lineage = Cpanel::ProcessInfo::get_pid_lineage();

    return Cpanel::Kill::safekill( $deadcmd, $verbose, $wait_time, \@lineage, $allowed_owners );
}

sub nooutputsystem {
    my (@unsafecmd) = @_;
    my (@cmd);
    while ( $unsafecmd[$#unsafecmd] eq '' ) { pop(@unsafecmd); }
    foreach (@unsafecmd) {
        my @cmds = split( / /, $_ );
        foreach (@cmds) { push( @cmd, $_ ); }
    }
    my $pid;
    unless ( $pid = Cpanel::Sys::Setsid::full_daemonize( { 'keep_parent' => 1 } ) ) {
        require Cpanel::CloseFDs;
        Cpanel::CloseFDs::fast_closefds();

        open( STDIN,  '<', '/dev/null' );
        open( STDOUT, '>', '/dev/null' );
        open( STDERR, '>', '/dev/null' );
        exec(@cmd) or exit 1;
    }
}

sub _has_proc {
    return -d "/proc";
}

sub check_service {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my %OPTS = @_;

    my $ignore_systemd = defined $OPTS{'ignore_systemd'} ? $OPTS{'ignore_systemd'} : 0;
    my ( $pid, $pidcheck ) = ( $OPTS{'pid'}, $OPTS{'check_method'} );
    my $info;

    # see if we can get info from systemctl #
    if ( !$ignore_systemd && ( $info = Cpanel::RestartSrv::Systemd::has_service_via_systemd( $OPTS{'service'} ) ) ) {
        my $pid_from_systemd = Cpanel::RestartSrv::Systemd::get_pid_via_systemd( $OPTS{'service'} );

        if ( !$pid || $pid == $pid_from_systemd ) {

            $pid //= $pid_from_systemd;

            $pidcheck = 'systemd';

            # lie for oneshot persistent service
            if ( $info && $info->{Type} && $info->{Type} eq 'oneshot' ) {
                return "$OPTS{'service'} (/bin/true - oneshot) ran successfully ($pidcheck check method).\n"
                  if $info->{'ActiveState'} eq 'active';
            }
            elsif ( !$pid && $info && $info->{'Type'} && $info->{'Type'} eq 'forking' ) {

                # at least one of the daemons is active, give the first PID #
                # if any of them go down systemd will take the rest down, so one PID is as good as any #
                ($pid) = Cpanel::RestartSrv::Systemd::get_pids_via_systemd( $OPTS{'service'} )
                  if $info->{'ActiveState'} eq 'active';
            }
            elsif ( $info && $info->{'Type'} && $info->{'Type'} eq 'simple' ) {
                if ( $info->{'MainPID'} == $pid ) {
                    if ( $info->{'ActiveState'} eq 'active' && $info->{'SubState'} eq 'running' ) {
                        return "$OPTS{'service'} ($info->{FragmentPath} - simple) is running with PID $pid ($pidcheck check method).\n";
                    }
                }
            }

            # we know that systemd is viewing the systemd as down
            #   it might be alive but outside of systemd control
            #   we will need to doom it
            return '' unless $pid;

        }
    }
    elsif ( !$pid && defined $OPTS{'pidfile'} && $OPTS{'pidfile'} ) {

        # the caller may be probing for the service daemon by other attributes, #
        # so there is a possibly of having no usable pidfile   :| #
        if ( -r $OPTS{'pidfile'} ) {
            $pid = Cpanel::LoadFile::load( $OPTS{'pidfile'} );

            # postgres can use more than one single line in the pidfile
            my @lines = split( "\n", $pid );
            $pid      = int( $lines[0] );
            $pidcheck = 'pidfile';
        }
    }

    # if on linux, or something with a /proc/PID setup, we can do this a little more reliably #
    if ( $pid && _has_proc() ) {

        # process may no longer be running #
        return '' if !-d "/proc/$pid";

        # determine owner, details, etc #
        my $diruid   = ( stat("/proc/$pid") )[4];
        my $dirowner = ( Cpanel::PwCache::getpwuid_noshadow($diruid) )[0];
        open my $cmd_fh, '<', "/proc/$pid/cmdline" or return '';
        my $cmdline = join ' ', split /\0/, scalar <$cmd_fh>;
        close $cmd_fh;

        # The process may have exited after the first pid existence check, invalidating everything that was gathered above.
        return '' if !-d "/proc/$pid";

        require Cpanel::Services::Command;

        # If its a command we should ignore we must due so here
        # so we do not incorrectly report that the service
        # is up and put restartsrv in a state where is cannot restart it
        # because one part of it belives its up and another part
        # believes its down
        if ( !Cpanel::Services::Command::should_ignore_this_command($cmdline) ) {
            $pidcheck .= '+/proc' if $pidcheck;
            $pidcheck ||= '/proc';
            return "$OPTS{'service'} ($cmdline) is running as $dirowner with PID $pid ($pidcheck check method).\n";
        }
    }

    if ( $pid && $OPTS{'service'} && $OPTS{'user'} ) {
        local $@;

        my $running_obj = eval {
            my $running_obj = Cpanel::ProcessCheck::Running->new(
                'use_services_ignore' => 1,                  # ignore things that false positives for services (like vim, emacs, perl test)
                'pid'                 => $pid,
                'pattern'             => $OPTS{'service'},
                'user'                => $OPTS{'user'},
            );
            $running_obj->check_all();
            $running_obj;
        };
        if ($running_obj) {
            my $cmdline_ar = $running_obj->pid_object()->cmdline();
            $pidcheck .= '+processcheck' if $pidcheck;
            $pidcheck ||= 'processcheck';
            return "$OPTS{'service'} (@$cmdline_ar) is running as $OPTS{'user'} with PID $pid ($pidcheck check method)\n";
        }
    }

    require Cpanel::Services;
    goto &Cpanel::Services::check_service;
}

sub find_mysqladmin {
    my @PATHS = qw(
      /usr/bin
      /usr/local/bin
      /usr/local/cpanel/3rdparty/bin
    );

    foreach my $path (@PATHS) {
        my $program = "$path/mysqladmin";

        return $program if -e $program;
    }

    return;
}

sub logged_startup {
    my ( $service, $wipe, $cmd_ar, %p_options ) = @_;

    # the exit code of the daemon's startup binary is not guaranteed unless wait is specified as an option #

    local $!;

    _mkdir_or_log_failure($Cpanel::Services::Log::STARTUP_LOG_DIR);

    my ( $to_run, @args ) = @$cmd_ar;

    if ( Cpanel::RestartSrv::Systemd::has_service_via_systemd($service) && 1 == getppid() ) {

        # systemd systems will call into the daemon running as PID 1 and have it launch the binary #
        # this daemon is capturing the output and whatnot, we don't need to track it here #
        exec $to_run, @args;
    }

    my $start_log_fh;
    try {
        $start_log_fh = _open_startup_log( $service, $wipe ? '>' : '>>' );
    }
    catch {
        open $start_log_fh, '>', '/dev/null' or die "Failed to open > /dev/null: $!";
    };

    # when specified, we'll wait for the daemon's startup binary and $? will be the exit code #
    my $wait = defined $p_options{'wait'} ? $p_options{'wait'} : 0;

    my $pid = !$wait ? _start_as_daemon( $to_run, $start_log_fh, @args ) : _start_capture_and_wait( $to_run, $start_log_fh, @args );
    close($start_log_fh);

    return $pid;
}

sub fetch_startup_log {
    my $real_service_name = shift;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($real_service_name);

    # this function is deprecated in favor Cpanel::Services::Log::fetch_service_startup_log #
    my ( $log_exists, $log ) = Cpanel::Services::Log::fetch_service_startup_log($real_service_name);
    return undef if !$log_exists;

    return $log;
}

sub append_to_startup_log {
    my ( $real_service_name, $msg ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($real_service_name);

    if ( length $msg ) {
        my $startup_log_fh = _open_startup_log( $real_service_name, '>>' );

        local $!;
        print {$startup_log_fh} $msg or die "The system failed to append to the “$real_service_name” log: $!";
        close($startup_log_fh);
    }

    return 1;
}

sub _start_as_daemon {
    my ( $path, $start_log_fh, @args ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::ForkSync');
    Cpanel::LoadModule::load_perl_module('Cpanel::ForkAsync');

    my $fork1 = Cpanel::ForkSync->new(
        sub {
            pipe my $err_rd, my $err_wr or die "pipe() error: $!";

            my $pid = Cpanel::ForkAsync::do_in_child(
                sub {
                    close $err_rd;

                    require Cpanel::CloseFDs;

                    open( STDERR, '>&=', fileno($start_log_fh) );
                    open( STDOUT, '>&=', fileno($start_log_fh) );

                    open( STDIN, '<', '/dev/null' );
                    Cpanel::CloseFDs::fast_closefds( except => [$err_wr] );

                    exec {$path} $path, @args or do {
                        my $err = $!;
                        syswrite $err_wr, pack( 'C', $! );
                        exit $!;
                    };
                }
            );

            close $err_wr;

            if ( sysread $err_rd, my $err, 1 ) {
                local $! = unpack 'C', $err;
                return { error => $!, path => $path };
            }

            return $pid;
        }
    );

    my $result = $fork1->return()->[0];
    if ( 'HASH' eq ref $result ) {
        die Cpanel::Exception::create( 'IO::ExecError', $result );    ## no extract maketext (variable is metadata; the default message will be used)
    }

    return $result;
}

sub _start_capture_and_wait {
    my ( $path, $start_log_fh, @args ) = @_;

    if ( !-f -x $path ) {
        $? = 2 << 8;
        return undef;
    }

    my $child;

    unless ( $child = Cpanel::Sys::Setsid::full_daemonize( { 'keep_parent' => 1 } ) ) {
        require Cpanel::CloseFDs;

        open( STDERR, '>&=', fileno($start_log_fh) );
        open( STDOUT, '>&=', fileno($start_log_fh) );

        open( STDIN, '<', '/dev/null' );
        Cpanel::CloseFDs::fast_closefds();
        exec {$path} $path, @args or do {
            print STDERR "failed to exec '$path': $!\n";
            exit $!;
        };
    }
    return $child;
}

sub _open_startup_log {
    my ( $service_name, $mode ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($service_name);

    my $log_file_name = Cpanel::Services::Log::get_service_name_from_legacy_name($service_name);

    my $path = "${Cpanel::Services::Log::STARTUP_LOG_DIR}/$log_file_name";

    local $!;
    open( my $startup_log_fh, $mode, $path ) or do {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $path, mode => $mode, error => $! ] );
    };

    return $startup_log_fh;
}

sub _mkdir_or_log_failure {
    my ($dir) = @_;

    if ( !-d $dir ) {
        require Cpanel::SafeDir::MK;

        Cpanel::SafeDir::MK::safemkdir( $dir, 0700 ) || do {
            require Cpanel::Logger;
            $logger ||= Cpanel::Logger->new();
            $logger->warn("Failed to create $dir: $!");
        };
    }

    return;
}

sub _croak {
    require Carp;
    goto \&Carp::croak;
}

1;
