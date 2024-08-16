package Cpanel::MysqlUtils::MyCnf::Basic;

# cpanel - Cpanel/MysqlUtils/MyCnf/Basic.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings) - This has not been audited to see if warnings are safe.

use Cpanel::LoadFile                                ();
use Cpanel::LoadModule                              ();
use Cpanel::IP::Loopback                            ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();

our $VERSION = '1.3';

our %MYDBCACHE;
our %HOMECACHE;
our $VAR_MYSQL = '/var/lib/mysql/mysql.sock';

#for testing
our $_SYSTEM_MY_CNF = '/etc/my.cnf';

sub get_mycnf {
    my $loadConfig = _getloadConfig_coderef();
    return $loadConfig->( $_SYSTEM_MY_CNF, undef, '\s*=\s*', '^\s*[#;]', 0, 1 );
}

#
#  We don't return a coderef here in order to keep perlcc from walking that
#  module
#
*getloadConfig_coderef = \&_getloadConfig_coderef;

sub _getloadConfig_coderef {
    my $module;
    if ( exists $INC{'Cpanel/Config/LoadConfig.pm'} ) {
        $module = 'Cpanel::Config::LoadConfig';
    }
    else {
        Cpanel::LoadModule::lazy_load_module('Cpanel::Config::LoadConfig::Tiny');
        $module = 'Cpanel::Config::LoadConfig::Tiny';
    }

    return $module->can('loadConfig');
}

