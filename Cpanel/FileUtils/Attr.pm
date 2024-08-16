package Cpanel::FileUtils::Attr;

# cpanel - Cpanel/FileUtils/Attr.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::FHUtils::Tiny ();
use Cpanel::Sys::Chattr   ();

sub get_file_or_fh_attributes {
    my ($target) = @_;

    my $fh;
    if ( Cpanel::FHUtils::Tiny::is_a($target) ) {
        $fh = $target;
    }
    else {
        open( $fh, '<', $target ) or return {
            'IMMUTABLE'   => 0,
            'APPEND_ONLY' => 0,
        };
    }

    return {
        'IMMUTABLE'   => Cpanel::Sys::Chattr::get_attribute( $fh, 'IMMUTABLE' ) ? 1 : 0,
        'APPEND_ONLY' => Cpanel::Sys::Chattr::get_attribute( $fh, 'APPEND' )    ? 1 : 0
    };
}

1;
