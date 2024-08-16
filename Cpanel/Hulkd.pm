package Cpanel::Hulkd;

# cpanel - Cpanel/Hulkd.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

BEGIN {
    $INC{'attributes.pm'} = '__DISABLED__';    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
}

use Cpanel::Config::Hulk                            ();
use Cpanel::Exception                               ();
use Cpanel::Hulkd::Proc                             ();
use Cpanel::Hulkd::Daemon                           ();
use Cpanel::Hulk::Cache::IpLists                    ();
use Cpanel::ForkAsync                               ();
use Cpanel::FHUtils::Blocking                       ();
use Cpanel::Wait::Constants                         ();
use Cpanel::MemUsage::Daemons::Banned               ();
use Cpanel::Hulkd::Processor                        ();
use Cpanel::Security::Authn::TwoFactorAuth::Enabled ();
use Cpanel::Services::Dormant                       ();
use Cpanel::Sys::Chattr                             ();
use Cpanel::ServerTasks                             ();
use Cpanel::Systemd::Notify                         ();

use IO::Select               ();
use Cpanel::Socket::INET     ();
use Cpanel::Socket::UNIX     ();
use Cpanel::Logger           ();
use Cpanel::FHUtils::FDFlags ();

use Try::Tiny;

Cpanel::MemUsage::Daemons::Banned::check();

our $SERVED_REQUEST_THAT_CAN_HANDLED_WITH_DORMANT_MODE = 10;

my $hostname;
my $conserve_memory                      = 0;
my $MAX_FILEFHANDLES_EXPECTED_TO_BE_OPEN = 1000;
my $LISTEN_BACKLOG                       = 45;
my $MAX_ERROR_LOG_SIZE                   = ( 1024**2 * 5 );    # 5 MEG
my $MAX_MAIN_LOG_SIZE                    = ( 1024**2 * 5 );    # 5 MEG

our @LOGS = (
    { 'key' => 'errlog',  'file' => '/usr/local/cpanel/logs/cphulkd_errors.log', 'max_size' => $MAX_ERROR_LOG_SIZE, 'fh' => \*STDERR },
    { 'key' => 'mainlog', 'file' => '/usr/local/cpanel/logs/cphulkd.log',        'max_size' => $MAX_MAIN_LOG_SIZE,  'fh' => \*STDOUT },
);

# 5 minutes
our $ALARM_INTERVAL                      = 300;
our $ALARM_COUNT_THAT_ESTIMATES_ONE_HOUR = 12;
our $HOT_RESTART_PENDING                 = 0;

sub new {
    my $class = shift;
    my $hulk  = {
        'start'        => scalar time(),
        'tfa_enabled'  => scalar Cpanel::Security::Authn::TwoFactorAuth::Enabled::is_enabled(),
        'debug'        => -e Cpanel::Config::Hulk::get_debug_file(),
        'dormant_mode' => Cpanel::Services::Dormant->new( service => 'cphulkd' ),
    };

    return bless $hulk, $class;
}

sub run_daemon {
    my ($hulk) = @_;

    my ( $switch, @opts ) = @ARGV;
    $switch ||= '';

    my $launch_opt = 0;    # Is launch_opt still needed?
    if ( defined $opts[0] && $opts[0] =~ /^[0-9]+$/ ) {
        $launch_opt = int shift @opts;
    }

    $hulk->sdnotify()->enable() if grep { $_ eq '--systemd' } @opts;

    if ( $switch eq '--restart' ) {
        if ( !$hulk->restart_daemon() ) {
            $hulk->stop_daemon();
            $hulk->start_daemon();
        }
    }
    elsif ( $switch eq '--stop' ) {
        $hulk->stop_daemon();
        exit;
    }
    elsif ( $switch eq '--help' ) {
        print "Usage: $0 [--start|--stop|--restart||--objcheck]\n";
        print "\t--objcheck does not have any info on if the main daemon is running" . "\n\tor if duplicate detectives are running\n";
        exit;
    }
    else {
        $hulk->start_daemon($launch_opt);
    }
    return;
}

