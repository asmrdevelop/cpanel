package Cpanel::MysqlRun;

# cpanel - Cpanel/MysqlRun.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AdminBin::Serializer     ();
use Cpanel::MysqlUtils::Unprivileged ();
use Cpanel::CachedCommand::Utils     ();
use Cpanel::CachedCommand::Valid     ();
use Cpanel::FileUtils::Write         ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Try::Tiny;

our $VERSION = '2.0';

our $MYSQL_RUN_KEY = 'Cpanel::MysqlRun::running';

our $CACHE_TTL = 600;

# Returns 0 if MySQL is down.

# Warns and returns 0 if we failed to determine whether it’s up or down.
# TODO: Ideally we would throw an exception in this case. For new code,
# please consider making a new function that doesn’t confuse the
# “not-running” and “dunno” states.
#
# Returns 1 if MySQL is up.
#
sub running {
    my $socket_mtime;

    if ( !Cpanel::MysqlUtils::MyCnf::Basic::is_remote_mysql() ) {
        my $socket = Cpanel::MysqlUtils::MyCnf::Basic::getmydbsocket('root');
        return 0 if !$socket;
        $socket_mtime = ( stat($socket) )[9];
        return 0 if !$socket_mtime;
    }

    my $datastore_file = Cpanel::CachedCommand::Utils::get_datastore_filename($MYSQL_RUN_KEY);
    my ( $datastore_file_size, $datastore_file_mtime ) = ( stat($datastore_file) )[ 7, 9 ];
    my $version_ref;
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
        try { $version_ref = Cpanel::AdminBin::Serializer::LoadFile($datastore_file); };

        # Historically we saved “error” here, but we no longer do because
        # we only want to store either:
        #
        #   a) the reported MySQL version, or
        #   b) undef, to indicate that the server is down
        #
        if ( $version_ref && !$version_ref->{'error'} ) {
            return $version_ref->{'version'} ? 1 : 0;
        }
    }

    my $host = Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost';
    my $port = Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root');

    my ( $version, $error );

    try {
        $version = Cpanel::MysqlUtils::Unprivileged::get_version_from_host( $host, $port );
    }
    catch {
        $error = $_;
        warn "Failed to determine MySQL state; we proceed as though the server were down. $_";
    };

    # We don’t cache a failure to determine whether MySQL is down or not;
    # we only want to cache the actual version, or undef (i.e., the server
    # is actually down).
    if ( !$error ) {
        try {
            Cpanel::FileUtils::Write::overwrite( $datastore_file, Cpanel::AdminBin::Serializer::Dump( { 'version' => $version } ), 0600 );

        }
        catch {
            do {
                local $@ = $_;
                die;
            } unless ( try { $_->error_name() eq 'EDQUOT' } );
        };
    }

    return $version ? 1 : 0;
}

1;
