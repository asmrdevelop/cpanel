package Cpanel::PostgresAdmin::Check;

# cpanel - Cpanel/PostgresAdmin/Check.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::CachedCommand::Valid         ();
use Cpanel::Exception                    ();
use Cpanel::JSON                         ();
use Cpanel::LoadModule                   ();
use Cpanel::PwCache                      ();
use Cpanel::GlobalCache                  ();
use Cpanel::DbUtils                      ();
use Cpanel::CachedCommand::Utils         ();
use Cpanel::Services::Enabled            ();
use Cpanel::FileUtils::Write::JSON::Lazy ();
use Cpanel::AdminBin::Serializer         ();
use Cpanel::FileUtils::Write             ();

use Try::Tiny;

our $VERSION = 2.0;

my $pg_cache;
my $is_configured_cache;
my $root_pgpass_file;
our $CACHE_TTL = 2;

our $POSTGRES_RUN_KEY = 'Cpanel::PostgresAdmin::Check::ping';

sub is_enabled_and_configured {
    return is_configured()->{'status'} && Cpanel::Services::Enabled::is_enabled('postgresql');
}

sub is_configured {
    return $is_configured_cache if ref $is_configured_cache;

    # Determine if PostgreSQL is installed
    my $psql_bin   = Cpanel::DbUtils::find_psql();
    my $postmaster = Cpanel::DbUtils::find_postmaster();
    if ( !$psql_bin || !$postmaster ) {
        return { 'status' => 0, 'message' => 'PostgreSQL is not installed. Could not locate executable psql client or postmaster daemon.' };
    }

    my $short_version;
    my $psqlversion = Cpanel::GlobalCache::cachedcommand( 'cpanel', $postmaster, '--version' );
    if ($psqlversion) {
        $psqlversion =~ m/\s(\d+)\.(\d+)/;
        my $pmajor = $1;
        my $pminor = $2;
        if ( $pmajor < 7 || ( $pmajor == 7 && $pminor < 3 ) ) {
            return { 'status' => 0, 'message' => "PostgreSQL version is not sufficient. Version $pmajor.$pminor is not supported." };
        }
        $short_version = $pmajor . '.' . $pminor;
    }
    else {
        return { 'status' => 0, 'message' => 'Failed to determine PostgreSQL version from server.' };
    }

    # Determine PostgreSQL user and home directory
    my $pg_info = pg_info($psql_bin);

    if ( !$pg_info->{'status'} ) {
        return $pg_info;
    }

    my $pg_user    = $pg_info->{'pg_user'};
    my $pg_uid     = $pg_info->{'pg_uid'};
    my $pg_homedir = $pg_info->{'pg_homedir'};

    # Check only available for root or postgres users due to permission issues
    if ( $> == 0 ) {

        # ** This cannot be set outside a sub {} or it will end up compiled in
        if ( !defined $root_pgpass_file ) {
            my ($root_homedir) = ( Cpanel::PwCache::getpwnam('root') )[7];
            $root_pgpass_file = $root_homedir . '/.pgpass';
        }

        # Check for pgpass file. Required to authenticate as $pg_user
        if ( !-e $root_pgpass_file || -z _ ) {
            if ( -e $pg_homedir . '/.pgpass' ) {
                system 'cp', $pg_homedir . '/.pgpass', $root_pgpass_file;
            }
            else {
                return { 'status' => 0, 'message' => 'PostgreSQL has not been configured by the administrator. Unable to locate pgpass file.' };
            }
        }
    }

    return ( $is_configured_cache = { 'status' => 1, 'message' => 'PostgreSQL is configured.', 'user' => $pg_user, 'homedir' => ( $pg_homedir || 1 ), 'psql' => $psql_bin, 'version' => $short_version } );
}