# This function causes the process to exec another version of the binary. It isn't a FULL restart.
sub restart_daemon {

    return Cpanel::Hulkd::Daemon::reload_daemons();
}

sub stop_daemon {

    return Cpanel::Hulkd::Daemon::stop_daemons();
}

#called from tests
sub _open_log_files {
    my ($hulk) = @_;
    foreach my $log (@LOGS) {

        # Rotate error log every 5M
        if ( -e $log->{'file'} ) {
            my $size = ( stat(_) )[7];
            if ( $size > $log->{'max_size'} ) {
                require Cpanel::Logs::Truncate;
                print "Clearing $log->{'key'} $log->{'file'}\n";
                Cpanel::Logs::Truncate::truncate_logfile( $log->{'file'} );
            }
        }

        $hulk->{ $log->{'key'} } = Cpanel::Logger->new( { 'alternate_logfile' => $log->{'file'}, 'open_now' => 1 } );

        if ( $log->{'fh'} ) {
            open( $log->{'fh'}, ">>&=", fileno( $hulk->{ $log->{'key'} }->get_fh() ) ) || die "Could not redirect $log->{'key'}: $!";
            Cpanel::Sys::Chattr::set_attribute( $hulk->{ $log->{'key'} }->get_fh(), 'APPEND' );
        }
    }
    return 1;
}

sub start_daemon {
    my ( $hulk, $launch_opt ) = @_;

    $hulk->_open_log_files();

    return $hulk->launcher($launch_opt);
}

sub launcher {
    my ( $hulk, $launch_opt ) = @_;

    my $applist_ref   = Cpanel::Hulkd::Proc::get_applist_ref();
    my $apps_to_start = Cpanel::Hulkd::Proc::get_apps_to_start( $hulk, $launch_opt );

    my $code = sub {
        my $app = shift;

        my $pidfile = "/var/run/cphulkd_${app}.pid";

        open( STDIN, '<', '/dev/null' );    ## no critic qw(RequireCheckedOpen)
        local $0 = 'cPhulkd - ' . $app;

        Cpanel::Hulkd::Proc::write_pid_file( $app, 'keep_open' => 1 )
          or $hulk->warn("Unable to write /var/run/cphulkd_${app}.pid file: $!");

        $applist_ref->{$app}->{'code'}($hulk);
    };

    my $start_processor = 0;

    # fork off all non 'processor' apps first
    foreach my $app ( @{$apps_to_start} ) {
        $app eq 'processor' ? $start_processor = 1 : Cpanel::ForkAsync::do_in_child( sub { $hulk->sdnotify()->safe_disable(); $code->($app); } );
    }

    # start the processor last
    $code->('processor') if $start_processor;

    return 1;
}

sub status_dump {
    my $self = shift;

    require Data::Dumper;
    my $dump = Data::Dumper::Dumper($self);

    return $dump if wantarray;
    print $dump;
    return 1;
}

sub dbprocessor_run {
    my $hulk = shift;

    $hulk->mainlog("DB processor startup with pid $$");
    my $dbsocket = $hulk->_init_db_socket();
    $hulk->_start_db_loop($dbsocket);
    exit 0;
}

