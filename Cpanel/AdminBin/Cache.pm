package Cpanel::AdminBin::Cache;

# cpanel - Cpanel/AdminBin/Cache.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Debug     ();
use Cpanel::StatCache ();
use Cpanel::PwCache   ();

sub check_cache_item {
    my ( $mtimetobeat, $file ) = @_;
    if ( !$file ) {
        Cpanel::Debug::log_warn('Missing file argument');
        return;
    }
    elsif ( !defined $mtimetobeat || $mtimetobeat !~ m/^\d+/ ) {
        Cpanel::Debug::log_warn('Cache mtime threshold not provided.');
        return;
    }
    elsif ( !$mtimetobeat ) {    # 0 means skip cache
        return;
    }

    my $cache_dir = _get_cache_dir() or return;

    return if !-e $cache_dir . '/' . $file;
    my ( $size, $mtime ) = ( stat(_) )[ 7, 9 ];
    return   if ( !$size || !$mtime );
    return 1 if ( $mtime > $mtimetobeat && $mtime <= time() );    #timewarp safe;
    return;
}

sub _get_cache_dir {
    my ($base_dir) = @_;

    $base_dir ||= $Cpanel::homedir || Cpanel::PwCache::gethomedir();
    if ( !$base_dir ) {
        Cpanel::Debug::log_warn('No base cache directory provided');
        return;
    }

    my $target_dir = $base_dir . '/.cpanel/datastore';

    if ( !Cpanel::StatCache::cachedmtime($target_dir) ) {
        if ( $> > 0 ) {    # Don't create datastore directory owned by root
            require Cpanel::SafeDir::MK;
            if ( Cpanel::SafeDir::MK::safemkdir( $target_dir, 0700 ) ) {
                Cpanel::StatCache::clearcache();
                return $target_dir;
            }
        }
        return;
    }
    return $target_dir;
}

1;
