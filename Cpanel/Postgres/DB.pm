package Cpanel::Postgres::DB;

# cpanel - Cpanel/Postgres/DB.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# use warnings;

use strict;

use Cpanel::DB::Map::Reader      ();
use Cpanel::PwCache              ();
use Cpanel::StatCache            ();
use Cpanel::LoadFile             ();
use Cpanel::CachedCommand::Utils ();
use Cpanel::CachedCommand::Save  ();

our $VERSION = 1.1;

my $DBCACHETTL = 14440;

sub listdbs {
    my @DBS;
    if (
        $Cpanel::CPCACHE{'postgres'}{'DBcached'}
        || (   exists $Cpanel::CPCACHE{'postgres'}{'cached'}
            && $Cpanel::CPCACHE{'postgres'}{'cached'}
            && $Cpanel::CPCACHE{'postgres'}{'DB'} )
    ) {
        foreach my $db ( sort keys %{ $Cpanel::CPCACHE{'postgres'}{'DB'} } ) {
            push @DBS, $db;
        }
    }
    else {
        $Cpanel::context = 'postgres';
        my $map = Cpanel::DB::Map::Reader->new( cpuser => $Cpanel::user || Cpanel::PwCache::getusername(), engine => 'postgresql' );
        @DBS = $map->get_databases();
        return if $Cpanel::CPERROR{'postgres'};
        return if !@DBS;
        $Cpanel::CPCACHE{'postgres'}{'DBcached'} = 1;
        foreach my $db (@DBS) {
            $Cpanel::CPCACHE{'postgres'}{'DB'}{$db} = 1;
        }
    }
    return @DBS;
}

sub countdbs {
    require Cpanel::UserDatastore;

    my $system_cachedir = Cpanel::UserDatastore::get_path($Cpanel::user);
    my ( $system_cachefile, $local_cachefile ) = ( $system_cachedir . '/postgres-db-count', Cpanel::CachedCommand::Utils::_get_datastore_filename('postgres-db-count') );

    my ( $local_cachefile_mtime, $system_cachefile_mtime ) = ( Cpanel::StatCache::cachedmtime($local_cachefile), Cpanel::StatCache::cachedmtime($system_cachefile) );
    my ( $cachefile,             $cachefile_mtime )        = ( $system_cachefile_mtime > $local_cachefile_mtime ) ? ( $system_cachefile, $system_cachefile_mtime ) : ( $local_cachefile, $local_cachefile_mtime );

    if ( ( $cachefile_mtime + $DBCACHETTL ) > time() ) {
        my $dbcount = Cpanel::LoadFile::loadfile($cachefile) || 0;
        return int $dbcount;
    }
    my @DBS = listdbs();
    Cpanel::CachedCommand::Save::store( 'name' => 'postgres-db-count', 'data' => ( scalar @DBS ) );
    return ( scalar @DBS );
}

1;
