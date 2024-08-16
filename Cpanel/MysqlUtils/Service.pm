package Cpanel::MysqlUtils::Service;

# cpanel - Cpanel/MysqlUtils/Service.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::CachedCommand            ();
use Cpanel::Database                 ();
use Cpanel::DbUtils                  ();
use Cpanel::LoadFile                 ();
use Cpanel::Chkservd::Tiny           ();
use Cpanel::Exception                ();
use Cpanel::TimeHiRes                ();
use Cpanel::Kill                     ();
use Cpanel::Locale                   ();
use Cpanel::Logger                   ();
use Cpanel::MariaDB                  ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::MysqlUtils::MyCnf::Full  ();
use Cpanel::MysqlUtils::Dir          ();
use Cpanel::PwCache                  ();
use Cpanel::LoadModule               ();
use Cpanel::Version::Compare         ();
use Cpanel::Sys::Hostname            ();
use Cpanel::OS                       ();

our $MAX_SHUTDOWN_WAIT_TIME = ( 15 * 60 );    # 15 minutes
our $MAX_SOCKET_WAIT_TIME   = 75;
our $MAX_PIDFILE_WAIT_TIME  = 15;

my $logger;
my $locale;
our $mysql_sock;

# This is actually a farily complicated process to determine what PID file MySQL is using without
# querying it. This is additionally complicated by the fact that it can be in a config file, in
# an init file, or even passed on command line.
#
# The current strategy is as follows:
# 1. Check mysql.cnf for a mention of mysql-pid and if an active pid and process exist, use that.
# 2. See if there's an active $hostname.pid file in mysql's data dir use it if there's an active pid in it.
# 3. See if there's an active $shorthostname.pid file that's active (MariaDB)
# 4. walk pid table looking for /usr/sbin/mysqld see if the pid file is mentioned in the command line.
# 5. Look for an 'active' PID file
# 6. Ask mysqld directly what the PID file is via parsing the output of --print-defaults
# 7. Assume it's hostname pid file (see #2) but down at the moment.
#
# CPANEL-3750: The pid file must not be cached
# because it can change locations between
# shutdown and startup
#
sub get_mysql_pid_file {

    # 1. Use the pid file listed in my.cnf if it's active
    my $my_cnf_pid_file = get_pid_file_from_cnf();
    if ($my_cnf_pid_file) {
        return $my_cnf_pid_file if ( is_pid_file_active($my_cnf_pid_file) );
    }

    # 2. See if there's an active $hostname.pid file that's active
    my $hostname_pid_file = get_mysql_hostname_pid_file();
    return $hostname_pid_file if ( is_pid_file_active($hostname_pid_file) );

    # 3. See if there's an active $shorthostname.pid file that's active (MariaDB)
    my $shorthostname_pid_file = get_mysql_shorthostname_pid_file();
    return $shorthostname_pid_file if ( is_pid_file_active($shorthostname_pid_file) );

    # 4. Walk pid table looking for /usr/sbin/mysqld and read it's pid file from cmdline options.
    my $proc_pid_files = search_mysqld_procs_for_pid_files();
    return $proc_pid_files if ($proc_pid_files);

    # 5. Look for an active pid file
    for my $path ( _get_all_pid_files_in_datadir() ) {

        # The contents of this file is not worth worrying about if
        # we cannot load it.
        my $pid = Cpanel::LoadFile::loadfile($path);
        if ( $pid && _pid_is_alive($pid) ) {
            return $path;
        }
    }

    # 6. Ask mysqld directly what the PID file is via parsing the output of --print-defaults
    my $defaults_pid_file = get_pid_file_from_mysqld_defaults();
    return $defaults_pid_file if ($defaults_pid_file);

    # 7. Assume it's mysql.cnf or hostname pid file (see #1 or #2) but down at the moment.
    return $my_cnf_pid_file || $hostname_pid_file;
}

#
# Walk /proc looking for a binary being run and then determine it's pid-file arguement
#
sub search_mysqld_procs_for_pid_files {
    my ($bin) = @_;
    my $pidfile_path = _get_mysqld_pidfile_path_via_systemd();
    return $pidfile_path if $pidfile_path;
    $pidfile_path = _get_mysqld_pidfile_path_via_proc_search($bin);
    return $pidfile_path if $pidfile_path;
    return undef;
}

