package Cpanel::SysQuota::Cache;

# cpanel - Cpanel/SysQuota/Cache.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $SYSQUOTA_DATASTORE_FILE = '/var/cpanel/repquota.datastore';
our $SYSQUOTA_CACHE_FILE     = '/var/cpanel/repquota.cache';

=encoding utf-8

=head1 NAME

Cpanel::SysQuota::Cache - A module for storing the system quota cache

=head1 SYNOPSIS

    use Cpanel::SysQuota::Cache;

    Cpanel::SysQuota::Cache::purge_cache();

=cut

=head2 purge_cache

Clear the in memory (if loaded) and disk repquota cache.

=cut

sub purge_cache {
    if ( $INC{'Cpanel/SysQuota.pm'} ) { Cpanel::SysQuota::_purge_memory_cache(); }
    unlink( $SYSQUOTA_DATASTORE_FILE, $SYSQUOTA_CACHE_FILE );
    return;
}

1;