sub pg_info {
    my $myuid = $>;
    return $pg_cache if ref $pg_cache && $pg_cache->{'uid_validity'} == $myuid && $pg_cache->{'pg_uid'};
    my $pgsql_bin       = shift || Cpanel::DbUtils::find_psql();
    my $pgsql_bin_mtime = ( stat($pgsql_bin) )[9];

    my $pg_info_cachefile = ( $myuid == 0 ? '/var/cpanel/pg_info.db' : Cpanel::CachedCommand::Utils::_get_datastore_filename('pg_info.db') );

    my @POSSIBLE_PG_USERS = ( 'postgres', 'pgsql' );

    my ( $pg_info_cachefile_uid, $pg_info_cachefile_mtime ) = ( stat($pg_info_cachefile) )[ 4, 9 ];
    my $cache_is_usable = ( $INC{'Cpanel/JSON.pm'} && $pg_info_cachefile_mtime && $pgsql_bin && ( $pg_info_cachefile_mtime > $pgsql_bin_mtime ) && $pg_info_cachefile_mtime > ( stat('/etc/passwd') )[9] ) ? 1 : 0;
    if ($cache_is_usable) {
        my $pgpwnam;
        try {
            $pgpwnam = Cpanel::JSON::LoadFile($pg_info_cachefile);
        };

        if ( $pgpwnam && ref $pgpwnam eq 'ARRAY' ) {
            $pg_cache = { 'status' => 1, 'pg_user' => $pgpwnam->[0], 'pg_uid' => $pgpwnam->[2], 'pg_homedir' => $pgpwnam->[7], 'uid_validity' => $myuid };
            return $pg_cache;

        }
        else {
            $cache_is_usable = 0;
        }
    }

    my ( $pg_user, $pg_uid, $pg_gid, $pg_homedir );
    foreach my $user (@POSSIBLE_PG_USERS) {
        my @PW = Cpanel::PwCache::getpwnam($user);
        ( $pg_user, $pg_uid, $pg_gid, $pg_homedir ) = (@PW)[ 0, 2, 3, 7 ];
        if ( $pg_uid && $pg_homedir ) {
            if ( !$pg_info_cachefile_mtime || $PW[11] > $pg_info_cachefile_mtime || $PW[12] > $pg_info_cachefile_mtime ) { $cache_is_usable = 0; }
            if ( !$cache_is_usable && $INC{'Cpanel/JSON.pm'} ) {
                $PW[1] = 'x';    #hide password
                my @DIR = split( /\/+/, $pg_info_cachefile );
                pop(@DIR);
                my $dir = join( '/', @DIR );
                if ( -w $dir || -w $pg_info_cachefile ) {
                    if ( Cpanel::FileUtils::Write::JSON::Lazy::write_file( $pg_info_cachefile, \@PW, 0640 ) ) {    # 0640 so it can be readable by the postgres GID
                        chown( $pg_uid, $pg_gid, $pg_info_cachefile );
                    }
                }
            }
            last;
        }
    }

    if ( !$pg_homedir ) {
        return { 'status' => 0, 'message' => 'No PostgreSQL user found.' };
    }

    $pg_cache = { 'status' => 1, 'pg_user' => $pg_user, 'pg_uid' => $pg_uid, 'pg_homedir' => $pg_homedir, 'uid_validity' => $myuid };
    return $pg_cache;
}

sub ping {
    my $psql = Cpanel::DbUtils::find_psql();
    return undef if !$psql;
    my $pg_info = pg_info($psql);

    return undef if ( !$pg_info->{'status'} );
    my $pg_user = $pg_info->{'pg_user'};
    #
    # from Cpanel::PostgresUtils find_pgsql_data
    #
    require Cpanel::PostgresUtils;
    my $datadir = Cpanel::PostgresUtils::find_pgsql_data();
    return undef if !$datadir;
    if ( -e $datadir . '/postmaster.pid' && ( ( stat(_) )[9] > ( time() - $CACHE_TTL ) ) ) {
        $CACHE_TTL = time() - ( stat(_) )[9] - 1;
    }

    my $socket_mtime = _get_socket_mtime();

    my $datastore_file = Cpanel::CachedCommand::Utils::get_datastore_filename($POSTGRES_RUN_KEY);
    my ( $datastore_file_size, $datastore_file_mtime ) = ( stat($datastore_file) )[ 7, 9 ];
    my $response_ref;
    if (
        Cpanel::CachedCommand::Valid::is_cache_valid(
            'datastore_file'       => $datastore_file,
            'datastore_file_mtime' => $datastore_file_mtime,
            'datastore_file_size'  => $datastore_file_size,
            'ttl'                  => $CACHE_TTL,
            'mtime'                => ( $socket_mtime || 0 ),
        )
    ) {
        # The below eval is not checked because the cache may
        # not exist or may be invalid and we will just fallback
        try { $response_ref = Cpanel::AdminBin::Serializer::LoadFile($datastore_file); };
        if ($response_ref) {
            return ( length $response_ref->{'ping'} && $response_ref->{'ping'} =~ m{ping}i ) ? 'PONG' : ();
        }
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Postgres::Connect');
    my ( $error, $ping );
    try {
        my $dbh = Cpanel::Postgres::Connect::get_dbi_handle();
        $ping = $dbh->selectrow_arrayref("SELECT 'PING';")->[0];
    }
    catch {
        $error = Cpanel::Exception::get_string($_);

    };

    try {
        Cpanel::FileUtils::Write::overwrite(
            $datastore_file,
            Cpanel::AdminBin::Serializer::Dump( { 'error' => $error, 'ping' => $ping } ), 0600
        );

    }
    catch {
        do {
            local $@ = $_;
            die;
        } unless ( try { $_->error_name() eq 'EDQUOT' } );
    };

    return ( length $ping && $ping =~ m{ping}i ) ? 'PONG' : ();
}

sub _get_socket_mtime {
    require Cpanel::PostgresUtils;
    my $socket_file = Cpanel::PostgresUtils::get_socket_file();

    if ( -e $socket_file ) {
        return ( stat(_) )[9];
    }
    return undef;

}

1;
