package Cpanel::Themes::CacheBuster;

# cpanel - Cpanel/Themes/CacheBuster.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#
# The purpose of this module is to provide a CacheBusting mechanism suitable for
# use in cPanel interface.

use strict;
use warnings;

use Cpanel::Debug                     ();
use Cpanel::PwCache                   ();
use Cpanel::Themes::Fallback          ();
use Cpanel::Themes::CacheBuster::Tiny ();
use Try::Tiny;

my $SPRITE_FILE_TO_CHECK = 'sprites/icon_spritemap.css';

our $cache_id;

*reset_cache_id = *Cpanel::Themes::CacheBuster::Tiny::reset_cache_id;

sub get_cache_id {

    # ideally this should be retrieved ONCE per page rendering
    # reality may work out in a different way, though
    return $cache_id if $cache_id;

    my $cache_id_file = Cpanel::Themes::CacheBuster::Tiny::_get_cache_id_file();
    $cache_id = ( stat($cache_id_file) )[9];

    if ( !$cache_id ) {
        return ( $cache_id = reset_cache_id() );
    }
    elsif ( $cache_id > time() ) {

        # Using localtime() since Cpanel::Debug::log_info logs in localtime
        my $user = $Cpanel::user || Cpanel::PwCache::getusername();
        Cpanel::Debug::log_info( "The cacheid for the user “$user” was reset because it was in the future: " . localtime($cache_id) );
        return ( $cache_id = reset_cache_id() );
    }
    return $cache_id;
}

# used for unit test, don't use this, please.
sub _set_cache_id {
    ($cache_id) = @_;
    return;
}

1;