sub processor_run {
    my $hulk = shift;

    my ( $socket, $httpsocket );
    $hulk->mainlog("processor startup with pid $$");

    my ( $listenfd, $acceptedfd, $httplistenfd ) = $hulk->_parse_argv( \@ARGV );

    if ($listenfd) {
        local $^F = $MAX_FILEFHANDLES_EXPECTED_TO_BE_OPEN;    #prevent cloexec

        try {
            $socket = Cpanel::Socket::UNIX->new_from_fd( $listenfd, '+<' );
        }
        catch {
            $hulk->die("Could not open fd listenfd: $listenfd - $_");
        };

        try {
            $httpsocket = Cpanel::Socket::INET->new_from_fd( $httplistenfd, '+<' );
        }
        catch {
            $hulk->die("Could not open fd httplistenfd: $httplistenfd - $_");
        };
    }
    else {
        ( $socket, $httpsocket ) = $hulk->_init_sockets();
    }

    $hulk->rebuild_caches();
    $hulk->purge_old_logins();
    Cpanel::ServerTasks::schedule_task( ['cPHulkTasks'], 10, 'update_country_ips' );

    $hulk->sdnotify()->ready();

    if ($acceptedfd) {
        my $client_socket;
        {
            local $^F = $MAX_FILEFHANDLES_EXPECTED_TO_BE_OPEN;    #prevent cloexec
            try {
                $client_socket = Cpanel::Socket::UNIX->new_from_fd( $acceptedfd, '+<' );
            }
            catch {
                $hulk->die("Could not reopen pre accepted connection: $_");
            };
        }

        # mark that connection coming from dormant mode
        $hulk->_handle_accepted_socket_and_reset_idleloops( $client_socket, 1 );
    }

    if ( !$hulk->main_loop( $socket, $httpsocket ) ) {
        exit(1);
    }

    exit(0);
}