sub get_pid_file_from_mysqld_defaults {
    require Cpanel::CachedCommand;
    my @cmd      = qw{/usr/sbin/mysqld --print-defaults};
    my $out      = Cpanel::CachedCommand::cachedcommand(@cmd);
    my @exploded = split( "\n", $out );
    my $pid;
    foreach my $line (@exploded) {
        next if index( $line, '--' ) != 0;
        my @opts        = split( / /, $line );
        my %opts_mapped = map { my $thing = $_; my @opt = split( /=/, $thing ); ( $opt[0], $opt[1] || '' ) } @opts;
        $pid = $opts_mapped{'--pid-file'};
        last if $pid;
    }
    return $pid;
}

sub _get_mysqld_pidfile_path_via_systemd {
    require Cpanel::MysqlUtils::ServiceName;
    require Cpanel::RestartSrv::Systemd;
    my $service_name = Cpanel::MysqlUtils::ServiceName::get_installed_version_service_name();
    if ( Cpanel::RestartSrv::Systemd::has_service_via_systemd($service_name) ) {
        require Cpanel::Proc::PID;
        my $pid = Cpanel::RestartSrv::Systemd::get_pid_via_systemd($service_name);
        local $@;
        my $cmdline = eval { Cpanel::Proc::PID->new($pid)->cmdline() };
        if ($cmdline) {
            my $pidfile_path = _get_mysqld_pidfile_path_from_commandline( join( " ", @$cmdline ) );
            return $pidfile_path if $pidfile_path;
        }
    }
    return undef;
}

sub _get_mysqld_pidfile_path_via_proc_search {

    # no systemd
    require Cpanel::PsParser;
    my $bin           = shift || '/usr/sbin/mysqld';
    my $mysql_uid     = ( Cpanel::PwCache::getpwnam('mysql') )[2];
    my $processes_arr = Cpanel::PsParser::fast_parse_ps( 'resolve_uids' => 0, 'want_uid' => $mysql_uid, 'exclude_self' => 1, 'exclude_kernel' => 1 );
    foreach my $proc (@$processes_arr) {
        next if $proc->{'command'} !~ m{^\Q$bin\E};
        my $pidfile_path = _get_mysqld_pidfile_path_from_commandline( $proc->{'command'} );
        return $pidfile_path if $pidfile_path;
    }
    return undef;
}

sub _get_mysqld_pidfile_path_from_commandline {
    my ($command_line) = @_;
    my ($pid_file)     = $command_line =~ m{ --pid-file=(\S+)};
    return undef     if !$pid_file;
    return $pid_file if ( $pid_file && -e $pid_file && !-z _ );
    my $datadir = Cpanel::MysqlUtils::Dir::getmysqldir() || '/var/lib/mysql';
    $datadir =~ s{/+$}{};
    return "$datadir/$pid_file" if -e "$datadir/$pid_file" && !-z _;
    return undef;
}

#
# Determine if there's a running process associated with
# the pid file mentioned in the passed file.
#
sub is_pid_file_active {
    my ($pid_file) = @_;
    return 0 if ( !$pid_file );

    return 0 if ( !-e $pid_file or -d _ or -z _ );
    my $pid = Cpanel::LoadFile::loadfile($pid_file);
    return _pid_is_alive($pid);
}

#
# Return the default mysql pid file name.
#
sub get_mysql_hostname_pid_file {

    # A Previous version of this code used to return undef if the system was in remote mysql mode.
    # This makes no sense. Especially since none of the code this sub returned to appeared to be
    # able to handle this correctly.
    my $datadir = Cpanel::MysqlUtils::Dir::getmysqldir() || '/var/lib/mysql';
    $datadir =~ s{/+$}{};    # Strip of trailing slashes so we can put only one back on.

    return $datadir . '/' . Cpanel::Sys::Hostname::gethostname() . '.pid';
}
#
# Return the default mysql pid file name.
#
sub get_mysql_shorthostname_pid_file {

    # A Previous version of this code used to return undef if the system was in remote mysql mode.
    # This makes no sense. Especially since none of the code this sub returned to appeared to be
    # able to handle this correctly.
    my $datadir = Cpanel::MysqlUtils::Dir::getmysqldir() || '/var/lib/mysql';
    $datadir =~ s{/+$}{};    # Strip of trailing slashes so we can put only one back on.

    return $datadir . '/' . Cpanel::Sys::Hostname::shorthostname() . '.pid';
}

