package Cpanel::ServiceManager::Services::Mysql;

# cpanel - Cpanel/ServiceManager/Services/Mysql.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Moo;
use Cpanel::ConfigFiles              ();
use Cpanel::Exception                ();
use Cpanel::RestartSrv               ();
use Cpanel::LoadFile                 ();
use Cpanel::LoadModule               ();
use Cpanel::Binaries                 ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::Service      ();
use Cpanel::MysqlUtils::ServiceName  ();
use Cpanel::MysqlUtils::Running      ();
use Cpanel::SafeRun::Errors          ();
use Cpanel::Services::Log            ();
use Cpanel::ServiceManager::Base     ();
use Cpanel::FileUtils::Lines         ();

extends 'Cpanel::ServiceManager::Base';

has '+suspend_time'     => ( is => 'ro', default => 60 );
has '+restart_attempts' => ( is => 'rw', default => 3 );
has '+processowner'     => ( is => 'ro', default => 'mysql' );

# If service_binary isn't defined the system will assume
# its 'mysql' which will make mysql startup fail when
# /usr/bin/mysql is not yet installed
has '+service_binary'   => ( is => 'ro', lazy => 1, default => sub { Cpanel::Binaries::path('mysqld') } );
has '+service_override' => ( is => 'ro', lazy => 1, default => sub { Cpanel::MysqlUtils::ServiceName::get_installed_version_service_name() } );

#
# CPANEL-3750: The pid file must not be cached
# because it can change locations between
# shutdown and startup
#
sub pidfile {
    return Cpanel::MysqlUtils::Service::get_mysql_pid_file();
}

sub stop {
    my $self = shift;

    my $shutdown_ok = Cpanel::MysqlUtils::Service::safe_shutdown_local_mysql();
    return 1 if $shutdown_ok;

    return $self->SUPER::stop(@_);
}

sub start {
    my $self = shift;

    Cpanel::MysqlUtils::Service::fixup_start_file();

    my $start_time = time();
    return $self->_mysql_error() unless $self->SUPER::start(@_);

    my $socket_ok = Cpanel::MysqlUtils::Service::wait_for_mysql_to_startup($start_time);
    if ($socket_ok) {    # Successfully located socket
        symlink_mysql_socket($start_time);
        Cpanel::MysqlUtils::Running::wait_for_mysql_to_come_online();
    }
    else {
        $self->_mysql_error();
    }

    return 1;
}

sub _mysql_error {
    print "The system failed to locate the MySQL® socket. Check the MySQL configuration.\n\n";
    print "-- Startup Output --\n";
    my ( $log_exists, $log ) = Cpanel::Services::Log::fetch_service_startup_log('mysql');
    print $log;
    print "-- End Startup Output --\n";

    return;
}

sub restart_attempt {
    my ($self) = @_;

    my ( $log_exists, $log ) = Cpanel::Services::Log::fetch_service_startup_log('mysql');
    return 0 if ( $log_exists && !_startup_log_looks_like_my_cnf_update_is_needed($log) ) && !_error_log_looks_like_my_cnf_update_is_needed();
    return 0 unless _attempt_to_repair_mysql_configuration();
    return 1;
}

sub check {
    my ($self) = shift;

    return 0 if !$self->SUPER::check(@_);
    local $ENV{'HOME'} = ( getpwnam('root') )[7];

    #
    # We used to make sure the mysql password was correct here
    # however this could cause mysql to restart in the middle
    # and cause other problems.
    #
    # We now rely on the peroidic checks of mysqluserstore
    # to reset the password if it cannot store mysql users
    # because the password is wrong
    #
    symlink_mysql_socket(0);

    my $hasmysql = 0;
    my $mysqlok  = 0;

    # We need this because during initial installation, DBI might not be
    # installed and we don't want to fail.
    eval {
        require Cpanel::MysqlUtils::Connect;
        $hasmysql = 1;
    };

    require Cpanel::MysqlUtils::MyCnf::Basic;
    my $dbpassword = Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass('root');    #read from /root/.my.cnf

    my %exception_parameters = ( 'service' => $self->service(), 'longmess' => undef );

    if ( $hasmysql && $dbpassword ) {
        no warnings 'once';
        local $SIG{"ALRM"} = sub {
            die Cpanel::Exception::create( 'ConnectionFailed', \%exception_parameters )->to_string();    ## no extract maketext (variable is metadata; the default message will be used)
        };
        alarm(30);
        my $dbh = eval { Cpanel::MysqlUtils::Connect::get_dbi_handle( 'extra_args' => { 'PrintError' => 0, 'RaiseError' => 0 } ) };
        if ( !$dbh ) {
            die Cpanel::Exception::create( 'Services::CheckFailed', [ service => $self->{'service'}, message => $DBI::errstr ] );
        }
        alarm(0);
        die Cpanel::Exception::create( 'ConnectionFailed', \%exception_parameters )->to_string() unless $dbh;    ## no extract maketext (variable is metadata; the default message will be used)
        $mysqlok = 1;

    }

    my $mysql_error_message;

    if ( !$mysqlok ) {
        require Cpanel::MysqlUtils::Running;

        my @reason;

        $mysqlok = do {
            local $SIG{'__WARN__'} = sub { push @reason, @_ };
            Cpanel::MysqlUtils::Running::is_mysql_running();
        };

        if ( !$mysqlok ) {
            if ( !@reason ) {
                push @reason, 'The service is down.';
            }

            $mysql_error_message = "@reason";
        }
    }

    if ( !$mysqlok ) {
        die Cpanel::Exception::create( 'Service::IsDown', [ 'service' => 'mysql', $mysql_error_message ? ( 'message' => $mysql_error_message ) : () ] );
    }

    return $mysqlok;
}