sub main_loop {
    my ( $hulk, $socket, $httpsocket ) = @_;

    # We use a self pipe to cause the select to unblock
    # when we need to purge the old logins
    my ( $self_pipe_read_handle, $self_pipe_write_handle ) = $hulk->_generate_selfpipe();

    my $ALRM_SINGLE_DIGIT_NUMBER = 1;
    my $CHLD_SINGLE_DIGIT_NUMBER = 2;
    my $HUP_SINGLE_DIGIT_NUMBER  = 3;
    my $TERM_SINGLE_DIGIT_NUMBER = 4;
    my $USR1_SINGLE_DIGIT_NUMBER = 3;

    local $SIG{'ALRM'} = sub { syswrite( $self_pipe_write_handle, $ALRM_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'CHLD'} = sub { syswrite( $self_pipe_write_handle, $CHLD_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'HUP'}  = sub { syswrite( $self_pipe_write_handle, $HUP_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'USR1'} = sub { syswrite( $self_pipe_write_handle, $USR1_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'TERM'} = sub { syswrite( $self_pipe_write_handle, $TERM_SINGLE_DIGIT_NUMBER ); };

    # We got SIGHUP or SIGUSR1 between startup and now
    _hot_restart_full( $hulk, $socket, $httpsocket ) if $HOT_RESTART_PENDING;

    my $alarm_count = 0;
    alarm($ALARM_INTERVAL);

    $hulk->{'dormant_mode'}->got_an_active_connection();
    my $selector = IO::Select->new( $self_pipe_read_handle, $socket, $httpsocket );

    while (1) {
        if ( my @ready_sockets = $selector->can_read( $hulk->{'dormant_mode'}->idle_timeout() ) ) {
            foreach my $ready_socket (@ready_sockets) {
                my $client_socket;
                if ( $ready_socket == $self_pipe_read_handle ) {
                    my $signal_type;
                    #
                    # The chld or alarm handler wrote to our self pipe so
                    # we know it's time to purge the old logins or wait
                    #
                    if ( sysread( $self_pipe_read_handle, $signal_type, 1 ) ) {
                        if ( $signal_type == $ALRM_SINGLE_DIGIT_NUMBER ) {

                            # check that the dbprocessor is still running every 5 minutes.
                            if ( !Cpanel::Hulkd::Daemon::get_db_proc_pid() ) {
                                $hulk->mainlog("dbprocessor is down, restarting it.");
                                $hulk->start_daemon( ['dbprocessor'] ) || return 0;
                            }

                            # check that the dbprocessor socket exists every 5 minutes.
                            # A restart is necessary to recover the socket
                            elsif ( !-S $Cpanel::Config::Hulk::dbsocket ) {
                                $hulk->mainlog("dbprocessor socket is missing, restarting cPHulk.");
                                $hulk->restart_daemon() || return 0;
                            }

                            # do old login purge every hour
                            if ( $alarm_count >= $ALARM_COUNT_THAT_ESTIMATES_ONE_HOUR ) {
                                $alarm_count = 0;
                                $hulk->_handle_periodic_purge($self_pipe_read_handle) || return 0;
                            }

                            $alarm_count++;
                            alarm($ALARM_INTERVAL);    # restart alarm
                        }
                        elsif ( $signal_type == $CHLD_SINGLE_DIGIT_NUMBER ) {
                            my $wait_result;
                            do {
                                $wait_result = waitpid( -1, $Cpanel::Wait::Constants::WNOHANG );
                                if ( $hulk->{'dormant_mode'} && $wait_result > 0 ) {
                                    my $exit_status = $? >> 8;
                                    if ( $exit_status != $SERVED_REQUEST_THAT_CAN_HANDLED_WITH_DORMANT_MODE ) {
                                        $hulk->{'dormant_mode'}->got_an_active_connection();
                                    }
                                }
                            } while $wait_result > 0;
                        }
                        elsif ( $signal_type == $HUP_SINGLE_DIGIT_NUMBER || $signal_type == $USR1_SINGLE_DIGIT_NUMBER ) {
                            _hot_restart_full( $hulk, $socket, $httpsocket );
                        }
                        elsif ( $signal_type == $TERM_SINGLE_DIGIT_NUMBER ) {
                            $hulk->sdnotify()->stopping();
                            Cpanel::Hulkd::Daemon::shutdown_db_proc();
                            $hulk->mainlog("processor shutdown via SIGTERM with pid $$");
                            return 1;    # Clean exit
                        }
                        else {
                            $hulk->errlog("Unexpected message from self pipe: $signal_type");
                            return 0;    # Unexpected signal
                        }
                    }
                }
                elsif ( $client_socket = $ready_socket->accept() ) {
                    $hulk->_handle_accepted_socket_and_reset_idleloops($client_socket) || return 0;    # Unexpected exit
                }
            }
        }

        # do not use else here as the query might comes from chckservd
        if ( $hulk->{'dormant_mode'}->should_go_dormant() ) {

            #go dormant
            #NOTE: We do *not* want to die() if exec() fails here because
            #all a failure here represents is a lack of optimization.
            #cphulkd needs to keep running if it can't go dormant.
            #
            $hulk->clear_expired_iptable_rules();
            _hot_restart_dormant( $hulk, $socket, $httpsocket );
        }
    }

    return 1;
}

sub _hot_restart_full {
    my ($self) = shift;

    return $self->_hot_restart( 'cphulkd', @_ );
}

sub _hot_restart_dormant {
    my ($self) = shift;

    return $self->_hot_restart( 'cphulkd-dormant', @_ );
}

#stubbed in tests
*_shutdown_db_proc = \*Cpanel::Hulkd::Daemon::shutdown_db_proc;

#stubbed in tests
sub _exec {
    my ( $progname, @args ) = @_;

    return exec {$progname} $progname, @args;
}

sub _hot_restart {
    my ( $self, $cmd, $socket, $httpsocket ) = @_;

    $self->sdnotify()->reloading();
    _shutdown_db_proc();

    # ensure the new process starts up ignoring USR1 and HUP so it does die if it gets another one before the
    # signal handler gets installed
    $SIG{'HUP'} = $SIG{'USR1'} = 'IGNORE';    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
    my @args = ( '--start', '0', '--httplisten=' . $httpsocket->fileno(), '--listen=' . $socket->fileno() );
    push( @args, '--systemd' ) if $self->sdnotify()->is_enabled();

    _exec( "/usr/local/cpanel/libexec/$cmd", @args ) or do {
        $self->warn("Failed to restart by exec cphulkd: $!");
    };

    return;
}

sub _start_db_loop {
    my ( $hulk, $dbsocket ) = @_;

    require Cpanel::Hulkd::Processor::DB;
    my $db_proc = Cpanel::Hulkd::Processor::DB->new($hulk);

    #restore default handlers for run_loop
    local @SIG{ 'CHLD', 'ALRM' } = ();

    return $db_proc->run_loop($dbsocket);
}

sub handle_one_connection {
    my ( $hulk, $socket, $from_dormant ) = @_;

    $socket or die "Missing socket parameter to handle_one_connection";

    local $SIG{'ALRM'} = sub {
        $hulk->die('Timeout while waiting for response');
    };

    my ( $serviced_non_dormant_request, $err );

    try {
        $serviced_non_dormant_request = Cpanel::Hulkd::Processor->new( $hulk, $socket )->run($from_dormant);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $hulk->errlog( 'The system encountered an error while processing a request: ' . Cpanel::Exception::get_string_no_id($err) );
    }

    exit($SERVED_REQUEST_THAT_CAN_HANDLED_WITH_DORMANT_MODE) if !$serviced_non_dormant_request;
    exit 0;
}

sub rebuild_caches {
    my ($self) = @_;

    {
        local $SIG{'__WARN__'} = sub {
            $self->warn(shift);
        };
        Cpanel::Hulkd::Processor::initialize();
    }

    return 1;
}

sub _report {
    return;    # not yet implemented at this time
}

# debug messages
sub debug {
    my $self = shift;
    return unless $self->{'debug'};

    return $self->{'mainlog'}->info(@_);
}

# general log messages
sub mainlog {
    my $self = shift;

    return $self->{'mainlog'}->info(@_);
}

# error conditions under normal operation
sub errlog {
    my $self = shift;

    return $self->{'errlog'}->info(@_);
}

# internal errors or debugging
sub warn {
    my $self = shift;

    return $self->{'errlog'}->warn(@_);
}

# fatal errors
sub die {
    my $self = shift;

    return $self->{'errlog'}->die(@_);
}

sub purge_old_logins {

    return Cpanel::ForkAsync::do_in_child(
        sub {
            Cpanel::Hulk::Cache::IpLists->new->expire_all();
            Cpanel::Hulkd::Processor::purge_old_logins();
        }
    );
}

sub _parse_argv {
    my ( $self, $argv_ref ) = @_;

    my ( $listenfd, $httplistenfd, $acceptedfd );

    foreach my $arg ( @{$argv_ref} ) {
        if ( $arg =~ /-listen=(\d+)/ ) {
            $listenfd = $1;
        }
        elsif ( $arg =~ /-httplisten=(\d+)/ ) {
            $httplistenfd = $1;
        }
        elsif ( $arg =~ /-accepted=(\d+)/ ) {
            $acceptedfd = $1;
        }
    }

    return ( $listenfd, $acceptedfd, $httplistenfd );
}

sub _init_db_socket {
    my $hulk = shift;

    local $^F = $MAX_FILEFHANDLES_EXPECTED_TO_BE_OPEN;    #prevent cloexec

    unlink($Cpanel::Config::Hulk::dbsocket);
    my $dbsocket = Cpanel::Socket::UNIX->new(
        Type   => $Cpanel::Hulk::Constants::SOCK_STREAM,
        Local  => $Cpanel::Config::Hulk::dbsocket,
        Listen => $LISTEN_BACKLOG,
    );

    return $dbsocket;
}

sub _init_sockets {
    my ($hulk) = @_;

    unlink($Cpanel::Config::Hulk::socket);
    my ( $socket, $unix_err );
    try {
        $socket = Cpanel::Socket::UNIX->new(
            Type   => $Cpanel::Hulk::Constants::SOCK_STREAM,
            Local  => $Cpanel::Config::Hulk::socket,
            Listen => $LISTEN_BACKLOG
        );
    }
    catch {
        $unix_err = $_;
        $hulk->die("Could not create unix domain socket at '$Cpanel::Config::Hulk::socket': $_");
    };
    Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($socket);

    my $mail_gid = ( getpwnam('mail') )[3];
    chown 0, $mail_gid, $Cpanel::Config::Hulk::socket;
    chmod 0660, $Cpanel::Config::Hulk::socket;

    my $httpsocket;
    my $attempts = 0;
    my $http_err;
    while ( ++$attempts < 100 ) {
        try {
            $httpsocket = Cpanel::Socket::INET->new(
                Type      => $Cpanel::Hulk::Constants::SOCK_STREAM,
                Proto     => $Cpanel::Hulk::Constants::PROTO_TCP,
                LocalAddr => '127.0.0.1',
                LocalPort => $Cpanel::Config::Hulk::HTTP_PORT,
                Listen    => $LISTEN_BACKLOG,
                ReuseAddr => 1,
            );
        }
        catch {
            $http_err = $_;
        };

        last if $httpsocket;

        system '/usr/local/cpanel/etc/init/kill_apps_on_ports', $Cpanel::Config::Hulk::HTTP_PORT;
    }
    Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($httpsocket);

    CORE::die "Could not bind to $Cpanel::Config::Hulk::HTTP_PORT: $http_err" if !$httpsocket;
    CORE::die "Could not bind to $Cpanel::Config::Hulk::socket: $unix_err"    if !$socket;
    return ( $socket, $httpsocket );
}

sub _handle_accepted_socket_and_reset_idleloops {
    my ( $hulk, $client_socket, $from_dormant ) = @_;

    if ( my $pid = fork() ) {
        $client_socket->close();
    }
    elsif ( defined $pid ) {
        $hulk->sdnotify()->safe_disable();
        $client_socket->autoflush(1);
        $hulk->handle_one_connection( $client_socket, $from_dormant );
    }
    else {
        $hulk->warn("Failed to fork(): $!\n");
        return 0;
    }

    return 1;
}

# For more info on self-pipes
# http://cr.yp.to/docs/selfpipe.html
# http://www.sitepoint.com/the-self-pipe-trick-explained/
sub _generate_selfpipe {

    my ( $self_pipe_read_handle, $self_pipe_write_handle );
    pipe( $self_pipe_read_handle, $self_pipe_write_handle ) || CORE::die("Could not generate self-pipe: $!");

    Cpanel::FHUtils::Blocking::set_non_blocking($self_pipe_read_handle);
    Cpanel::FHUtils::Blocking::set_non_blocking($self_pipe_write_handle);

    return ( $self_pipe_read_handle, $self_pipe_write_handle );
}

sub _handle_periodic_purge {
    my ($hulk) = @_;

    # Purge the whitelist/blacklist caches and expire old logins
    $hulk->purge_old_logins();

    #Build a cache between hits
    $hulk->rebuild_caches();

    $hulk->clear_expired_iptable_rules();

    return 1;
}

sub clear_expired_iptable_rules {
    my $hulk = shift;

    if (

        $Cpanel::Hulkd::Processor::conf_ref->{'block_brute_force_with_firewall'}
        || $Cpanel::Hulkd::Processor::conf_ref->{'block_excessive_brute_force_with_firewall'}

    ) {
        require Cpanel::XTables::TempBan;
        my $banner     = Cpanel::XTables::TempBan->new( 'chain' => 'cphulk' );
        my @ipversions = $banner->supported_ip_versions();
        foreach my $ipversion (@ipversions) {
            try {
                $banner->ipversion($ipversion);
                $banner->expire_time_based_rules();
            }
            catch {
                my $err = $_;

                # IPv6 is likely to fail on many systems so we do not log errors
                # at this time.
                if ( $ipversion == 4 ) {
                    my $error_as_string = Cpanel::Exception::get_string($err);
                    $hulk->errlog("Cpanel::XTables::TempBan could not expire time based rules due to an error: $error_as_string.");
                }
            }
        }
    }

    return 1;
}

sub sdnotify ($self) {
    return Cpanel::Systemd::Notify->get_instance( 'service' => 'cphulkd' );
}

1;