#
# Look for a value for pid-file in section [mysqld] inside /etc/my.cnf
#
my $_my_cnf;

sub clear_cache {
    return undef $_my_cnf;
}

sub get_pid_file_from_cnf {
    my $array_ref = ( $_my_cnf ||= Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf_preserve_lines() );

    foreach my $hash_ref (@$array_ref) {
        if (   $hash_ref->{'section'}
            && $hash_ref->{'section'} eq "mysqld"
            && $hash_ref->{'key'}
            && $hash_ref->{'key'} eq "pid-file"
            && $hash_ref->{'value'} ) {
            return $hash_ref->{'value'};
        }
    }

    return undef;
}

#
# Based on detected pid file, determine if MySQL is running.
#
sub is_mysql_active {

    # Purge any dead pid files. We don't care if there's an error.
    eval { remove_all_dead_pid_files_in_datadir() };

    # Now read the remaining guessed pid file to see if it's there.
    my ( $pid, $pidfile ) = get_mysql_pid_info();

    if ( !$pid && Cpanel::OS::is_systemd() ) {
        require Cpanel::RestartSrv::Systemd;

        my $service = Cpanel::Database->new()->service_name;
        $pid = Cpanel::RestartSrv::Systemd::get_pid_via_systemd($service);
    }

    #return if it's up.
    return _pid_is_alive($pid);
}

sub _get_all_pid_files_in_datadir {
    my $datadir = Cpanel::MysqlUtils::Dir::getmysqldir() || return;

    return if !-d $datadir;

    local $!;
    opendir( my $datadir_fh, $datadir ) or do {
        die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $datadir, error => $! ] );
    };

    my @pid_files = map { "$datadir/$_" } grep ( m{\.pid\z}, readdir($datadir_fh) );

    if ($!) {
        die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $datadir, error => $! ] );
    }

    return @pid_files;
}

sub remove_all_dead_pid_files_in_datadir {
    local $!;

    for my $path ( _get_all_pid_files_in_datadir() ) {

        # If we cannot read the file we assume we want it to go away.
        # The contents of this file is not worth worrying about if
        # we cannot load it.
        my $pid = Cpanel::LoadFile::loadfile($path);
        if ( !$pid || ( $pid && !_pid_is_alive($pid) ) ) {
            unlink $path or warn Cpanel::Exception::create( 'IO::UnlinkError', [ path => $path, error => $! ] )->to_string();
        }
    }

    return 1;
}

sub safe_shutdown_local_mysql {

    my $shutdown_mysql = 0;

    my $max_time_needed_to_try_all_shutdown_methods = ( 60 + ( $MAX_SHUTDOWN_WAIT_TIME * 2 ) );

    Cpanel::Chkservd::Tiny::suspend_service( 'mysql', $max_time_needed_to_try_all_shutdown_methods );

    my $err;

    try {
        my ( $pid, $pidfile ) = get_mysql_pid_info();

        # Prevent chkservd from checking the service
        $shutdown_mysql++ if _shutdown_mysql_using_local_dbconnection();
        $shutdown_mysql++ if _shutdown_mysql_using_sigterm( $pid, $pidfile );
        $shutdown_mysql++ if _shutdown_mysql_using_init_script();
        $shutdown_mysql++ if _shutdown_mysql_using_safekill();
        $shutdown_mysql++ if $pidfile && $pid && !_pid_is_alive($pid);

        remove_all_dead_pid_files_in_datadir() if $shutdown_mysql;

        # If safe_mysqld gets stuck we need to terminate it so
        # mysql can start up next time
        my $mysql_uid = ( Cpanel::PwCache::getpwnam('mysql') )[2];
        Cpanel::Kill::safekill( [ 'safe_mysqld', 'mysqld_safe' ], undef, 15, undef, { $mysql_uid => 1 } );
    }
    catch {
        $err = $_;
    }
    finally {

        # Ok to resume checking in 60 seconds
        Cpanel::Chkservd::Tiny::suspend_service( 'mysql', 60 );
    };

    if ($err) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn( "Error while during MySQL shutdown: " . Cpanel::Exception::get_string($err) );
    }

    return $shutdown_mysql ? 1 : 0;
}

