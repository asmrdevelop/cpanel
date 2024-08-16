package Cpanel::Logs::Truncate;

# cpanel - Cpanel/Logs/Truncate.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Sys::Chattr ();

sub truncate_logfile {
    my $file    = shift;
    my $success = 1;
    my $errno;

    # If the open inadvertently creates the file, do so with restrictive permssions
    my $old_umask = umask(0077);

    if ( open my $fh, '>>', $file ) {
        my $append_only = Cpanel::Sys::Chattr::get_attribute( $fh, 'APPEND' );
        Cpanel::Sys::Chattr::remove_attribute( $fh, 'APPEND' ) if $append_only;
        truncate( $fh, 0 ) or do {
            $success = 0;
            $errno   = $!;
        };
        Cpanel::Sys::Chattr::set_attribute( $fh, 'APPEND' ) if $append_only;
        close $fh;
    }
    else {
        $success = 0;
        $errno   = $!;
    }
    umask($old_umask);
    $! = $errno unless $success;
    return $success;
}

1;
