package Cpanel::PwCache::PwFile;

# cpanel - Cpanel/PwCache/PwFile.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic (RequireUseWarnings)

use Cpanel::PwCache::Find ();

sub get_line_from_pwfile {
    my ( $lookup_file, $lookup_key, $lc_flag ) = @_;
    my @PW;

    if ( open my $lookup_fh, '<', $lookup_file ) {
        if ( $lc_flag && $lc_flag == 1 ) {
            @PW = Cpanel::PwCache::Find::field_with_value_in_pw_file( $lookup_fh, 0, $lookup_key, $lc_flag );
        }
        else {
            @PW = Cpanel::PwCache::Find::field_with_value_in_pw_file( $lookup_fh, 0, $lookup_key );
        }
        close $lookup_fh;
    }
    return \@PW;
}

sub get_keyvalue_from_pwfile {
    my ( $lookup_file, $key_position, $lookup_key ) = @_;

    my $pwref = get_line_from_pwfile( $lookup_file, $lookup_key );
    if ( defined $pwref && @{$pwref} ) {
        return $pwref->[$key_position];
    }
    return;
}

1;