# start_time is the system time
# right before the mysql startup call
# was made.  We use this to make sure the pidfile
# has aged.
sub wait_for_mysql_to_startup {
    my ($start_time) = @_;

    # Not localized since this is only intended to help the implementer.
    return ( 0, 'Implementer error: The “start_time” argument is required.' ) if !$start_time;

    $locale ||= Cpanel::Locale->get_handle();

    # TODO: make this throw an exception on 11.46+
    if ( _wait_for_pid_file_to_exist($start_time) ) {
        return ( 1, 'ok' ) if _wait_for_socket_creation($start_time);

        return ( 0, $locale->maketext('[asis,MySQL] created a [asis,pid] file but failed to start.') );
    }
    else {
        return ( 0, $locale->maketext('[asis,MySQL] failed to start.') );
    }
}

sub possible_mysql_socket_paths {
    my $mysql_config_bin = Cpanel::DbUtils::find_mysql_config();
    $mysql_sock ||= Cpanel::CachedCommand::cachedcommand( $mysql_config_bin, '--socket' );
    chomp($mysql_sock) if defined $mysql_sock;

    my $root_sock = Cpanel::MysqlUtils::MyCnf::Basic::getmydbsocket('root');

    return (
        $mysql_sock || (),
        $root_sock  || (),
        qw(
          /var/run/mysqld/mysqld.sock
          /var/db/mysql/mysql.sock
          /var/lib/mysql/mysql.sock
          /usr/local/lib/mysql.sock
        ),
    );
}

sub deprecated_possible_mysql_socket_paths {
    return (
        qw(/tmp/mysql.sock
          /var/tmp/mysql.sock
          /usr/local/tmp/mysql.sock)
    );
}

# Waits for a mysql pid file that is
# at least as new as $start_time
#
# In theory the pid file should already exist
# when this function is called because we do so
# after the init script is finished.  It should
# only not exist if mysql startup has failed.
# We give mysql MAX_PIDFILE_WAIT_TIME seconds
# just in case the pid file isn't created
# before the init script finishes because
# the behavior changes in the future.
sub _wait_for_pid_file_to_exist {
    my ($start_time) = @_;

    my $pid_file_updated = 0;
    for ( 1 .. ( $MAX_PIDFILE_WAIT_TIME * 10 ) ) {
        my $pidfile = get_mysql_pid_file();
        my $mtime   = ( stat($pidfile) )[9];

        if ( $mtime && $mtime >= $start_time ) {
            $pid_file_updated = 1;
            last;
        }

        Cpanel::TimeHiRes::sleep(0.05);
    }

    return $pid_file_updated;
}

sub get_mysql_pid_info {
    my ( $pid, $pidfile );

    if ( $pidfile = get_mysql_pid_file() ) {

        # TODO: replace with Cpanel::LoadFile::load in 11.46 or later
        $pid = Cpanel::LoadFile::loadfile($pidfile);
    }

    return ( $pid, $pidfile );
}

sub _get_local_dbh {
    my $dbpassword = Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass();
    my $dbh;

    require Cpanel::MysqlUtils;
    local $@;    # TODO: will replace with Try::Tiny later
    eval {       # not using try as we want to backport
        local $SIG{'__DIE__'};
        $dbh = Cpanel::MysqlUtils->new(
            'dbuser'   => 'root',
            'database' => 'mysql',
            'dbpass'   => $dbpassword,
            'dbserver' => 'localhost'
        );
    };

    return $dbh;
}

