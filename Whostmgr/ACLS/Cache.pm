
# cpanel - Whostmgr/ACLS/Cache.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ACLS::Cache;

use strict;
use warnings;

use Cpanel::AdminBin::Serializer ();

our $CACHE_FILE = '/var/cpanel/dynamicaclitems.cache';
our $DRIVER_DIR = '/usr/local/cpanel/Cpanel/Config/ConfigObj/Driver';    # Must update $Cpanel::Config::ConfigObj::DRIVER_DIR as well if this changes

sub load_dynamic_acl_cache_if_current {
    my $dir_mtime   = ( stat $DRIVER_DIR )[9] || 0;
    my $cache_mtime = ( stat $CACHE_FILE )[9] || 0;

    # Expire disk cache if list of available drivers appears to have been updated, or if 30 minutes elapse
    return if !$cache_mtime || $dir_mtime > $cache_mtime || time() > $cache_mtime + 1800;

    my $data;
    eval {
        local $SIG{'__DIE__'};     # Suppress spewage as we may be reading an invalid cache
        local $SIG{'__WARN__'};    # and since failure is ok to throw it away
        $data = Cpanel::AdminBin::Serializer::LoadFile($CACHE_FILE);
    };

    # OK to fail here since we will just return undef and not use the cache

    return $data;
}

sub write_dynamic_acl_cache {
    my $data = shift;
    require Cpanel::FileUtils::Write;
    return Cpanel::FileUtils::Write::overwrite( $CACHE_FILE, Cpanel::AdminBin::Serializer::Dump($data), 0700 );
}

1;
