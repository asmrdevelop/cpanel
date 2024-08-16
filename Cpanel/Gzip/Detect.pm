package Cpanel::Gzip::Detect;

# cpanel - Cpanel/Gzip/Detect.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $GZIP_SIGNATURE = "\x1F\x8B\x08";

sub file_is_gzipped {
    my ($file) = @_;

    my $buffer;
    if ( open( my $fh, '<', $file ) ) {
        read( $fh, $buffer, length $GZIP_SIGNATURE );
        if ( $buffer eq $GZIP_SIGNATURE ) {
            return 1;
        }
    }

    return 0;

}
1;