sub _shutdown_mysql_using_local_dbconnection {
    my $dbh = _get_local_dbh();

    return 0 if !$dbh;

    local $@;              # TODO: will replace with Try::Tiny later
    my $retval = eval {    # not using try as we want to backport
        my $version = $dbh->selectrow_array('SELECT VERSION()');
        return 0 unless $version;

        # MariaDB now requires a minimum value of 10 for max_connections.
        return 0 if Cpanel::MariaDB::version_is_mariadb($version);

        return 0 if Cpanel::Version::Compare::compare( $version, '<', '5.7.9' );
        $dbh->do("SET GLOBAL max_connections = 1;");
        $dbh->do('SHUTDOWN');    # only supported since 5.7.9
        $dbh->disconnect();
    };
    if ($@) {
        warn $@;
        return 0;
    }
    return defined $retval ? $retval : 1;
}

sub _shutdown_mysql_using_sigterm {
    my ( $pid, $pidfile ) = @_;

    return 0 if !_pid_is_alive($pid);

    kill 'TERM', $pid;

    #
    # Wait for pidfile to disappear
    #
    for ( 0 .. ( $MAX_SHUTDOWN_WAIT_TIME * 10 ) ) {
        if ( !-e $pidfile ) {
            return 1;
        }
        Cpanel::TimeHiRes::sleep(0.1);
    }

    return 0;
}

sub _shutdown_mysql_using_init_script {

    Cpanel::LoadModule::load_perl_module('Cpanel::RestartSrv');
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Timed');

    # Call the init script to stop just in case to ensure
    # everything gets cleaned up
    if ( my $init_script = Cpanel::RestartSrv::getinitfile('mysql') ) {
        Cpanel::SafeRun::Timed::timedsaferun( $MAX_SHUTDOWN_WAIT_TIME, $init_script, 'stop' );
        return $? ? 0 : 1;
    }

    return 0;
}

sub _shutdown_mysql_using_safekill {
    my $mysql_uid = ( Cpanel::PwCache::getpwnam('mysql') )[2];
    my $db_obj    = Cpanel::Database->new();
    return Cpanel::Kill::safekill( [ $db_obj->daemon_name() ], undef, $MAX_SHUTDOWN_WAIT_TIME, undef, { $mysql_uid => 1 } );
}

sub _pid_is_alive {
    my ($pid) = @_;

    return 0    if !$pid;
    chomp($pid) if defined $pid;
    return kill( 0, $pid ) ? 1 : 0;
}

# Waits for a mysql socket that is not a symlink
# and is at least a new as $start_time
#
# We are expecting mysql to create a new .sock
# file with an updated mtime. Once that exists,
# we can assume that mysql is online.
#
sub _wait_for_socket_creation {
    my ($start_time) = @_;

    for ( 1 .. $MAX_SOCKET_WAIT_TIME ) {
        return 1 if get_socket($start_time);
        sleep 1;
    }

    return;
}

# Returns sockets that are not symlinks
# and are at least a new as $start_time
#
sub get_socket {
    my ($start_time) = @_;

    my @sockets;
    foreach my $socket ( possible_mysql_socket_paths() ) {
        if ( !-l $socket && -e _ && -S _ && ( stat(_) )[9] >= $start_time ) {
            push @sockets, { 'socket' => $socket, 'mtime' => ( stat(_) )[9] };
        }
    }

    return if !@sockets;
    return ( sort { $b->{'mtime'} <=> $a->{'mtime'} } @sockets )[0]->{'socket'};
}

sub fixup_start_file {

    if ( my $start_file = Cpanel::OS::db_mariadb_start_file() ) {
        require Cpanel::FileUtils::Modify;

        # This is needed because when this script is run by systemd '~/.my.cnf' is translated to '/nonexistent/.my.cnf'.
        # We need to tell this script the exact path to /root/.my.cnf so it can pull in root's password and log into the database successfully.
        Cpanel::FileUtils::Modify::match_replace(
            $start_file,
            [
                { match => qr/--defaults-(extra-)?file=\/etc\/mysql\/debian\.cnf/m, replace => '--defaults-extra-file=/root/.my.cnf' },
            ]
        );
    }

    return 1;
}

1;