sub _error_log_looks_like_my_cnf_update_is_needed {

    my $mysql_dir = q{/var/lib/mysql};
    return unless -d $mysql_dir;

    # get last active error log
    my @error_files;
    if ( opendir my $mysql_dh, $mysql_dir ) {
        @error_files = map { $mysql_dir . '/' . $_ } grep { m{\.err$} } readdir $mysql_dh;
    }
    return unless @error_files;
    my %mtimes = map  { $_, ( stat($_) )[9] || 0 } @error_files;
    my @sorted = sort { $mtimes{$b} <=> $mtimes{$a} } keys %mtimes;

    # get most active error log
    my $last = shift @sorted;

    # read last lines
    my @lines = Cpanel::FileUtils::Lines::get_last_lines( $last, 100 );

    # check if there is an unknown variable
    foreach my $line (@lines) {
        return 1 if $line =~ m<\bunknown\s+(?:variable|option)\b>;
    }

    return;
}

sub _startup_log_looks_like_my_cnf_update_is_needed {
    my ($startup_log) = @_;

    return unless defined $startup_log;
    return $startup_log =~ m<\bunknown\s+(?:variable|option)\b>;
}

# We used to auto adjust mysql configuration to accomodate changes on the system
# at restart, however this sometimes resulted in a race condition where
# restartsrv would hang while reading from the mysql socket.  We now do the
# adjustment every 2 hours via bin/mysqluserstore which is where the mysql
# connection check was moved to previously.

sub symlink_mysql_socket {
    my ($start_time) = @_;

    my $realsocket = Cpanel::MysqlUtils::Service::get_socket($start_time);

    my @possible_socket_paths = ( Cpanel::MysqlUtils::Service::possible_mysql_socket_paths(), Cpanel::MysqlUtils::Service::deprecated_possible_mysql_socket_paths() );

    if ( !$realsocket ) {
        foreach my $socket (@possible_socket_paths) {
            unlink $socket;
        }
    }
    else {
        foreach my $socket (@possible_socket_paths) {
            next if $socket eq $realsocket;
            my @DIR = split /\//, $socket;
            pop @DIR;
            my $dir = join '/', @DIR;
            next if !-d $dir;
            my $link = calclink( $realsocket, $socket );
            if ( !-e $socket ) {
                unlink $socket;
                symlink $link, $socket;
            }
            elsif ( -l $socket ) {
                my $link_target = readlink($socket);
                if ( $link_target ne $link ) {
                    unlink $socket;
                    symlink $link, $socket;
                }
            }
        }
    }
    return $realsocket;
}

sub syntax_check_mycnf {
    require Cpanel::SafeRun::Errors;
    require Cpanel::DbUtils;
    my $binary = Cpanel::DbUtils::find_mysqld();
    local $ENV{'LANG'} = 'C';
    my $syntax_check_output = Cpanel::SafeRun::Errors::saferunallerrors( $binary, '--help', '--verbose', '-u', 'mysql' );
    return ( $syntax_check_output =~ /\[ERROR\]/ ? 0 : 1, $syntax_check_output );
}

sub _append_startup_errors_to_log {
    my ( $err_log_path, $err_log_position ) = @_;

    my $startup_errors;
    if ( -s $err_log_path ) {
        try {
            $startup_errors = Cpanel::LoadFile::load(
                $err_log_path,
                $err_log_position,
            );
        }
        catch { warn $_ };
    }

    Cpanel::RestartSrv::append_to_startup_log( 'mysql', $startup_errors ) if $startup_errors;
    return 1;

}

sub calclink {
    my ( $src, $dest ) = @_;
    my @DDEST = split( /\//, $dest );
    my @DD;
    for ( my $i = 1; $i < $#DDEST; $i++ ) {
        push( @DD, '..' );
    }
    return ( join( '/', @DD ) . $src );
}

sub _attempt_to_repair_mysql_configuration {
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Version');
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::MyCnf::Migrate');
    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Restart');

    no warnings qw/redefine once/;

    # disable recursive call, as we are going to restart
    local *Cpanel::MysqlUtils::Restart::restart = sub { };

    # Local mysql version
    my $version = Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default();

    Cpanel::MysqlUtils::MyCnf::Migrate::migrate_my_cnf_file( $Cpanel::ConfigFiles::MYSQL_CNF, $version );

    print "Unrecognized configuration options may have caused the MySQL startup errors.\n";
    print "The system has attempted to auto-update your MySQL configuration file for your MySQL version.\n";
    print "This should resolve any errors that stem from an outdated MySQL configuration file.\n";

    return 1;
}

1;