sub _getmydb_param {
    my ( $param, $file ) = @_;

    if ( !$param || !$file ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
        my $logger = 'Cpanel::Logger'->new();
        $logger->warn('Missing arguments');
        return;
    }

    my $value;
    my ( $file_size, $file_mtime ) = ( stat($file) )[ 7, 9 ];

    if ($file_mtime) {
        if ( !exists $MYDBCACHE{$file} || $MYDBCACHE{$file}->{'mtime'} != $file_mtime || $MYDBCACHE{$file}->{'size'} != $file_size ) {
            my $loadConfig_module = _getloadConfig_coderef();
            my $data              = $loadConfig_module->( $file, undef, '\s*=\s*', '^\s*[#;]', 0, 1 );
            if ($data) {
                $MYDBCACHE{$file} = {
                    'data'  => $data,
                    'mtime' => $file_mtime,
                    'size'  => $file_size,
                };
            }
        }

        if ( exists $MYDBCACHE{$file} && ref $MYDBCACHE{$file} && ref $MYDBCACHE{$file}{'data'} && $MYDBCACHE{$file}{'data'}{$param} ) {
            $value = $MYDBCACHE{$file}->{'data'}->{$param};
            $value =~ s{ (?: \A \s* ["'] | ["']\s* \z ) }{}xmsg;
        }
    }

    return $value;
}

sub get_dot_my_dot_cnf {
    my $user = shift || 'root';
    my $homedir;
    if ( exists $HOMECACHE{$user} ) {
        $homedir = $HOMECACHE{$user};
    }
    else {
        require Cpanel::PwCache;
        $HOMECACHE{$user} = $homedir = Cpanel::PwCache::gethomedir($user);
    }

    return $homedir . '/.my.cnf';

}

sub _getmydbparm {
    my ( $param, $user ) = @_;
    my $uid;

    if ( !$user ) {
        $uid //= $>;
        $user = 'root' if $uid == 0;
        if ( !$user ) {
            require Cpanel::PwCache;
            $user = Cpanel::PwCache::getusername();
        }
    }

    my $privs_obj;
    if ( $user ne 'root' && ( $uid //= $> ) == 0 ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds::ReducedPrivileges');
        $privs_obj = 'Cpanel::AccessIds::ReducedPrivileges'->new($user);
    }

    return _getmydb_param( $param, get_dot_my_dot_cnf($user) );
}

=head1 getmydbsocket($user)

Read the .my.cnf from the given user's home directory (if it exists) and return
an appropriate socket name for MySQL. Uses the socket directive if one is
present; otherwise, we will check /etc/my.cnf for a socket directive. If some are found
we will determine the most recently created socket.

=cut

sub getmydbsocket {    ## no critic qw(Subroutines::RequireArgUnpacking)

    # do it in a fallback manner
    # /home/user/.my.cnf
    # /etc/my.cnf

    my $socket = _getmydbparm( 'socket', @_ );

    if ( $socket && -S $socket ) {
        return $socket;
    }

    my @potential_sockets;
    my $conf = Cpanel::LoadFile::load_if_exists($_SYSTEM_MY_CNF);

    if ( length $conf && index( $conf, 'socket' ) > -1 ) {

        # The text 'socket' appears in my.cnf
        # So we must parse it
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::MyCnf::Full');

        my $ref = 'Cpanel::MysqlUtils::MyCnf::Full'->can('etc_my_cnf')->( $_SYSTEM_MY_CNF, $conf );

        if ($ref)    # theoretically /etc/my.cnf does not exist
        {
            # there was much discussion about where to get the socket value
            # if it does not exist in .my.cnf, so here is a priority based
            # search for it.

            push @potential_sockets, $ref->{'client'}->{'socket'} if length $ref->{'client'}->{'socket'};
            push @potential_sockets, $ref->{'mysql'}->{'socket'}  if length $ref->{'mysql'}->{'socket'};
            push @potential_sockets, $ref->{'mysqld'}->{'socket'} if length $ref->{'mysqld'}->{'socket'};
        }
    }

    push @potential_sockets, $VAR_MYSQL;

    my %MTIME_CACHE;
    foreach my $check_socket (@potential_sockets) {
        if ( -S $check_socket ) {
            $MTIME_CACHE{$check_socket} = ( stat(_) )[9];
        }
    }
    foreach my $newest_socket ( sort { $MTIME_CACHE{$b} <=> $MTIME_CACHE{$a} || ( -l $a ? ( -l $b ? 0 : 1 ) : -1 ) || $a cmp $b } keys %MTIME_CACHE ) {
        return $newest_socket;
    }

    return;
}

sub getmydbuser {
    return _getmydbparm( 'user', @_ );
}

sub getmydbpass {
    my $password = _getmydbparm( 'pass', @_ ) || _getmydbparm( 'password', @_ );

    # Decode utf8 characters, since loadConfig() is not reading in using UTF-8
    return defined $password && utf8::decode($password) ? $password : undef;
}

sub getmydbhost {
    my $host = _getmydbparm( 'host', @_ );

    # If no host is defined, and we're running as the user, query the root settings through adminbin
    if ( !$host && $> != 0 ) {

        # require'd in to only load Cpanel::JSON if needed.
        Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin');
        $host = 'Cpanel::AdminBin'->can('adminrun')->( 'cpmysql', 'GETHOST' );
    }

    return $host;
}

sub getmydbport { return _getmydbparm( 'port', @_ ); }

# This is the default host for which we're interested in grants.  Specifically,
# if we're using remote_mysql, this should be a host for which we have grants on
# the remote MySQL server.
sub get_grant_host {
    if ( is_remote_mysql() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Sys::Hostname');
        Cpanel::Sys::Hostname::gethostname();
    }
    return 'localhost';
}

sub get_server {
    if ( !is_remote_mysql() ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::DIp::MainIP');
        return Cpanel::DIp::MainIP::getmainserverip();
    }
    else {
        my $server = getmydbhost('root');
        Cpanel::LoadModule::load_perl_module('Cpanel::SocketIP');
        return Cpanel::SocketIP::_resolveIpAddress($server);
    }
}

sub is_local_mysql {
    my $mysql_host = shift || getmydbhost('root') || 'localhost';
    return is_remote_mysql($mysql_host) ? 0 : 1;
}

sub is_remote_mysql {
    my $host = shift || getmydbhost('root');
    return 0 if !$host;

    if ( Cpanel::IP::Loopback::is_loopback($host) ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');

        return $> != 0
          ? Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'IS_ACTIVE_PROFILE_CPCLOUD' )
          : Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } )->is_active_profile_cpcloud();
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Domain::Local');
    return ( $host && !Cpanel::Domain::Local::domain_or_ip_is_on_local_server($host) ) ? 1 : 0;
}

sub get_server_version {
    my ($dbh) = @_;

    return $dbh->selectrow_array('SELECT VERSION()');
}

sub clear_cache {
    %MYDBCACHE = ();
    return;
}
1;
