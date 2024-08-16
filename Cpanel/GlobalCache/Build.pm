package Cpanel::GlobalCache::Build;

# cpanel - Cpanel/GlobalCache/Build.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::GlobalCache      ();
use Cpanel::CachedCommand    ();
use Cpanel::LoadFile         ();
use Cpanel::FileUtils::Write ();
use Cpanel::JSON             ();

sub save_cache ( $cachename, $cacheref ) {

    my $global_cache_dir = Cpanel::GlobalCache::default_product_dir() . "/globalcache";

    if ( !-e $global_cache_dir ) {    # FIXME: error checking
        mkdir( $global_cache_dir, 0755 );
    }
    my $cache_file = $global_cache_dir . '/' . $cachename . '.cache';

    my $can_json = Cpanel::JSON::canonical_dump($cacheref);

    #Only write out the file if it has changed to avoid updating the mtime
    my $current_cache = Cpanel::LoadFile::loadfile($cache_file);
    if ( !length $current_cache || $current_cache ne $can_json ) {

        # No locking needed here since its just a cache and safe
        # to overwrite anytime as long as its an atomic write
        # so its never empty
        return Cpanel::FileUtils::Write::overwrite( $cache_file, $can_json, 0644 );
    }
    return 1;
}

sub build_cache ( $cachename, $cachelistref ) {

    my $cacheref = {};

    foreach my $cacher (@$cachelistref) {
        if ( $cacher->{'type'} eq 'file' ) {
            $cacheref->{ $cacher->{'type'} }{ $cacher->{'key'} } = Cpanel::LoadFile::loadfile( $cacher->{'key'} );
        }
        elsif ( $cacher->{'type'} eq 'command' ) {
            my $val = Cpanel::CachedCommand::cachedcommand( @{ $cacher->{'key'} } );
            if ( $cacher->{'keeplines'} ) {
                my @lines = split( /\n/, $val );
                splice( @lines, $cacher->{'keeplines'} ) if scalar @lines > $cacher->{'keeplines'};
                $val = join( "\n", @lines );
            }
            $cacheref->{ $cacher->{'type'} }{ join( '_', @{ $cacher->{'key'} } ) } = $val;
        }
        elsif ( $cacher->{'type'} eq 'data' ) {
            $cacheref->{ $cacher->{'type'} }{ $cacher->{'key'} } = $cacher->{'value'};
        }
    }

    return save_cache( $cachename, $cacheref );
}

1;
